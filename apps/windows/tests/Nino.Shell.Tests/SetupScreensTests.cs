// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Text;
using Nino.Core.Tv;
using Nino.Shell.Setup;

namespace Nino.Shell.Tests;

// Kurulum sihirbazı ekranlarının saf hesapları (kurulum.md §1, §5, §8.1, §12.1; tv-kurulum.md §3.5, §10.3).
public sealed class SetupScreensTests
{
    static readonly TextCatalog En = TextCatalog.For("en");
    static readonly TextCatalog Tr = TextCatalog.For("tr");

    [Fact]
    public void Ps5ListHasEightStepsInOrderWithMarks()
    {
        var rows = SetupSidebar.Rows(SetupStep.PsnSignIn, xbox: false, Tr);
        Assert.Equal(8, rows.Count);
        Assert.Equal([SetupStep.Welcome, SetupStep.SecondAccount, SetupStep.PsnSignIn, SetupStep.Console, SetupStep.Tv,
            SetupStep.Model, SetupStep.Test, SetupStep.BetterTranslation], rows.Select(r => r.Step));
        Assert.Equal([1, 2, 3, 4, 5, 6, 7, 8], rows.Select(r => r.Number));
        Assert.Equal([StepMark.Done, StepMark.Done, StepMark.Current, StepMark.Upcoming], rows.Take(4).Select(r => r.Mark));
        Assert.Equal(Tr.Get("setup.welcome.title"), rows[0].Name);
        Assert.Equal(Tr.Get("home.toggle.connectPs5"), rows[3].Name);
        Assert.Equal("3. " + Tr.Get("setup.psnSignIn.title"), rows[2].AccessibleName);
    }

    [Fact]
    public void XboxListDropsSecondAccountAndUsesXboxNames()
    {
        var rows = SetupSidebar.Rows(SetupStep.Console, xbox: true, En);
        Assert.Equal(7, rows.Count);
        Assert.DoesNotContain(rows, r => r.Step == SetupStep.SecondAccount);
        Assert.Equal(En.Get("setup.steps.signInXbox"), rows[1].Name);
        Assert.Equal(En.Get("setup.steps.consoleXbox"), rows[2].Name);
        Assert.Equal(3, rows[2].Number);
        Assert.Equal(StepMark.Current, rows[2].Mark);
        Assert.Equal(StepMark.Done, rows[1].Mark);
    }

    [Fact]
    public void CounterText()
    {
        Assert.Equal("Step 3 of 8", SetupSidebar.Counter(3, 8, En));
        Assert.Equal("Adım 2 / 7", SetupSidebar.Counter(2, 7, Tr));
    }

    [Fact]
    public void ContinueButtonRules()
    {
        var welcome = WizardButtons.For(SetupStep.Welcome, false);
        Assert.False(welcome.BackVisible);
        Assert.True(welcome.ContinueVisible && welcome.ContinuePrimary && welcome.ContinueIsDefault);
        Assert.Equal("common.continue", welcome.ContinueKey);

        var test = WizardButtons.For(SetupStep.Test, false);
        Assert.True(test.BackVisible);
        Assert.False(test.ContinueVisible);

        var skip = WizardButtons.For(SetupStep.BetterTranslation, false);
        Assert.Equal("setup.skipForNow", skip.ContinueKey);
        Assert.False(skip.ContinuePrimary);
        Assert.False(skip.ContinueIsDefault);

        var ready = WizardButtons.For(SetupStep.BetterTranslation, true);
        Assert.Equal("common.continue", ready.ContinueKey);
        Assert.True(ready.ContinuePrimary && ready.ContinueIsDefault);
    }

    [Theory]
    [InlineData("https://www.microsoft.com/link", "microsoft.com/link")]
    [InlineData("https://www.microsoft.com/link/", "microsoft.com/link")]
    [InlineData("https://login.live.com/oauth20_remoteconnect.srf", "login.live.com/oauth20_remoteconnect.srf")]
    [InlineData("https://microsoft.com/", "microsoft.com")]
    [InlineData("", "")]
    public void MicrosoftLinkText(string url, string expected) => Assert.Equal(expected, MicrosoftLink.Display(url));

    [Fact]
    public void TvPairTexts()
    {
        Assert.Equal(En.Get("tv.pair.error.samsungRejected"), TvPairText.Describe(TvBrand.Samsung, "rejected", false, En));
        Assert.Equal(En.Get("tv.pair.error.samsungTimeout"), TvPairText.Describe(TvBrand.Samsung, "cannot connect", false, En));
        Assert.Equal(En.Get("tv.pair.error.samsungTimeout"), TvPairText.Describe(TvBrand.Samsung, null, true, En));
        // Samsung'un 60 saniyelik izin beklemesi TvRemotes'ta "timeout" sebebiyle biter.
        Assert.Equal(En.Get("tv.pair.error.samsungTimeout"), TvPairText.Describe(TvBrand.Samsung, "timeout", false, En));
        Assert.Equal(En.Get("tv.pair.error.noResponse"), TvPairText.Describe(TvBrand.Samsung, "closed", false, En));
        Assert.Equal(En.Get("tv.pair.error.noResponse") + " (timeout)", TvPairText.Describe(TvBrand.Lg, "timeout", false, En));
        Assert.Equal(En.Get("tv.pair.error.noResponse"), TvPairText.Describe(TvBrand.Lg, "cannot connect", false, En));
        Assert.Equal(En.Get("tv.pair.error.noResponse"), TvPairText.Describe(TvBrand.AndroidTv, "x", false, En));
    }

