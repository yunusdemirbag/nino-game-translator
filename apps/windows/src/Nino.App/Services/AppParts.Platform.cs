// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.App.Services;
using Nino.App.Views;
using Nino.Core.Data;
using Nino.Shell.Platform;

namespace Nino.App.Startup;

// Açılışın "Windows hizmetleri" parçası: WindowsPlatform.Create, açılışın açtığı günlüklerle.
public static partial class AppParts
{
    static partial void CreatePlatform(string dataFolder, Action<Action> post, ref PlatformPieces? pieces)
    {
        var logs = AppLogs.Current;
        var parts = WindowsPlatform.Create(dataFolder, post, new WindowsPlatformOptions
        {
            RemotePlayLog = logs?.RemotePlay,
            Errors = logs?.Errors,
            Subtitles = logs?.Subtitles,
            TvInstall = logs?.TvInstall,
            Dispatcher = Application.Current?.Dispatcher,
        });
        Platform = parts;
        // Ayarlardaki HDMI yakalama kartı aygıt listesi (önizleme denetimi beklemeden okur).
        CaptureCardDevices.Start(line =>
        {
            try { logs?.Errors.Write(line); } catch (Exception) { }
        });
        pieces = new PlatformPieces(parts.Services, parts.Secrets, parts.Settings, parts.Sleep);
    }

    static partial void CreatePsnSignInWindow(ref IPsnSignInWindow? window)
    {
        var logs = AppLogs.Current;
        var folder = logs?.Folder ?? NinoDataFolder.Current.Path;
        window = new PsnSignInHost(folder, logs is null ? null : line => logs.RemotePlay.Nino(line));
    }

    /// <summary>Son kurulan Windows parçaları (zamanlayıcılar, kısayollar, uyanma bildirimi için); kurulmadıysa null.</summary>
    public static WindowsPlatformParts? Platform { get; private set; }
}
