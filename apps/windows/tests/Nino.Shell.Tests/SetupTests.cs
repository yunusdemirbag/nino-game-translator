// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Shell.Tests;

// Tarif §20, kurulum senaryoları 1–14.
public sealed class SetupTests
{
    [Fact] // 1
    public void FreshInstallStartsAtWelcome()
    {
        var c = new World().Open();
        Assert.Equal(SetupStep.Welcome, c.Step);
        Assert.Equal(8, c.StepCount);
        Assert.Equal(1, c.StepNumber);
    }

    [Fact] // 2
    public void OldInstallWithEverythingIsDoneAndRecordsSetupCompleteOnce()
    {
        var w = new World().WithPs5().WithTv();
        var c = w.Open();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.True(w.Secrets.Get<bool>(SecretKeys.SetupComplete));
    }

    [Fact] // 3
    public async Task Ps5OnlyResumesAtTvAndSamsungPairingDoesNotFinishSetup()
    {
        var w = new World().WithPs5();
        var c = w.Open();
        Assert.Equal(SetupStep.Tv, c.Step);
        w.Services.SamsungPackage = null;
        w.Services.PairKey = "samsung-token";
        Assert.True(await c.PairTvAsync(new Nino.Core.Tv.TvRecord("Samsung", "192.168.1.60", Nino.Core.Tv.TvBrand.Samsung)));
        Assert.True(c.TvPaired);
        var again = w.Open();
        Assert.Equal(SetupStep.Tv, again.Step);
        Assert.False(w.Secrets.Get<bool>(SecretKeys.SetupComplete));
    }

    [Fact] // 4
    public async Task FourAdvancesFromTvReachDoneAndReopenStaysDone()
    {
        var w = new World().WithPs5();
        w.Services.Model.Installed = true;
        var c = w.Open();
        await c.PairTvAsync(new Nino.Core.Tv.TvRecord("Samsung", "192.168.1.60", Nino.Core.Tv.TvBrand.Samsung));
        for (var i = 0; i < 4; i++) c.Advance();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.Equal(SetupStep.Done, w.Open().Step);
    }

    [Fact] // 5
    public void NoTvThenThreeAdvancesIsDone()
    {
        var w = new World().WithPs5();
        w.Services.Model.Installed = true;
        var c = w.Open();
        Assert.False(c.CanContinue);
        c.NoTv();
        Assert.Equal(SetupStep.Model, c.Step);
        Assert.Equal(SubtitleOutput.Computer, c.Settings.Output);
        Assert.Equal(0, w.Services.TvCalls);
        Assert.Equal(SetupStep.Tv, w.Open().Step);
        for (var i = 0; i < 3; i++) c.Advance();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.Equal(SetupStep.Done, w.Open().Step);
    }