    const string Log = @"%LOCALAPPDATA%\Nino\tvinstall.log";

    [Fact]
    public void UnknownCardIsHidden()
    {
        var view = TvAppCardView.Build(TvAppStatus.Unknown, TvBrand.Lg, null, null, Log, En);
        Assert.False(view.Visible);
    }

    [Fact]
    public void LgDevModeOffShowsStepsAndPassphrase()
    {
        var view = TvAppCardView.Build(new TvAppStatus(TvAppKind.DevModeOff), TvBrand.Lg, null, null, Log, En);
        Assert.True(view.Visible && view.LgSteps && view.Passphrase);
        Assert.False(view.SamsungSteps || view.AndroidSteps || view.Reopen || view.Retry);
        Assert.Equal(En.Get("tvApp.status.devModeOff.lg"), view.Status);
        Assert.Equal("", view.Detail);
        Assert.True(TvAppCardView.Polls(new TvAppStatus(TvAppKind.DevModeOff)));
    }

    [Fact]
    public void SamsungAndAndroidDevModeOff()
    {
        var samsung = TvAppCardView.Build(new TvAppStatus(TvAppKind.DevModeOff), TvBrand.Samsung, null, null, Log, Tr);
        Assert.True(samsung.SamsungSteps);
        Assert.False(samsung.Passphrase || samsung.LgSteps);
        Assert.Equal(Tr.Get("tvApp.status.devModeOffSamsung"), samsung.Status);

        var android = TvAppCardView.Build(new TvAppStatus(TvAppKind.DevModeOff), TvBrand.AndroidTv, null, null, Log, Tr);
        Assert.True(android.AndroidSteps);
        Assert.Equal(Tr.Get("tvApp.status.devModeOff.android"), android.Status);
    }

    [Fact]
    public void UpToDateDetails()
    {
        var lg = TvAppCardView.Build(new TvAppStatus(TvAppKind.UpToDate, "1.4.0"), TvBrand.Lg, 999, null, Log, En);
        Assert.Equal(En.Format("tvApp.status.ready", "1.4.0"), lg.Status);
        Assert.Equal(En.Format("tvApp.detail.lgHoursLeft", 999), lg.Detail);
        var lgNoHours = TvAppCardView.Build(new TvAppStatus(TvAppKind.UpToDate, "1.4.0"), TvBrand.Lg, null, null, Log, En);
        Assert.Equal(En.Get("tvApp.detail.lgAutoExtend"), lgNoHours.Detail);
        var samsung = TvAppCardView.Build(new TvAppStatus(TvAppKind.UpToDate, "1.4.0"), TvBrand.Samsung, null, null, Log, En);
        Assert.Equal(En.Get("tvApp.detail.samsungSourceSwitch"), samsung.Detail);
        Assert.Equal("", samsung.Problem);
    }

    [Fact]
    public void SignInAndConfirmStates()
    {
        var signIn = TvAppCardView.Build(new TvAppStatus(TvAppKind.SamsungSignIn, SignInUrl: "https://x"), TvBrand.Samsung,
            null, null, Log, En);
        Assert.True(signIn.Reopen);
        Assert.Equal(En.Get("tvApp.detail.samsungSignIn") + " " + En.Get("tvApp.detail.samsungNoAccount"), signIn.Detail);
        var confirm = TvAppCardView.Build(new TvAppStatus(TvAppKind.ConfirmOnTv), TvBrand.AndroidTv, null, null, Log, En);
        Assert.Equal(En.Get("tvApp.status.approveOnTv"), confirm.Status);
        Assert.Equal(En.Get("tvApp.detail.approveOnTv"), confirm.Detail);
    }

    [Fact]
    public void HostPcMismatchIsAloneAndPollsAndShowsSamsungSteps()
    {
        var status = new TvAppStatus(TvAppKind.Failed, Error: TvError.HostPcMismatch, TvHostPcIp: "192.168.1.5",
            ThisComputer: "192.168.1.20");
        var view = TvAppCardView.Build(status, TvBrand.Samsung, null, "10.0.0.9", Log, En);
        Assert.Equal(En.Format("tvApp.error.hostPcMismatch", "192.168.1.5", "192.168.1.20"), view.Problem);
        Assert.True(view.SamsungSteps && view.Retry);
        Assert.True(TvAppCardView.Polls(status));
        var noAddresses = TvAppCardView.ProblemText(new TvAppStatus(TvAppKind.Failed, Error: TvError.HostPcMismatch),
            TvBrand.Samsung, null, Log, En);
        Assert.Equal(En.Format("tvApp.error.hostPcMismatch", "?", "?"), noAddresses);
    }

