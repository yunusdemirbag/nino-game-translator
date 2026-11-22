// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

public class LineLayoutTests
{
    static OcrLine L(string text, double left, double top, double right, double bottom, double? conf = null) =>
        new(text, new Box(left, top, right, bottom), conf);

    [Fact]
    public void Reading()
    {
        var r = new OcrReading([new("Untie", null, 0.9), new("the rope", null, 0.7), new("now,"), new("  ")]);
        Assert.Equal(3, r.Lines.Count);
        Assert.Equal(0.8, r.Confidence!.Value, 9);
        Assert.Null(r.Box);
        Assert.Equal(0.8, ButtonHints.Remove(OcrJunk.Clean(r)).Confidence!.Value, 9);
        Assert.Equal("a\nb", OcrReading.FromText(" a \r\n\r\nb").Text);
    }

    [Fact]
    public void EdgeToEdge()
    {
        var r = new OcrReading([L("ksjdhfksjdhfkjsdhf", 0, 0, 1, 0.1), L("Keep", 0.06, 0.2, 0.94, 0.3), L("Left", 0, 0.4, 0.7, 0.5),
            new("unboxed")]);
        Assert.Equal(["Keep", "Left", "unboxed"], LineLayout.RemoveEdgeToEdge(r).Lines.Select(l => l.Text));
    }

    [Fact]
    public void MergesRow()
    {
        var r = new OcrReading([L("We have to move.", 0.40, 0.501, 0.70, 0.60, 0.9), L("HOLT:", 0.30, 0.50, 0.385, 0.60, 0.8),
            L("9", 0.95, 0.50, 0.97, 0.60)]);
        var m = LineLayout.MergeRows(r);
        Assert.Equal(["HOLT: We have to move.", "9"], m.Lines.Select(l => l.Text));
        Assert.Equal(0.8, m.Lines[0].Confidence);
        Assert.Equal(new Box(0.30, 0.50, 0.70, 0.60), m.Lines[0].Box);
        var unboxed = new OcrReading([new("a"), L("b", 0, 0, 1, 1)]);
        Assert.Same(unboxed, LineLayout.MergeRows(unboxed));
    }

    static readonly Box Area = new(0.06, 0.56, 0.98, 1.0);

    [Fact]
    public void GiantLines()
    {
        var two = new OcrReading([L("We made it!", 0.1, 0.60, 0.9, 0.69), L("Go now.", 0.1, 0.70, 0.9, 0.79)]);
        Assert.Same(two, LineLayout.RemoveGiantLines(two, Area, out _));
        Assert.False(LineLayout.IsGiantBlock(two, Area));

        var sign = new OcrReading([L("Welcome to Leonida", 0.1, 0.05, 0.9, 0.35), L("Why are we stopping?", 0.1, 0.80, 0.9, 0.88)]);
        var kept = LineLayout.RemoveGiantLines(sign, Area, out var dropped);
        Assert.Equal("Why are we stopping?", kept.Text);
        Assert.Equal(["Welcome to Leonida"], dropped);

        var narrow = new Box(0.1, 0.85, 0.9, 0.95);
        var stay = new OcrReading([L("Keep your lamp lit.", 0.1, 0.2, 0.9, 0.7)]);
        Assert.Same(stay, LineLayout.RemoveGiantLines(stay, narrow, out _));
        Assert.True(LineLayout.RemoveGiantLines(new OcrReading([L("Keep your lamp lit.", 0.1, 0, 0.9, 1)]), Box.Whole, out _).IsEmpty);

        var unboxed = new OcrReading([new("Whatever")]);
        Assert.Same(unboxed, LineLayout.RemoveGiantLines(unboxed, Area, out _));
        Assert.False(LineLayout.IsGiantBlock(unboxed, Area));

        var seven = new OcrReading(Enumerable.Range(0, 7).Select(i => L("Line " + i, 0.1, i * 0.12, 0.9, i * 0.12 + 0.09)));
        Assert.True(LineLayout.IsGiantBlock(seven, Area));
        Assert.False(LineLayout.IsGiantBlock(new OcrReading(seven.Lines.Take(3)), Area));
        Assert.True(LineLayout.IsGiantBlock(new OcrReading([L("a", 0.1, 0.05, 0.9, 0.15), L("b", 0.1, 0.65, 0.9, 0.75)]), Area));

        var what = new OcrReading([L("Who was that? 00060000", 0.1, 0.60, 0.9, 0.80)]);
        Assert.Same(what, LineLayout.RemoveGiantLines(what, Area, out _));
        Assert.True(LineLayout.RemoveGiantLines(new OcrReading([L("Boat Charters", 0.1, 0.60, 0.9, 0.80)]), Area, out _).IsEmpty);
    }

