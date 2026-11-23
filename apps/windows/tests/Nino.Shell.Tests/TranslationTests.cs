// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Design;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

sealed class FakeXbox : IXboxService
{
    public readonly List<(StoredXboxConsole Console, string Token, bool Legacy)> Streams = [];
    public int Clears;
    public event Action<string>? TokenRefreshed;
    public void Clear() => Clears++;
    public Task<XboxSignInCode> BeginSignInAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(new XboxSignInCode("ABCD", "https://microsoft.com/link", TimeSpan.FromMinutes(15)));
    public Task<string> FinishSignInAsync(CancellationToken cancellationToken = default) => Task.FromResult("xbox-token");
    public Task<IReadOnlyList<StoredXboxConsole>> FindConsolesAsync(string token, CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<StoredXboxConsole>>([new StoredXboxConsole { Id = "x1", Name = "Oturma Odası", Model = "XboxSeriesX", StreamingEnabled = true }]);
    public XboxStreamQuality LastQuality { get; private set; }

    public IVideoSource CreateStream(StoredXboxConsole console, string token, bool legacyFrameRate, XboxStreamQuality quality)
    {
        Streams.Add((console, token, legacyFrameRate));
        LastQuality = quality;
        return new FakeStream { Kind = "xbox" };
    }
    public void Refresh(string token) => TokenRefreshed?.Invoke(token);
    public void Dispose() { }
}

// Tarif §20, çeviri senaryoları 15–34.
public sealed class TranslationTests
{
    static World Ready(SubtitleOutput output = SubtitleOutput.Tv, bool tv = true)
    {
        var w = new World(new AppSettings { Output = output }).WithPs5();
        if (tv) w.WithTv();
        w.Services.Model.Installed = true;
        return w;
    }

    [Fact] // 15
    public async Task DoubleStartOpensOneSessionAndOneWatch()
    {
        var w = Ready();
        var c = w.Open();
        var a = c.StartAsync();
        var b = c.StartAsync();
        await Task.WhenAll(a, b);
        Assert.Single(w.Services.Ps5Sessions);
        Assert.Single(w.Services.Watches);
        Assert.True(c.IsTranslating);
    }

    [Fact] // 16
    public async Task WatchTokenIsSavedAndEmptySamsungTokenKeepsOld()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        w.Services.Watches[0].Request.KeyChanged("new-token");
        Assert.Equal("new-token", w.Secrets.Get<string>(SecretKeys.TvKey));

        var w2 = Ready(tv: false);
        w2.WithTv(StoredTvBrand.Samsung, "samsung-token", "192.168.1.60", "Samsung");
        w2.Services.PairKey = "";
        var c2 = w2.Open();
        await c2.PairTvAsync(new TvRecord("Samsung", "192.168.1.60", TvBrand.Samsung));
        Assert.Equal("samsung-token", w2.Secrets.Get<string>(SecretKeys.TvKey));
    }

