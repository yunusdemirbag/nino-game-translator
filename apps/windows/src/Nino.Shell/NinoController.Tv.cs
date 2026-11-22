// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Tv;
using Nino.Shell.Platform;
using Nino.TvInstall;

namespace Nino.Shell;

// TV arama ve eşleşme (§6.9), TV uygulaması kartının durum makinesi (§8; tv-kurulum.md §5).
public sealed partial class NinoController
{
    IReadOnlyList<FoundTv> _foundTvs = [];
    bool _searchingTvs;
    bool _pairingTv;
    string? _tvPairError;
    TvAppStatus _tvApp = TvAppStatus.Unknown;
    bool _tvLaunchFailed;
    bool _tvCheckRunning;
    bool _samsungCheckRunning;
    int? _lgHoursLeft;
    IDisposable? _tvAppTimer;

    /// <summary>Bulunan TV'ler.</summary>
    public IReadOnlyList<FoundTv> FoundTvs => _foundTvs;

    /// <summary>TV aranıyor mu.</summary>
    public bool SearchingTvs => _searchingTvs;

    /// <summary>TV eşleşmesi sürüyor mu.</summary>
    public bool PairingTv => _pairingTv;

    /// <summary>TV eşleşmesinin hatası (ekran <see cref="TvException"/> türünü kendi metnine çevirir).</summary>
    public string? TvPairError => _tvPairError;

    /// <summary>TV uygulaması kartının durumu.</summary>
    public TvAppStatus TvApp => _tvApp;

    /// <summary>LG geliştirici modunun kalan saati (biliniyorsa).</summary>
    public int? LgHoursLeft => _lgHoursLeft;

    /// <summary>Son eşleşme denemesinde TV'deki uygulama başlatılamadıysa true.</summary>
    public bool TvAppLaunchFailed => _tvLaunchFailed;

    /// <summary>Nino bu TV'ye uygulamayı kurabilir mi.</summary>
    public bool CanInstallTvApp => _tv is { } tv && (tv.Brand == TvBrand.Lg
        ? _services.LgPackageVersion is not null
        : _services.PackageFor(tv.Brand) is not null);

    // ---- Arama ve eşleşme ----

    /// <summary>TV arar (LG + Samsung).</summary>
    public async Task SearchTvsAsync(CancellationToken cancellationToken = default)
    {
        if (_searchingTvs) return;
        _searchingTvs = true;
        Refresh();
        try
        {
            var found = await _services.FindTvsAsync(cancellationToken).ConfigureAwait(false);
            await OnUi();
            _foundTvs = found;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("TV araması hata verdi", e);
            _foundTvs = [];
        }
        finally
        {
            _searchingTvs = false;
            Refresh();
        }
    }

    /// <summary>Bulunan TV ile eşleşir.</summary>
    public Task<bool> PairTvAsync(FoundTv tv, CancellationToken cancellationToken = default) =>
        PairTvAsync(new TvRecord(tv.Name, tv.Host, tv.Brand), cancellationToken);

    /// <summary>TV ile eşleşir (§6.9). Başarıda true.</summary>
    public async Task<bool> PairTvAsync(TvRecord tv, CancellationToken cancellationToken = default)
    {
        if (_pairingTv) return false;
        _pairingTv = true;
        _tvPairError = null;
        Refresh();
        try
        {
            try { await _server.StartAsync(cancellationToken).ConfigureAwait(false); }
            catch (Exception e) { _logs.Subtitle("altyazı sunucusu açılamadı: " + e.Message); }
            await OnUi();
            var saved = _secrets.Get<string>(SecretKeys.TvKey);
            var parameters = _server.LaunchParameters(_services.AddressNear(tv.Host));
            var result = await _services.PairTvAsync(tv, saved, parameters, cancellationToken).ConfigureAwait(false);
            await OnUi();
            if (_tv is { } old && (old.Brand != tv.Brand || (tv.Brand != TvBrand.AndroidTv && old.Host != tv.Host)))
                _secrets.Remove(SecretKeys.TvAppVersion);
            SaveTv(tv);
            _secrets.Set(SecretKeys.TvKey, TvRecord.KeyToStore(saved, result.Key));
            _tvLaunchFailed = !result.Launched;
            _tvApp = TvAppStatus.Unknown;
            if (_settings.Output == SubtitleOutput.Computer) ChangeSettings(s => s.Output = SubtitleOutput.Tv);
            _server.SendToTv = ShowsOnTv;
            Refresh();
            if (tv.Brand == TvBrand.Lg) await RecheckTvAppAsync().ConfigureAwait(false);
            else Background(RecheckTvAppAsync);
            await OnUi();
            return true;
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            await OnUi();
            _tvPairError = e is TvException te ? te.Error.ToString() : e.Message;
            _logs.Error("TV ile eşleşilemedi", e);
            return false;
        }
        finally
        {
            _pairingTv = false;
            Refresh();
        }
    }

