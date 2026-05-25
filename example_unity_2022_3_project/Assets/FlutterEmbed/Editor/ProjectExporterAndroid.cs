using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using UnityEngine;

internal class ProjectExporterAndroid : ProjectExporter
{
    // [portola] H8 markers used for idempotent, bounded build.gradle edits (no greedy regex rewrites).
    internal const string NamespaceMarkerStart = "// PORTOLA-MARKER-START flutter_embed_unity namespace";
    internal const string NamespaceMarkerEnd = "// PORTOLA-MARKER-END flutter_embed_unity namespace";
    internal const string NdkPathMarker = "// PORTOLA-MARKER ndkPath removed by flutter_embed_unity exporter";
    internal const string ActivityRemovedComment = " activity block was removed by flutter_embed_unity exporter (H8 XML DOM) ";

    protected override void TransformExportedProject(string exportPath)
    {
        Debug.Log("Transforming Unity export for Flutter integration...");

        // [portola] H8 — fail-fast against dangerous deletion targets before we touch the tree.
        ProjectExportHelpers.AssertSafeExportDirectory(exportPath);

        // The exported project has this structure:
        //
        // <unityLibrary>
        // |
        // |- <gradle>
        // |- <launcher>
        // |- <unityLibrary>
        // |- build.gradle
        // |- gradle.properties
        // |- local.properties
        // |- settings.gradle
        //
        // The structure is:
        // A library part in the unityLibrary module that you can integrate into any other Gradle project. This contains the Unity runtime and Player data.
        // A thin launcher part in the launcher module that contains the application name and its icons. This is a simple Android application that launches Unity.
        //
        // This needs to be transformed into a single module (the unityLibrary part).
        // The launcher module is not needed, as the user's Flutter project's android part will be the 'launcher'.
        // However, we do need the string.xml file from the launcher, as this contains some strings which Unity
        // will expect to find (and will crash with android.content.res.Resources$NotFoundException if they don't exist)
        // So, first, copy strings.xml
        // from `<exportPath>\launcher\src\main\res\values\`
        // to   `<exportPath>\unityLibrary\src\main\res\values\`

        string stringsResourceFileFromPath = new string[] {exportPath, "launcher", "src", "main", "res", "values", "strings.xml"}
                .Aggregate((a, b) => Path.Combine(a, b));
        string stringResourcesFileToPath = new string[] {exportPath, "unityLibrary", "src", "main", "res", "values", "strings.xml"}
                .Aggregate((a, b) => Path.Combine(a, b));

        FileInfo stringsResourceFile = new FileInfo(stringsResourceFileFromPath);

        if(!stringsResourceFile.Exists) {
            ProjectExportHelpers.ShowErrorMessage($"Unexpected error: '{stringsResourceFile.FullName} not found");
            return;
        }

        stringsResourceFile.MoveTo(stringResourcesFileToPath);
        Debug.Log($"Moved {stringsResourceFileFromPath} to {stringResourcesFileToPath}");

        // Inspect gradle.properties and report the value of unityStreamingAssets, which should be added
        // to the user's android/gradle.properties. Read-only line scan (no regex rewrite).
        FileInfo gradlePropertiesFile = new FileInfo(Path.Combine(exportPath, "gradle.properties"));
        if(gradlePropertiesFile.Exists) {
            string unityStreamingAssets = ReadGradlePropertyValue(File.ReadAllText(gradlePropertiesFile.FullName), "unityStreamingAssets");
            if (unityStreamingAssets != null)
            {
                Debug.Log($"The following should be added to your project's android/gradle.properties:\n" +
                    $"unityStreamingAssets={unityStreamingAssets}");
            }
        }

        // The launcher folder can now be deleted
        DirectoryInfo launcherDirectory = new DirectoryInfo(Path.Combine(exportPath, "launcher"));
        Directory.Delete(launcherDirectory.FullName, true);
        Debug.Log($"Deleted {launcherDirectory.FullName}");

        // The gradle folder can be deleted
        DirectoryInfo gradleDirectory = new DirectoryInfo(Path.Combine(exportPath, "gradle"));
        Directory.Delete(gradleDirectory.FullName, true);
        Debug.Log($"Deleted {gradleDirectory.FullName}");

        // The files at the root of exportPath can be deleted
        DirectoryInfo exportDirectory = new DirectoryInfo(exportPath);
        foreach (FileInfo file in exportDirectory.GetFiles()) {
            file.Delete();
            Debug.Log($"Deleted {file.FullName}");
        }

        // Now move the contents of
        //    '<exportPath>/unityLibrary/unityLibrary'
        // to '<exportPath>/unityLibrary'
        // so that the unityLibrary module is 'promoted' to being the main and only module of the export
        DirectoryInfo unityLibrarySubModuleDirectory = new DirectoryInfo(Path.Combine(exportPath, "unityLibrary"));
        if(!unityLibrarySubModuleDirectory.Exists) {
            ProjectExportHelpers.ShowErrorMessage($"Unexpected error: '{unityLibrarySubModuleDirectory.FullName} not found");
            return;
        }
        ProjectExportHelpers.MoveContentsOfDirectory(unityLibrarySubModuleDirectory, exportDirectory);
        unityLibrarySubModuleDirectory.Delete(true);
        Debug.Log($"Moved {unityLibrarySubModuleDirectory.FullName} to {exportDirectory.FullName}");

        // The export includes an activity in the AndroidManifest.xml which is not going to be
        // used (because we are using a Flutter PlatfromView instead). Remove it using an XML DOM
        // edit instead of a regex rewrite (audit P0-6: regex breaks silently on Unity version churn).
        FileInfo androidManifestFile = new FileInfo(Path.Combine(exportPath, "src", "main", "AndroidManifest.xml"));
        if(!androidManifestFile.Exists) {
            ProjectExportHelpers.ShowErrorMessage($"Unexpected error: '{androidManifestFile.FullName} not found");
            return;
        }
        string androidManifestContents = File.ReadAllText(androidManifestFile.FullName);
        androidManifestContents = RemoveActivitiesFromManifest(androidManifestContents);
        File.WriteAllText(androidManifestFile.FullName, androidManifestContents, new UTF8Encoding(false));
        Debug.Log($"Removed <activity> elements from {androidManifestFile.FullName} (XML DOM)");

        // Add the namespace 'com.unity3d.player' to unityLibrary\build.gradle for compatibility with Gradle 8.
        // Done with a bounded, idempotent marker block instead of a regex replace of 'android {'.
        FileInfo buildGradleFile = new FileInfo(Path.Combine(exportPath, "build.gradle"));
        if(!buildGradleFile.Exists) {
            ProjectExportHelpers.ShowErrorMessage($"Unexpected error: '{buildGradleFile.FullName} not found");
            return;
        }
        string buildGradleContents = File.ReadAllText(buildGradleFile.FullName);
        string withNamespace = AddNamespaceToBuildGradle(buildGradleContents, "com.unity3d.player");
        if (withNamespace != buildGradleContents)
        {
            buildGradleContents = withNamespace;
            File.WriteAllText(buildGradleFile.FullName, buildGradleContents);
            Debug.Log($"Added namespace 'com.unity3d.player' to {buildGradleFile.FullName} for Gradle 8 compatibility");
        }

        // (optional) Add the namespace 'com.UnityTechnologies.XR.Manifest' to unityLibrary\xrmanifest.androidlib\build.gradle
        // for compatibility with Gradle 8
        FileInfo xrBuildGradleFile = new FileInfo(Path.Combine(exportPath, "xrmanifest.androidlib", "build.gradle"));
        if(xrBuildGradleFile.Exists) {
            string xrBuildGradleContents = File.ReadAllText(xrBuildGradleFile.FullName);
            string xrWithNamespace = AddNamespaceToBuildGradle(xrBuildGradleContents, "com.UnityTechnologies.XR.Manifest");
            if (xrWithNamespace != xrBuildGradleContents)
            {
                File.WriteAllText(xrBuildGradleFile.FullName, xrWithNamespace);
                Debug.Log($"Added namespace 'com.UnityTechnologies.XR.Manifest' to {xrBuildGradleFile.FullName} for Gradle 8 compatibility");
            }
        }

        // Using project templates created with Flutter 3.29 or later now causes a build error due to an NDK version conflict.
        // For example:
        //
        // android.ndkVersion is [27.0.12077973] but android.ndkPath /Applications/Unity/Hub/Editor/2022.3.62f1/PlaybackEngines/AndroidPlayer/NDK
        // refers to a different version [23.1.7779620]
        //
        // To resolve this we now need to remove the explicit reference to NDK 23.1 in unityLibrary\build.gradle, and allow the higher version
        // used by the Flutter project to take precendence. Comment out each ndkPath line (bounded, idempotent, line-anchored — no multiline regex).
        string withoutNdkPath = CommentOutNdkPath(buildGradleContents);
        if (withoutNdkPath != buildGradleContents)
        {
            buildGradleContents = withoutNdkPath;
            File.WriteAllText(buildGradleFile.FullName, buildGradleContents);
            Debug.Log($"ndkPath property was removed from {buildGradleFile.FullName}");
        }

        DirectoryInfo burstDebugInformation = new DirectoryInfo(Path.Join(exportPath, "..", "unityLibrary_BurstDebugInformation_DoNotShip"));
        if(burstDebugInformation.Exists) {
            Directory.Delete(burstDebugInformation.FullName, true);
            Debug.Log($"Deleted {burstDebugInformation.FullName}");
        }

        Debug.Log("Transforming Unity export for Flutter integration complete");
    }

