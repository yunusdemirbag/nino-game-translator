// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Design;
using Nino.Core.Health;
using Nino.Core.Settings;
using Nino.Shell.Panels;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

public class PanelTests
{
    [Theory]
    [InlineData("Grand Theft Auto V", "GTA")]
    [InlineData("Mafia: The Old Country", "MTO")]
    [InlineData("Red Dead Redemption 2", "RDR")]
    [InlineData("Cyberpunk 2077", "C2")]
    [InlineData("", "")]
    [InlineData("(Beta) - Ghost", "BG")]
    public void PackInitialsFollowTheRule(string title, string expected) =>
        Assert.Equal(expected, SettingsPanelRules.PackInitials(title));

    [Fact]
    public void WaitSecondsUseCultureSeparator()
    {
        Assert.Equal("0,8", SettingsPanelRules.Seconds(800, CultureInfo.GetCultureInfo("tr-TR")));
        Assert.Equal("0.3", SettingsPanelRules.Seconds(300, CultureInfo.InvariantCulture));
        Assert.Equal("1.234.567", SettingsPanelRules.Thousands(1234567, CultureInfo.GetCultureInfo("tr-TR")));
    }

    [Fact]
    public void ExtraAreasStartWhereTheSpecSays()
    {
        Assert.Equal(new Region(0.05, 0.28, 0.60, 0.97), SettingsPanelRules.ExtraStartRegion(1));
        Assert.Equal(new Region(0.72, 0.95, 0.60, 0.97), SettingsPanelRules.ExtraStartRegion(2));
        Assert.Equal(new Region(0.35, 0.65, 0.30, 0.70), SettingsPanelRules.ExtraStartRegion(3));
    }

    [Fact]
    public void CustomSlidersMoveTheRegionUp()
    {
        // Üst %90, yükseklik %20 → üst 0.80, alt 1.00 (tarif örneği).
        var r = RegionPresets.FromSliders(new Region(0.62, 0.97, 0.14, 0.86), 90, 20);
        Assert.Equal(0.80, r.Top, 6);
        Assert.Equal(1.00, r.Bottom, 6);
        Assert.Equal(0.14, r.Left);
        Assert.Equal(35, SettingsPanelRules.SliderPercent(35.4, 0, 95));
        Assert.Equal(95, SettingsPanelRules.SliderPercent(99, 0, 95));
    }

    [Fact]
    public void SavedWindowThatIsNotOpenComesFirst()
    {
        VisibleWindow[] open = [new("obs64", "Projector"), new("game", "Game")];
        var (items, selected) = SettingsPanelRules.CaptureWindows(open, new CaptureWindowChoice { ProcessName = "game", Title = "Game" });
        Assert.Equal(1, selected);
        Assert.Equal(2, items.Count);
        (items, selected) = SettingsPanelRules.CaptureWindows(open, new CaptureWindowChoice { ProcessName = "x", Title = "Gone" });
        Assert.Equal(0, selected);
        Assert.True(items[0].NotOpen);
        Assert.Equal(3, items.Count);
        (items, selected) = SettingsPanelRules.CaptureWindows(open, null);
        Assert.Equal(-1, selected);
        // Süreç adı aynı ama başlık farklı: eşleşmez.
        (_, selected) = SettingsPanelRules.CaptureWindows(open, new CaptureWindowChoice { ProcessName = "game", Title = "Other" });
        Assert.Equal(0, selected);
    }

    [Fact]
    public void NoticedProblemsAreLastThreeDaysNewestFirst()
    {
        var now = new DateTimeOffset(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);
        var records = Enumerable.Range(0, 10)
            .Select(i => new ProblemRecord { Date = now - TimeSpan.FromHours(i * 10), Kind = ProblemKind.Ps5Dropped })
            .ToList();
        var noticed = SettingsPanelRules.NoticedProblems(records, now);
        Assert.Equal(6, noticed.Count);
        Assert.Equal(now, noticed[0].Date);
        Assert.All(noticed, r => Assert.True(r.Date >= now - TimeSpan.FromDays(3)));
        var recent = SettingsPanelRules.RecentProblems(records);
        Assert.Equal(8, recent.Count);
        Assert.True(recent[0].Date > recent[1].Date);
    }

