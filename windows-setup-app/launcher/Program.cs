using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;

namespace CloudflareV2RaySetup;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();

        try
        {
            var appDir = AppContext.BaseDirectory;
            var projectRoot = ResolveProjectRoot(appDir);
            var scriptPath = Path.Combine(appDir, "CloudflareSetupApp.ps1");

            if (!File.Exists(scriptPath))
            {
                scriptPath = ExtractEmbeddedScript();
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{scriptPath}\"",
                WorkingDirectory = projectRoot,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            startInfo.Environment["CLOUDFLARE_SETUP_PROJECT_ROOT"] = projectRoot;

            using var process = Process.Start(startInfo);
            process?.WaitForExit();
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                ex.Message,
                "Could not start setup",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string ResolveProjectRoot(string appDir)
    {
        var candidates = new[]
        {
            Path.GetFullPath(Path.Combine(appDir, "..")),
            appDir,
            Environment.CurrentDirectory
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(Path.Combine(candidate, "wrangler.toml")) &&
                Directory.Exists(Path.Combine(candidate, "public")) &&
                Directory.Exists(Path.Combine(candidate, "functions")))
            {
                return candidate;
            }
        }

        return Path.GetFullPath(Path.Combine(appDir, ".."));
    }

    private static string ExtractEmbeddedScript()
    {
        var assembly = Assembly.GetExecutingAssembly();
        const string resourceName = "CloudflareSetupApp.ps1";
        using var stream = assembly.GetManifestResourceStream(resourceName);

        if (stream is null)
        {
            throw new FileNotFoundException("The embedded setup script is missing from the EXE.");
        }

        var tempDir = Path.Combine(Path.GetTempPath(), "CloudflareV2RaySetup");
        Directory.CreateDirectory(tempDir);
        var scriptPath = Path.Combine(tempDir, "CloudflareSetupApp.ps1");

        using var file = File.Create(scriptPath);
        stream.CopyTo(file);
        return scriptPath;
    }
}
