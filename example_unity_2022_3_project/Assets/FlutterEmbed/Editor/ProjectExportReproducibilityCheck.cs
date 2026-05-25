using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;

// [portola] H8 — batch-invokable reproducibility self-check (golden snapshot + idempotency + guards).
//
// This validates the exporter's reproducibility-critical logic WITHOUT running a full IL2CPP/Gradle
// Android build, so it provides real PASS evidence even on a host where the native build chain is
// incomplete. It exercises the same hardened code paths the real export uses.
//
// Invoke (clean Library is fine — Unity imports the project, compiles, then runs this):
//   <Unity> -batchmode -nographics -projectPath <example_unity_2022_3_project> \
//           -buildTarget Android -executeMethod ProjectExportReproducibilityCheck.RunAll \
//           -exportPath <tmp>/android/unityLibrary -quit -logFile <log>
//
// Exit code 0 = all checks green; 1 = at least one check failed (details logged as [H8][FAIL]).
public static class ProjectExportReproducibilityCheck
{
    public static void RunAll()
    {
        int failures = 0;
        failures += Run("Android batch preset sets canonical reproducible state", CheckPreset);
        failures += Run("AndroidManifest <activity> removed via XML DOM, other nodes preserved", CheckManifestTransform);
        failures += Run("build.gradle namespace inserted as idempotent marker block", CheckNamespaceTransform);
        failures += Run("build.gradle ndkPath commented out idempotently", CheckNdkPathTransform);
        failures += Run("gradle.properties value read without regex", CheckPropertyRead);
        failures += Run("export path safety guard rejects dangerous targets, allows valid", CheckPathGuard);
        failures += Run("PreCheckAndroid passes after preset (no hidden Editor state)", CheckPreCheckPasses);

        if (failures > 0)
        {
            Debug.LogError($"[H8] ProjectExportReproducibilityCheck FAILED: {failures} check(s) failed.");
            if (Application.isBatchMode)
            {
                EditorApplication.Exit(1);
            }
            else
            {
                throw new Exception($"[H8] ProjectExportReproducibilityCheck FAILED: {failures} check(s) failed.");
            }
            return;
        }

        Debug.Log("[H8] ProjectExportReproducibilityCheck PASSED: all checks green.");
        if (Application.isBatchMode)
        {
            EditorApplication.Exit(0);
        }
    }

    private static int Run(string name, Action check)
    {
        try
        {
            check();
            Debug.Log($"[H8][PASS] {name}");
            return 0;
        }
        catch (Exception e)
        {
            Debug.LogError($"[H8][FAIL] {name}: {e.Message}");
            return 1;
        }
    }

    private static void CheckPreset()
    {
        A1BatchPresets.ApplyAndroid();

        if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
        {
            throw new Exception($"activeBuildTarget is {EditorUserBuildSettings.activeBuildTarget}, expected Android");
        }
        if (!EditorUserBuildSettings.exportAsGoogleAndroidProject)
        {
            throw new Exception("exportAsGoogleAndroidProject is false (the M6A hidden-state bug)");
        }
        if (PlayerSettings.GetScriptingBackend(BuildTargetGroup.Android) != ScriptingImplementation.IL2CPP)
        {
            throw new Exception("Android scripting backend is not IL2CPP");
        }
        if (PlayerSettings.Android.targetArchitectures != A1BatchPresets.CanonicalAndroidArchitectures)
        {
            throw new Exception($"Android targetArchitectures is {PlayerSettings.Android.targetArchitectures}, expected ARMv7 | ARM64");
        }
    }

    private static void CheckManifestTransform()
    {
        string input =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n" +
            "  <application android:label=\"unity\">\n" +
            "    <activity android:name=\"com.unity3d.player.UnityPlayerActivity\" android:label=\"unity\">\n" +
            "      <intent-filter>\n" +
            "        <action android:name=\"android.intent.action.MAIN\" />\n" +
            "        <category android:name=\"android.intent.category.LAUNCHER\" />\n" +
            "      </intent-filter>\n" +
            "      <meta-data android:name=\"unityplayer.UnityActivity\" android:value=\"true\" />\n" +
            "    </activity>\n" +
            "    <meta-data android:name=\"keep.me\" android:value=\"1\" />\n" +
            "  </application>\n" +
            "</manifest>";

        string output = ProjectExporterAndroid.RemoveActivitiesFromManifest(input);

        if (output.Contains("<activity"))
        {
            throw new Exception("<activity> still present after transform");
        }
        if (!output.Contains("keep.me"))
        {
            throw new Exception("non-activity node (keep.me meta-data) was lost");
        }
        if (!output.Contains("xmlns:android"))
        {
            throw new Exception("android namespace declaration was lost");
        }
        if (!output.Contains("<application"))
        {
            throw new Exception("<application> element was lost");
        }
        if (!output.Contains("activity block was removed"))
        {
            throw new Exception("removal marker comment missing");
        }
        // Output must still be well-formed XML.
        System.Xml.Linq.XDocument.Parse(output);
    }