    [Fact]
    public void SamsungUnreachableProblemLines()
    {
        var status = new TvAppStatus(TvAppKind.Failed, Error: TvError.Unreachable, Reason: "TV kapattı");
        var text = TvAppCardView.ProblemText(status, TvBrand.Samsung, "192.168.1.20", Log, En);
        Assert.Equal(string.Join("\n\n",
            En.Get("tvApp.error.unreachableSamsung"),
            En.Format("tvApp.problem.hostPcIp", "192.168.1.20"),
            En.Format("tvApp.problem.detailsSamsung", "TV kapattı"),
            En.Get("tvApp.problem.restartSamsung"),
            En.Format("status.sendLogFile", Log)), text);
    }

    [Fact]
    public void SamsungInstallFailedAndConnectionLost()
    {
        var failed = TvAppCardView.ProblemText(new TvAppStatus(TvAppKind.Failed, Error: TvError.InstallFailed),
            TvBrand.Samsung, null, Log, En);
        Assert.Equal(string.Join("\n\n", En.Get("tvApp.error.installFailed"), En.Get("tvApp.problem.serverMaintenance"),
            En.Get("tvApp.problem.restartSamsung"), En.Format("status.sendLogFile", Log)), failed);
        var lost = TvAppCardView.ProblemText(new TvAppStatus(TvAppKind.Failed, Error: TvError.ConnectionLost),
            TvBrand.Samsung, null, Log, En);
        Assert.Equal(string.Join("\n\n", En.Get("tvApp.error.connectionLost"), En.Get("tvApp.detail.anynet"),
            En.Format("status.sendLogFile", Log)), lost);
    }

    [Fact]
    public void LgAndAndroidProblemsStopAfterReason()
    {
        var lg = TvAppCardView.ProblemText(new TvAppStatus(TvAppKind.Failed, Error: TvError.InstallFailed, Reason: " disk "),
            TvBrand.Lg, null, Log, En);
        Assert.Equal(En.Get("tvApp.error.installFailed") + "\n\n" + En.Format("tvApp.problem.detailsTv", "disk"), lg);
        var android = TvAppCardView.ProblemText(new TvAppStatus(TvAppKind.Failed, Error: TvError.Unreachable),
            TvBrand.AndroidTv, "192.168.1.20", Log, En);
        Assert.Equal(En.Get("tv.pair.error.noResponse"), android);
        var passphrase = TvAppCardView.Build(new TvAppStatus(TvAppKind.PassphraseNeeded, Error: TvError.WrongPassphrase),
            TvBrand.Lg, null, null, Log, En);
        Assert.True(passphrase.Passphrase);
        Assert.Equal(En.Get("tvApp.error.wrongPassphrase"), passphrase.Problem);
        Assert.False(passphrase.Retry);
    }

    [Fact]
    public void SamsungHostStepUsesAddressOrQuestionMark()
    {
        Assert.Contains("192.168.1.20", TvAppCardView.SamsungHostStep("192.168.1.20", En));
        Assert.Contains("Host PC IP: ?.", TvAppCardView.SamsungHostStep(null, En));
    }

    [Fact]
    public void CaptureGuideDotsAndButtons()
    {
        Assert.Equal((true, true), CaptureGuideSteps.Dot(1, 1));
        Assert.Equal((false, true), CaptureGuideSteps.Dot(0, 1));
        Assert.Equal((false, false), CaptureGuideSteps.Dot(2, 1));
        Assert.Equal("common.cancel", CaptureGuideSteps.BackKey(0, inWindow: true));
        Assert.Equal("common.back", CaptureGuideSteps.BackKey(0, inWindow: false));
        Assert.Equal("common.back", CaptureGuideSteps.BackKey(1, inWindow: true));
        Assert.Equal("common.continue", CaptureGuideSteps.NextKey(1));
        Assert.Equal("common.done", CaptureGuideSteps.NextKey(2));
    }

    [Fact]
    public void PsnWindowClosedTexts()
    {
        var c = new World().Open();
        Assert.Equal(c.Text.Get("wizard.psn.error.windowClosed"), c.PsnWindowClosedText(null));
        Assert.Equal(c.Text.Get("wizard.psn.error.rateLimited"), c.PsnWindowClosedText("HTTP 429"));
        Assert.StartsWith(c.Text.Get("wizard.psn.error.pageFailed") + " (HTTP 503) ", c.PsnWindowClosedText("HTTP 503"));
    }
}