    [Fact]
    public void LogZipNameIsStamped() =>
        Assert.Equal("Nino-kayitlar-2026-11-22-21-04-05.zip", SettingsPanelRules.LogZipName(new DateTime(2026, 11, 22, 21, 4, 5)));

    // ---- Kısayol kaydı ----

    [Fact]
    public void CaptureStepsFollowTheRules()
    {
        Assert.Equal(CaptureStepKind.Wait, HotkeyCapture.Decide(0xA2, true, false, false, false).Kind);
        Assert.Equal(CaptureStepKind.Wait, HotkeyCapture.Decide(0x10, false, false, true, false).Kind);
        Assert.Equal(CaptureStepKind.Cancel, HotkeyCapture.Decide(0x1B, false, false, false, false).Kind);
        Assert.Equal(CaptureStepKind.Clear, HotkeyCapture.Decide(0x08, false, false, false, false).Kind);
        Assert.Equal(CaptureStepKind.Clear, HotkeyCapture.Decide(0x2E, false, false, false, false).Kind);
        var win = HotkeyCapture.Decide(0x41, false, false, false, true);
        Assert.Equal(CaptureStepKind.Error, win.Kind);
        Assert.Equal(HotkeyValidity.Reserved, win.Problem);
        Assert.Equal(CaptureStepKind.Assign, HotkeyCapture.Decide(0x69, false, false, false, false).Kind); // Num 9
        Assert.Equal(CaptureStepKind.Assign, HotkeyCapture.Decide(0x71, false, false, false, false).Kind); // F2
        Assert.Equal(HotkeyValidity.Unsupported, HotkeyCapture.Decide(0x7B, false, false, false, false).Problem); // F12
        Assert.Equal(HotkeyValidity.Unsupported, HotkeyCapture.Decide(0x1B, false, true, false, false).Problem); // Alt+Esc
        Assert.Equal(HotkeyValidity.NeedsModifier, HotkeyCapture.Decide(0x54, false, false, false, false).Problem); // T
        Assert.Equal(HotkeyValidity.NeedsModifier, HotkeyCapture.Decide(0x54, false, false, true, false).Problem); // Shift+T
        Assert.Equal(HotkeyValidity.NeedsModifier, HotkeyCapture.Decide(0x43, true, false, false, false).Problem); // Ctrl+C
        Assert.Equal(CaptureStepKind.Assign, HotkeyCapture.Decide(0x54, false, true, false, false).Kind); // Alt+T
        Assert.Equal(CaptureStepKind.Assign, HotkeyCapture.Decide(0x54, false, true, true, false).Kind); // Alt+Shift+T
        var ctrlShiftT = HotkeyCapture.Decide(0x54, true, false, true, false);
        Assert.Equal(new HotkeyKey(KeyModifiers.Control | KeyModifiers.Shift, 0x54), ctrlShiftT.Key);
        Assert.Equal(HotkeyValidity.AltGr, HotkeyCapture.Decide(0x33, true, true, false, false).Problem); // Ctrl+Alt+3
        Assert.Equal(HotkeyValidity.Reserved, HotkeyCapture.Decide(0x73, false, true, false, false).Problem); // Alt+F4
        Assert.Equal("settings.shortcuts.error.altGr", HotkeyCapture.ProblemKey(HotkeyValidity.AltGr));
    }

    // ---- Bölge seçici ----

    static readonly Region Box = new(0.5, 0.9, 0.2, 0.8); // 1000×500'de x 200–800, y 250–450

