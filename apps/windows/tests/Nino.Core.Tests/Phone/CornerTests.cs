// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;
using static Nino.Core.Tests.Phone.PhoneTestData;

namespace Nino.Core.Tests.Phone;

/// <summary>GTA 6 köşe öğeleri: sağ alt mesaj/uygulama bildirimi kartı, sol üst ipucu, sağ üst bildirim.</summary>
public class CornerTests
{
    static readonly BgraFrame CardFrame = BgraFrame.Filled(64, 36, 30);
    static readonly BgraFrame GoneFrame = BgraFrame.Filled(64, 36, 200);

    sealed class Rig
    {
        public readonly ManualMsClock Clock = new(100_000);
        public readonly PrefixTranslator Own = new("TR: ");
        public volatile bool MapOpen;
        public Box? Phone;
        public int Changes;
        public readonly CornerReader Reader;

        public Rig(Func<string, string?>? ready = null)
        {
            Reader = new CornerReader(new OverlayServices
            {
                Clock = Clock,
                Own = Own,
                Ready = ready,
                Paused = () => MapOpen,
                PhoneBox = _ => Phone,
                Changed = () => Interlocked.Increment(ref Changes),
            });
        }

        /// <summary>Bir sonraki tura kadar bekleyip okumayı işler (başlattığı çevirileri bekler).</summary>
        public async Task Read(OcrReading reading, BgraFrame? frame = null, long afterMs = CornerReader.ReadEveryMs)
        {
            Clock.Advance(afterMs);
            await Reader.Process(reading, frame ?? CardFrame);
        }

        /// <summary>Kararlı okuma: aynı okuma iki kez.</summary>
        public async Task ReadTwice(OcrReading reading, BgraFrame? frame = null)
        {
            await Read(reading, frame);
            await Read(reading, frame);
        }
    }

    static OcrReading BuckMe() => R(L("BuckMe", 0.70, 0.80, 0.76, 0.825),
        L("b Dre'Quan bucked you for the ride home", 0.70, 0.835, 0.95, 0.86));

    static OcrReading Donnie() => R(L("Donnie", 0.70, 0.80, 0.75, 0.825),
        L("Where are you at? We need to talk.", 0.70, 0.835, 0.93, 0.86));

    static OcrReading Hint() => R(L("Use cover to avoid taking damage from", 0.03, 0.10, 0.30, 0.13),
        L("enemy fire while you reload your weapon.", 0.03, 0.135, 0.31, 0.165));

    [Fact]
    public async Task BuckMeNotificationTranslatedBottomRight()
    {
        var rig = new Rig();
        await rig.Read(BuckMe());
        Assert.Empty(rig.Reader.Items);
        Assert.Equal(0, rig.Own.Calls);
        await rig.Read(BuckMe());
        var item = Assert.Single(rig.Reader.Items);
        // Uygulama adı çevrilmez; gövdenin başındaki simge kırıntısı atılır.
        Assert.Equal("BuckMe: TR: Dre'Quan bucked you for the ride home", item.Text);
        Assert.Equal(["Dre'Quan bucked you for the ride home"], rig.Own.Requests);
        // Kartın hemen üstünde, sağ altta.
        Assert.True(item.Box.Left > 0.6 && item.Box.Bottom < 0.80);
        Assert.Equal("#eef0f5", item.Fill);
        Assert.True(rig.Changes > 0);
    }

    [Fact]
    public async Task PersonMessageTranslatedAndRememberedAfterGap()
    {
        var rig = new Rig();
        await rig.ReadTwice(Donnie());
        Assert.Equal("Donnie: TR: Where are you at? We need to talk.", Assert.Single(rig.Reader.Items).Text);
        rig.Reader.Reset();
        Assert.Empty(rig.Reader.Items);
        // Hafızadaki çeviri ilk görülüşte yeniden gösterilir, yeniden çevrilmez.
        await rig.Read(Donnie());
        Assert.Single(rig.Reader.Items);
        Assert.Equal(1, rig.Own.Calls);
    }