    private static void CheckNamespaceTransform()
    {
        string gradle = "apply plugin: 'com.android.library'\n\nandroid {\n\tcompileSdkVersion 34\n}\n";

        string once = ProjectExporterAndroid.AddNamespaceToBuildGradle(gradle, "com.unity3d.player");
        if (!once.Contains("namespace 'com.unity3d.player'"))
        {
            throw new Exception("namespace not inserted");
        }
        if (!once.Contains(ProjectExporterAndroid.NamespaceMarkerStart) || !once.Contains(ProjectExporterAndroid.NamespaceMarkerEnd))
        {
            throw new Exception("PORTOLA marker block missing");
        }

        string twice = ProjectExporterAndroid.AddNamespaceToBuildGradle(once, "com.unity3d.player");
        if (twice != once)
        {
            throw new Exception("namespace transform is not idempotent");
        }

        string already = "android {\n\tnamespace 'x'\n}\n";
        if (ProjectExporterAndroid.AddNamespaceToBuildGradle(already, "com.unity3d.player") != already)
        {
            throw new Exception("should not insert when a namespace is already declared");
        }

        // Regression: Unity 2022.3.62f3 emits its own namespace, and its build.gradle MIXES CRLF
        // (template) with bare LF (appended IL2CPP block). The transform must detect the existing
        // namespace across both EOL styles and NOT add a duplicate into a second android block.
        string unityMixed = "apply plugin: 'com.android.library'\r\ndependencies {\r\n}\r\n\r\n" +
            "android {\n    namespace \"com.unity3d.player\"\n    ndkPath \"x\"\n}\r\n\r\nandroid {\n    task t {}\n}\r\n";
        if (ProjectExporterAndroid.AddNamespaceToBuildGradle(unityMixed, "com.unity3d.player") != unityMixed)
        {
            throw new Exception("must not add a duplicate namespace when Unity already declares one (mixed CRLF/LF)");
        }
    }

    private static void CheckNdkPathTransform()
    {
        string gradle = "android {\n\tndkPath \"/some/path/AndroidPlayer/NDK\"\n\tcompileSdkVersion 34\n}\n";

        string once = ProjectExporterAndroid.CommentOutNdkPath(gradle);
        if (once.Split('\n').Any(l => l.TrimStart().StartsWith("ndkPath")))
        {
            throw new Exception("an active ndkPath line remains");
        }
        if (!once.Contains(ProjectExporterAndroid.NdkPathMarker))
        {
            throw new Exception("ndkPath PORTOLA marker missing");
        }

        string twice = ProjectExporterAndroid.CommentOutNdkPath(once);
        if (twice != once)
        {
            throw new Exception("ndkPath transform is not idempotent");
        }

        // Regression: ndkPath inside a mixed CRLF/LF block (as Unity 2022.3.62f3 produces) must
        // still be commented out, not missed by single-delimiter line splitting.
        string mixedNdk = "android {\r\n    namespace \"x\"\n    ndkPath \"/p/NDK\"\n}\r\n";
        string mixedOut = ProjectExporterAndroid.CommentOutNdkPath(mixedNdk);
        if (mixedOut.Split('\n').Any(l => l.TrimStart().StartsWith("ndkPath")))
        {
            throw new Exception("ndkPath in a mixed CRLF/LF block was not commented out");
        }
    }

    private static void CheckPropertyRead()
    {
        string props = "unityStreamingAssets=.unity3d, .bundle\nsomeOther=ignored\n";
        string value = ProjectExporterAndroid.ReadGradlePropertyValue(props, "unityStreamingAssets");
        if (value != ".unity3d, .bundle")
        {
            throw new Exception($"unexpected property value '{value}'");
        }
        if (ProjectExporterAndroid.ReadGradlePropertyValue(props, "missingKey") != null)
        {
            throw new Exception("missing key should read as null");
        }
    }

    private static void CheckPathGuard()
    {
        // A valid export target must NOT throw.
        string safe = Path.Combine(Path.GetTempPath(), "portola_h8_export", "android", "unityLibrary");
        ProjectExportHelpers.AssertSafeExportDirectory(safe);

        // Dangerous targets MUST throw.
        AssertRejected("Assets", Application.dataPath);
        AssertRejected("project root", Path.Combine(Application.dataPath, ".."));
        AssertRejected("ProjectSettings", Path.Combine(Application.dataPath, "..", "ProjectSettings"));
        AssertRejected("Packages", Path.Combine(Application.dataPath, "..", "Packages"));
        AssertRejected("filesystem root", Path.GetPathRoot(Application.dataPath));
        AssertRejected("ancestor of project root", Path.Combine(Application.dataPath, "..", ".."));
        AssertRejected("empty path", "");
    }

    private static void AssertRejected(string label, string path)
    {
        bool threw = false;
        try
        {
            ProjectExportHelpers.AssertSafeExportDirectory(path);
        }
        catch (Exception)
        {
            threw = true;
        }
        if (!threw)
        {
            throw new Exception($"expected rejection of dangerous path [{label}]: '{path}'");
        }
    }

    private static void CheckPreCheckPasses()
    {
        A1BatchPresets.ApplyAndroid();
        ProjectExportChecker checker = new ProjectExportChecker();
        ProjectExportCheckerResult result = checker.PreCheckAndroid();
        if (!result.IsSuccessful)
        {
            throw new Exception("PreCheckAndroid failed after preset — a hidden Editor-state dependency remains " +
                "(ensure invocation passes -buildTarget Android and -exportPath <...>/android/unityLibrary)");
        }
    }
}
