using System.IO;
using UnityEditor;
using UnityEngine;

internal class ProjectExportHelpers
{
    static internal void ShowErrorMessage(string errorMessage)
    {
        if (!Application.isBatchMode) {
            EditorUtility.DisplayDialog(
                            "Export incomplete",
                            errorMessage,
                            "Okay");
        } else {
            // We don't have any UI to help the user, abort the export.
            throw new System.Exception(errorMessage);
        }
    }

    // [portola] H8 — fail-fast guard against deleting/overwriting dangerous targets during export.
    // The batch exporter deletes the chosen export directory before writing; this refuses any path
    // that is a filesystem root, the Unity project root, or Assets/Packages/ProjectSettings/Library
    // (or an ancestor of one of those). Throws on a dangerous path; returns quietly when safe.
    static internal void AssertSafeExportDirectory(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            throw new System.Exception("Export path safety check failed: path is null or empty.");
        }

        string full;
        try
        {
            full = NormalizeFull(path);
        }
        catch (System.Exception e)
        {
            throw new System.Exception($"Export path safety check failed: invalid path '{path}': {e.Message}");
        }

        // Refuse a filesystem / drive root (e.g. 'C:\' or '/').
        string root = Path.GetPathRoot(full);
        if (!string.IsNullOrEmpty(root) &&
            PathsEqual(full, root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)))
        {
            throw new System.Exception($"Export path safety check failed: refusing filesystem root '{full}'.");
        }

        string assets = NormalizeFull(Application.dataPath);                          // <project>/Assets
        string projectRoot = NormalizeFull(Path.Combine(Application.dataPath, "..")); // <project>
        string packages = NormalizeFull(Path.Combine(projectRoot, "Packages"));
        string projectSettings = NormalizeFull(Path.Combine(projectRoot, "ProjectSettings"));
        string library = NormalizeFull(Path.Combine(projectRoot, "Library"));

        foreach (string protectedPath in new[] { projectRoot, assets, packages, projectSettings, library })
        {
            if (PathsEqual(full, protectedPath) || IsAncestorOf(full, protectedPath))
            {
                throw new System.Exception(
                    $"Export path safety check failed: '{full}' would delete protected Unity location '{protectedPath}'. " +
                    "Choose an export path outside the Unity project (e.g. '<your flutter project>/android/unityLibrary').");
            }
        }
    }

    private static string NormalizeFull(string p)
    {
        return Path.GetFullPath(p).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static bool PathsEqual(string a, string b)
    {
        return string.Equals(a, b, System.StringComparison.OrdinalIgnoreCase);
    }

    // True when `ancestor` is a strict parent directory of `descendant` (so deleting `ancestor`
    // would also delete `descendant`).
    private static bool IsAncestorOf(string ancestor, string descendant)
    {
        return descendant.StartsWith(ancestor + Path.DirectorySeparatorChar, System.StringComparison.OrdinalIgnoreCase);
    }

    static internal void MoveContentsOfDirectory(DirectoryInfo from, DirectoryInfo to)
    {
        Directory.CreateDirectory(to.FullName);

        // Copy each file into the new directory.
        foreach (FileInfo fi in from.GetFiles())
        {
            fi.MoveTo(Path.Combine(to.FullName, fi.Name));
        }

        // Copy each subdirectory using recursion.
        foreach (DirectoryInfo diSourceSubDir in from.GetDirectories())
        {
            DirectoryInfo nextTargetSubDir =
                to.CreateSubdirectory(diSourceSubDir.Name);
            MoveContentsOfDirectory(diSourceSubDir, nextTargetSubDir);
        }
    }
}