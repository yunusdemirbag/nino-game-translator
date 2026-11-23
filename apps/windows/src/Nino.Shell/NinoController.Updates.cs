// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Link;
using Nino.Core.Tv;

namespace Nino.Shell;

// "Güncellemeleri Denetle" (Hakkında): uygulama güncellemesini elle denetler ve eşli TV'deki Nino'nun sürümüne bakar.
// Denetim yalnız okur: TV'ye hiçbir şey kurmaz; kurulum yalnız "Yeni Sürümü Kur" (InstallTvUpdate) ile başlar ve TV
// uygulaması kartının olağan akışını (RecheckTvAppAsync) kullanır.
public sealed partial class NinoController
{
    AppUpdateState _manualUpdate = AppUpdateState.Idle;
    TvUpdateState _tvUpdate = TvUpdateState.None;
    bool _tvUpdateInstallDone;
    int _updateCheckGen;
    readonly Dictionary<long, string?> _tvAppVersions = [];

    /// <summary>Uygulama satırının durumu (indirme ve kendiliğinden bulunan sürüm de yansır).</summary>
    public AppUpdateState AppUpdate
    {
        get
        {
            if (_updating) return new AppUpdateState(AppUpdateKind.Downloading, _updateVersion, Math.Clamp(_updateProgress, 0, 1));
            if (_manualUpdate.Kind == AppUpdateKind.Checking) return _manualUpdate;
            if (_updateError is { } error) return new AppUpdateState(AppUpdateKind.Failed, _updateVersion, Error: error);
            if (_updateVersion is { } v) return new AppUpdateState(AppUpdateKind.Available, v);
            return _manualUpdate;
        }
    }

    /// <summary>TV satırının durumu (kurulum sürerken TV uygulaması kartına göre).</summary>
    public TvUpdateState TvUpdate => UpdateRules.Resolve(_tvUpdate, _tvApp, _tvUpdateInstallDone);

    /// <summary>Uygulama ya da TV satırı denetleniyor mu (düğme kapalı).</summary>
    public bool CheckingForUpdates => _manualUpdate.Kind == AppUpdateKind.Checking || _tvUpdate.Kind == TvUpdateKind.Checking;

    /// <summary>
    /// "Güncellemeleri Denetle": uygulamanın yeni sürümünü arar (hata "ulaşılamadı" olur; kendiliğinden kurmaz, kurulum
    /// <see cref="InstallUpdateAsync"/> ile) ve eşli TV'deki Nino'nun sürümüne bakar. İkisi birlikte yürür.
    /// </summary>
    public async Task CheckForUpdatesNowAsync(CancellationToken cancellationToken = default)
    {
        if (CheckingForUpdates || _updating) return;
        var gen = ++_updateCheckGen;
        var app = CheckAppUpdateNowAsync(gen, cancellationToken);
        var tv = CheckTvUpdateAsync(gen, cancellationToken);
        await Task.WhenAll(app, tv).ConfigureAwait(false);
        await OnUi();
    }

    async Task CheckAppUpdateNowAsync(int gen, CancellationToken cancellationToken)
    {
        if (_services.Updater is not { } updater) return;
        _manualUpdate = new AppUpdateState(AppUpdateKind.Checking);
        _updateError = null;
        Refresh();
        AppUpdateState result;
        try
        {
            var version = await updater.FindNewerAsync(cancellationToken).ConfigureAwait(false);
            await OnUi();
            _updateVersion = version;
            result = version is null ? new AppUpdateState(AppUpdateKind.UpToDate) : new AppUpdateState(AppUpdateKind.Available, version);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await OnUi();
            result = AppUpdateState.Idle;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("Güncelleme denetlenemedi", e);
            result = new AppUpdateState(AppUpdateKind.Failed);
        }
        if (gen == _updateCheckGen) _manualUpdate = result;
        Refresh();
    }

    async Task CheckTvUpdateAsync(int gen, CancellationToken cancellationToken)
    {
        if (_tv is not { } tv || BundledTvVersion(tv.Brand) is not { } bundled)
        {
            _tvUpdate = TvUpdateState.None;
            Refresh();
            return;
        }
        _tvUpdate = new TvUpdateState(TvUpdateKind.Checking, Bundled: bundled);
        _tvUpdateInstallDone = false;
        Refresh();
        var connected = _tvAppVersions.Values.ToList();
        var known = _tvApp.Kind == TvAppKind.UpToDate && _tvApp.Version is { Length: > 0 } card
            ? card
            : tv.Brand == TvBrand.Lg ? null : _secrets.Get<string>(SecretKeys.TvAppVersion);
        var on = false;
        if (connected.Count == 0 && tv.Host.Length > 0)
        {
            try { on = await _services.TvAwakeAsync(tv, cancellationToken).ConfigureAwait(false); }
            catch (Exception) { on = false; }
            await OnUi();
        }
        if (gen != _updateCheckGen || _tv is null) return;
        _tvUpdate = UpdateRules.DecideTv(true, bundled, connected, known, on);
        Refresh();
    }

    string? BundledTvVersion(TvBrand brand) =>
        brand == TvBrand.Lg ? _services.LgPackageVersion : _services.PackageFor(brand)?.Version;

    /// <summary>
    /// "Yeni Sürümü Kur": TV uygulaması kartının kur/yenile akışı (TV'deki sürüm eskiyse kurar). İlerleme ve sonuç
    /// <see cref="TvUpdate"/>'ten okunur; kart parola, onay ya da giriş beklerse durum "ayarlarda sürer" olur.
    /// </summary>
    public async Task InstallTvUpdateAsync()
    {
        if (_tvUpdate.Kind != TvUpdateKind.Outdated) return;
        _tvUpdate = _tvUpdate with { Kind = TvUpdateKind.Installing };
        _tvUpdateInstallDone = false;
        Refresh();
        try { await RecheckTvAppAsync().ConfigureAwait(false); }
        finally
        {
            await OnUi();
            _tvUpdateInstallDone = true;
            Refresh();
        }
    }

    /// <summary>TV bağlantısı kuruldu: bildirdiği uygulama sürümü (8787'de yok) güncelleme denetimi için saklanır.</summary>
    void NoteTvLinkUp(TvLinkConnected e) => _tvAppVersions[e.Id] = e.AppVersion;

    /// <summary>TV bağlantısı bitti.</summary>
    void NoteTvLinkDown(TvLinkDropped e) => _tvAppVersions.Remove(e.Id);
}
