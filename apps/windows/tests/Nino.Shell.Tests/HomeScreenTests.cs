// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.App.Startup;
using Nino.Core.Design;
using Nino.Core.Text;
using Nino.RemotePlay;

namespace Nino.Shell.Tests;

/// <summary>Ana ekranın arayüzsüz kuralları (ana-ekran.md) ve açılıştaki eksik dosya denetimi (kimlikler-veri.md §3.3).</summary>
public sealed class HomeScreenTests
{
    static readonly TextCatalog Text = TextCatalog.FromValues("tr", new Dictionary<string, string>
    {
        ["home.footer.gameWindow"] = "Pencereden",
        ["status.card.defaultName"] = "Kart",
        ["home.footer.ps5Ready"] = "%@ · hazır",
        ["home.footer.connectTv"] = "TV Bağlayın ›",
    });

    // ---- Yay (§4.9) ----

    [Fact]
    public void SpringStartsAtOneAndStopsAtDuration()
    {
        Assert.Equal(1, PlugSpring.Remaining(0));
        Assert.Equal(0, PlugSpring.Remaining(0.9));
        Assert.Equal(0, PlugSpring.Remaining(2));
        var omega = 2 * Math.PI / 0.55;
        var omegaD = omega * Math.Sqrt(1 - 0.49);
        var t = 0.2;
        var expected = Math.Exp(-0.7 * omega * t) * (Math.Cos(omegaD * t) + 0.7 * omega / omegaD * Math.Sin(omegaD * t));
        Assert.Equal(expected, PlugSpring.Remaining(t), 12);
        Assert.InRange(PlugSpring.Remaining(0.05), 0.5, 1);
        Assert.InRange(Math.Abs(PlugSpring.Remaining(0.85)), 0, 0.1);
    }

    // ---- Bırakma (§4.10) ----

    [Fact]
    public void ShortDragIsAClick()
    {
        var scene = LivingRoomScene.Ps5;
        Assert.Equal(PlugRelease.Toggle, PlugDrop.Decide(scene, false, new ScenePoint(3, 4)));
        Assert.Equal(PlugRelease.Toggle, PlugDrop.Decide(scene, true, new ScenePoint(0, 0)));
    }

    [Fact]
    public void DroppingNearTheSocketToggles()
    {
        var scene = LivingRoomScene.Ps5;
        var toSocket = new ScenePoint(scene.Socket.X - scene.PlugRest.X + 20, scene.Socket.Y - scene.PlugRest.Y + 30);
        Assert.Equal(PlugRelease.Toggle, PlugDrop.Decide(scene, false, toSocket));
        // Takılı fiş prizin yakınında bırakılırsa yerine döner; uzağa çekilirse çevirisi durur.
        Assert.Equal(PlugRelease.SnapBack, PlugDrop.Decide(scene, true, new ScenePoint(50, 60)));
        Assert.Equal(PlugRelease.Toggle, PlugDrop.Decide(scene, true, new ScenePoint(0, 200)));
        // Çıkık fiş biraz sürüklenip bırakılırsa yerine döner.
        Assert.Equal(PlugRelease.SnapBack, PlugDrop.Decide(scene, false, new ScenePoint(-40, -20)));
    }

    [Fact]
    public void SocketReachIsStrictlyBelow140()
    {
        var scene = LivingRoomScene.Xbox;
        var rest = scene.PlugRest;
        var socket = scene.Socket;
        // Bitiş = dinlenme + fark; prizden tam 140 uzakta "yakın" sayılmaz.
        var exactly = new ScenePoint(socket.X - rest.X, socket.Y + 140 - rest.Y);
        Assert.Equal(PlugRelease.SnapBack, PlugDrop.Decide(scene, false, exactly));
        var inside = new ScenePoint(socket.X - rest.X, socket.Y + 139 - rest.Y);
        Assert.Equal(PlugRelease.Toggle, PlugDrop.Decide(scene, false, inside));
    }

    // ---- TV ekranı (§5) ----

    [Fact]
    public void TvScreenChoice()
    {
        Assert.Equal(TvScreenKind.Idle, TvScreenRule.Choose(false, false));
        Assert.Equal(TvScreenKind.Idle, TvScreenRule.Choose(false, true));
        Assert.Equal(TvScreenKind.Splash, TvScreenRule.Choose(true, false));
        Assert.Equal(TvScreenKind.Live, TvScreenRule.Choose(true, true));
        Assert.False(TvScreenRule.DownloadsVisible(true, TvScreenKind.Idle));
        Assert.True(TvScreenRule.DownloadsVisible(false, TvScreenKind.Idle));
        Assert.False(TvScreenRule.DownloadsVisible(false, TvScreenKind.Splash));
        Assert.True(TvScreenRule.DownloadsVisible(false, TvScreenKind.Live));
    }

