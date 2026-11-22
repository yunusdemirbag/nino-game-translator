// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using Nino.Core.Logging;
using Nino.Shell.Platform;
using RpLog = Nino.RemotePlay.RemotePlayLog;

namespace Nino.App.Startup;

/// <summary>
/// Uygulamanın günlükleri (kimlikler-veri.md §8), açılışta bir kez açılır: <c>hata.log</c>, <c>altyazi.log</c>
/// (açılışta etkin) ve Remote Play tanılama günlüğü <c>remoteplay.log</c>. Her dosyanın tek yazanı vardır: Remote Play
/// günlüğü <see cref="RemotePlay"/> nesnesidir; Windows hizmetleri (<c>CoreShellServicesOptions.RemotePlayLog</c>)
/// yenisini açmadan bunu kullanmalıdır (<see cref="Current"/>).
/// </summary>
public sealed class AppLogs : IShellLogs, IDisposable
{
    AppLogs(string dataFolder)
    {
        Folder = dataFolder;
        Errors = new ErrorLog(Path.Combine(dataFolder, LogNames.Error));
        Subtitles = new SubtitleLog(Path.Combine(dataFolder, LogNames.Subtitle)) { Enabled = true };
        RemotePlay = new RpLog(Path.Combine(dataFolder, RpLog.FileName));
        TvInstall = new TvInstallLog(Path.Combine(dataFolder, LogNames.TvInstall));
    }

    /// <summary>Açılışta açılan günlükler (açılmadıysa null).</summary>
    public static AppLogs? Current { get; private set; }

    /// <summary>Veri klasörü.</summary>
    public string Folder { get; }

    /// <summary><c>hata.log</c>.</summary>
    public ErrorLog Errors { get; }

    /// <summary><c>altyazi.log</c>.</summary>
    public SubtitleLog Subtitles { get; }

    /// <summary><c>remoteplay.log</c> (yerel köprü satırları dahil; tek yazan).</summary>
    public RpLog RemotePlay { get; }

    /// <summary><c>tvinstall.log</c>.</summary>
    public TvInstallLog TvInstall { get; }

    /// <summary>Günlükleri açar (bir kez; ikinci çağrı aynı nesneyi verir).</summary>
    public static AppLogs Open(string dataFolder) => Current ??= new AppLogs(dataFolder);

    /// <inheritdoc />
    string? IShellLogs.RemotePlayLogPath => Path.Combine(Folder, RpLog.FileName);

    /// <inheritdoc />
    void IShellLogs.RemotePlay(string line) => RemotePlay.Nino(line);

    /// <inheritdoc />
    public void Subtitle(string line) => Subtitles.Write(line);

    /// <inheritdoc />
    public void Error(string message, Exception? error = null) => Errors.Write(message, error);

    /// <summary>Kapanışta bekleyen satırları yazar (en çok 2 sn) ve yazıcıları kapatır.</summary>
    public void Dispose()
    {
        try { Subtitles.Flush(TimeSpan.FromSeconds(2)); } catch (Exception) { }
        try { Subtitles.Dispose(); } catch (Exception) { }
        try { RemotePlay.Dispose(); } catch (Exception) { }
    }
}
