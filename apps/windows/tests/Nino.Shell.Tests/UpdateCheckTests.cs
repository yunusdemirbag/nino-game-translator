// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Link;
using Nino.Core.Support;
using Nino.Shell.Platform;
using Nino.TvInstall;

namespace Nino.Shell.Tests;

// Hakkında › "Güncellemeleri Denetle": uygulama (yeni / güncel / hata) × TV (yeni / güncel / yok) ve TV satırının
// saf kararı; denetim hiçbir şey kurmaz.
public sealed class UpdateCheckTests
{
    sealed class Updater : IAppUpdater
    {
        public string? Newer;
        public Exception? Error;
        public int Installs;
        public bool CanSelfUpdate => true;
        public string DownloadPage => "https://example.org/download";

        public Task<string?> FindNewerAsync(CancellationToken cancellationToken = default) =>
            Error is not null ? Task.FromException<string?>(Error) : Task.FromResult(Newer);

        public Task DownloadAndInstallAsync(IProgress<double> progress, Action beforeInstall, CancellationToken cancellationToken = default)
        {
            beforeInstall();
            Installs++;
            return Task.CompletedTask;
        }
    }

    public enum AppCase { Newer, Current, Error }

    public enum TvCase { Newer, Current, None }

    public static TheoryData<AppCase, TvCase> Matrix()
    {
        var data = new TheoryData<AppCase, TvCase>();
        foreach (var a in Enum.GetValues<AppCase>())
        foreach (var t in Enum.GetValues<TvCase>())
            data.Add(a, t);
        return data;
    }

    [Theory]
    [MemberData(nameof(Matrix))]
    public async Task AppAndTvMatrix(AppCase app, TvCase tv)
    {
        var w = new World().WithPs5();
        if (tv != TvCase.None) w.WithTv();
        var updater = new Updater
        {
            Newer = app == AppCase.Newer ? "9.9.9" : null,
            Error = app == AppCase.Error ? new HttpRequestException("ağ") : null,
        };
        w.Services.UpdaterService = updater;
        w.Services.LgPackage = "0.6.1";
        var c = w.Open();
        if (tv != TvCase.None) w.Services.Server.LinkUp(1, TvLinkKind.WebTv, appVersion: tv == TvCase.Newer ? "0.5.0" : "0.6.1");

        await c.CheckForUpdatesNowAsync();

        var expectedApp = app switch
        {
            AppCase.Newer => new AppUpdateState(AppUpdateKind.Available, "9.9.9"),
            AppCase.Current => new AppUpdateState(AppUpdateKind.UpToDate),
            _ => new AppUpdateState(AppUpdateKind.Failed),
        };
        Assert.Equal(expectedApp, c.AppUpdate);
        var expectedTv = tv switch
        {
            TvCase.Newer => new TvUpdateState(TvUpdateKind.Outdated, "0.5.0", "0.6.1"),
            TvCase.Current => new TvUpdateState(TvUpdateKind.UpToDate, "0.6.1", "0.6.1"),
            _ => TvUpdateState.None,
        };
        Assert.Equal(expectedTv, c.TvUpdate);
        Assert.False(c.CheckingForUpdates);

        // Denetim yalnız okur: hiçbir şey kurulmaz.
        Assert.Equal(0, updater.Installs);
        Assert.Equal(0, w.Services.LgInstalls);
        Assert.Equal(0, w.Services.SamsungInstalls);
    }

    [Fact]
    public async Task AvailableUpdateInstallsOnlyWhenAsked()
    {
        var w = new World().WithPs5();
        var updater = new Updater { Newer = "9.9.9" };
        w.Services.UpdaterService = updater;
        var c = w.Open();
        await c.CheckForUpdatesNowAsync();
        Assert.Equal(0, updater.Installs);
        await c.InstallUpdateAsync();
        Assert.Equal(1, updater.Installs);
    }

    [Fact]
    public async Task NoUpdaterLeavesAppRowIdle()
    {
        var w = new World().WithPs5();
        var c = w.Open();
        await c.CheckForUpdatesNowAsync();
        Assert.Equal(AppUpdateState.Idle, c.AppUpdate);
    }

    [Fact]
    public async Task TvOffOrAppClosedWithoutConnection()
    {
        var w = new World().WithPs5().WithTv();
        var c = w.Open();
        await c.CheckForUpdatesNowAsync();
        Assert.Equal(TvUpdateKind.Unreachable, c.TvUpdate.Kind);
        Assert.Equal(1, w.Services.TvAwakeCalls);

        w.Services.TvOn = true;
        await c.CheckForUpdatesNowAsync();
        Assert.Equal(TvUpdateKind.AppClosed, c.TvUpdate.Kind);
    }