    [Fact]
    public void LiveLineChoice()
    {
        Assert.Equal(new LiveLine("Bağlanıyor…", false),
            LiveLineRule.Choose(SourcePhase.Connecting, "Merhaba", "Bağlanıyor…", "bekleniyor"));
        Assert.Equal(new LiveLine("bekleniyor", false), LiveLineRule.Choose(SourcePhase.Streaming, null, "Bağlı", "bekleniyor"));
        Assert.Equal(new LiveLine("bekleniyor", false), LiveLineRule.Choose(SourcePhase.Streaming, "", "Bağlı", "bekleniyor"));
        Assert.Equal(new LiveLine("Merhaba", true), LiveLineRule.Choose(SourcePhase.Streaming, "Merhaba", "Bağlı", "bekleniyor"));
    }

    // ---- İndirme sayacı (§5.4, §5.5) ----

    [Fact]
    public void CountUpShowsOneTwoThreeThenAccelerates()
    {
        const long total = 3439;
        Assert.Equal(1, DownloadCountUp.Shown(0, total));
        Assert.Equal(1, DownloadCountUp.Shown(279, total));
        Assert.Equal(2, DownloadCountUp.Shown(280, total));
        Assert.Equal(3, DownloadCountUp.Shown(560, total));
        Assert.Equal(3, DownloadCountUp.Shown(840, total));
        var half = 840 + 1550 / 2.0;
        Assert.Equal((long)Math.Round(Math.Pow(0.5, 2.6) * total, MidpointRounding.AwayFromZero), DownloadCountUp.Shown(half, total));
        Assert.Equal(total, DownloadCountUp.Shown(840 + 1550, total));
        Assert.Equal(total, DownloadCountUp.Shown(9999, total));
        Assert.False(DownloadCountUp.Finished(2389));
        Assert.True(DownloadCountUp.Finished(2390));
    }

    [Fact]
    public void CountUpPlaysOnlyAboveThreeWithMotion()
    {
        Assert.False(DownloadCountUp.Plays(3, false));
        Assert.True(DownloadCountUp.Plays(4, false));
        Assert.False(DownloadCountUp.Plays(3439, true));
    }

    [Fact]
    public void DownloadsUseRegionalGrouping()
    {
        Assert.Equal("3.439", DownloadCountUp.Format(3439, CultureInfo.GetCultureInfo("tr-TR")));
        Assert.Equal("3,439", DownloadCountUp.Format(3439, CultureInfo.GetCultureInfo("en-US")));
        Assert.Equal("12", DownloadCountUp.Format(12, CultureInfo.GetCultureInfo("en-US")));
    }

    // ---- Cam anahtar (§6.5) ----

    [Fact]
    public void ToggleLabels()
    {
        Assert.Equal("status.common.connecting", GlassToggleText.TitleKey(true, false));
        Assert.Equal("home.toggle.turnOn", GlassToggleText.TitleKey(false, true));
        Assert.Equal("home.toggle.connectPs5", GlassToggleText.TitleKey(false, false));
        Assert.Equal("home.toggle.turkishSubtitles", GlassToggleText.SubtitleKey(false, true));
        Assert.Equal("home.toggle.turkishSubtitles", GlassToggleText.SubtitleKey(true, false));
        Assert.Equal("home.toggle.tapToSetUp", GlassToggleText.SubtitleKey(false, false));
    }

    [Fact]
    public void CrescentAndStarGeometry()
    {
        const double b = 52.2;
        var (moon, r) = CrescentStar.Moon(b);
        Assert.Equal(0.42 * b, moon.X, 9);
        Assert.Equal(b / 2, moon.Y, 9);
        Assert.Equal(0.42 * b, r, 9);
        var (cut, cr) = CrescentStar.Cut(b);
        Assert.Equal(0.42 * b + 0.32 * r, cut.X, 9);
        Assert.Equal(0.8 * r, cr, 9);
        var star = CrescentStar.Star(b);
        Assert.Equal(10, star.Count);
        // İlk köşe sola, aya bakar.
        Assert.Equal(0.8 * b - 0.17 * b, star[0].X, 9);
        Assert.Equal(b / 2, star[0].Y, 9);
        var inner = Math.Sqrt(Math.Pow(star[1].X - 0.8 * b, 2) + Math.Pow(star[1].Y - b / 2, 2));
        Assert.Equal(0.17 * b * 0.382, inner, 9);
    }

    // ---- Aç/kapat (§4.11) ----