    [Fact] // 17
    public async Task SleepGuardAndConsoleMove()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        Assert.True(w.Sleep.Active);
        w.Services.Ps5Sessions[0].Move(new Ps5Console("192.168.1.77", "PS5-789", new byte[16], new byte[16]));
        Assert.Equal("192.168.1.77", w.Secrets.Get<StoredConsole>(SecretKeys.Console)!.Host);
        c.Stop();
        Assert.False(w.Sleep.Active);
    }

    [Fact] // 18
    public async Task DropClearsTvAndStartAnnounces()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        Assert.Single(w.Services.Server.Of<TranslationStarted>());
        w.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        w.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.Network));
        Assert.NotEmpty(w.Services.Server.Of<SubtitleCleared>());
        c.Stop();
        Assert.Single(w.Services.Server.Of<TranslationStopped>());
    }

    [Fact] // 19
    public void SettingsChangeLeavesOnlySetupCompleteInSecretsAndPersists()
    {
        var w = new World();
        var c = w.Open();
        var s = c.Settings;
        s.Style.FontSize = 58;
        c.UpdateSettings(s);
        Assert.True(w.Secrets.Contains(SecretKeys.SetupComplete));
        foreach (var key in new[] { SecretKeys.AccountId, SecretKeys.Console, SecretKeys.Tv, SecretKeys.TvKey })
            Assert.False(w.Secrets.Contains(key));
        Assert.Equal(58, w.Open().Settings.Style.FontSize);
        Assert.NotEmpty(w.Services.Server.Of<StyleChanged>());
    }

    [Fact] // 20
    public async Task SourceLanguageChangeRebuildsReader()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        var s = c.Settings;
        s.SourceLanguage = "ja";
        c.UpdateSettings(s);
        Assert.Equal("ja", c.ActiveLanguage);
        Assert.Equal(["en", "ja"], w.Services.ReaderFactory.Languages);
    }

    [Fact] // 21
    public async Task OcrMissing()
    {
        var w = Ready();
        w.Services.ReaderFactory.Pack = false;
        var c = w.Open();
        await c.StartAsync();
        Assert.True(c.OcrMissing);

        var w2 = Ready();
        w2.Services.ReaderFactory.None = true;
        var c2 = w2.Open();
        await c2.StartAsync();
        Assert.True(c2.OcrMissing);
        Assert.True(c2.IsTranslating);
    }

    [Fact] // 22
    public async Task FreeEngineFailures()
    {
        var w = Ready();
        w.Services.Factory.CreateError = new InvalidOperationException("ct2");
        var c = w.Open();
        await c.StartAsync();
        Assert.True(c.IsTranslating);
        Assert.Equal(TranslatorStatus.EngineFailed, c.TranslatorStatus);
        // Motor açılamadı diye uyarı çıkmaz: çeviri havuzdan ya da başka yoldan gelebilir; yalnız çeviri denemesi
        // başarısız olup ardından hiç çeviri gelmediyse görünür.
        Assert.False(c.TranslationsMissing);

        var w2 = Ready();
        var c2 = w2.Open();
        await c2.StartAsync();
        w2.Services.Model.Fail();
        Assert.Equal(TranslatorStatus.EngineFailed, c2.TranslatorStatus);
        await c2.SaveDeepLKeyAsync("key:fx");
        Assert.Equal(TranslatorStatus.Ready, c2.TranslatorStatus);
        Assert.Null(w2.Services.Factory.DeepL[^1].Fallback);
        c2.RemoveKey(OnlineEngine.DeepL);
        Assert.Equal(TranslatorStatus.EngineFailed, c2.TranslatorStatus);
    }

    [Fact] // 22b (§11.5 örnekleri)
    public async Task DeepLKeyExamples()
    {
        var w = new World(new AppSettings()).WithPs5().WithTv();
        w.Services.DeepLAnswer = Nino.Translation.Online.KeyCheckStatus.InvalidKey;
        var c = w.Open();
        await c.SaveDeepLKeyAsync("  wrong  ");
        Assert.Equal("wrong", w.Services.DeepLTried[^1]);
        Assert.False(c.HasKey(OnlineEngine.DeepL));
        Assert.False(c.OnlineEnabled);
        w.Services.DeepLAnswer = Nino.Translation.Online.KeyCheckStatus.Valid;
        await c.SaveDeepLKeyAsync("key:fx");
        Assert.True(c.OnlineEnabled);
        Assert.Equal(TranslatorStatus.Ready, c.TranslatorStatus);
        await c.StartAsync();
        Assert.Equal(("key:fx", (ITranslator?)null), w.Services.Factory.DeepL[^1]);
        c.RemoveKey(OnlineEngine.DeepL);
        Assert.False(c.OnlineEnabled);
        Assert.Equal(TranslatorStatus.DownloadRequired, c.TranslatorStatus);
    }

    [Fact] // §11.5 yerel model
    public async Task LocalServerExample()
    {
        var w = new World(new AppSettings
        {
            OnlineTranslation = true,
            OnlineEngine = OnlineEngine.Local,
            LocalAiBaseUrl = SettingsRules.LmStudioBaseUrl,
            LocalAiModel = " qwen2.5-7b-instruct ",
        });
        var c = w.Open();
        await c.TryLocalServerAsync();
        var tried = w.Services.AiTried[^1];
        Assert.Equal("http://localhost:1234/v1/chat/completions", tried.Local!.ChatUrl);
        Assert.Equal("qwen2.5-7b-instruct", tried.Model);
        Assert.Equal("", tried.Key);
        await c.TryLocalServerAsync(" lm-key ");
        Assert.Equal("lm-key", w.Secrets.Get<string>(SecretKeys.LocalAIKey));
        Assert.Equal("local:localhost:1234/qwen2.5-7b-instruct", tried.Local.EngineName);
        var s = c.Settings;
        s.LocalAiBaseUrl = "ftp://nowhere";
        c.UpdateSettings(s);
        Assert.False(c.OnlineEnabled);
        Assert.Equal(Nino.Translation.Online.KeyCheckStatus.Unreachable, await c.TryLocalServerAsync());
    }

    [Fact] // 23
    public async Task LoginPasscode()
    {
        var w = Ready();
        var c = w.Open();
        Assert.False(c.SaveLoginPasscode("12a4"));
        Assert.True(c.SaveLoginPasscode(" 4321 "));
        await c.StartAsync();
        Assert.Equal("4321", w.Services.Passcodes[^1]);
        c.Stop();
        c.RemoveLoginPasscode();
        await c.StartAsync();
        Assert.Null(w.Services.Passcodes[^1]);
        c.SaveLoginPasscode("4321");
        c.ResetEverything();
        Assert.False(c.HasLoginPasscode);
    }

    [Fact] // 24
    public async Task DisplayStaysOnRules()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        Assert.True(w.Sleep.Active);
        Assert.False(w.Sleep.DisplayOn);
        var s = c.Settings;
        s.Output = SubtitleOutput.Both;
        c.UpdateSettings(s);
        Assert.True(w.Sleep.DisplayOn);
        s.Output = SubtitleOutput.Tv;
        c.UpdateSettings(s);
        Assert.False(w.Sleep.DisplayOn);
        c.Stop();
        Assert.False(w.Sleep.Active);

        var w2 = new World(new AppSettings { FrameSource = FrameSource.RemotePlayWindow, Output = SubtitleOutput.Computer });
        var c2 = w2.Open();
        await c2.StartAsync();
        Assert.True(w2.Sleep.DisplayOn);
    }

    [Fact] // 25
    public async Task ChosenWindowRestartsWhenWindowChanges()
    {
        var w = new World(new AppSettings
        {
            FrameSource = FrameSource.ChosenWindow,
            Output = SubtitleOutput.Computer,
            CaptureWindow = new CaptureWindowChoice { ProcessName = "obs64", Title = "Windowed Projector (Preview)" },
        });
        var c = w.Open();
        await c.StartAsync();
        Assert.Single(w.Services.ChosenSources);
        Assert.Empty(w.Services.Ps5Sessions);
        var s = c.Settings;
        s.CaptureWindow = new CaptureWindowChoice { ProcessName = "game", Title = "Gameplay" };
        c.UpdateSettings(s);
        await c.WhenIdleAsync();
        Assert.Equal(2, w.Services.ChosenSources.Count);
        Assert.Equal("chosen:game/Gameplay", w.Services.ChosenSources[1].Kind);
        Assert.True(c.IsTranslating);
    }

    [Fact] // 26
    public async Task RemotePlayWindowWithoutRecord()
    {
        var w = new World(new AppSettings { FrameSource = FrameSource.RemotePlayWindow, RemotePlayApp = RemotePlayApp.Chiaki, Output = SubtitleOutput.Computer });
        var c = w.Open();
        Assert.Equal(SetupStep.Done, c.Step);
        Assert.False(w.Secrets.Contains(SecretKeys.SetupComplete));
        Assert.True(c.CanStart);
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.remotePlayWindow.idle"), c.ConsoleStatusText);
        await c.StartAsync();
        Assert.Equal([RemotePlayApp.Chiaki], w.Services.RemotePlayApps);
        Assert.Empty(w.Services.Ps5Sessions);

        var w2 = new World(new AppSettings { FrameSource = FrameSource.RemotePlayWindow });
        w2.Services.RemotePlayInstalled = false;
        Assert.StartsWith(Nino.Core.Text.TextCatalog.For("en").Get("status.remotePlayWindow.notInstalled"), w2.Open().ConsoleStatusText);
    }

    [Fact] // 27
    public async Task SwitchingToRemotePlayWindowWhileRunning()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        var s = c.Settings;
        s.FrameSource = FrameSource.RemotePlayWindow;
        c.UpdateSettings(s);
        await c.WhenIdleAsync();
        Assert.True(w.Services.Ps5Sessions[0].Stopped);
        Assert.Equal([RemotePlayApp.Automatic], w.Services.RemotePlayApps);
        Assert.True(c.IsTranslating);
    }

    [Fact] // 28
    public async Task XboxLegacyFrameRate()
    {
        var w = new World(new AppSettings { XboxLegacyFrameRate = true }).WithTv();
        var xbox = new FakeXbox();
        w.Services.XboxService = xbox;
        w.Secrets.Set(SecretKeys.ConsoleKind, StoredConsoleKind.Xbox);
        w.Secrets.Set(SecretKeys.XboxToken, "tok");
        w.Secrets.Set(SecretKeys.XboxConsole, new StoredXboxConsole { Id = "x1", Name = "Oturma OdasA+", StreamingEnabled = true });
        var c = w.Open();
        await c.StartAsync();
        Assert.True(xbox.Streams[^1].Legacy);
        Assert.True(w.Saved.XboxLegacyFrameRate);
        await c.FindXboxConsolesAsync();
        Assert.Equal("Oturma Odası", w.Secrets.Get<StoredXboxConsole>(SecretKeys.XboxConsole)!.Name);
        xbox.Refresh("tok-2");
        Assert.Equal("tok-2", w.Secrets.Get<string>(SecretKeys.XboxToken));
    }

    [Fact]
    public async Task XboxStreamQualityReachesTheServiceAndRestarts()
    {
        var w = new World(new AppSettings { XboxStreamQuality = XboxStreamQuality.P720 }).WithTv();
        var xbox = new FakeXbox();
        w.Services.XboxService = xbox;
        w.Secrets.Set(SecretKeys.ConsoleKind, StoredConsoleKind.Xbox);
        w.Secrets.Set(SecretKeys.XboxToken, "tok");
        w.Secrets.Set(SecretKeys.XboxConsole, new StoredXboxConsole { Id = "x1", Name = "Salon", StreamingEnabled = true });
        var c = w.Open();
        await c.StartAsync();
        Assert.Equal(XboxStreamQuality.P720, xbox.LastQuality);
        var count = xbox.Streams.Count;
        var s = c.Settings.Clone();
        s.XboxStreamQuality = XboxStreamQuality.Auto;
        c.UpdateSettings(s);
        await c.WhenIdleAsync();
        Assert.True(xbox.Streams.Count > count);
        Assert.Equal(XboxStreamQuality.Auto, xbox.LastQuality);
    }

    [Fact] // 29
    public async Task GameWindowSource()
    {
        var w = new World(new AppSettings { VideoSource = VideoSource.Window, Output = SubtitleOutput.Computer });
        var c = w.Open();
        Assert.True(c.CanStart);
        await c.StartAsync();
        Assert.Empty(w.Services.Ps5Sessions);
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.gameWindow.ps5.startPlaying"), c.ConsoleStatusText);
        var src = w.Services.WindowSources[0];
        src.Window(WindowCaptureState.Capturing, "PS Remote Play", GameWindowRules.GameArea(1280, 720));
        Assert.Equal(SourcePhase.Streaming, c.SessionStatus.Phase);
        Assert.Equal("Reading PS Remote Play", c.ConsoleStatusText);
        Assert.Equal(new PixelRect(0, 0, 1280, 720), c.GameArea);
        c.Stop();
        Assert.True(src.Stopped);
        Assert.Null(c.GameArea);
        Assert.Equal(WindowCaptureState.Stopped, c.WindowState);

        await c.StartAsync();
        var s = c.Settings;
        s.VideoSource = VideoSource.Ps5;
        c.UpdateSettings(s);
        await c.WhenIdleAsync();
        Assert.True(w.Services.WindowSources[1].Stopped);
        Assert.False(c.IsTranslating);
    }

    [Fact] // 30
    public async Task CaptureCard()
    {
        var w = new World(new AppSettings { VideoSource = VideoSource.Card, Output = SubtitleOutput.Computer });
        w.Secrets.Set(SecretKeys.CaptureCardId, "card-1");
        var c = w.Open();
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.card.idle"), c.ConsoleStatusText);
        await c.StartAsync();
        var card = Assert.Single(w.Services.CardSources);
        Assert.True(card.ShowGame);
        Assert.Equal("card-1", card.DeviceId);
        Assert.True(c.CardPlayerVisible);
        card.Card(new CardStatus(CardCaptureState.NoCard));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.card.notPlugged"), c.ConsoleStatusText);
        Assert.Equal(StatusTone.Warning, c.ConsoleTone);
        card.Card(new CardStatus(CardCaptureState.Capturing, "Elgato HD60 X"), new PixelRect(0, 0, 1920, 1080));
        Assert.Equal(SourcePhase.Streaming, c.SessionStatus.Phase);
        Assert.Equal("Reading Elgato HD60 X", c.ConsoleStatusText);
        Assert.Equal(StatusTone.Good, c.ConsoleTone);
        Assert.Equal(new PixelRect(0, 0, 1920, 1080), c.GameArea);
        card.Card(new CardStatus(CardCaptureState.BlackPicture, "Elgato HD60 X"));
        Assert.Equal(StatusTone.Warning, c.ConsoleTone);
        c.ToggleCardFullScreen();
        Assert.Equal(1, card.FullScreens);
        card.CloseWindow();
        Assert.False(c.IsTranslating);
        Assert.True(card.Stopped);
        Assert.Equal(CardCaptureState.Stopped, c.CardState.State);

        // Geçen kartın geç olayları yok sayılır.
        await c.StartAsync();
        var second = w.Services.CardSources[1];
        card.Card(new CardStatus(CardCaptureState.Capturing, "Old"), new PixelRect(1, 1, 1, 1));
        card.CloseWindow();
        Assert.True(c.IsTranslating);
        Assert.Null(c.GameArea);
        c.Stop();

        // Geçişli kart (TV): oyun gösterilmez, bekçi var.
        var w2 = new World(new AppSettings { VideoSource = VideoSource.Card }).WithTv();
        var c2 = w2.Open();
        await c2.StartAsync();
        Assert.False(w2.Services.CardSources[0].ShowGame);
        Assert.Single(w2.Services.Watches);
        var s = c2.Settings;
        s.Output = SubtitleOutput.Computer;
        c2.UpdateSettings(s);
        await c2.WhenIdleAsync();
        Assert.Equal(2, w2.Services.CardSources.Count);
        Assert.True(w2.Services.CardSources[1].ShowGame);
        Assert.True(w2.Services.CardSources[0].Stopped);

        // Kartta "ikisi de" korunur, PS5'te TV olur.
        var w3 = new World(new AppSettings { VideoSource = VideoSource.Card, Output = SubtitleOutput.Both });
        Assert.Equal(SubtitleOutput.Both, w3.Open().Settings.Output);
        var w4 = new World(new AppSettings { Output = SubtitleOutput.Both });
        Assert.Equal(SubtitleOutput.Tv, w4.Open().Settings.Output);
    }

    [Fact] // 31
    public async Task ComputerOnlyNeverTouchesTv()
    {
        var w = Ready(SubtitleOutput.Computer, tv: false);
        w.Secrets.Set(SecretKeys.Tv, new StoredTv { Name = "Samsung", Host = "192.168.1.60", Brand = StoredTvBrand.Samsung });
        w.Services.FirewallService = new FakeFirewall { Rule = true };
        var c = w.Open();
        Assert.True(c.CanStart);
        Assert.False(c.ShowsOnTv);
        await c.StartAsync();
        Assert.Empty(w.Services.Watches);
        w.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.Network));
        w.Timers.Advance(TimeSpan.FromMinutes(5));
        await c.CheckConnectionsAsync();
        Assert.Equal(0, w.Services.TvCalls);
        c.Stop();
        Assert.False(w.Sleep.Active);
    }

    [Fact] // 31b
    public async Task StartFailureLeavesNothingBehind()
    {
        var w = Ready(SubtitleOutput.Computer, tv: false);
        w.Services.Ps5Error = new NativeLibraryMissingException("nino_native");
        var c = w.Open();
        var cleared = 0;
        c.ComputerOverlayCleared += () => cleared++;
        await Assert.ThrowsAsync<NativeLibraryMissingException>(() => c.StartAsync());
        Assert.False(c.IsTranslating);
        Assert.False(c.IsStarting);
        Assert.False(w.Sleep.Active);
        Assert.Equal(1, cleared);
        w.Services.Ps5Error = null;
        await c.StartAsync();
        Assert.True(c.IsTranslating);
    }

    [Fact] // 31c
    public async Task TvOnlyWithoutTvAndOutputSwitches()
    {
        var w = Ready(SubtitleOutput.Tv, tv: false);
        var c = w.Open();
        Assert.False(c.CanStart);
        Assert.True(c.NeedsTv);
        Assert.Equal("Not set up", c.TvStatusText);
        await c.StartAsync();
        Assert.Empty(w.Services.Ps5Sessions);

        var w2 = Ready(SubtitleOutput.Computer);
        var c2 = w2.Open();
        await c2.StartAsync();
        Assert.Empty(w2.Services.Watches);
        var s = c2.Settings;
        s.Output = SubtitleOutput.Both;
        c2.UpdateSettings(s);
        Assert.True(Assert.Single(w2.Services.Watches).Running);
        s.Output = SubtitleOutput.Computer;
        c2.UpdateSettings(s);
        Assert.False(w2.Services.Watches[0].Running);

        var w3 = Ready(SubtitleOutput.Tv, tv: false);
        var c3 = w3.Open();
        c3.NoTv();
        await c3.PairTvAsync(w3.Services.FoundTv);
        Assert.Equal(SubtitleOutput.Tv, c3.Settings.Output);
    }

    [Fact] // 32
    public async Task ExtraAreas()
    {
        var c0 = new World().Open();
        Assert.Null(c0.Settings.ExtraRegion1);
        Assert.False(c0.Settings.ExtraLive1);
        Assert.Equal(OneShotResult.NotConfigured, await c0.TranslateExtraRegionAsync(1));
        Assert.Equal(ResultTarget.Tv, c0.Settings.FreeAreaTarget);

        var w = Ready(SubtitleOutput.Computer);
        var settings = w.Saved;
        settings.ExtraRegion1 = new Region(0.03, 0.30, 0.66, 0.98);
        settings.ExtraLive1 = true;
        settings.ExtraRegion2 = new Region(0.5, 0.9, 0.1, 0.3);
        settings.ExtraTarget2 = ResultTarget.Computer;
        w.SettingsStore.Save(settings);
        var c = w.Open();
        Assert.Equal(OneShotResult.NotRunning, await c.TranslateExtraRegionAsync(2));
        await c.StartAsync();
        Assert.Equal(2, w.Services.ReaderFactory.Languages.Count);
        var popups = new List<PopupText>();
        c.ComputerPopup += popups.Add;
        w.Services.ReaderFactory.Text = "";
        w.Services.Ps5Sessions[0].Frame(World.Frame());
        Assert.Equal(OneShotResult.NoText, await c.TranslateExtraRegionAsync(2));
        var noText = Nino.Core.Text.TextCatalog.For("en").Get("status.area.noText");
        Assert.Equal(noText, Assert.Single(popups).Text);
        Assert.DoesNotContain(w.Services.Server.Of<Nino.Core.Link.SubtitleShown>(), e => e.Text == noText);
        w.Services.ReaderFactory.Text = "Quest log";
        settings = c.Settings;
        settings.ExtraTarget2 = ResultTarget.Tv;
        c.UpdateSettings(settings);
        Assert.Equal(OneShotResult.Shown, await c.TranslateExtraRegionAsync(2));
        var shown = w.Services.Server.Of<Nino.Core.Link.SubtitleShown>()[^1];
        Assert.Equal("TR: Quest log", shown.Text);
        Assert.NotNull(shown.Box);
        Assert.True(shown.DurationMs >= 6000);
        w.Services.ReaderFactory.Text = "";

        w.Services.ReaderFactory.Text = "Find the key";
        for (var i = 0; i < 4; i++)
        {
            w.Services.Ps5Sessions[0].Frame(BgraFrame.Filled(64, 36, (byte)(60 * i + 30)));
            await c.WaitForReadingAsync();
            w.Timers.Advance(TimeSpan.FromMilliseconds(1100));
        }
        Assert.Contains(w.Services.Server.Of<RegionShown>(), r => r.Id == "area1" && r.Text.StartsWith("TR: "));
        c.Stop();
        Assert.NotEmpty(w.Services.Server.Of<RegionsCleared>());

        Assert.Equal(OneShotResult.NotRunning, (await c.TranslateFreeAreaAsync(World.Frame(), Box.Whole)).Result);
        await c.StartAsync();
        w.Services.ReaderFactory.Text = "";
        Assert.Equal(OneShotResult.NoText, (await c.TranslateFreeAreaAsync(World.Frame(), Box.Whole)).Result);
    }

    [Fact] // 33
    public async Task TranslateScreen()
    {
        var w = Ready(SubtitleOutput.Computer);
        var c = w.Open();
        Assert.Equal(OneShotResult.NotRunning, await c.TranslateScreenAsync());
        await c.StartAsync();
        Assert.Equal(OneShotResult.NotRunning, await c.TranslateScreenAsync());
        Assert.Contains(w.Services.Server.Of<SubtitleShown>(), s => s.Text.Contains("PS5"));
        var overlay = new List<LocalSubtitleEvent>();
        c.ComputerOverlayEvent += overlay.Add;
        w.Services.ReaderFactory.Text = "";
        w.Services.Ps5Sessions[0].Frame(World.Frame());
        Assert.Equal(OneShotResult.NoText, await c.TranslateScreenAsync());
        w.Services.ReaderFactory.Text = "Check the radio";
        Assert.Equal(OneShotResult.Shown, await c.TranslateScreenAsync());
        Assert.Contains(overlay, e => e.Kind == LocalEventKind.Screen && e.Text.Contains("TR: Check the radio"));
        Assert.Equal(OneShotResult.Cleared, await c.TranslateScreenAsync());
        Assert.Contains(overlay, e => e.Kind == LocalEventKind.ScreenClear);
        Assert.Equal(OneShotResult.Shown, await c.TranslateScreenAsync());
    }

    [Fact] // 34
    public async Task StatusTextsAndDots()
    {
        var w = Ready();
        var c = w.Open();
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Format("status.ps5.pairedIdle", "PS5-789"), c.ConsoleStatusText);
        Assert.Equal(StatusTone.Idle, c.ConsoleTone);
        Assert.Equal(StatusTone.Idle, c.TvTone);
        await c.StartAsync();
        Assert.Equal(StatusTone.Warning, c.ConsoleTone);
        Assert.Equal(StatusTone.Warning, c.TvTone);
        var s = w.Services.Ps5Sessions[0];
        s.Status(SourceStatus.Down(DisconnectReason.ConsoleAsleep));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.ps5.asleep"), c.ConsoleStatusText);
        s.Status(SourceStatus.Down(DisconnectReason.Network));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.ps5.unreachable"), c.ConsoleStatusText);
        s.Status(SourceStatus.Down(DisconnectReason.NotFound, "192.168.1.70"));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Format("status.ps5.notFound", "192.168.1.70"), c.ConsoleStatusText);
        s.Status(SourceStatus.Down(DisconnectReason.Other, "Session Request RP Version Mismatch"));
        Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Format("status.common.reconnectingDetail", "Session Request RP Version Mismatch"), c.ConsoleStatusText);
        s.Status(SourceStatus.Streaming);
        Assert.Equal("Connected", c.ConsoleStatusText);
        Assert.Equal(StatusTone.Good, c.ConsoleTone);
        Assert.True(c.MainAccountHint);
        w.Services.Server.SetTvCount(1);
        Assert.Equal(StatusTone.Good, c.TvTone);
        Assert.Equal("Connected", c.TvStatusText);
        c.Stop();
        Assert.Equal(StatusTone.Good, c.TvTone);
        Assert.Equal(StatusTone.Idle, c.ConsoleTone);

        var tr = Ready();
        tr.Text = Nino.Core.Text.TextCatalog.For("tr");
        var ct = tr.Open();
        await ct.StartAsync();
        tr.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.Rejected, "0x80108bff"));
        Assert.Contains("0x80108bff", ct.ConsoleStatusText);
        tr.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        Assert.Equal(tr.Text.Get("status.common.connected"), ct.ConsoleStatusText);
    }

    [Fact] // §14 deneme altyazısı ve geçmiş
    public async Task TestSubtitleGoesToStreamWindowAlways()
    {
        var w = Ready(SubtitleOutput.Tv);
        var c = w.Open();
        var overlay = new List<LocalSubtitleEvent>();
        var stream = new List<LocalSubtitleEvent>();
        c.ComputerOverlayEvent += overlay.Add;
        c.StreamWindowEvent += stream.Add;
        await c.SendTestSubtitleAsync();
        Assert.Empty(overlay);
        var e = Assert.Single(stream);
        Assert.Equal(8000, e.DurationMs);
        Assert.Equal(w.Text.Get("status.testSubtitle"), e.Text);

        var w2 = Ready(SubtitleOutput.Computer);
        var c2 = w2.Open();
        var overlay2 = new List<LocalSubtitleEvent>();
        c2.ComputerOverlayEvent += overlay2.Add;
        await c2.SendTestSubtitleAsync();
        Assert.Single(overlay2);
    }

    [Fact]
    public async Task ShownLineGoesToHistoryAndMetrics()
    {
        var w = Ready();
        var c = w.Open();
        await c.StartAsync();
        Assert.Equal("", c.MetricsLine);
        w.Services.ReaderFactory.Text = "Lower the bridge";
        var src = w.Services.Ps5Sessions[0];
        src.Status(SourceStatus.Streaming);
        for (var i = 0; i < 12 && c.History.Count == 0; i++)
        {
            src.Frame(World.Frame());
            await c.WaitForReadingAsync();
            w.Timers.Advance(TimeSpan.FromMilliseconds(400));
        }
        var entry = Assert.Single(c.History);
        Assert.Equal("Lower the bridge", entry.Source);
        Assert.Equal("TR: Lower the bridge", entry.Translation);
        var en = Nino.Core.Text.TextCatalog.For("en");
        Assert.Equal(en.Format("reading.metrics.ocr", 0) + " · " + en.Format("reading.metrics.translation", 0) + " · " +
            en.Format("reading.metrics.delay", 0),
            System.Text.RegularExpressions.Regex.Replace(c.MetricsLine, @"\d+", "0"));
        Assert.False(c.MainAccountHint);
        c.Stop();
        await c.StartAsync();
        Assert.Equal("", c.MetricsLine);
    }

    [Fact]
    public async Task PauseClearsAndAnnounces()
    {
        var w = Ready();
        var c = w.Open();
        c.TogglePause();
        Assert.False(c.IsPaused);
        await c.StartAsync();
        c.TogglePause();
        Assert.True(c.IsPaused);
        Assert.Contains(w.Services.Server.Of<SubtitleShown>(), s => s.Text == w.Text.Get("status.pause.paused") && s.DurationMs == 1800);
        c.TogglePause();
        Assert.False(c.IsPaused);
    }

    [Fact]
    public void ClickThroughToggles()
    {
        var c = new World().Open();
        c.ToggleClickThrough();
        Assert.True(c.Settings.OverlayClickThrough);
        c.ToggleClickThrough();
        Assert.False(c.Settings.OverlayClickThrough);
    }

    [Fact]
    public void StreamBackgroundRoundTrip()
    {
        var w = new World();
        var c = w.Open();
        Assert.Equal(StreamBackground.Green, c.StreamBackground);
        c.SetStreamBackground(StreamBackground.Magenta);
        Assert.Equal("magenta", w.Secrets.Get<string>(SecretKeys.StreamBackground));
        Assert.Equal(StreamBackground.Magenta, w.Open().StreamBackground);
        w.Secrets.Set(SecretKeys.StreamBackground, "bozuk");
        Assert.Equal(StreamBackground.Green, w.Open().StreamBackground);
        Assert.Equal(0xFF, (StreamBackgroundColors.Rgb(StreamBackground.Green) >> 8) & 0xFF);
        Assert.Equal(1, StreamBackgroundColors.BoxOpacity(60));
        Assert.Equal(0, StreamBackgroundColors.BoxOpacity(0));
    }
}