    [Fact]
    public async Task DroppedLinkIsForgotten()
    {
        var w = new World().WithPs5().WithTv();
        var c = w.Open();
        w.Services.Server.LinkUp(7, TvLinkKind.WebTv, appVersion: "0.6.1");
        w.Services.Server.LinkDown(7, TvLinkKind.WebTv, TvLinkEndReason.Closed);
        await c.CheckForUpdatesNowAsync();
        Assert.Equal(TvUpdateKind.Unreachable, c.TvUpdate.Kind);
    }

    [Fact]
    public async Task InstallTvUpdateRunsTheCardFlow()
    {
        var w = new World().WithPs5().WithTv();
        w.Services.Model.Installed = true;
        w.Services.LgDevOpen = true;
        w.Secrets.Set(SecretKeys.TvDevKey, "dev-key");
        w.Services.LgOnTv = "0.4.0";
        var c = w.Open();
        w.Services.Server.LinkUp(1, TvLinkKind.WebTv, appVersion: "0.4.0");
        await c.CheckForUpdatesNowAsync();
        Assert.Equal(TvUpdateKind.Outdated, c.TvUpdate.Kind);
        Assert.Equal(0, w.Services.LgInstalls);

        await c.InstallTvUpdateAsync();
        Assert.Equal(1, w.Services.LgInstalls);
        Assert.Equal(new TvUpdateState(TvUpdateKind.UpToDate, "0.6.1", "0.6.1"), c.TvUpdate);
    }

    [Fact]
    public async Task InstallWaitingForPassphraseContinuesInSettings()
    {
        var w = new World().WithPs5().WithTv();
        w.Services.LgDevOpen = true;
        w.Services.PairLaunched = false;
        var c = w.Open();
        await c.PairTvAsync(w.Services.FoundTv);
        w.Services.Server.LinkUp(1, TvLinkKind.WebTv, appVersion: "0.4.0");
        await c.CheckForUpdatesNowAsync();
        await c.InstallTvUpdateAsync();
        Assert.Equal(TvAppKind.PassphraseNeeded, c.TvApp.Kind);
        Assert.Equal(TvUpdateKind.ContinueInSettings, c.TvUpdate.Kind);
    }

    // ---- Saf karar ----

    [Fact]
    public void DecideTvRules()
    {
        Assert.Equal(TvUpdateState.None, UpdateRules.DecideTv(false, "0.7.0", [], null, true));
        Assert.Equal(TvUpdateState.None, UpdateRules.DecideTv(true, null, ["0.1"], null, true));
        // Bağlı uygulamaların en yenisi.
        Assert.Equal(new TvUpdateState(TvUpdateKind.UpToDate, "0.7.0", "0.7.0"),
            UpdateRules.DecideTv(true, "0.7.0", ["0.6.0", "0.7.0", null], null, false));
        // Sürüm bildirmeyen bağlantı: bilinen sürüm yoksa eski, varsa ona göre.
        Assert.Equal(new TvUpdateState(TvUpdateKind.Outdated, "", "0.7.0"), UpdateRules.DecideTv(true, "0.7.0", [null], null, false));
        Assert.Equal(new TvUpdateState(TvUpdateKind.UpToDate, "0.7.0", "0.7.0"),
            UpdateRules.DecideTv(true, "0.7.0", [null], "0.7.0", false));
        // Bağlantı yok: TV kapalı / Nino kapalı / bilinen sürüm.
        Assert.Equal(TvUpdateKind.Unreachable, UpdateRules.DecideTv(true, "0.7.0", [], "0.7.0", false).Kind);
        Assert.Equal(TvUpdateKind.AppClosed, UpdateRules.DecideTv(true, "0.7.0", [], null, true).Kind);
        Assert.Equal(new TvUpdateState(TvUpdateKind.Outdated, "0.6.9", "0.7.0"), UpdateRules.DecideTv(true, "0.7.0", [], "0.6.9", true));
    }