    [Fact]
    public void PickerFindsEdgesInsideAndOutside()
    {
        Assert.Equal(RegionDragMode.Resize, RegionPickerMath.ModeAt(Box, 205, 300, 1000, 500, out var e));
        Assert.Equal(RegionEdges.Left, e);
        RegionPickerMath.ModeAt(Box, 795, 448, 1000, 500, out e);
        Assert.Equal(RegionEdges.Right | RegionEdges.Bottom, e);
        Assert.Equal(RegionDragMode.Move, RegionPickerMath.ModeAt(Box, 500, 350, 1000, 500, out _));
        Assert.Equal(RegionDragMode.Draw, RegionPickerMath.ModeAt(Box, 100, 100, 1000, 500, out _));
        // Büyütülmüş çerçevenin dışı: kenara yakın olsa da yeni çizim.
        Assert.Equal(RegionDragMode.Draw, RegionPickerMath.ModeAt(Box, 189, 300, 1000, 500, out _));
        Assert.Equal(RegionCursor.NorthWestSouthEast, RegionPickerMath.CursorAt(Box, 200, 250, 1000, 500));
        Assert.Equal(RegionCursor.NorthEastSouthWest, RegionPickerMath.CursorAt(Box, 800, 250, 1000, 500));
        Assert.Equal(RegionCursor.NorthSouth, RegionPickerMath.CursorAt(Box, 500, 452, 1000, 500));
        Assert.Equal(RegionCursor.Move, RegionPickerMath.CursorAt(Box, 500, 350, 1000, 500));
        Assert.Equal(RegionCursor.Cross, RegionPickerMath.CursorAt(Box, 50, 50, 1000, 500));
    }

    [Fact]
    public void PickerMovesResizesAndDraws()
    {
        var moved = RegionPickerMath.Move(Box, 0.5, -0.9);
        Assert.Equal(0.6, moved.Right - moved.Left, 6);
        Assert.Equal(1.0, moved.Right, 6);
        Assert.Equal(0.0, moved.Top, 6);
        var resized = RegionPickerMath.Resize(Box, RegionEdges.Left, 0.95, 0.5);
        Assert.Equal(0.77, resized.Left, 6); // karşı kenara en çok 0.03
        var drawn = RegionPickerMath.Draw(0.7, 0.8, 0.1, 0.2);
        Assert.Equal(new Region(0.2, 0.8, 0.1, 0.7), drawn);
        var tiny = RegionPickerMath.Draw(0.5, 0.5, 0.51, 0.6);
        Assert.Same(Box, RegionPickerMath.Finish(RegionDragMode.Draw, Box, tiny));
        Assert.Equal(drawn, RegionPickerMath.Finish(RegionDragMode.Draw, Box, drawn));
        Assert.Equal(281, RegionPickerMath.PreviewHeight(double.NaN));
        Assert.Equal(120, RegionPickerMath.PreviewHeight(100));
        Assert.Equal(450, RegionPickerMath.PreviewHeight(800), 6);
        Assert.Equal(600, RegionPickerMath.PreviewHeight(800, 4, 3), 6);
    }

    // ---- Elle seçilen alan ve altyazı penceresi ----

    [Fact]
    public void FreeAreaBoxGoesBelowOrAbove()
    {
        Assert.True(FreeAreaMath.TooSmall(10, 500, 1920, 1080));
        Assert.False(FreeAreaMath.TooSmall(100, 100, 1920, 1080));
        var (left, top) = FreeAreaMath.ResultPosition(100, 100, 300, 400, 80, 1920, 1080);
        Assert.Equal(100, left);
        Assert.Equal(300 + 1080 * 0.012, top, 6);
        (_, top) = FreeAreaMath.ResultPosition(100, 900, 1050, 400, 80, 1920, 1080);
        Assert.Equal(900 - 1080 * 0.012 - 80, top, 6);
        (left, _) = FreeAreaMath.ResultPosition(1800, 100, 200, 400, 80, 1920, 1080);
        Assert.Equal(1520, left);
        Assert.Equal(3, FreeAreaMath.BorderThickness(1080));
        Assert.Equal(34.56, FreeAreaMath.FontSize(1080), 6);
        Assert.Equal(16, FreeAreaMath.FontSize(100));
    }