    // ---- Pure, testable transforms (exercised by ProjectExportReproducibilityCheck) ----

    // Removes every <activity> element from an AndroidManifest using an XML DOM, leaving a comment
    // in its place. Namespace declarations and all other nodes are preserved by the parser.
    internal static string RemoveActivitiesFromManifest(string manifestXml)
    {
        XDocument doc = XDocument.Parse(manifestXml, LoadOptions.None);
        List<XElement> activities = doc.Descendants("activity").ToList();
        foreach (XElement activity in activities)
        {
            activity.AddBeforeSelf(new XComment(ActivityRemovedComment));
            activity.Remove();
        }
        return SerializeXml(doc);
    }

    // Inserts `namespace '<value>'` inside the first `android {` block, wrapped in PORTOLA markers.
    // Idempotent: returns input unchanged if the marker is already present or a namespace is declared.
    internal static string AddNamespaceToBuildGradle(string gradle, string namespaceValue)
    {
        if (gradle.Contains(NamespaceMarkerStart) || ContainsNamespaceDeclaration(gradle))
        {
            return gradle;
        }

        string[] lines = SplitLines(gradle);
        List<string> outLines = new(lines.Length + 3);
        bool inserted = false;
        foreach (string line in lines)
        {
            outLines.Add(line);
            if (!inserted && line.TrimStart().StartsWith("android {"))
            {
                outLines.Add($"\t{NamespaceMarkerStart} (Gradle 8 compat)");
                outLines.Add($"\tnamespace '{namespaceValue}'");
                outLines.Add($"\t{NamespaceMarkerEnd}");
                inserted = true;
            }
        }

        return inserted ? string.Join("\n", outLines) : gradle;
    }

