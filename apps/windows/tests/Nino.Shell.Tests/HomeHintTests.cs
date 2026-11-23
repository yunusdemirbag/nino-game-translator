// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;
using Nino.Core.Text;
using Nino.RemotePlay;

namespace Nino.Shell.Tests;

/// <summary>Fiş balonu, Enter kısayolu ve alt şerit kuralları (Mac'in ana ekranıyla aynı; HomeHints.cs, HomeStrip.cs).</summary>
public sealed class HomeHintTests
{
    static readonly DateTimeOffset T0 = new(2026, 11, 23, 12, 0, 0, TimeSpan.Zero);

    static DateTimeOffset At(double seconds) => T0 + TimeSpan.FromSeconds(seconds);

    // ---- Fiş balonunun görünürlüğü ----

    [Fact]
    public void Constants_MatchMac()
    {
        Assert.Equal(0.06, PlugHintVisibility.FadedOpacity);
        Assert.Equal(TimeSpan.FromSeconds(1), PlugHintVisibility.HoverLinger);
        Assert.Equal(TimeSpan.FromSeconds(2), PlugHintVisibility.UseFlash);
        Assert.Equal(TimeSpan.FromSeconds(0.2), PlugHintVisibility.FadeIn);
        Assert.Equal(TimeSpan.FromSeconds(0.5), PlugHintVisibility.FadeOut);
    }

    [Fact]
    public void NeverUsed_AlwaysVisible_UntilFirstUse()
    {
        var hint = new PlugHintVisibility(learned: false);
        Assert.True(hint.IsVisible(At(0)));
        Assert.True(hint.IsVisible(At(1000)));
        Assert.Null(hint.NextChange(At(0)));
        hint.PlugUsed(At(10));
        Assert.True(hint.Learned);
        Assert.True(hint.IsVisible(At(11.9)));
        Assert.False(hint.IsVisible(At(12)));
        Assert.Equal(PlugHintVisibility.FadedOpacity, hint.Opacity(At(12)));
    }

    [Fact]
    public void Learned_FadedUntilHover_LingersOneSecond()
    {
        var hint = new PlugHintVisibility(learned: true);
        Assert.False(hint.IsVisible(At(0)));
        Assert.Equal(0.06, hint.Opacity(At(0)));
        hint.HoverChanged(true, At(1));
        Assert.True(hint.IsVisible(At(1)));
        Assert.Null(hint.NextChange(At(1)));
        Assert.True(hint.IsVisible(At(100)));
        hint.HoverChanged(false, At(5));
        Assert.True(hint.IsVisible(At(5.99)));
        Assert.Equal(At(6), hint.NextChange(At(5)));
        Assert.False(hint.IsVisible(At(6)));
        Assert.Null(hint.NextChange(At(6)));
    }

    [Fact]
    public void Use_FlashesTwoSeconds_AndNeverShortens()
    {
        var hint = new PlugHintVisibility(learned: true);
        hint.PlugUsed(At(0));
        Assert.True(hint.IsVisible(At(1.9)));
        // Fare çıkışı (1 sn) daha uzun görünürlüğü kısaltmaz.
        hint.HoverChanged(true, At(0.2));
        hint.HoverChanged(false, At(0.3));
        Assert.Equal(At(2), hint.VisibleUntil);
        Assert.False(hint.IsVisible(At(2)));
        // Tekrarlanan hover-girişi aynı durumda değişiklik yapmaz.
        hint.HoverChanged(false, At(10));
        Assert.Equal(At(2), hint.VisibleUntil);
    }

    [Fact]
    public void Flag_FileInDataFolder()
    {
        Assert.True(PlugHintFlag.Read(null));
        var folder = Path.Combine(Path.GetTempPath(), "nino-hint-" + Guid.NewGuid().ToString("N"));
        try
        {
            Assert.False(PlugHintFlag.Read(folder));
            PlugHintFlag.Write(folder);
            Assert.True(PlugHintFlag.Read(folder));
            Assert.True(File.Exists(Path.Combine(folder, "plug-hint-learned")));
        }
        finally
        {
            if (Directory.Exists(folder)) Directory.Delete(folder, true);
        }
    }

    // ---- Balonun metni ----

    [Fact]
    public void HintText_FirstMatch()
    {
        Assert.Equal("home.plug.unplugToStop", PlugHintText.Key(true, true, true, false));
        Assert.Null(PlugHintText.Key(true, false, true, false));
        Assert.Equal("home.plug.plugInToStart", PlugHintText.Key(false, false, true, true));
        Assert.Equal("home.hint.connectTVFirst", PlugHintText.Key(false, false, false, true));
        Assert.Equal("home.hint.connectPS5First", PlugHintText.Key(false, false, false, false));
    }

    // ---- Balonun yeri ----