    // ---- TV uygulaması durumu ----

    void SetTvApp(TvAppStatus status)
    {
        _tvApp = status;
        var poll = status.Kind == TvAppKind.DevModeOff
            || (status.Kind == TvAppKind.Failed && status.Error == TvError.HostPcMismatch);
        if (poll && _tvAppTimer is null)
            _tvAppTimer = _timers.Every(TimeSpan.FromSeconds(3), () => Post(() => Background(RecheckTvAppAsync)));
        else if (!poll && _tvAppTimer is not null)
        {
            _tvAppTimer.Dispose();
            _tvAppTimer = null;
        }
        Refresh();
    }

    /// <summary>TV uygulamasını yeniden denetler (aynı anda iki kez çalışmaz). "Tekrar dene" de bunu çağırır.</summary>
    public async Task RecheckTvAppAsync()
    {
        if (_tvCheckRunning || _tv is not { } tv) return;
        _tvCheckRunning = true;
        try
        {
            switch (tv.Brand)
            {
                case TvBrand.Lg: await CheckLgAsync(tv).ConfigureAwait(false); break;
                case TvBrand.Samsung: await CheckSamsungAsync(tv).ConfigureAwait(false); break;
                default: await CheckAndroidAsync(tv).ConfigureAwait(false); break;
            }
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("TV uygulaması denetlenemedi", e);
        }
        finally
        {
            await OnUi();
            _tvCheckRunning = false;
            Refresh();
        }
    }

    // ---- LG (§8.1) ----

    async Task CheckLgAsync(TvRecord tv)
    {
        if (_services.LgPackageVersion is null) return;
        var open = await _services.LgDevModeOpenAsync(tv.Host).ConfigureAwait(false);
        await OnUi();
        if (_tvApp.Kind == TvAppKind.Installing) return;
        if (!open)
        {
            SetTvApp(_tvLaunchFailed ? new TvAppStatus(TvAppKind.DevModeOff) : TvAppStatus.Unknown);
            return;
        }
        if (_secrets.Get<string>(SecretKeys.TvDevKey) is not { Length: > 0 } key)
        {
            SetTvApp(_tvLaunchFailed ? new TvAppStatus(TvAppKind.PassphraseNeeded) : TvAppStatus.Unknown);
            return;
        }
        await InstallLgAsync(tv, key).ConfigureAwait(false);
    }

    /// <summary>LG: TV parolasıyla anahtar alıp kurar ("TV'ye Kur").</summary>
    public async Task InstallLgWithPassphraseAsync(string passphrase)
    {
        if (_tv is not { Brand: TvBrand.Lg } tv || string.IsNullOrWhiteSpace(passphrase)) return;
        SetTvApp(new TvAppStatus(TvAppKind.Installing));
        string key;
        try
        {
            key = await _services.LgFetchKeyAsync(tv.Host, passphrase.Trim()).ConfigureAwait(false);
            await OnUi();
        }
        catch (TvException e)
        {
            await OnUi();
            SetTvApp(new TvAppStatus(TvAppKind.PassphraseNeeded, Error: e.Error));
            return;
        }
        catch (Exception e)
        {
            await OnUi();
            SetTvApp(new TvAppStatus(TvAppKind.PassphraseNeeded, Error: TvError.KeyServerClosed, Reason: e.Message));
            return;
        }
        _secrets.Set(SecretKeys.TvDevKey, key);
        await InstallLgAsync(tv, key).ConfigureAwait(false);
    }