    [Fact]
    public async Task ReadyTranslationIsUsedFirst()
    {
        var rig = new Rig(t => t == "Where are you at? We need to talk." ? "Neredesin? Konuşmamız lazım." : null);
        await rig.ReadTwice(Donnie());
        Assert.Equal("Donnie: Neredesin? Konuşmamız lazım.", Assert.Single(rig.Reader.Items).Text);
        Assert.Equal(0, rig.Own.Calls);
    }

    [Fact]
    public async Task TopLeftHintTranslated()
    {
        var rig = new Rig();
        await rig.ReadTwice(Hint());
        var item = Assert.Single(rig.Reader.Items);
        Assert.Equal("TR: Use cover to avoid taking damage from enemy fire while you reload your weapon.", item.Text);
        // Oyunun kutusunun hemen altında, koyu buzlu.
        Assert.True(item.Box.Top >= 0.165 && item.Box.Left < 0.05);
        Assert.Equal("#1c1c24", item.Fill);
    }

    [Fact]
    public async Task TopRightNoticeTranslatedOnFirstSight()
    {
        var rig = new Rig();
        await rig.Read(R(L("Map updated", 0.82, 0.20, 0.95, 0.23)));
        var item = Assert.Single(rig.Reader.Items);
        Assert.Equal("TR: Map updated", item.Text);
        Assert.True(item.Box.Right <= 0.995 && item.Box.Left > 0.5);
    }

    [Fact]
    public async Task MenuScreenIsNotTranslated()
    {
        var rig = new Rig();
        var menu = R(L("Map", 0.04, 0.20, 0.08, 0.23), L("Game", 0.04, 0.25, 0.09, 0.28), L("Store", 0.04, 0.30, 0.09, 0.33),
            L("Help", 0.04, 0.35, 0.08, 0.38), L("Online services are available now", 0.82, 0.20, 0.97, 0.23));
        await rig.ReadTwice(menu);
        await rig.ReadTwice(R(Hint().Lines.Concat(menu.Lines).ToArray()));
        Assert.Empty(rig.Reader.Items);
        Assert.Equal(0, rig.Own.Calls);
    }

    [Fact]
    public async Task NotSearchedWhileMapOpen()
    {
        var rig = new Rig();
        await rig.ReadTwice(Donnie());
        Assert.Single(rig.Reader.Items);
        rig.MapOpen = true;
        await rig.ReadTwice(R(BuckMe().Lines.Concat(Hint().Lines).ToArray()));
        Assert.Empty(rig.Reader.Items);
        Assert.Equal(1, rig.Own.Calls);
    }

    [Fact]
    public async Task OpenPhoneDropsCardAndHidesItsText()
    {
        var rig = new Rig();
        await rig.ReadTwice(Donnie());
        Assert.Single(rig.Reader.Items);
        rig.Phone = new Box(0.85, 0.30, 0.99, 0.70);
        await rig.Read(Donnie());
        Assert.Empty(rig.Reader.Items);
        // Telefonun içindeki yazı köşe bildirimi sayılmaz.
        await rig.Read(R(L("Lucia is typing a message", 0.86, 0.20 + 0.15, 0.98, 0.38)));
        Assert.Empty(rig.Reader.Items);
    }

    [Fact]
    public async Task CardLeavesWithMapHysteresis()
    {
        var rig = new Rig();
        await rig.ReadTwice(BuckMe());
        Assert.Single(rig.Reader.Items);
        // Tek kaçırma ya da aynı görüntü kalmaz.
        await rig.Read(OcrReading.Empty, GoneFrame, 500);
        Assert.Single(rig.Reader.Items);
        await rig.Read(OcrReading.Empty, CardFrame, 500);
        await rig.Read(OcrReading.Empty, CardFrame, 500);
        await rig.Read(OcrReading.Empty, CardFrame, MapReader.MissClearMs);
        Assert.Single(rig.Reader.Items);
        // Görüntü değişince kalkar.
        await rig.Read(OcrReading.Empty, GoneFrame, 500);
        Assert.Empty(rig.Reader.Items);
    }

    [Fact]
    public async Task CardSeenAgainResetsMisses()
    {
        var rig = new Rig();
        await rig.ReadTwice(BuckMe());
        await rig.Read(OcrReading.Empty, GoneFrame, 1_000);
        await rig.Read(OcrReading.Empty, GoneFrame, 1_000);
        await rig.Read(BuckMe(), CardFrame, 1_000);
        await rig.Read(OcrReading.Empty, GoneFrame, 1_000);
        await rig.Read(OcrReading.Empty, GoneFrame, 4_000);
        Assert.Single(rig.Reader.Items);
    }

