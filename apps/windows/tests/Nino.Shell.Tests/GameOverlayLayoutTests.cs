// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Shell.Panels;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

/// <summary>Kart oynatıcısında altyazı penceresinin yeri ve örtü panellerinin çizim hesabı.</summary>
public sealed class GameOverlayLayoutTests
{
    static readonly PixelRect Game = new(0, 0, 1920, 1080);
    static readonly ScreenRect Screen = new(0, 0, 1920, 1080);
    static readonly ScreenRect Work = new(0, 0, 1920, 1032);
    const double Height = 513;
    static readonly double Text = CardOverlaySeat.TextBlockHeight(46, 1);

    static OverlaySeat Place(Box? english, SubtitlePlacement placement = SubtitlePlacement.Cover,
        OverlayPlacement? saved = null, OverlaySeat? current = null) =>
        CardOverlaySeat.Place(Game, 96, Height, Text, english, placement, saved, [Screen], Work, 1, current);

    static bool Overlaps(OverlaySeat seat, Box english)
    {
        var (top, bottom) = CardOverlaySeat.Zone(seat, Text);
        return bottom > english.Top * 1080 && top < english.Bottom * 1080;
    }

    [Fact]
    public void SavedPlacementWins()
    {
        var seat = Place(new Box(0.2, 0.85, 0.8, 0.92), saved: new OverlayPlacement { Left = 100, Top = 200, Width = 1000 });
        Assert.True(seat.UserPlaced);
        Assert.Equal(new ScreenRect(100, 200, 1000, Height), seat.Rect);
    }

    [Fact]
    public void WithoutEnglishBoxSitsAtTheBottomLikeBefore()
    {
        var seat = Place(null);
        Assert.Equal(OverlayDrawing.OnGame(Game, 96, Height), seat.Rect);
        Assert.False(seat.TopAligned);
        Assert.Equal(OverlayDrawing.OnGame(Game, 96, Height), Place(new Box(0.2, 0.85, 0.8, 0.92), SubtitlePlacement.Fixed).Rect);
    }

    [Fact]
    public void BottomSubtitleGoesAboveTheEnglishLine()
    {
        var english = new Box(0.2, 0.85, 0.8, 0.92);
        Assert.True(Overlaps(Place(null), english));
        var seat = Place(english);
        Assert.False(seat.TopAligned);
        Assert.Equal(0.85 * 1080 - 1080 * CardOverlaySeat.Gap, seat.Rect.Bottom, 6);
        Assert.False(Overlaps(seat, english));
        Assert.Equal(1728, seat.Rect.Width);
    }

    [Fact]
    public void TopSubtitleGoesBelow()
    {
        var english = new Box(0.2, 0.04, 0.8, 0.1);
        var seat = Place(english);
        Assert.True(seat.TopAligned);
        Assert.Equal(0.1 * 1080 + 1080 * CardOverlaySeat.Gap, seat.Rect.Y, 6);
        Assert.False(Overlaps(seat, english));
    }

    [Fact]
    public void BelowPlacementPrefersBelow()
    {
        var english = new Box(0.2, 0.5, 0.8, 0.55);
        Assert.True(Place(english, SubtitlePlacement.Below).TopAligned);
        Assert.False(Place(english, SubtitlePlacement.Above).TopAligned);
        // Altında yer yoksa üstüne.
        Assert.False(Place(new Box(0.2, 0.88, 0.8, 0.95), SubtitlePlacement.Below).TopAligned);
    }

    [Fact]
    public void StaysPutWhileItDoesNotOverlap()
    {
        var first = Place(new Box(0.2, 0.85, 0.8, 0.92));
        var next = Place(new Box(0.22, 0.86, 0.78, 0.93), current: first);
        Assert.Equal(first, next);
        var moved = Place(new Box(0.2, 0.62, 0.8, 0.7), current: first);
        Assert.NotEqual(first, moved);
        Assert.False(Overlaps(moved, new Box(0.2, 0.62, 0.8, 0.7)));
    }

    [Fact]
    public void DpiIsApplied()
    {
        var seat = CardOverlaySeat.Place(new PixelRect(0, 0, 3840, 2160), 192, Height, Text, new Box(0.2, 0.85, 0.8, 0.92),
            SubtitlePlacement.Cover, null, [Screen], Work, 1);
        Assert.Equal(0.85 * 1080 - 1080 * CardOverlaySeat.Gap, seat.Rect.Bottom, 6);
    }