    async Task InstallLgAsync(TvRecord tv, string key)
    {
        SetTvApp(new TvAppStatus(TvAppKind.Installing));
        var package = _services.LgPackageVersion!;
        try
        {
            var installed = await _services.LgInstalledVersionAsync(tv.Host, key).ConfigureAwait(false);
            await OnUi();
            if (installed is not null && !TvVersions.IsNewerStrict(package, installed))
            {
                SetTvApp(new TvAppStatus(TvAppKind.UpToDate, installed));
                await RenewLgAsync(tv, key).ConfigureAwait(false);
                return;
            }
            await _services.LgInstallAsync(tv.Host, key).ConfigureAwait(false);
            await OnUi();
            SetTvApp(new TvAppStatus(TvAppKind.UpToDate, package));
            _tvLaunchFailed = false;
            await RenewLgAsync(tv, key).ConfigureAwait(false);
            await OpenTvAppAsync(tv).ConfigureAwait(false);
        }
        catch (TvException e)
        {
            await OnUi();
            if (e.Error == TvError.KeyRejected)
            {
                _secrets.Remove(SecretKeys.TvDevKey);
                SetTvApp(new TvAppStatus(TvAppKind.PassphraseNeeded));
            }
            else SetTvApp(new TvAppStatus(TvAppKind.Failed, Error: e.Error, Reason: ReasonFor(e)));
        }
        catch (Exception e)
        {
            await OnUi();
            SetTvApp(UnexpectedFailure(e));
        }
    }

    TvAppStatus UnexpectedFailure(Exception e)
    {
        _logs.Error("TV uygulaması kurulamadı", e);
        return new TvAppStatus(TvAppKind.Failed, Error: TvError.InstallFailed, Reason: e.Message);
    }

    static string? ReasonFor(TvException e) =>
        e.Error is TvError.InstallFailed or TvError.NotEnoughSpace && e.Detail.Trim() is { Length: > 0 } d ? d : null;

    async Task RenewLgAsync(TvRecord tv, string key)
    {
        var name = SecretKeys.DevSessionRenewed(tv.Host);
        DateTimeOffset? last = _secrets.TryGet<DateTimeOffset>(name, out var at) ? at : null;
        var now = _timers.Now;
        if (!LgDevSession.IsDue(last, now)) return;
        try
        {
            var hours = await _services.LgRenewDevModeAsync(tv.Host, key).ConfigureAwait(false);
            await OnUi();
            _lgHoursLeft = hours;
            _secrets.Set(name, now);
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("LG geliştirici modu uzatılamadı", e);
        }
    }

    async Task OpenTvAppAsync(TvRecord tv)
    {
        if (_watch is { } watch)
        {
            watch.ReconnectNow();
            return;
        }
        try
        {
            await _services.PairTvAsync(tv, _secrets.Get<string>(SecretKeys.TvKey),
                _server.LaunchParameters(_services.AddressNear(tv.Host))).ConfigureAwait(false);
        }
        catch (Exception) { }
        await OnUi();
    }

    // ---- Samsung (§8.2) ----

    bool RememberedUpToDate(TvAppPackage package) =>
        _secrets.Get<string>(SecretKeys.TvAppVersion) is { Length: > 0 } v && !TvVersions.IsNewerStrict(package.Version, v);

    async Task CheckSamsungAsync(TvRecord tv)
    {
        if (_services.PackageFor(TvBrand.Samsung) is not { } package) return;
        var remembered = RememberedUpToDate(package);
        var stored = _secrets.Get<string>(SecretKeys.TvAppVersion);
        var pre = await _services.SamsungPrecheckAsync(tv.Host).ConfigureAwait(false);
        var gateOpen = pre.Info.DeveloperMode != false && await _services.SamsungDevModeOpenAsync(tv.Host).ConfigureAwait(false);
        await OnUi();
        if (!gateOpen)
        {
            SetTvApp(remembered ? new TvAppStatus(TvAppKind.UpToDate, stored ?? package.Version) : new TvAppStatus(TvAppKind.DevModeOff));
            return;
        }
        if (Nino.TvInstall.Samsung.SamsungDeviceInfo.IsHostPcMismatch(pre.Info.DeveloperIp, pre.ThisComputer))
        {
            SetTvApp(remembered ? new TvAppStatus(TvAppKind.UpToDate, stored ?? package.Version)
                : new TvAppStatus(TvAppKind.Failed, Error: TvError.HostPcMismatch, TvHostPcIp: pre.Info.DeveloperIp,
                    ThisComputer: pre.ThisComputer));
            return;
        }
        SetTvApp(remembered ? new TvAppStatus(TvAppKind.UpToDate, stored ?? package.Version) : new TvAppStatus(TvAppKind.Installing));
        _samsungCheckRunning = true;
        try
        {
            var result = await _services.SamsungInstallAsync(tv.Host, InstallEvents()).ConfigureAwait(false);
            await OnUi();
            var version = result.Version.Length > 0 ? result.Version : package.Version;
            _secrets.Set(SecretKeys.TvAppVersion, version);
            SetTvApp(new TvAppStatus(TvAppKind.UpToDate, version));
            if (result.Installed) await OpenTvAppAsync(tv).ConfigureAwait(false);
        }
        catch (TvException e)
        {
            await OnUi();
            if (e.Error == TvError.Unreachable && remembered) SetTvApp(new TvAppStatus(TvAppKind.UpToDate, stored ?? package.Version));
            else SetTvApp(new TvAppStatus(TvAppKind.Failed, Error: e.Error, Reason: e.Detail.Trim() is { Length: > 0 } d ? d : null));
        }
        catch (Exception e)
        {
            await OnUi();
            SetTvApp(UnexpectedFailure(e));
        }
        finally
        {
            await OnUi();
            _samsungCheckRunning = false;
        }
    }