    [Fact]
    public void Placement_FullSize_ArrowAboveSocket()
    {
        var scene = LivingRoomScene.Ps5;
        var width = SceneView.CanvasWidth(scene);
        var p = PlugHintPlacement.Compute(scene, width, LivingRoomScene.ImageHeight);
        Assert.Equal(scene.ShiftLeft + scene.Socket.X, p.ArrowTip.X, 6);
        Assert.Equal(scene.Socket.Y - 54, p.ArrowTip.Y, 6);
        Assert.Equal(p.ArrowTip.Y - 20, p.Box.Bottom, 6);
        // Balon TV çerçevesinin sağında ve alanın içinde; en çok 220 geniş.
        Assert.True(p.Box.X >= scene.ShiftLeft + scene.Frame.Right + 10 - 1e-6);
        Assert.True(p.Box.Right <= width - 4 + 1e-6);
        Assert.True(p.Box.Width <= PlugHintPlacement.MaxWidth);
        Assert.Equal(scene.Frame.Y, p.Box.Y, 6);
    }

    [Fact]
    public void Placement_ScalesDownAndCenters()
    {
        var scene = LivingRoomScene.Xbox;
        var view = SceneView.Of(scene, 800, 400);
        Assert.Equal(Math.Min(800 / SceneView.CanvasWidth(scene), 400 / LivingRoomScene.ImageHeight), view.Scale, 9);
        var p = PlugHintPlacement.Compute(scene, 800, 400);
        var socket = view.Point(scene.Socket);
        Assert.Equal(socket.X, p.ArrowTip.X, 6);
        Assert.Equal(socket.Y - 54 * view.Scale, p.ArrowTip.Y, 6);
        Assert.True(p.Box.Width >= 60);
        Assert.True(p.Box.Right <= 796 + 1e-6);
        // Hiç büyümez.
        Assert.Equal(1, SceneView.Of(scene, 5000, 5000).Scale);
        Assert.Equal(0, SceneView.Of(scene, 0, 100).Scale);
    }

    // ---- Enter ----

    [Fact]
    public void ReturnKey_OnlyOnHome_NoTextNoModifiers()
    {
        Assert.True(HomeReturnKey.ShouldHandle(true, false, false, true, true, false, false));
        Assert.False(HomeReturnKey.ShouldHandle(false, false, false, true, true, false, false));
        Assert.False(HomeReturnKey.ShouldHandle(true, true, false, true, true, false, false));
        Assert.False(HomeReturnKey.ShouldHandle(true, false, true, true, true, false, false));
        Assert.False(HomeReturnKey.ShouldHandle(true, false, false, false, true, false, false));
        Assert.False(HomeReturnKey.ShouldHandle(true, false, false, true, false, false, false));
        Assert.False(HomeReturnKey.ShouldHandle(true, false, false, true, true, true, false));
        Assert.False(HomeReturnKey.ShouldHandle(true, false, false, true, true, false, true));
    }

    // ---- Başlık ve alt şerit ----

    [Fact]
    public void VersionLabel_ShortAndTooltip()
    {
        Assert.Equal("V4.0", VersionLabel.Short("4.0.5"));
        Assert.Equal("V4.1", VersionLabel.Short("4.1.0-beta.2"));
        Assert.Equal("V0.0", VersionLabel.Short(""));
        Assert.Equal("V4.0 (4.0.5)", VersionLabel.Tooltip("4.0.5"));
    }

    [Fact]
    public void UpdateCenter_FirstMatch()
    {
        var downloading = UpdateCenterState.Choose(true, "4.1.0", UpdateCheckState.UpToDate, true);
        Assert.Equal(UpdateCenterKind.Downloading, downloading.Kind);
        Assert.Equal("4.1.0", downloading.Version);
        Assert.False(downloading.ShowsRecheck);
        Assert.Equal(UpdateCenterKind.NewVersion, UpdateCenterState.Choose(false, "4.1.0", UpdateCheckState.Checking, false).Kind);
        Assert.Equal("home.update.checking", UpdateCenterState.Choose(false, null, UpdateCheckState.Checking, false).TextKey);
        Assert.Equal("home.update.upToDate", UpdateCenterState.Choose(false, null, UpdateCheckState.UpToDate, false).TextKey);
        Assert.Equal("home.update.allUpToDate", UpdateCenterState.Choose(false, null, UpdateCheckState.UpToDate, true).TextKey);
        Assert.Equal("home.update.check", UpdateCenterState.Choose(false, null, UpdateCheckState.Failed, true).TextKey);
        var idle = UpdateCenterState.Choose(false, null, UpdateCheckState.Idle, false);
        Assert.Equal(UpdateCenterKind.Check, idle.Kind);
        Assert.True(idle.ShowsRecheck);
    }

    static readonly TextCatalog Text = TextCatalog.FromValues("tr", new Dictionary<string, string>
    {
        ["home.translation.poolGame"] = "Nino ile %@",
    });