public sealed class PhoneAndCoreTests
{
    [Fact]
    public async Task PoolFirstGameSetsUpPhoneReadersAndKeepsReading()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            var w = new World().WithPs5().WithTv();
            w.Services.Model.Installed = true;
            w.Services.PoolService = new Nino.Core.Library.TranslationPool(new Nino.Core.Library.TranslationPoolOptions(folder,
                new Uri("http://127.0.0.1:9/"), "1.0.0", new HttpClient()), "tr", true);
            var c = w.Open();
            c.ChooseGame("GTA VI");
            await c.StartAsync();
            w.Services.ReaderFactory.Text = "";
            for (var i = 0; i < 3; i++)
            {
                w.Services.Ps5Sessions[0].Frame(Nino.Core.Imaging.BgraFrame.Filled(64, 36, (byte)(i * 50)));
                await c.WaitForReadingAsync();
                w.Timers.Advance(TimeSpan.FromMilliseconds(500));
            }
            Assert.True(c.IsTranslating);
            Assert.True(w.Services.ReaderFactory.Languages.Count >= 3); // altyazı + telefon + harita
            c.Stop();
            Assert.Empty(w.Logs.Errors);
        }
        finally { Directory.Delete(folder, true); }
    }

    sealed class SmokeServices(CoreShellServicesOptions o) : CoreShellServices(o)
    {
        public override ITextReaderFactory Readers { get; } = new FakeReaders();
    }

    [Fact]
    public async Task CoreServicesBuildWithoutNetwork()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            var secrets = new MemorySecretStore();
            using var services = new SmokeServices(new CoreShellServicesOptions
            {
                DataFolder = folder,
                Secrets = secrets,
                Http = new HttpClient(),
                KeepLegacyTurkish = true,
            });
            Assert.True(services.FreeModel.Supports("en", "tr"));
            Assert.False(services.FreeModel.IsInstalled("en", "tr"));
            Assert.Null(services.Pool);
            Assert.Equal(Path.Combine(folder, "history.json"), services.HistoryPath);
            var w = new World();
            var c = new NinoController(services, secrets, w.SettingsStore, w.Sleep, w.Text, a => a(),
                new ShellOptions { Timers = w.Timers });
            Assert.Equal(SetupStep.Welcome, c.Step);
            Assert.Equal(TranslatorStatus.DownloadRequired, c.TranslatorStatus);
            await c.DisposeAsync();
        }
        finally { Directory.Delete(folder, true); }
    }
}
