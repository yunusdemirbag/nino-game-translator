// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

/// <summary>Eski duran yazı süzgeci (zincir adım 12; 9 sn).</summary>
public sealed class StaleLineFilterTests
{
    static OcrReading Read(params string[] lines) =>
        new(lines.Select((t, i) => new OcrLine(t, new Box(0.2, 0.7 + i * 0.05, 0.8, 0.74 + i * 0.05))));

    static string[] Texts(OcrReading r) => r.Lines.Select(l => l.Text).ToArray();

    [Fact]
    public void OldStuckLineIsDroppedWhenANewLineArrives()
    {
        var f = new StaleLineFilter();
        Assert.Equal(["Go to the docks."], Texts(f.Apply(Read("Go to the docks."), 0)));
        Assert.Equal(["Go to the docks."], Texts(f.Apply(Read("Go to the docks."), 5_000)));
        Assert.Equal(["Go to the docks."], Texts(f.Apply(Read("Go to the docks."), 12_000)));
        var r = f.Apply(Read("Go to the docks.", "Where have you been?"), 12_500);
        Assert.Equal(["Where have you been?"], Texts(r));
    }

    [Fact]
    public void OnlyOldLinesAreKept()
    {
        var f = new StaleLineFilter();
        f.Apply(Read("Go to the docks.", "Find the boat."), 0);
        var r = f.Apply(Read("Go to the docks.", "Find the boat."), 30_000);
        Assert.Equal(["Go to the docks.", "Find the boat."], Texts(r));
        Assert.Equal(["Go to the docks."], Texts(f.Apply(Read("Go to the docks."), 40_000)));
    }

    [Fact]
    public void NineSecondBoundary()
    {
        var f = new StaleLineFilter();
        f.Apply(Read("Mission text"), 0);
        f.Apply(Read("Mission text"), 1);
        Assert.Equal(["Mission text", "Hello there"], Texts(f.Apply(Read("Mission text", "Hello there"), 8_999)));

        var g = new StaleLineFilter();
        g.Apply(Read("Mission text"), 0);
        Assert.Equal(["Hello there"], Texts(g.Apply(Read("Mission text", "Hello there"), 9_000)));
    }

    [Fact]
    public void VanishedLineStartsFresh()
    {
        var f = new StaleLineFilter();
        f.Apply(Read("Mission text"), 0);
        f.Apply(Read("Something else"), 10_000);
        var r = f.Apply(Read("Mission text", "Hello there"), 10_500);
        Assert.Equal(["Mission text", "Hello there"], Texts(r));
    }

    [Fact]
    public void KeyIgnoresSmallReadingNoise()
    {
        var f = new StaleLineFilter();
        f.Apply(Read("Go to the docks."), 0);
        var r = f.Apply(Read("go to the docks", "New line here"), 10_000);
        Assert.Equal(["New line here"], Texts(r));
    }

    [Fact]
    public void ResetForgets()
    {
        var f = new StaleLineFilter();
        f.Apply(Read("Mission text"), 0);
        f.Reset();
        Assert.Equal(["Mission text", "Hello"], Texts(f.Apply(Read("Mission text", "Hello"), 20_000)));
    }

    [Fact]
    public void EmptyReadingStaysEmpty()
    {
        var f = new StaleLineFilter();
        Assert.True(f.Apply(OcrReading.Empty, 0).IsEmpty);
    }
}