    [Fact]
    public void ResolveFollowsTheCard()
    {
        var installing = new TvUpdateState(TvUpdateKind.Installing, "0.5.0", "0.7.0");
        Assert.Equal(installing, UpdateRules.Resolve(installing, new TvAppStatus(TvAppKind.UpToDate, "0.5.0"), installDone: false));
        Assert.Equal(installing, UpdateRules.Resolve(installing, new TvAppStatus(TvAppKind.Installing), installDone: true));
        Assert.Equal(TvUpdateKind.ContinueInSettings,
            UpdateRules.Resolve(installing, new TvAppStatus(TvAppKind.ConfirmOnTv), installDone: false).Kind);
        Assert.Equal(new TvUpdateState(TvUpdateKind.UpToDate, "0.7.0", "0.7.0"),
            UpdateRules.Resolve(installing, new TvAppStatus(TvAppKind.UpToDate, "0.7.0"), installDone: true));
        var outdated = installing with { Kind = TvUpdateKind.Outdated };
        Assert.Equal(outdated, UpdateRules.Resolve(outdated, TvAppStatus.Unknown, false));
    }

    [Fact]
    public void VersionTexts()
    {
        Assert.Equal("V4.1 (4.1.0)", UpdateRules.VersionLine("4.1.0"));
        Assert.Equal("V4.0 (4.0.0-beta.2)", UpdateRules.VersionLine("4.0.0-beta.2"));
        Assert.Equal("4.0.2 → 4.1.0", UpdateRules.Versions("4.0.2", "4.1.0"));
        Assert.Equal("? → 4.1.0", UpdateRules.Versions("", "4.1.0"));
        Assert.True(UpdateRules.IsCurrent("0.7.1", "0.7.0"));
        Assert.False(UpdateRules.IsCurrent("", "0.7.0"));
        Assert.False(UpdateRules.IsCurrent("0.6.9", "0.7.0"));
        Assert.Equal([3001, 3000], UpdateRules.WakePorts(Nino.Core.Tv.TvBrand.Lg));
    }

    // ---- Hata bildirimi taslağı ----

    [Fact]
    public async Task ReportDraftSendsLogsTextFilesAndHidesKeys()
    {
        var dir = Directory.CreateTempSubdirectory("nino-report-").FullName;
        try
        {
            var w = new World().WithPs5();
            w.Services.HealthDir = dir;
            w.Secrets.Set(SecretKeys.DeepLKey, "deepl-secret-1234:fx");
            var c = w.Open();
            var draft = c.ReportDraft;
            draft.Description = "Altyazı gelmedi deepl-secret-1234:fx";
            draft.Add([ReportAttachment.Image("a.jpg", [1, 2, 3]), ReportAttachment.TextFile("not.txt", "satır deepl-secret-1234:fx")]);

            var result = await c.SendReportDraftAsync();
            Assert.Equal(ReportStatus.Sent, result.Status);
            Assert.Equal(ReportPhase.Sent, draft.Phase);
            var body = Assert.Single(w.Services.Reports);
            Assert.Single(body.Images);
            Assert.Contains("Altyazı gelmedi", body.Text);
            Assert.DoesNotContain("deepl-secret-1234", body.Text);
            Assert.NotNull(body.Log);
            Assert.Contains("— ek: not.txt —", body.Log);
            Assert.DoesNotContain("deepl-secret-1234", body.Log);
            Assert.Null(body.Contact);

            draft.Reset();
            Assert.Equal("", draft.Description);
            Assert.Empty(draft.Attachments);

            w.Services.ReportAnswer = ReportStatus.Limited;
            await c.SendReportDraftAsync();
            Assert.Equal(ReportPhase.Editing, draft.Phase);
            Assert.Equal(ReportStatus.Limited, draft.Error);
            draft.Description = "x";
            Assert.Null(draft.Error);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void ReportDraftLimits()
    {
        var d = new ReportDraft();
        d.BeginPreparing();
        Assert.False(d.CanSend);
        var images = Enumerable.Range(0, 4).Select(i => ReportAttachment.Image($"{i}.jpg", [1])).ToList();
        d.Add(images, endPreparing: true);
        Assert.True(d.CanSend);
        Assert.Equal(3, d.Attachments.Count);
        Assert.Equal(ReportAttachmentFailure.Limit, d.AttachError);
        d.Add([ReportAttachment.TextFile("a.txt", "a"), ReportAttachment.TextFile("b.txt", "b"), ReportAttachment.TextFile("c.txt", "c")]);
        Assert.Equal(5, d.Attachments.Count);
        Assert.False(d.CanAdd);
        d.Remove(d.Attachments[0].Id);
        Assert.Null(d.AttachError);
        Assert.True(d.CanAdd);
        d.Add([], failed: true);
        Assert.Equal(ReportAttachmentFailure.Unreadable, d.AttachError);
    }
}
