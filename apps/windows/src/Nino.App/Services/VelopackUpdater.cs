// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;
using Velopack;
using Velopack.Sources;

namespace Nino.App.Services;

/// <summary>
/// Uygulama güncelleyicisi (kimlikler-veri §10): kurulumla gelen kopya Velopack'in GitHub kaynağıyla (ön sürümler
/// hariç, jeton yok) kendini günceller; zip kopyası yalnız GitHub'ın "son sürüm" adresini okur ve indirme sayfasını
/// gösterir. Deneme sayacı ve akış denetleyicidedir.
/// </summary>
public sealed class VelopackUpdater : IAppUpdater
{
    readonly HttpClient _http;
    readonly string _currentVersion;
    readonly UpdateManager? _manager;
    UpdateInfo? _pending;

    /// <param name="http">Paylaşılan HTTP istemcisi (zip kopyasının sorusu için).</param>
    /// <param name="currentVersion">Nino'nun sürümü.</param>
    public VelopackUpdater(HttpClient http, string currentVersion)
    {
        _http = http;
        _currentVersion = currentVersion;
        try
        {
            var manager = new UpdateManager(new GithubSource(UpdateSource.Repository, null, false));
            if (manager.IsInstalled) _manager = manager;
        }
        catch (Exception)
        {
            _manager = null;
        }
    }

    /// <inheritdoc />
    public bool CanSelfUpdate => _manager is not null;

    /// <inheritdoc />
    public string DownloadPage => UpdateSource.ReleasesPage;

    /// <inheritdoc />
    public async Task<string?> FindNewerAsync(CancellationToken cancellationToken = default)
    {
        if (_manager is { } manager)
        {
            var info = await manager.CheckForUpdatesAsync().ConfigureAwait(false);
            _pending = info;
            return info?.TargetFullRelease.Version.ToString();
        }
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, UpdateSource.LatestApi);
            request.Headers.UserAgent.Add(new ProductInfoHeaderValue(UpdateSource.UserAgent, null));
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(UpdateSource.Timeout);
            using var response = await _http.SendAsync(request, timeout.Token).ConfigureAwait(false);
            if (response.StatusCode != System.Net.HttpStatusCode.OK) return null;
            var json = await response.Content.ReadAsStringAsync(timeout.Token).ConfigureAwait(false);
            return UpdateSource.NewerFromLatestJson(json, _currentVersion);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException)
        {
            return null;
        }
    }

    /// <inheritdoc />
    public async Task DownloadAndInstallAsync(IProgress<double> progress, Action beforeInstall, CancellationToken cancellationToken = default)
    {
        if (_manager is not { } manager) throw new InvalidOperationException("Bu kopya kendini güncelleyemiyor.");
        var info = _pending ?? await manager.CheckForUpdatesAsync().ConfigureAwait(false)
            ?? throw new InvalidOperationException("Yeni sürüm bulunamadı.");
        await manager.DownloadUpdatesAsync(info, p => progress.Report(Math.Clamp(p / 100.0, 0, 1)), cancellationToken)
            .ConfigureAwait(false);
        if (cancellationToken.IsCancellationRequested) throw new OperationCanceledException(cancellationToken);
        beforeInstall();
        manager.ApplyUpdatesAndRestart(info.TargetFullRelease);
    }
}