    [Fact]
    public void ToggleDecision()
    {
        Assert.Equal(HomeToggleAction.Stop, HomeToggleRule.Decide(true, true, false, true));
        Assert.Equal(HomeToggleAction.Start, HomeToggleRule.Decide(false, true, false, true));
        Assert.Equal(HomeToggleAction.OpenTvStep, HomeToggleRule.Decide(false, false, true, true));
        Assert.Equal(HomeToggleAction.OpenConsoleStep, HomeToggleRule.Decide(false, false, true, false));
        Assert.Equal(HomeToggleAction.OpenConsoleStep, HomeToggleRule.Decide(false, false, false, true));
        Assert.Equal(SetupStep.Tv, HomeToggleRule.StepFor(HomeToggleAction.OpenTvStep));
        Assert.Equal(SetupStep.Console, HomeToggleRule.StepFor(HomeToggleAction.OpenConsoleStep));
    }

    // ---- Alt şerit (§3.2) ----

    static HomeFooterInput Ps5Ready => new()
    {
        ConsoleTitle = "PS5",
        OnStreamPath = true,
        FrameSourceIsPs5 = true,
        HasConsole = true,
        ConsoleName = "PS5-123",
        ConsoleStatusText = "PS5-123 ile eşleşti.",
        ShowsOnTv = true,
        TvPaired = true,
        TvStatusText = "Bağlı",
        TvTone = StatusTone.Good,
        TranslationSourceText = "Ücretsiz",
    };

    [Fact]
    public void FooterShowsPairedPs5AsReady()
    {
        var state = HomeFooter.Compute(Ps5Ready, Text);
        Assert.Equal("PS5", state.SourceName);
        Assert.Equal("PS5-123 · hazır", state.SourceValue);
        Assert.Equal("Bağlı", state.TvValue);
        Assert.Equal(StatusTone.Good, state.TvTone);
        Assert.False(state.TvClickOpensSetup);
        Assert.Equal("Ücretsiz", state.TranslationSource);
        Assert.Equal("PS5 · hazır", HomeFooter.Compute(Ps5Ready with { ConsoleName = "" }, Text).SourceValue);
    }

    [Fact]
    public void FooterFallsBackToStatusText()
    {
        Assert.Equal("Bağlanıyor…", HomeFooter.Compute(Ps5Ready with { IsTranslating = true, ConsoleStatusText = "Bağlanıyor…" }, Text).SourceValue);
        Assert.Equal("Durum", HomeFooter.Compute(Ps5Ready with { IsXbox = true, ConsoleStatusText = "Durum" }, Text).SourceValue);
        Assert.Equal("Durum", HomeFooter.Compute(Ps5Ready with { FrameSourceIsPs5 = false, ConsoleStatusText = "Durum" }, Text).SourceValue);
        Assert.Equal("Durum", HomeFooter.Compute(Ps5Ready with { HasConsole = false, ConsoleStatusText = "Durum" }, Text).SourceValue);
        Assert.Equal("Durum", HomeFooter.Compute(Ps5Ready with { OnStreamPath = false, ConsoleStatusText = "Durum" }, Text).SourceValue);
    }

    [Fact]
    public void FooterSourceNames()
    {
        Assert.Equal("Pencereden", HomeFooter.Compute(Ps5Ready with { UsesGameWindow = true }, Text).SourceName);
        Assert.Equal("Kart", HomeFooter.Compute(Ps5Ready with { UsesCaptureCard = true }, Text).SourceName);
        Assert.Equal("Xbox", HomeFooter.Compute(Ps5Ready with { ConsoleTitle = "Xbox" }, Text).SourceName);
    }

    [Fact]
    public void FooterAsksToConnectATv()
    {
        var state = HomeFooter.Compute(Ps5Ready with { TvPaired = false, TvTone = StatusTone.Idle }, Text);
        Assert.True(state.TvVisible);
        Assert.Equal("TV Bağlayın ›", state.TvValue);
        Assert.Equal(StatusTone.Warning, state.TvTone);
        Assert.True(state.TvClickOpensSetup);
        Assert.False(HomeFooter.Compute(Ps5Ready with { ShowsOnTv = false }, Text).TvVisible);
    }

    // ---- Oyun kartı (§3.4 kart 2) ----

    [Fact]
    public void GamePickerOffersTypedNameOnlyWhenNew()
    {
        Assert.False(GamePickerRule.OffersTyped(null, ["A"]));
        Assert.False(GamePickerRule.OffersTyped("  ", ["A"]));
        Assert.False(GamePickerRule.OffersTyped("God of War", ["God of War", "Hades"]));
        Assert.False(GamePickerRule.OffersTyped("god of war", ["God of War"]));
        Assert.True(GamePickerRule.OffersTyped("My Indie Game", ["God of War"]));
        Assert.Equal(5, GamePickerRule.Shown(["a", "b", "c", "d", "e", "f", "g"]).Count);
        Assert.Equal(2, GamePickerRule.Shown(["a", "b"]).Count);
    }

