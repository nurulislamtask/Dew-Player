using System.Windows;
using FlyleafLib;
using Velopack;
using Velopack.Sources;

namespace LLPlayer.Services;

/// <summary>
/// Auto update via GitHub Releases (Velopack). Only works in the installed build (DewPlayer-Setup.exe).
/// </summary>
public static class UpdateService
{
    public const string RepoUrl = "https://github.com/nurulislamtask/Dew-Player";

    private static readonly LogHandler Log = new("[App] [UpdateService  ] ");
    private static readonly UpdateManager Mgr = new(new GithubSource(RepoUrl, null, false));
    private static int _busy;

    public static bool IsInstalled => Mgr.IsInstalled;

    public static async Task CheckAsync(bool userInitiated)
    {
        // allow only one check at a time
        if (Interlocked.Exchange(ref _busy, 1) == 1)
        {
            return;
        }

        try
        {
            if (!Mgr.IsInstalled)
            {
                if (userInitiated)
                {
                    Show("Updates work only in the installed version.\nInstall Dew Player with DewPlayer-Setup.exe from GitHub Releases.");
                }
                return;
            }

            bool auto = Application.Current.Dispatcher.Invoke(() => ((App)Application.Current).Container.Resolve<FlyleafManager>().Config.AutoUpdate);
            if (!userInitiated && !auto)
            {
                return;
            }

            UpdateInfo? info = await Mgr.CheckForUpdatesAsync();
            if (info == null)
            {
                if (userInitiated)
                {
                    Show($"You are on the latest version ({App.Version}).");
                }
                return;
            }

            string newVer = info.TargetFullRelease.Version.ToString();
            Log.Info($"Update found: {newVer}");

            // download in the background, no UI blocked
            await Mgr.DownloadUpdatesAsync(info);

            bool restart = Application.Current.Dispatcher.Invoke(() =>
                MessageBox.Show(
                    $"Dew Player {newVer} is ready.\nRestart now to finish updating?\n\n(No = update will be applied when you close the app)",
                    App.Name, MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes);

            if (restart)
            {
                Mgr.ApplyUpdatesAndRestart(info.TargetFullRelease);
            }
            else
            {
                Mgr.WaitExitThenApplyUpdates(info.TargetFullRelease, silent: true, restart: false);
            }
        }
        catch (Exception ex)
        {
            Log.Error($"Update failed: {ex.Message}");
            if (userInitiated)
            {
                Show($"Update check failed:\n{ex.Message}");
            }
        }
        finally
        {
            Interlocked.Exchange(ref _busy, 0);
        }
    }

    private static void Show(string text) =>
        Application.Current.Dispatcher.Invoke(() =>
            MessageBox.Show(text, App.Name, MessageBoxButton.OK, MessageBoxImage.Information));
}
