// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Reading;
using Nino.Shell.Panels;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

public class StreamWindowTests
{
    [Theory]
    [InlineData(720, 720 / 1080.0)]
    [InlineData(1080, 1)]
    [InlineData(2160, 2)]
    [InlineData(100, 0.2)]
    [InlineData(0, 720 / 1080.0)]
    [InlineData(double.NaN, 720 / 1080.0)]
    public void ScaleFollowsContentHeight(double height, double expected) =>
        Assert.Equal(expected, StreamWindowRules.Scale(height), 6);

    [Fact]
    public void PaddingsScale()
    {
        Assert.Equal(24, StreamWindowRules.SidePadding(1), 6);
        Assert.Equal(16, StreamWindowRules.RegionTop(1), 6);
        Assert.Equal(720 * 0.07, StreamWindowRules.BottomPadding(720), 6);
        Assert.Equal(720 * 0.07, StreamWindowRules.BottomPadding(0), 6);
        Assert.Equal(1080 * 0.07, StreamWindowRules.BottomPadding(1080), 6);
    }

    [Fact]
    public void WindowSizesMatchTheRecipe()
    {
        Assert.Equal((1296d, 759d), (StreamWindowRules.WindowWidth, StreamWindowRules.WindowHeight));
        Assert.Equal((400d, 260d), (StreamWindowRules.MinWidth, StreamWindowRules.MinHeight));
    }

    [Theory]
    [InlineData(StackRole.Current, true, 1)]
    [InlineData(StackRole.Previous, true, 0.6)]
    [InlineData(StackRole.SecondPrevious, true, 0.45)]
    [InlineData(StackRole.Previous, false, 1)]
    public void TextAlphaFadesOnlyInsideTheBox(StackRole role, bool boxed, double expected) =>
        Assert.Equal(expected, StreamWindowRules.TextAlpha(role, boxed), 6);

    [Fact]
    public void BoxOnlyWithBackground()
    {
        Assert.True(StreamWindowRules.HasBox(60));
        Assert.False(StreamWindowRules.HasBox(0));
    }

    [Fact]
    public void BackgroundChangeIsObserved()
    {
        var w = new World();
        var c = w.Open();
        var changed = new List<string?>();
        c.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        c.SetStreamBackground(StreamBackground.Black);
        Assert.Contains(nameof(NinoController.StreamBackground), changed);
        Assert.Equal(0x000000, StreamBackgroundColors.Rgb(c.StreamBackground));
    }
}

public class RemotePlayLogTapTests
{
    [Fact]
    public void LinesReachHealthAndStallNotes()
    {
        using var log = Nino.RemotePlay.RemotePlayLog.Silent();
        var health = new Nino.Core.Health.HealthRecorder();
        var notes = new List<string>();
        long now = 1000;
        using var tap = RemotePlayLogTap.Attach(log, health, notes.Add, () => now);
        log.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Warning, "Send Buffer re-sending packet");
        log.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Warning, "Video FEC failure");
        log.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Warning, "FEC failed");
        now = 1250;
        log.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Info, "Received IDR frame");
        Assert.Equal(1, health.Snapshot().Resends);
        Assert.Equal(1, health.Snapshot().Stalls);
        Assert.Equal(["görüntü durdu (FEC hatası), IDR karesi bekleniyor", "görüntü yeniden geldi (IDR karesi), 250 ms ara"], notes);

        tap.Dispose();
        log.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Warning, "Send Buffer re-sending packet");
        Assert.Equal(1, health.Snapshot().Resends);
    }
}