    [Fact]
    public void OverlayHandlesKeepTheCenter()
    {
        ScreenRect[] screens = [new(0, 0, 1920, 1080)];
        Assert.Equal((340, 320), OverlayDrawing.ResizeFromCenter(0, 1000, -500, [new(0, 0, 200, 1080)]));
        Assert.Equal(320, OverlayDrawing.ResizeFromCenter(0, 1000, double.NaN, screens).Width);
        Assert.Equal(1920, OverlayDrawing.ResizeFromCenter(0, 1000, 2000, screens).Width);
        Assert.Equal((-50, 1100), OverlayDrawing.ResizeFromCenter(0, 1000, 50, screens));
        Assert.Equal(900, OverlayLayout.ResizeWidth(900, [new(0, 0, double.NaN, 1080)]));
        Assert.Equal(36.8, OverlayDrawing.LineFontSize(46, 1, false, 1), 6);
        Assert.Equal(46, OverlayDrawing.LineFontSize(0, 1, true, 1), 6);
        Assert.Equal(0.83, OverlayDrawing.LineBackground(100, false), 6);
        Assert.Equal(-1, OverlayDrawing.RegionAlignment(0.2));
        Assert.Equal(1, OverlayDrawing.RegionAlignment(0.7));
        Assert.Equal(0, OverlayDrawing.RegionAlignment(null));
        var seat = OverlayDrawing.OnGame(new PixelRect(0, 0, 1920, 1080), 192, 400);
        Assert.Equal(864, seat.Width);
        Assert.Equal(540 - 540 * 0.03, seat.Bottom, 6);
        Assert.Equal(48, seat.X, 6);
    }

    // ---- Sağlık ----

    [Fact]
    public void HealthDetailsHaveTheFixedLines()
    {
        var text = HealthDetailsText.Build(new HealthDetailsText.Input("0.1.0", "10.0.26100", 8, null, false, "Disconnected",
            null, 0, "Unknown", null, null, ["ağ: wifi, oturumdaki ağ kaybı 0, TV kaybı 0"], null, ["satır 1", "", "satır 2"]));
        var lines = text.Split('\n');
        Assert.Equal("Nino 0.1.0, Windows 10.0.26100, 8 çekirdek", lines[0]);
        Assert.Equal("motor: ücretsiz, çeviri: durdu, PS5: Disconnected", lines[1]);
        Assert.Equal("TV: yok, bağlı TV uygulaması 0, TV uygulaması: Unknown", lines[2]);
        Assert.Contains("— altyazi.log, en son satırlar —\n-\n", text);
        Assert.EndsWith("— tvinstall.log, en son satırlar —\nsatır 1\nsatır 2", text);
    }

    [Fact]
    public void CardPreviewLooks()
    {
        Assert.Equal(StatusTone.Good, CardPreviewLook.For(CardCaptureState.Capturing).Tone);
        Assert.False(CardPreviewLook.For(CardCaptureState.BlackPicture).PlaceholderVisible);
        var noPermission = CardPreviewLook.For(CardCaptureState.NeedsPermission);
        Assert.True(noPermission.PlaceholderLock);
        Assert.True(noPermission.ShowCameraSettings);
        var stopped = CardPreviewLook.For(CardCaptureState.Stopped);
        Assert.Equal(StatusTone.Idle, stopped.Tone);
        Assert.Null(stopped.DetailKey);
        // Kart başka uygulamada açıkken "kartı takın" değil, "kart meşgul" denir.
        var inUse = CardPreviewLook.For(CardCaptureState.InUse);
        Assert.Equal(StatusTone.Warning, inUse.Tone);
        Assert.Equal("cardGuide.preview.inUsePill", inUse.PillKey);
        Assert.Equal("cardGuide.preview.inUseDetail", inUse.DetailKey);
        Assert.True(Nino.Shell.WindowsRules.CaptureCardRules.IsInUse(unchecked((int)0xC00D3704)));
        Assert.False(Nino.Shell.WindowsRules.CaptureCardRules.IsInUse(unchecked((int)0x80004005)));
    }
}