    // ---- Android TV (§8.3) ----

    async Task CheckAndroidAsync(TvRecord tv)
    {
        if (_services.PackageFor(TvBrand.AndroidTv) is not { } package) return;
        var needed = !RememberedUpToDate(package);
        var host = tv.Host;
        var reachable = host.Length > 0 && await _services.AndroidAdbOpenAsync(host).ConfigureAwait(false);
        await OnUi();
        if (!reachable)
        {
            if (!needed)
            {
                SetTvApp(new TvAppStatus(TvAppKind.UpToDate, _secrets.Get<string>(SecretKeys.TvAppVersion)));
                return;
            }
            var found = await _services.AndroidScanAsync().ConfigureAwait(false);
            await OnUi();
            if (found.Count == 0)
            {
                SetTvApp(new TvAppStatus(TvAppKind.DevModeOff));
                return;
            }
            host = found[0];
        }
        SetTvApp(new TvAppStatus(TvAppKind.Installing));
        try
        {
            var result = await _services.AndroidInstallAsync(host, InstallEvents()).ConfigureAwait(false);
            await OnUi();
            if (_tv is { } current) SaveTv(current with { Host = host });
            var version = result.Version.Length > 0 ? result.Version : package.Version;
            _secrets.Set(SecretKeys.TvAppVersion, version);
            SetTvApp(new TvAppStatus(TvAppKind.UpToDate, version));
        }
        catch (TvException e)
        {
            await OnUi();
            SetTvApp(new TvAppStatus(TvAppKind.Failed, Error: e.Error, Reason: ReasonFor(e)));
        }
        catch (Exception e)
        {
            await OnUi();
            SetTvApp(UnexpectedFailure(e));
        }
    }

    // ---- Kurulum olayları (§8.4) ----

    TvInstallEvents InstallEvents() => new(
        url => Post(() =>
        {
            if (!AcceptsInstallEvent()) return;
            SetTvApp(_tvApp with { Kind = TvAppKind.SamsungSignIn, SignInUrl = url });
            _browser.Open(url);
        }),
        () => Post(() =>
        {
            if (AcceptsInstallEvent()) SetTvApp(new TvAppStatus(TvAppKind.ConfirmOnTv));
        }),
        step => Post(() =>
        {
            if (!AcceptsInstallEvent()) return;
            if (_tvApp.Kind == TvAppKind.SamsungSignIn) SetTvApp(new TvAppStatus(TvAppKind.Installing));
            else if (_tvApp.Kind != TvAppKind.Installing
                && step is "signin" or "certificate" or "signing" or "installing" or "uninstalling")
                SetTvApp(new TvAppStatus(TvAppKind.Installing));
        }));

    bool AcceptsInstallEvent() => _samsungCheckRunning
        || _tvApp.Kind is TvAppKind.Installing or TvAppKind.SamsungSignIn or TvAppKind.ConfirmOnTv;

    /// <summary>Samsung giriş sayfasını yeniden açar.</summary>
    public void ReopenSamsungSignIn()
    {
        if (_tvApp.SignInUrl is { } url) _browser.Open(url);
    }
}
