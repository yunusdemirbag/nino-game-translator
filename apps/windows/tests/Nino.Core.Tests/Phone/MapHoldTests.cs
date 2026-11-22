// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;

namespace Nino.Core.Tests.Phone;

/// <summary>Harita kartının kalkma gecikmesi ve TV'ye 60 sn'de bir yeniden gönderilmesi.</summary>
public class MapHoldTests
{
    /// <summary>Kartın göründüğü kare (koyu) ve kartın gittiği kare (açık harita).</summary>
    static readonly BgraFrame CardFrame = BgraFrame.Filled(64, 36, 30);
    static readonly BgraFrame GoneFrame = BgraFrame.Filled(64, 36, 200);

    sealed class Rig
    {
        public readonly ManualMsClock Clock = new(100_000);
        public readonly RecordingOutput Output = new();
        public readonly PrefixTranslator Own = new("TR: ");
        public readonly PhoneOverlay Overlay;
        public volatile bool CardVisible = true;
        public readonly List<string> Log = [];

        public Rig()
        {
            Overlay = new PhoneOverlay(Output, Clock);
            var mapOcr = new FuncReader(_ => CardVisible
                ? new OcrReading(Fixtures.Load("gta6-harita-buckme").Lines
                    .Select(l => l with { Box = l.Box!.Value.RelativeTo(MapReader.ReadArea) }))
                : OcrReading.Empty);
            Overlay.Install(new OverlayServices { Clock = Clock, Own = Own, Log = l => { lock (Log) Log.Add(l); } },
                new FuncReader(_ => OcrReading.Empty), mapOcr, _ => null);
        }

        public MapReader Map => Overlay.Map!;

        public async Task ShowCard()
        {
            Map.Process(Fixtures.Load("gta6-harita-buckme"), CardFrame);
            await Map.Showing!;
            Assert.Single(Map.Items);
            Assert.Single(Output.Screens);
        }

        /// <summary>Bir sonraki tura kadar bekleyip kartsız bir okuma işler.</summary>
        public void Miss(BgraFrame frame, long afterMs = MapReader.ReadEveryMs)
        {
            Clock.Advance(afterMs);
            Map.Process(OcrReading.Empty, frame);
        }
    }

    [Fact]
    public async Task SingleMissKeepsCard()
    {
        var rig = new Rig();
        await rig.ShowCard();
        rig.Miss(GoneFrame);
        Assert.Single(rig.Map.Items);
        Assert.Equal(0, rig.Output.Clears);
        Assert.True(rig.Overlay.Showing);
    }

    [Fact]
    public async Task ThreeMissesSameImageKeepCard()
    {
        var rig = new Rig();
        await rig.ShowCard();
        for (var i = 0; i < 5; i++) rig.Miss(CardFrame);
        Assert.Single(rig.Map.Items);
        Assert.Equal(0, rig.Output.Clears);
    }

    [Fact]
    public async Task ThreeMissesAfterFourSecondsWithChangedImageClear()
    {
        var rig = new Rig();
        await rig.ShowCard();
        rig.Miss(GoneFrame, 500);
        rig.Miss(GoneFrame, 500);
        rig.Miss(GoneFrame, 500);
        Assert.Single(rig.Map.Items);
        Assert.Equal(0, rig.Output.Clears);
        rig.Miss(GoneFrame, MapReader.MissClearMs - 1_000);
        Assert.Empty(rig.Map.Items);
        Assert.Equal(1, rig.Output.Clears);
        Assert.False(rig.Overlay.Showing);
        Assert.Contains(rig.Log, l => l.StartsWith("harita kartı kalktı", StringComparison.Ordinal));
    }

