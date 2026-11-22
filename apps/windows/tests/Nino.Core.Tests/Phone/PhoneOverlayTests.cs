// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;

namespace Nino.Core.Tests.Phone;

public class PhoneOverlayTests
{
    static FuncReader MapOcr() => new(_ => new OcrReading(Fixtures.Load("gta6-harita-buckme").Lines
        .Select(l => l with { Box = l.Box!.Value.RelativeTo(MapReader.ReadArea) })));

    [Fact]
    public async Task CombinedListSentClearedAndRefreshed()
    {
        var clock = new ManualMsClock(0);
        var output = new RecordingOutput();
        var overlay = new PhoneOverlay(output, clock);
        var mapOcr = MapOcr();
        overlay.Install(new OverlayServices { Clock = clock, Own = new PrefixTranslator("TR: ") },
            new FuncReader(_ => OcrReading.Empty), mapOcr, _ => null);
        Assert.True(overlay.Installed);
        var frame = BgraFrame.Blank(64, 36);
        overlay.OnFrame(frame);
        await overlay.Map!.Running!;
        await overlay.Map.Showing!;
        var sent = Assert.Single(output.Screens);
        Assert.True(sent.Overlay);
        Assert.Equal(PhoneOverlay.DurationMs, sent.Duration);
        Assert.True(Assert.Single(sent.Items).Card);
        Assert.True(overlay.Map.RecentlyOpen(MapReader.PhonePauseMs));

        clock.Advance(PhoneOverlay.RefreshMs);
        overlay.OnFrame(frame);
        await overlay.Map.Running!;
        Assert.True(output.Screens.Count >= 2);

        overlay.Remove();
        Assert.Equal(1, output.Clears);
        Assert.False(overlay.Showing);
    }

    [Fact]
    public void HooksSeeReaders()
    {
        var overlay = new PhoneOverlay(new RecordingOutput(), new ManualMsClock(0));
        var hooks = overlay.CreateLineHooks(() => true, _ => null);
        Assert.False(hooks.MapOpen);
        Assert.True(hooks.SearchPhone);
        overlay.Install(new OverlayServices(), new FuncReader(_ => OcrReading.Empty), new FuncReader(_ => OcrReading.Empty));
        overlay.Update(_ => "x", true);
        Assert.True(overlay.Phone!.Glossary);
        Assert.NotNull(overlay.Map!.Ready);
    }
}
