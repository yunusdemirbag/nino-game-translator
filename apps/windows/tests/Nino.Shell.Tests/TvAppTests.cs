// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Tv;
using Nino.Shell.Platform;
using Nino.TvInstall;
using Nino.TvInstall.Samsung;

namespace Nino.Shell.Tests;

// Tarif §20, TV uygulaması senaryoları 35–38.
public sealed class TvAppTests
{
    static World Lg()
    {
        var w = new World().WithPs5().WithTv();
        w.Services.Model.Installed = true;
        return w;
    }

    [Fact] // 35a
    public async Task LgDevModeClosedAndPassphrase()
    {
        var w = Lg();
        w.Services.PairLaunched = false;
        var c = w.Open();
        await c.PairTvAsync(w.Services.FoundTv);
        Assert.Equal(TvAppKind.DevModeOff, c.TvApp.Kind);
        Assert.True(c.CanInstallTvApp);

        w.Services.LgDevOpen = true;
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.PassphraseNeeded, c.TvApp.Kind);

        var pairsBefore = w.Services.Pairs;
        w.Services.LgOnTv = null;
        await c.InstallLgWithPassphraseAsync(" ABC123 ");
        Assert.Equal(new TvAppStatus(TvAppKind.UpToDate, "0.6.1"), c.TvApp);
        Assert.Equal(1, w.Services.LgInstalls);
        Assert.Equal("dev-key", w.Secrets.Get<string>(SecretKeys.TvDevKey));
        Assert.Equal(pairsBefore + 1, w.Services.Pairs);
        Assert.Equal(999, c.LgHoursLeft);
    }

    [Fact] // 35b
    public async Task LgPassphraseErrors()
    {
        var w = Lg();
        var c = w.Open();
        await c.InstallLgWithPassphraseAsync("nope");
        Assert.Equal(TvAppKind.PassphraseNeeded, c.TvApp.Kind);
        Assert.Equal(TvError.WrongPassphrase, c.TvApp.Error);
        w.Services.LgKeyError = TvError.KeyServerClosed;
        await c.InstallLgWithPassphraseAsync("ABC123");
        Assert.Equal(TvError.KeyServerClosed, c.TvApp.Error);
        Assert.Equal(0, w.Services.LgInstalls);
    }

    [Fact] // 35c
    public async Task LgOldVersionInstallsCurrentDoesNotKeyRejectedAndRenewOncePerDay()
    {
        var w = Lg();
        w.Services.LgDevOpen = true;
        w.Secrets.Set(SecretKeys.TvDevKey, "dev-key");
        w.Services.LgOnTv = "0.4.0";
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(1, w.Services.LgInstalls);
        Assert.Equal("0.6.1", c.TvApp.Version);
        await c.RecheckTvAppAsync();
        Assert.Equal(1, w.Services.LgInstalls);
        Assert.Equal(1, w.Services.Renewals);

        w.Services.LgKeyRejected = true;
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.PassphraseNeeded, c.TvApp.Kind);
        Assert.False(w.Secrets.Contains(SecretKeys.TvDevKey));
    }

    [Fact] // 35d
    public async Task LgRunningAppWithoutKeyIsUnknownAndSamsungNotViaLg()
    {
        var w = Lg();
        w.Services.LgDevOpen = true;
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.Unknown, c.TvApp.Kind);

        var w2 = new World().WithTv(StoredTvBrand.Samsung, "k", "192.168.1.60", "Samsung");
        w2.Services.LgDevOpen = true;
        var c2 = w2.Open();
        await c2.RecheckTvAppAsync();
        Assert.Equal(0, w2.Services.LgInstalls);
        Assert.Equal(TvAppKind.Unknown, c2.TvApp.Kind);
    }

    static World Samsung()
    {
        var w = new World().WithTv(StoredTvBrand.Samsung, "samsung-token", "192.168.1.60", "Samsung");
        w.Services.SamsungPackage = new TvAppPackage("/tv-app/nino.wgt", "0.7.0");
        w.Services.SamsungInstall = _ => new TvInstallResult("0.7.0", true);
        return w;
    }

    [Fact] // 36a
    public async Task SamsungDevModeOffThenSignInAndInstall()
    {
        var w = Samsung();
        w.Services.SamsungGate = false;
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.DevModeOff, c.TvApp.Kind);
        Assert.True(c.CanInstallTvApp);

        w.Services.SamsungGate = true;
        w.Services.SamsungInstall = events =>
        {
            events.SignInWaiting("https://account.samsung.com/signin");
            return new TvInstallResult("0.7.0", true);
        };
        await c.RecheckTvAppAsync();
        Assert.Contains("https://account.samsung.com/signin", w.Browser.Opened);
        Assert.Equal(new TvAppStatus(TvAppKind.UpToDate, "0.7.0"), c.TvApp);
        Assert.Equal("0.7.0", w.Secrets.Get<string>(SecretKeys.TvAppVersion));
        w.Timers.Advance(TimeSpan.FromSeconds(10));
        await c.WhenIdleAsync();
        Assert.Equal(1, w.Services.SamsungInstalls);
    }

    [Fact] // 36b
    public async Task SamsungRememberedButStillAskedToInstall()
    {
        var w = Samsung();
        w.Secrets.Set(SecretKeys.TvAppVersion, "0.7.0");
        w.Services.SamsungInstall = _ => new TvInstallResult("0.7.0", false);
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(1, w.Services.SamsungInstalls);
        Assert.Equal("0.7.0", c.TvApp.Version);
        Assert.Equal("0.7.0", w.Secrets.Get<string>(SecretKeys.TvAppVersion));
    }

    [Fact] // 36c
    public async Task SamsungUnreachable()
    {
        var w = Samsung();
        w.Secrets.Set(SecretKeys.TvAppVersion, "0.7.0");
        w.Services.SamsungInstall = _ => throw new TvException(TvError.Unreachable, "sdb: closed");
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.UpToDate, c.TvApp.Kind);

        w.Secrets.Remove(SecretKeys.TvAppVersion);
        c = w.Open(); // depoya denetleyicinin dışından yazıldı: yeniden açılış
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.Failed, c.TvApp.Kind);
        Assert.Equal(TvError.Unreachable, c.TvApp.Error);
        Assert.Equal("sdb: closed", c.TvApp.Reason);
    }

    [Fact] // 36d
    public async Task SamsungHostPcMismatch()
    {
        var w = Samsung();
        w.Services.Precheck = new SamsungPrecheck(new SamsungDeviceInfo(true, "192.168.1.50"), "192.168.1.34");
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(0, w.Services.SamsungInstalls);
        Assert.Equal(TvError.HostPcMismatch, c.TvApp.Error);
        Assert.Equal("192.168.1.50", c.TvApp.TvHostPcIp);
        Assert.Equal("192.168.1.34", c.TvApp.ThisComputer);
        w.Services.Precheck = new SamsungPrecheck(new SamsungDeviceInfo(true, "192.168.1.34"), "192.168.1.34");
        w.Timers.Advance(TimeSpan.FromSeconds(3));
        await c.WhenIdleAsync();
        Assert.Equal(1, w.Services.SamsungInstalls);
        Assert.Equal(TvAppKind.UpToDate, c.TvApp.Kind);
    }

    [Fact] // 36e
    public async Task SamsungPort8001SaysClosedAndFailures()
    {
        var w = Samsung();
        w.Services.Precheck = new SamsungPrecheck(new SamsungDeviceInfo(false, null), "192.168.1.34");
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.DevModeOff, c.TvApp.Kind);

        w.Services.Precheck = SamsungPrecheck.Unknown;
        w.Services.SamsungInstall = _ => throw new TvException(TvError.PackageBlocked, "app_id[NinoTVApps.Nino] install failed[118, -22]");
        await c.RecheckTvAppAsync();
        Assert.Equal("app_id[NinoTVApps.Nino] install failed[118, -22]", c.TvApp.Reason);
        w.Services.SamsungInstall = _ => throw new TvException(TvError.LoginFailed, "Samsung hesabına giriş zamanında bitmedi");
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.Failed, c.TvApp.Kind);
        Assert.Equal("Samsung hesabına giriş zamanında bitmedi", c.TvApp.Reason);
    }

    [Fact] // 37
    public async Task AndroidTvFoundOnNetwork()
    {
        var w = new World().WithTv(StoredTvBrand.AndroidTv, "", "", "Android TV");
        w.Services.AndroidPackage = new TvAppPackage("/tv-app/nino.apk", "0.7.0");
        var c = w.Open();
        await c.RecheckTvAppAsync();
        Assert.Equal(TvAppKind.DevModeOff, c.TvApp.Kind);
        w.Services.AdbScan = ["192.168.1.40"];
        var sawConfirm = false;
        w.Services.AndroidInstall = (host, events) =>
        {
            events.ApprovalWaiting();
            sawConfirm = c.TvApp.Kind == TvAppKind.ConfirmOnTv;
            return new TvInstallResult("0.7.0", true);
        };
        await c.RecheckTvAppAsync();
        Assert.True(sawConfirm);
        Assert.Equal(new TvAppStatus(TvAppKind.UpToDate, "0.7.0"), c.TvApp);
        Assert.Equal("192.168.1.40", c.Tv!.Host);
        Assert.Equal("192.168.1.40", w.Secrets.Get<StoredTv>(SecretKeys.Tv)!.Host);
    }

    [Fact] // 38
    public async Task TvMovedIsSaved()
    {
        var w = Lg();
        var c = w.Open();
        await c.StartAsync();
        w.Services.Watches[0].Request.Moved(new TvRecord("LG TV", "192.168.1.230", TvBrand.Lg));
        Assert.Equal("192.168.1.230", c.Tv!.Host);
        Assert.Equal("192.168.1.230", w.Secrets.Get<StoredTv>(SecretKeys.Tv)!.Host);
    }

    [Fact]
    public async Task LateInstallEventDoesNotOverrideResult()
    {
        var w = Samsung();
        TvInstallEvents? saved = null;
        w.Services.SamsungInstall = e =>
        {
            saved = e;
            return new TvInstallResult("0.7.0", true);
        };
        var c = w.Open();
        await c.RecheckTvAppAsync();
        saved!.Progress("installing");
        Assert.Equal(TvAppKind.UpToDate, c.TvApp.Kind);
    }
}