    [Fact] // 6
    public async Task AllStepsInOrder()
    {
        var w = new World();
        w.Services.Model.Installed = true;
        var c = w.Open();
        c.Advance();
        Assert.Equal(SetupStep.SecondAccount, c.Step);
        c.Advance();
        Assert.Equal(SetupStep.PsnSignIn, c.Step);
        Assert.False(c.CanContinue);
        Assert.True(await c.CompletePsnSignInAsync("https://remoteplay.dl.playstation.net/remoteplay/redirect?code=abc"));
        Assert.Contains("PSN girişi tamam", w.Logs.RemotePlayLines);
        c.Advance();
        Assert.Equal(SetupStep.Console, c.Step);
        Assert.True(await c.PairPs5Async("192.168.1.253", "1234 5678"));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Format("wizard.ps5.paired", "PS5-789", "192.168.1.253"), c.PairedMessage);
        Assert.Contains(w.Logs.RemotePlayLines, l => l == "PS5 eşleşmesi saklandı (192.168.1.253): PS5-789");
        c.ContinueAfterPairing();
        Assert.Equal(SetupStep.Tv, c.Step);
        Assert.True(await c.PairTvAsync(w.Services.FoundTv));
        c.Advance();
        Assert.Equal(SetupStep.Model, c.Step);
        c.Advance();
        Assert.Equal(SetupStep.Test, c.Step);
        c.Advance();
        Assert.Equal(SetupStep.BetterTranslation, c.Step);
        c.Advance();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.True(w.Secrets.Get<bool>(SecretKeys.SetupComplete));
    }

    [Fact] // 7
    public void BetterTranslationCanBeSkippedAndBackWalks()
    {
        var w = new World().WithPs5();
        w.Services.Model.Installed = true;
        var c = w.Open();
        c.NoTv();
        c.Advance();
        c.Advance();
        Assert.Equal(SetupStep.BetterTranslation, c.Step);
        Assert.True(c.CanContinue);
        c.Advance();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.Equal(OnlineEngine.Free, SettingsRules.SelectedEngine(c.Settings));
        c.GoToStep(SetupStep.BetterTranslation);
        c.Advance();
        c.Back();
        Assert.Equal(SetupStep.BetterTranslation, c.Step);
        c.Back();
        Assert.Equal(SetupStep.Test, c.Step);
    }

    [Fact] // 8
    public async Task GeminiKeyIsTriedTrimmedAndSaved()
    {
        var w = new World().WithPs5();
        var c = w.Open();
        Assert.Equal(KeyCheckStatus.Valid, await c.SaveAiKeyAsync(OnlineEngine.Gemini, "  AIza-free  "));
        var tried = Assert.Single(w.Services.AiTried);
        Assert.Equal(AiService.Gemini, tried.Service);
        Assert.Equal("AIza-free", tried.Key);
        Assert.Equal("gemini-3.5-flash-lite", tried.Model);
        Assert.Equal("AIza-free", w.Secrets.Get<string>(SecretKeys.GeminiKey));
        Assert.Equal(OnlineEngine.Gemini, c.Settings.OnlineEngine);
        Assert.True(c.UsingFreeGemini);

        var w2 = new World();
        w2.Services.AiAnswer = KeyCheckStatus.InvalidKey;
        var c2 = w2.Open();
        await c2.SaveAiKeyAsync(OnlineEngine.Gemini, "wrong");
        Assert.False(w2.Secrets.Contains(SecretKeys.GeminiKey));
        w2.Services.AiAnswer = KeyCheckStatus.QuotaExhausted;
        await c2.SaveAiKeyAsync(OnlineEngine.Gemini, "used-up");
        Assert.Equal("used-up", w2.Secrets.Get<string>(SecretKeys.GeminiKey));
    }

    [Fact] // 9
    public void GetFreeKeySelectsGeminiButNotOnline()
    {
        var c = new World().Open();
        c.GetFreeGeminiKey();
        Assert.Equal(OnlineEngine.Gemini, c.Settings.OnlineEngine);
        Assert.False(c.OnlineEnabled);
    }

    [Fact] // 10
    public async Task ModelDownloadStartsOnceFromWelcome()
    {
        var w = new World();
        w.Services.Model.Gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var c = w.Open();
        c.Advance();
        c.StartModelDownload();
        Assert.Equal(1, w.Services.Model.Downloads);
        Assert.True(c.ModelDownloading);
        Assert.Equal(0.5, c.ModelProgress);
        c.GoToStep(SetupStep.Model);
        Assert.False(c.CanContinue);
        w.Services.Model.Gate.SetResult();
        await c.WhenIdleAsync();
        Assert.False(c.ModelDownloading);
        Assert.True(c.CanContinue);
        Assert.Equal(1, c.ModelProgress);
    }

    [Fact] // 11
    public async Task AutoAdvanceAfterPairingOnlyFromConsoleStep()
    {
        var w = new World();
        w.Secrets.Set(SecretKeys.AccountId, World.Account);
        var c = w.Open();
        c.Advance();
        c.Advance();
        c.Advance();
        Assert.Equal(SetupStep.Console, c.Step);
        await c.PairPs5Async("192.168.1.253", "12345678");
        c.Back();
        c.ContinueAfterPairing();
        Assert.Equal(SetupStep.PsnSignIn, c.Step);
        c.Advance();
        c.ContinueAfterPairing();
        Assert.Equal(SetupStep.Tv, c.Step);
    }

    [Fact] // 12a
    public void GameWindowShortcut()
    {
        var w = new World();
        var c = w.Open();
        c.UseGameWindowHere();
        Assert.Equal(SetupStep.Model, c.Step);
        Assert.True(c.CanStart);
        Assert.True(c.ShowsOnComputer);
        Assert.False(c.ShowsOnTv);
        Assert.Equal(1, w.Services.Model.Downloads);
        c.Back();
        Assert.Equal(SetupStep.Welcome, c.Step);
        c.UseGameWindowHere();
        c.GoToStep(SetupStep.Done);
        var again = w.Open();
        Assert.Equal(SetupStep.Done, again.Step);
        Assert.True(again.UsesGameWindow);
    }

    [Fact] // 12b
    public async Task XboxWindowShortcut()
    {
        var w = new World();
        var c = w.Open();
        c.UseXboxWindow();
        Assert.Equal(SetupStep.Tv, c.Step);
        Assert.True(c.ShowsOnTv);
        Assert.False(c.ShowsOnComputer);
        Assert.False(c.CanStart);
        c.Back();
        Assert.Equal(SetupStep.Welcome, c.Step);
        var s = c.Settings;
        s.Output = SubtitleOutput.Computer;
        c.UpdateSettings(s);
        Assert.True(c.CanStart);
        await c.StartAsync();
        Assert.Equal(GameConsole.Xbox, Assert.Single(w.Services.WindowSources).Console);
        Assert.Contains("\"GameConsole\":\"Xbox\"", SettingsJson.Serialize(w.Saved));
    }

    [Fact] // 12c
    public void CardGuideToComputer()
    {
        var w = new World();
        w.Services.Model.Installed = true;
        var c = w.Open();
        c.OpenCardGuide();
        Assert.True(c.CardGuideOpen);
        c.FinishCardGuide(onTv: false);
        Assert.False(c.CardGuideOpen);
        Assert.Equal(SetupStep.Test, c.Step);
        Assert.Equal(SubtitleOutput.Computer, c.Settings.Output);
        Assert.True(c.CanStart);
        c.Back();
        Assert.True(c.CardGuideOpen);
        Assert.Equal(SetupStep.Welcome, c.Step);
        c.FinishCardGuide(onTv: false);
        c.GoToStep(SetupStep.Done);
        var again = w.Open();
        Assert.Equal(SetupStep.Done, again.Step);
        Assert.True(again.UsesCaptureCard);
    }

    [Fact] // 12d
    public void CardGuideToTv()
    {
        var w = new World();
        var c = w.Open();
        c.OpenCardGuide();
        c.FinishCardGuide(onTv: true);
        Assert.Equal(SetupStep.Tv, c.Step);
        Assert.Equal(SubtitleOutput.Tv, c.Settings.Output);
        c.Back();
        Assert.True(c.CardGuideOpen);

        var w2 = new World().WithTv();
        var c2 = w2.Open();
        c2.OpenCardGuide();
        c2.FinishCardGuide(onTv: true);
        Assert.Equal(c2.ModelInstalled ? SetupStep.Test : SetupStep.Model, c2.Step);
    }

    [Fact] // 12e
    public void CardGuideCancelThenContinueGoesBackToPs5()
    {
        var c = new World().Open();
        c.OpenCardGuide();
        c.FinishCardGuide(onTv: false);
        c.Back();
        c.CancelCardGuide();
        c.Advance();
        Assert.Equal(VideoSource.Ps5, c.Settings.VideoSource);
        Assert.Equal(SetupStep.SecondAccount, c.Step);
    }

    [Fact] // 12f
    public void CardGuideFromSettingsOnlySaves()
    {
        var w = new World().WithPs5().WithTv();
        var c = w.Open();
        c.FinishCardGuide(onTv: false);
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.True(c.UsesCaptureCard);
        Assert.Equal(SubtitleOutput.Computer, c.Settings.Output);
    }

    [Fact] // 12g
    public void NoSecondAccountReadsRemotePlayWindow()
    {
        var c = new World().Open();
        c.Advance();
        c.UseRemotePlayWindow();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.Equal(FrameSource.RemotePlayWindow, c.Settings.FrameSource);
        Assert.Equal(SubtitleOutput.Computer, c.Settings.Output);
        Assert.False(c.HasAccount);
        Assert.True(c.CanStart);
    }

    [Fact] // 12h
    public void ChosenWindowNeedsWindowBeforeStart()
    {
        var c = new World().Open();
        c.Advance();
        c.UseChosenWindow();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.False(c.CanStart);
        var s = c.Settings;
        s.CaptureWindow = new CaptureWindowChoice { ProcessName = "obs64", Title = "Windowed Projector (Preview)" };
        c.UpdateSettings(s);
        Assert.True(c.CanStart);
    }

    [Fact] // 13
    public void ConsoleChangeInSettings()
    {
        var c = new World().WithPs5().WithTv().Open();
        c.SetGameConsole(GameConsole.Xbox);
        Assert.Equal(GameConsole.Xbox, c.Settings.GameConsole);
        Assert.Equal(VideoSource.Window, c.Settings.VideoSource);
        var s = c.Settings;
        s.VideoSource = VideoSource.Card;
        c.UpdateSettings(s);
        c.SetGameConsole(GameConsole.Ps5);
        Assert.Equal(VideoSource.Card, c.Settings.VideoSource);
    }

    [Fact] // 14
    public void LinkAccountAfterWindowSetup()
    {
        var c = new World().Open();
        c.UseGameWindowHere();
        c.GoToStep(SetupStep.Done);
        Assert.False(c.AccountLinkNeeded);
        var s = c.Settings;
        s.VideoSource = VideoSource.Ps5;
        c.UpdateSettings(s);
        Assert.True(c.AccountLinkNeeded);
        Assert.False(c.CanStart);
        c.LinkAccount();
        Assert.Equal(SetupStep.SecondAccount, c.Step);
    }

    [Fact]
    public void ManualAccountIdRules()
    {
        var w = new World();
        var c = w.Open();
        foreach (var bad in new[] { "", "AQIDBAUGBw==", "AQIDBAUGBwgJ", "AQIDBAUGBw!=", "1234567890" })
            Assert.False(c.SetManualAccountId(bad));
        Assert.False(w.Secrets.Contains(SecretKeys.AccountId));
        Assert.True(c.SetManualAccountId("  " + Convert.ToBase64String([1, 2, 3, 4, 5, 6, 7, 8]) + " "));
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, w.Secrets.Get<byte[]>(SecretKeys.AccountId));
    }

    [Fact]
    public async Task PairingCodeAndErrorMessages()
    {
        var w = new World();
        var c = w.Open();
        Assert.False(await c.PairPs5Async("", "12345678"));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("wizard.ps5.error.notFound"), c.PairError);
        foreach (var code in new[] { "1234", "", "123456789", "1234567O" })
        {
            Assert.False(await c.PairPs5Async("192.168.1.253", code));
            Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("wizard.ps5.error.codeLength"), c.PairError);
        }
        Assert.False(await c.PairPs5Async("192.168.1.253", "12345678"));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("wizard.ps5.error.signInFirst"), c.PairError);

        c.SetManualAccountId(Convert.ToBase64String(World.Account));
        w.Services.RegisterError = new Nino.RemotePlay.PairingException(Nino.RemotePlay.PairingOutcome.WrongCode, 0x80108b09,
            "0x80108b09 (Regist failed, probably invalid PIN)");
        Assert.False(await c.PairPs5Async("192.168.1.253", "12345678"));
        Assert.Contains("0x80108b09 (Regist failed, probably invalid PIN)", c.PairError);
        Assert.Contains("/logs/remoteplay.log", c.PairError);
    }

    [Fact]
    public async Task PsnErrorsCarryDetailAndLogHint()
    {
        var w = new World();
        w.Services.SignInError = new Nino.RemotePlay.PsnSignInException(Nino.RemotePlay.PsnSignInFailure.RateLimited, 429, "too many");
        var c = w.Open();
        Assert.False(await c.CompletePsnSignInAsync("https://x"));
        Assert.StartsWith(Nino.Core.Text.TextCatalog.For("en").Get("wizard.psn.error.rateLimited"), c.PsnError);
        Assert.Contains("HTTP 429, too many", c.PsnError);
        Assert.Contains("/logs/remoteplay.log", c.PsnError);
    }

    [Fact]
    public void ResetEverythingAndFromTv()
    {
        var w = new World().WithPs5().WithTv();
        w.Secrets.Set(SecretKeys.LoginPasscode, "4321");
        var c = w.Open();
        c.ResetFromTv();
        Assert.Equal(SetupStep.Tv, c.Step);
        Assert.True(w.Secrets.Contains(SecretKeys.AccountId));
        Assert.False(w.Secrets.Contains(SecretKeys.Tv));
        Assert.Equal(SetupStep.Tv, w.Open().Step);
        c.ResetEverything();
        Assert.Equal(SetupStep.Welcome, c.Step);
        Assert.False(w.Secrets.Contains(SecretKeys.AccountId));
        Assert.False(w.Secrets.Contains(SecretKeys.LoginPasscode));
        Assert.Equal(SetupStep.Welcome, w.Open().Step);
    }
}