    // Comments out every line that declares ndkPath, annotated with a PORTOLA marker.
    // Idempotent: an already-commented line no longer begins with `ndkPath`.
    internal static string CommentOutNdkPath(string gradle)
    {
        string[] lines = SplitLines(gradle);
        bool changed = false;
        for (int i = 0; i < lines.Length; i++)
        {
            if (lines[i].TrimStart().StartsWith("ndkPath"))
            {
                lines[i] = $"\t{NdkPathMarker}: {lines[i].Trim()}";
                changed = true;
            }
        }
        return changed ? string.Join("\n", lines) : gradle;
    }

    // Returns the value of a `key=value` line in gradle.properties, or null. Read-only, no regex.
    internal static string ReadGradlePropertyValue(string propertiesContent, string key)
    {
        foreach (string raw in SplitLines(propertiesContent))
        {
            string line = raw.Trim();
            if (line.StartsWith(key + "="))
            {
                return line.Substring(key.Length + 1);
            }
        }
        return null;
    }

    private static bool ContainsNamespaceDeclaration(string gradle)
    {
        return SplitLines(gradle).Any(l => l.TrimStart().StartsWith("namespace "));
    }

    // Splits on any line-ending style. Unity's exported build.gradle mixes CRLF (from the gradle
    // template) and bare LF (from the appended IL2CPP block), so splitting on a single detected
    // delimiter would merge lines and silently no-op the namespace/ndkPath edits — exactly the
    // Unity-version churn break H8 targets. Callers rejoin with "\n" (Gradle is EOL-agnostic).
    private static string[] SplitLines(string text)
    {
        return text.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n');
    }

    private static string SerializeXml(XDocument doc)
    {
        XmlWriterSettings settings = new XmlWriterSettings
        {
            Encoding = new UTF8Encoding(false),
            Indent = true,
            OmitXmlDeclaration = false,
        };
        using Utf8StringWriter sw = new Utf8StringWriter();
        using (XmlWriter xw = XmlWriter.Create(sw, settings))
        {
            doc.Save(xw);
        }
        return sw.ToString();
    }

    // StringWriter that reports UTF-8 so the XML declaration says encoding="utf-8".
    private sealed class Utf8StringWriter : StringWriter
    {
        public override Encoding Encoding => new UTF8Encoding(false);
    }
}