    [Fact]
    public void PanelFlags()
    {
        var backdrop = ScreenPanelLayout.Layout(new ScreenItem(new Box(0.3, 0.2, 0.57, 0.85), "Lucia")
            { Line = 0.022, Fill = "#f5f5f6", Alpha = 0.6, Backdrop = true }, 1920, 1080)!;
        Assert.Equal(PanelKind.Backdrop, backdrop.Kind);
        Assert.Equal(new ScreenRect(576, 216, 0.27 * 1920, 0.65 * 1080).X, backdrop.Rect.X, 6);
        Assert.Equal(0.6, backdrop.FillAlpha);
        Assert.Equal(new PanelColor(0xF5, 0xF5, 0xF6), backdrop.Fill);
        Assert.Equal(ScreenPanelLayout.DarkInk, backdrop.Ink);
        Assert.False(backdrop.VerticalCenter);

        var bubble = ScreenPanelLayout.Layout(new ScreenItem(new Box(0.31, 0.5, 0.45, 0.53), "Motoru tamir ettin mi?")
            { Line = 0.02, Fill = "#acccfe", Ink = "#2c2c2e", Alpha = 0.95, Side = true, Angle = 5.71 }, 1920, 1080)!;
        Assert.Equal(PanelKind.Side, bubble.Kind);
        Assert.True(bubble.Shadow);
        Assert.Equal(5.71, bubble.Angle);
        Assert.Equal(new PanelColor(0x2C, 0x2C, 0x2E), bubble.Ink);
        Assert.Equal(0.02 * 1080 * 0.78, bubble.FontSize, 6);
        Assert.True(bubble.CornerRadius <= bubble.Rect.Height / 2);

        var card = ScreenPanelLayout.Layout(new ScreenItem(new Box(0.55, 0.6, 0.8, 0.7), "ÇİÇEK AL\nCüzdanı bul.")
            { Line = 0.02, Card = true, Alpha = 0.3 }, 1920, 1080)!;
        Assert.Equal(PanelKind.Card, card.Kind);
        Assert.Equal(1, card.FillAlpha);
        Assert.Equal(ScreenPanelLayout.CardFill, card.Fill);
        Assert.True(card.AccentBar && card.BoldFirstLine);
        Assert.Equal(ScreenPanelLayout.LightInk, card.Ink);

        var plain = ScreenPanelLayout.Layout(new ScreenItem(new Box(0.1, 0.1, 0.4, 0.2), "Görev") { Plain = true, Line = 0.03 },
            1920, 1080)!;
        Assert.Null(plain.Fill);
        Assert.True(plain.Shadow);

        var cover = ScreenPanelLayout.Layout(new ScreenItem(new Box(0.1, 0.9, 0.5, 0.94), "Limana git") { Italic = true }, 1920, 1080)!;
        Assert.Equal(PanelKind.Cover, cover.Kind);
        Assert.True(cover.Italic);
        Assert.Equal(0, cover.Angle);
        Assert.Equal(ScreenPanelLayout.LightInk, cover.Ink);
    }

    [Fact]
    public void BadItemsAreSkipped()
    {
        Assert.Null(ScreenPanelLayout.Layout(new ScreenItem(new Box(0.5, 0.5, 0.5, 0.5), "x"), 1920, 1080));
        Assert.Null(ScreenPanelLayout.Layout(new ScreenItem(new Box(0.1, 0.1, 0.2, 0.2), "x"), 0, 1080));
        var all = ScreenPanelLayout.LayoutAll([new ScreenItem(new Box(0.1, 0.1, 0.2, 0.2), "a"),
            new ScreenItem(new Box(0.5, 0.5, 0.5, 0.5), "b")], 1920, 1080);
        Assert.Single(all);
        var flipped = ScreenPanelLayout.Layout(new ScreenItem(new Box(0.4, 0.3, 0.2, 0.1), "x"), 100, 100)!;
        Assert.Equal(new ScreenRect(20, 10, 20, 20), flipped.Rect);
    }

    [Fact]
    public void HighlightRuns()
    {
        Assert.Equal([new PanelRun("Limanlara", true), new PanelRun(" git", false)], ScreenPanelLayout.Runs("⟦Limanlara⟧ git"));
        Assert.Equal([new PanelRun("a b", false)], ScreenPanelLayout.Runs("a ⟦b"));
        Assert.Equal([new PanelRun("a b", false)], ScreenPanelLayout.Runs("a⟧ b"));
        Assert.Equal([new PanelRun("x ", false), new PanelRun("y", true)], ScreenPanelLayout.Runs("x ⟦⟦y⟧"));
        Assert.Empty(ScreenPanelLayout.Runs(""));
    }

    [Fact]
    public void ColorsAndArea()
    {
        Assert.Equal(new PanelColor(0xAC, 0xCC, 0xFE), PanelColor.Parse("#acccfe"));
        Assert.Null(PanelColor.Parse("blue"));
        Assert.Null(PanelColor.Parse("#12345"));
        Assert.Equal(new ScreenRect(50, 25, 960, 540), ScreenPanelLayout.AreaOnScreen(new PixelRect(100, 50, 1920, 1080), 192));
    }
}