    [Fact]
    public async Task TurkishGameTextIsNotTranslated()
    {
        var rig = new Rig();
        await rig.ReadTwice(R(L("Siper alarak düşman ateşinden korun ve", 0.03, 0.10, 0.30, 0.13),
            L("silahını yeniden doldur.", 0.03, 0.135, 0.25, 0.165)));
        Assert.Empty(rig.Reader.Items);
        Assert.Equal(0, rig.Own.Calls);
    }

    [Fact]
    public async Task CallCardShowsTurkishStatus()
    {
        var rig = new Rig();
        await rig.Read(R(L("Harbor Cabs", 0.70, 0.80, 0.80, 0.825), L("Calling...", 0.70, 0.835, 0.78, 0.86)));
        Assert.Equal("Harbor Cabs aranıyor…", Assert.Single(rig.Reader.Items).Text);
        // Konuşma başlayınca (sayaç) yazı hemen kalkar.
        await rig.Read(R(L("Harbor Cabs", 0.70, 0.80, 0.80, 0.825), L("00:05", 0.70, 0.835, 0.74, 0.86)));
        Assert.Empty(rig.Reader.Items);
        Assert.Equal(0, rig.Own.Calls);
    }

    [Fact]
    public async Task OfferedFramesAreReadEveryTwoSeconds()
    {
        var clock = new ManualMsClock(100_000);
        var own = new PrefixTranslator("TR: ");
        var reads = 0;
        var reader = new CornerReader(new OverlayServices
        {
            Clock = clock,
            Own = own,
            Ocr = new FuncReader(_ => { Interlocked.Increment(ref reads); return BuckMe(); }),
        });
        async Task Offer()
        {
            reader.OfferFrame(CardFrame);
            await reader.Running!;
            if (reader.Showing is { } s) await s;
        }
        await Offer();
        clock.Advance(500);
        reader.OfferFrame(CardFrame);
        Assert.Equal(1, reads);
        clock.Advance(CornerReader.ReadEveryMs);
        await Offer();
        Assert.Equal(2, reads);
        Assert.Equal("BuckMe: TR: Dre'Quan bucked you for the ride home", Assert.Single(reader.Items).Text);
    }

    [Theory]
    [InlineData("Donnie", true)]
    [InlineData("Uncle Ray", true)]
    [InlineData("SET DESTINATION", false)]
    [InlineData("Pick me up at the docks.", false)]
    public void SenderNames(string text, bool name) => Assert.Equal(name, GameCards.IsName(text));

    [Theory]
    [InlineData("BuckMe", true)]
    [InlineData("Donnie", false)]
    [InlineData("BUCKME", false)]
    public void AppNames(string text, bool app) => Assert.Equal(app, GameCards.IsAppName(text));

    [Theory]
    [InlineData("RECENTER L3", true)]
    [InlineData("ADD MARKER C", true)]
    [InlineData("Map updated", false)]
    public void MapButtons(string text, bool button) => Assert.Equal(button, TopRightNotice.IsMapButton(text));

    [Fact]
    public void OutputMergesOverlayAndCorners()
    {
        var inner = new RecordingOutput();
        var output = new CornerScreenOutput(inner, new ManualMsClock());
        var phone = new ScreenItem("a", "telefon", new Box(0.6, 0.3, 0.8, 0.7), 0.03);
        var corner = new ScreenItem("b", "köşe", new Box(0.7, 0.7, 0.9, 0.75), 0.03);
        output.ShowScreen([phone], PhoneOverlay.DurationMs, true);
        output.SetCorners([corner]);
        Assert.Equal(["telefon", "köşe"], inner.Screens[^1].Items.Select(i => i.Text));
        output.ClearScreen();
        Assert.Equal(["köşe"], inner.Screens[^1].Items.Select(i => i.Text));
        Assert.Equal(0, inner.Clears);
        output.SetCorners([]);
        Assert.Equal(1, inner.Clears);
        Assert.False(output.Showing);
    }
}