    [Theory]
    [InlineData("OHM BOY", true)]
    [InlineData("BOAT CHARTERS TO LON", true)]
    [InlineData("We made it!", false)]
    [InlineData("You finished half of the diving course", false)]
    public void Label(string text, bool label) => Assert.Equal(label, LineLayout.LooksLikeLabel(text));

    static readonly Box Bottom40 = new(0, 0.6, 1, 1);

    [Fact]
    public void SelectsBlockAwayFromMenus()
    {
        string[] menu = ["MAP", "HELP", "PROGRESS", "PLAYER", "STORY", "ONLINE", "SOCIAL CLUB", "SETTINGS"];
        var lines = menu.Select((m, i) => L(m, 0.02, i * 0.09, 0.2, i * 0.09 + 0.07)).ToList();
        lines.Add(L("PHOTO MODE", 0.85, 0.9, 0.97, 0.97));
        Assert.True(LineLayout.SelectSubtitleBlock(new OcrReading(lines), Bottom40).IsEmpty);

        var sub = LineLayout.SelectSubtitleBlock(new OcrReading([
            L("The trail goes cold if we wait too long.", 0.25, 0.7, 0.75, 0.77),
            L("9", 0.02, 0.7, 0.04, 0.77),
            L("PHOTO MODE", 0.85, 0.9, 0.97, 0.97)]), Bottom40);
        Assert.Equal("The trail goes cold if we wait too long.", sub.Text);
        Assert.Equal(new Box(0.25, 0.7, 0.75, 0.77), sub.Box);

        var two = LineLayout.SelectSubtitleBlock(new OcrReading([
            L("Ivy and Rook... they both got away.", 0.3, 0.6, 0.7, 0.67), L("We have to hurry.", 0.4, 0.68, 0.6, 0.75)]), Bottom40);
        Assert.Equal(2, two.Lines.Count);

        var side = LineLayout.SelectSubtitleBlock(new OcrReading([L("Smuggler: We're nervous about this one.", 0.05, 0.7, 0.5, 0.77)]),
            Bottom40);
        Assert.Equal("Smuggler: We're nervous about this one.", side.Text);

        var unboxed = OcrReading.FromText("MAP\nHELP");
        Assert.Same(unboxed, LineLayout.SelectSubtitleBlock(unboxed, Bottom40));
    }

    static readonly Box Default = new(0.14, 0.62, 0.86, 0.97);

    [Fact]
    public void CenteredLines()
    {
        var r = LineLayout.KeepCentered(new OcrReading([L("The bridge is closing soon.", 0.35, 0.5, 0.65, 0.6),
            L("Room Rates Today", 0.80, 0.1, 0.95, 0.2)]), Default);
        Assert.Equal("The bridge is closing soon.", r.Text);
    }

    [Fact]
    public void CentersBox()
    {
        var b = LineLayout.CenterOnScreen(new Box(0.45, 0.85, 0.75, 0.9));
        Assert.Equal(0.25, b.Left, 9);
        Assert.Equal(0.75, b.Right, 9);
        Assert.Equal(0.85, b.Top, 9);
        Assert.Equal(new Box(0.02, 0.1, 0.2, 0.15), LineLayout.CenterOnScreen(new Box(0.02, 0.1, 0.2, 0.15)));
    }

    [Fact]
    public void QuestLine()
    {
        var r = LineLayout.RemoveBelowQuestLine(new OcrReading([L("I'll be there soon.", 0.3, 0.70, 0.7, 0.76),
            L("Go to Jason's room", 0.35, 0.905, 0.65, 0.96)]), Default, 0.935);
        Assert.Equal("I'll be there soon.", r.Text);
        var two = new OcrReading([L("HOLT: Get in the truck,", 0.3, 0.86, 0.7, 0.90), L("we have to move.", 0.35, 0.905, 0.65, 0.945)]);
        Assert.Same(two, LineLayout.RemoveBelowQuestLine(two, Default, 0.935));
    }
}