    [Fact]
    public async Task NotMapScreenAlsoWaits()
    {
        var rig = new Rig();
        await rig.ShowCard();
        var other = new OcrReading([new OcrLine("Press X to continue", new Box(0.4, 0.8, 0.6, 0.83))]);
        rig.Clock.Advance(MapReader.ReadEveryMs);
        rig.Map.Process(other, GoneFrame);
        Assert.Single(rig.Map.Items);
        for (var i = 0; i < 2; i++)
        {
            rig.Clock.Advance(MapReader.ReadEveryMs);
            rig.Map.Process(other, GoneFrame);
        }
        Assert.Empty(rig.Map.Items);
        Assert.Equal(1, rig.Output.Clears);
    }

    [Fact]
    public async Task TwoMissesThenBackNoNewTranslation()
    {
        var rig = new Rig();
        await rig.ShowCard();
        var calls = rig.Own.Calls;
        var screens = rig.Output.Screens.Count;
        rig.Miss(GoneFrame);
        rig.Miss(GoneFrame);
        rig.Clock.Advance(MapReader.ReadEveryMs);
        rig.Map.Process(Fixtures.Load("gta6-harita-buckme"), CardFrame);
        await rig.Map.Showing!;
        Assert.Equal(calls, rig.Own.Calls);
        Assert.Single(rig.Map.Items);
        Assert.Equal(screens, rig.Output.Screens.Count);
        Assert.Equal(0, rig.Output.Clears);

        // Sayaç sıfırlandı: yeniden iki kaçırma kartı silmez.
        rig.Miss(GoneFrame);
        rig.Miss(GoneFrame);
        Assert.Single(rig.Map.Items);
        Assert.Equal(0, rig.Output.Clears);
    }

    [Fact]
    public async Task ClearedCardComesBackFromMemory()
    {
        var rig = new Rig();
        await rig.ShowCard();
        var calls = rig.Own.Calls;
        for (var i = 0; i < MapReader.MissesToClear; i++) rig.Miss(GoneFrame);
        Assert.Empty(rig.Map.Items);
        rig.Clock.Advance(MapReader.ReadEveryMs);
        rig.Map.Process(Fixtures.Load("gta6-harita-buckme"), CardFrame);
        await rig.Map.Showing!;
        Assert.Single(rig.Map.Items);
        Assert.Equal(calls, rig.Own.Calls);
    }

    [Fact]
    public async Task RefreshEverySixtySecondsSameList()
    {
        var rig = new Rig();
        rig.Overlay.OnFrame(CardFrame);
        await rig.Map.Running!;
        await rig.Map.Showing!;
        var first = Assert.Single(rig.Output.Screens);

        rig.Clock.Advance(PhoneOverlay.RefreshMs - 1);
        rig.Overlay.OnFrame(CardFrame);
        await rig.Map.Running!;
        Assert.Single(rig.Output.Screens);

        rig.Clock.Advance(1);
        rig.Overlay.OnFrame(CardFrame);
        await rig.Map.Running!;
        Assert.Equal(2, rig.Output.Screens.Count);
        var again = rig.Output.Screens[^1];
        Assert.Equal(first.Items, again.Items);
        Assert.Equal(PhoneOverlay.DurationMs, again.Duration);
        Assert.True(again.Overlay);

        // Okuma kartı kaçırsa da görüntü aynıysa kart kalır ve yenileme sürer.
        rig.CardVisible = false;
        for (var i = 0; i < 30; i++)
        {
            rig.Clock.Advance(MapReader.ReadEveryMs);
            rig.Overlay.OnFrame(CardFrame);
            await rig.Map.Running!;
        }
        Assert.Equal(0, rig.Output.Clears);
        Assert.Equal(3, rig.Output.Screens.Count);
        Assert.Equal(first.Items, rig.Output.Screens[^1].Items);
    }

    [Fact]
    public void SignatureDiffersOnlyWhenEnoughChanges()
    {
        var a = new byte[100];
        var b = new byte[100];
        for (var i = 0; i < 9; i++) b[i] = 100;
        Assert.False(MapReader.Differs(a, b));
        b[9] = 100;
        Assert.True(MapReader.Differs(a, b));
        Assert.Null(MapReader.SignatureOf(CardFrame, new Box(1.2, 0.5, 1.5, 0.6)));
    }
}