    // ---- Yazı tanıma paketi (§3.4 kart 9) ----

    [Fact]
    public void OcrLanguageCodeIsValidatedBeforeElevation()
    {
        Assert.True(OcrLanguageCode.IsSafe("en"));
        Assert.True(OcrLanguageCode.IsSafe("en-US"));
        Assert.True(OcrLanguageCode.IsSafe("zh-Hans"));
        Assert.False(OcrLanguageCode.IsSafe(null));
        Assert.False(OcrLanguageCode.IsSafe(""));
        Assert.False(OcrLanguageCode.IsSafe("en'; Remove-Item C:\\"));
        Assert.False(OcrLanguageCode.IsSafe("e"));
        Assert.Equal("Language.OCR~~~en-*", OcrLanguageCode.CapabilityPattern("en"));
        Assert.Equal("Language.OCR~~~en-*", OcrLanguageCode.CapabilityPattern("EN-us"));
        Assert.Null(OcrLanguageCode.CapabilityPattern("en$x"));
    }

    // ---- Eksik dosya denetimi (kimlikler-veri §3.3) ----

    const string Deps = """
        {
          "runtimeTarget": { "name": ".NETCoreApp,Version=v10.0/win-x64" },
          "targets": {
            ".NETCoreApp,Version=v10.0/win-x64": {
              "Nino/0.1.0": { "dependencies": {}, "runtime": { "Nino.dll": {} } },
              "Nino.RemotePlay/0.1.0": { "runtime": { "Nino.RemotePlay.dll": {} } },
              "Velopack/1.2.161": { "runtime": { "lib/net8.0/Velopack.dll": { "assemblyVersion": "1.0.0.0" } } },
              "Native/1.0": { "native": { "runtimes/win-x64/native/x.dll": {} } },
              "Dup/1.0": { "runtime": { "lib/NINO.DLL": {} } }
            },
            ".NETCoreApp,Version=v10.0": { "Other/1.0": { "runtime": { "lib\\Other.dll": {} } } }
          }
        }
        """;

    [Fact]
    public void DepsRuntimeNamesAreFileNamesOnly()
    {
        var names = StartupFiles.RuntimeFileNames(Deps);
        Assert.Equal(["Nino.dll", "Nino.RemotePlay.dll", "Other.dll", "Velopack.dll"], names);
        Assert.Empty(StartupFiles.RuntimeFileNames("{ bozuk"));
        Assert.Empty(StartupFiles.RuntimeFileNames("[]"));
    }

    [Fact]
    public void MissingFilesAreFoundInTheAppFolder()
    {
        var folder = Path.Combine(Path.GetTempPath(), "nino-startup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            Assert.Empty(StartupFiles.FindMissing(folder));
            File.WriteAllText(Path.Combine(folder, StartupFiles.DepsFile), Deps);
            foreach (var name in new[] { "nino.dll", "Velopack.dll", "Other.dll" }) File.WriteAllText(Path.Combine(folder, name), "");
            Assert.Equal(["Nino.RemotePlay.dll"], StartupFiles.FindMissing(folder));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void MissingFilesMessageListsAtMostEight()
    {
        var turkish = StartupMessages.MissingFiles(["Nino.RemotePlay.dll"], true);
        Assert.Contains("Nino.RemotePlay.dll", turkish);
        Assert.Contains("antivirüs", turkish);
        var english = StartupMessages.MissingFiles(Enumerable.Range(1, 10).Select(i => $"f{i}.dll").ToArray(), false);
        Assert.Contains("• f8.dll", english);
        Assert.DoesNotContain("f9.dll", english);
        Assert.Contains("…", english);
        Assert.Contains("Extract all", english);
    }

    [Fact]
    public void ErrorMessagesEndWithTheReportHint()
    {
        var text = StartupMessages.StartupError(new InvalidOperationException("boom"), @"C:\Users\a\AppData\Local\Nino\hata.log", false);
        Assert.StartsWith(TextCatalog.For("en").Get("app.error.startup"), text);
        Assert.Contains("InvalidOperationException: boom", text);
        Assert.Contains(@"C:\Users\a\AppData\Local\Nino\hata.log", text);
        Assert.EndsWith(StartupMessages.IssuesUrl, text);
        Assert.StartsWith(TextCatalog.For("tr").Get("app.error.crash"), StartupMessages.Crash(null, null, true));
    }
}