    [Fact]
    public void TranslationLink_NeverSaysFree()
    {
        Assert.Equal("Nino ile Hades II", TranslationLinkRule.Value("Hades II", true, "tr", "DeepL", Text));
        Assert.Equal("DeepL", TranslationLinkRule.Value("Hades II", true, "ar", "DeepL", Text));
        Assert.Equal("Gemini", TranslationLinkRule.Value("Hades", false, "tr", "Gemini", Text));
        Assert.Equal("Nino ile Hades", TranslationLinkRule.Value("Hades", false, "tr", null, Text));
        Assert.Equal("Nino", TranslationLinkRule.Value(null, false, "tr", null, Text));
        Assert.Equal("Nino", TranslationLinkRule.Value("  ", true, "tr", null, Text));
    }

    [Fact]
    public void ShortDropKeys()
    {
        Assert.Equal("home.short.asleep", HomeShortStatus.DropKey(DisconnectReason.ConsoleAsleep));
        Assert.Equal("home.short.busy", HomeShortStatus.DropKey(DisconnectReason.InUse));
        Assert.Equal("home.short.pairAgain", HomeShortStatus.DropKey(DisconnectReason.Refused));
        Assert.Equal("home.short.pairAgain", HomeShortStatus.DropKey(DisconnectReason.RegistrationInvalid));
        Assert.Equal("home.short.passcode", HomeShortStatus.DropKey(DisconnectReason.LoginPasscode));
        Assert.Equal("home.short.passcodeWrong", HomeShortStatus.DropKey(DisconnectReason.LoginPasscodeIncorrect));
        Assert.Equal("home.short.remotePlayOff", HomeShortStatus.DropKey(DisconnectReason.RemotePlayDisabled));
        Assert.Equal("home.short.notFound", HomeShortStatus.DropKey(DisconnectReason.NotFound));
        Assert.Equal("home.short.noReply", HomeShortStatus.DropKey(DisconnectReason.Network));
        Assert.Equal("home.short.sessionRefused", HomeShortStatus.DropKey(DisconnectReason.Rejected));
        Assert.Null(HomeShortStatus.DropKey(DisconnectReason.Other));
        Assert.Null(HomeShortStatus.DropKey(null));
    }

    [Theory]
    [InlineData("en")]
    [InlineData("tr")]
    [InlineData("ar")]
    [InlineData("bn")]
    [InlineData("fil")]
    [InlineData("hi")]
    [InlineData("id")]
    [InlineData("ms")]
    [InlineData("nl")]
    [InlineData("th")]
    [InlineData("ur")]
    [InlineData("vi")]
    public void HomeKeys_InEveryLanguage(string language)
    {
        var text = TextCatalog.For(language);
        var keys = HomeShortStatus.Keys.Concat(
        [
            "home.plug.unplugToStop", "home.plug.plugInToStart", "home.hint.connectTVFirst", "home.hint.connectPS5First",
            "home.update.allUpToDate", "home.update.bannerTitle", "home.update.check", "home.update.checking",
            "home.update.download", "home.update.upToDate", "home.update.downloading", "home.update.newVersion",
            "home.version", "home.translation.poolGame", "home.keySuggestion.title", "home.keySuggestion.detail",
            "home.keySuggestion.dismiss", "home.tv.connect", "home.action.start", "home.action.stop",
        ]);
        foreach (var key in keys) Assert.NotEqual(key, text.Get(key));
    }

    // ---- Anahtar önerisi ----

    static readonly HashSet<string> None = [];

    [Fact]
    public void KeySuggestion_Rules()
    {
        PackInfo[] packs = [new("god-of-war", "God of War", 10)];
        Assert.Equal("Hades", KeySuggestionRule.Game(true, false, "en", "Hades", false, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(false, false, "en", "Hades", false, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, true, "en", "Hades", false, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, false, "ja", "Hades", false, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, false, "en", null, false, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, false, "en", "GTA 6", true, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, false, "en", "Hades", false, true, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, false, "en", "God of War", false, false, packs, None));
        Assert.Null(KeySuggestionRule.Game(true, false, "en", "Hades", false, false, packs,
            new HashSet<string> { KeySuggestionRule.IdOf("Hades") }));
    }

    [Fact]
    public void KeySuggestion_DismissedFile()
    {
        Assert.Empty(KeySuggestionRule.ReadDismissed(null));
        var folder = Path.Combine(Path.GetTempPath(), "nino-key-" + Guid.NewGuid().ToString("N"));
        try
        {
            Assert.Empty(KeySuggestionRule.ReadDismissed(folder));
            KeySuggestionRule.WriteDismissed(folder, ["b", "a"]);
            Assert.Equal(["a", "b"], File.ReadAllLines(Path.Combine(folder, KeySuggestionRule.DismissedFile)));
            Assert.Equal(new HashSet<string> { "a", "b" }, KeySuggestionRule.ReadDismissed(folder));
        }
        finally
        {
            if (Directory.Exists(folder)) Directory.Delete(folder, true);
        }
    }
}
