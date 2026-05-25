using System.Collections.Generic;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;

// [portola] H8 — single point of truth for the reproducible Android batch export preset.
//
// Why this exists (audit P0-6 / P1-6):
// The upstream exporter only *checks* Editor state (build target, "Export project",
// scripting backend, target architectures) and aborts when a human has not configured
// it through the GUI first. That makes batch / CI export depend on hidden, machine-local
// Editor state. On a fresh checkout with a clean Library/, `exportAsGoogleAndroidProject`
// defaults to false and `activeBuildTarget` defaults to the host standalone target, so the
// upstream PreCheck fails — exactly the M6A "hidden exportAsGoogleAndroidProject" situation.
//
// This preset *sets* every reproducibility-relevant value explicitly before the PreCheck
// verifier runs, so a clean checkout produces a byte-deterministic export without any GUI
// interaction. The downstream ProjectExportChecker is kept as a defence-in-depth verifier:
// if the preset ever fails to set a value, the checker still hard-fails the build.
//
// Pollution note (see CHANGELOG-portola.md H8): in batch mode this mutates user/Library
// EditorUserBuildSettings state (activeBuildTarget, exportAsGoogleAndroidProject). Those are
// not committed project files. The PlayerSettings values it sets (IL2CPP, ARMv7+ARM64) already
// match the committed ProjectSettings.asset, so re-affirming them produces no repo churn, and
// the preset never calls AssetDatabase.SaveAssets / saves the project.
internal static class A1BatchPresets
{
    // Target architectures: ARM64 is the primary Portola target. ARMv7 (32-bit) is retained
    // because the existing repo口径 — committed ProjectSettings.asset (AndroidTargetArchitectures: 3)
    // and ProjectExportChecker.PreCheckAndroid — both require ARMv7 + ARM64. Dropping ARMv7 here
    // would also require relaxing the checker, which is out of H8 scope.
    internal const AndroidArchitecture CanonicalAndroidArchitectures =
        AndroidArchitecture.ARMv7 | AndroidArchitecture.ARM64;

    // Applies the canonical Android batch preset and returns an audit trail of what it set.
    // Safe to call when already configured (idempotent: setting the same values is a no-op diff).
    internal static List<string> ApplyAndroid()
    {
        List<string> applied = new();

        // 1. Active build target = Android. The CLI `-buildTarget Android` arg normally handles
        //    this, but we switch defensively so the preset is correct even when invoked without it.
        if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
        {
            EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
            applied.Add($"[A1BatchPresets] Switched activeBuildTarget -> Android");
        }
        else
        {
            applied.Add("[A1BatchPresets] activeBuildTarget already Android");
        }

        // 2. Export as a Gradle project (the M6A hidden-state bug). User/Library state, default false.
        if (!EditorUserBuildSettings.exportAsGoogleAndroidProject)
        {
            EditorUserBuildSettings.exportAsGoogleAndroidProject = true;
            applied.Add("[A1BatchPresets] Set exportAsGoogleAndroidProject = true");
        }
        else
        {
            applied.Add("[A1BatchPresets] exportAsGoogleAndroidProject already true");
        }

        // 3. IL2CPP scripting backend (required for ARM64). Committed as IL2CPP already; re-affirm.
        ScriptingImplementation backend = PlayerSettings.GetScriptingBackend(BuildTargetGroup.Android);
        if (backend != ScriptingImplementation.IL2CPP)
        {
            PlayerSettings.SetScriptingBackend(BuildTargetGroup.Android, ScriptingImplementation.IL2CPP);
            applied.Add($"[A1BatchPresets] Set Android scripting backend IL2CPP (was {backend})");
        }
        else
        {
            applied.Add("[A1BatchPresets] Android scripting backend already IL2CPP");
        }

        // 4. Target architectures ARMv7 + ARM64.
        if (PlayerSettings.Android.targetArchitectures != CanonicalAndroidArchitectures)
        {
            PlayerSettings.Android.targetArchitectures = CanonicalAndroidArchitectures;
            applied.Add("[A1BatchPresets] Set Android targetArchitectures = ARMv7 | ARM64");
        }
        else
        {
            applied.Add("[A1BatchPresets] Android targetArchitectures already ARMv7 | ARM64");
        }

        return applied;
    }
}
