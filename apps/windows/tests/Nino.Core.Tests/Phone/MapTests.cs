// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;
using static Nino.Core.Tests.Phone.PhoneTestData;

namespace Nino.Core.Tests.Phone;

public class MapTests
{
    [Fact]
    public void BuyFlowersCard()
    {
        var card = MapCard.Find(R(L("BUY FLOWERS", 0.60, 0.40, 0.72, 0.425), L("Lucia will appreciate this", 0.60, 0.44, 0.72, 0.46),
            L("Have some flowers delivered to the", 0.60, 0.47, 0.80, 0.49), L("house for Lucia.", 0.60, 0.495, 0.70, 0.515)));
        Assert.NotNull(card);
        Assert.Equal("BUY FLOWERS", card!.Title);
        Assert.Equal(["Lucia will appreciate this", "Have some flowers delivered to the house for Lucia."], card.Sentences);
    }

    [Fact]
    public void BuckMeCard()
    {
        var card = MapCard.Find(Fixtures.Load("gta6-harita-buckme"))!;
        Assert.Equal("DEPOSIT CASH INTO BUCKME", card.Title);
        Assert.Equal(2, card.Sentences.Count);
        Assert.StartsWith("Use the index", card.Sentences[0]);
        Assert.EndsWith("nearby ATMs", card.Sentences[0]);
        Assert.Contains("checking account at an ATM", card.Sentences[^1]);
        Assert.True(card.Box.Bottom > 0.58);
    }

    [Fact]
    public void FishCard()
    {
        var card = MapCard.Find(Fixtures.Load("gta6-harita-balik"))!;
        Assert.Equal("CATCH A BIGGER FISH", card.Title);
        Assert.Equal(["Cal challenged you to catch a stoplight parrotfish larger than 0.9 kg."], card.Sentences);
    }

    [Fact]
    public void MotelMarkerCard()
    {
        var card = MapCard.Find(R(L("RECENTER", 0.85, 0.85, 0.93, 0.87), L("SET DESTINATION", 0.85, 0.88, 0.95, 0.90),
            L("HARBOR INN", 0.60, 0.40, 0.72, 0.425), L("A small inn by the water with", 0.60, 0.44, 0.78, 0.46),
            L("◆ clean rooms and fair prices. Simple, but not bad.", 0.59, 0.465, 0.80, 0.485)))!;
        var all = string.Join(" ", card.Sentences);
        Assert.Contains("clean rooms and fair prices. Simple, but not bad.", all);
        Assert.DoesNotContain("◆", all);
    }

    [Fact]
    public void FrameFromImage()
    {
        var f = BgraFrame.Blank(640, 360);
        for (var y = 0; y < 360; y++)
            for (var x = 0; x < 640; x++)
            {
                double fx = (x + 0.5) / 640, fy = (y + 0.5) / 360;
                var dark = fx is >= 0.60 and <= 0.90 && fy is >= 0.30 and <= 0.61 && !(fy is >= 0.570 and <= 0.578);
                var v = (byte)(dark ? 30 : 200);
                f.SetPixel(x, y, v, v, v);
            }
        var frame = MapCard.FindFrame(f, new Box(0.65, 0.35, 0.85, 0.55));
        Assert.NotNull(frame);
        Assert.True(frame!.Value.Bottom > 0.6);
    }

    [Theory]
    [InlineData("HARBOR CUSTOMS", "", true)]
    [InlineData("MOLLY'S CORNER", "A dive bar by the docks.", true)]
    [InlineData("JASON'S MAILBOX", "", false)]
    [InlineData("REEL DEAL", "Bait shop for anglers and divers.", true)]
    [InlineData("NEW NEIGHBORS", "Grab a few things from the corner store near the motel.", false)]
    [InlineData("CHECK ON MARCO", "Stop by and see how Marco is doing at the hotel.", false)]
    [InlineData("LATE ON RENT", "You still owe Rosa money for the room.", false)]
    [InlineData("THE PIER", "", true)]
    public void Venue(string title, string description, bool venue) =>
        Assert.Equal(venue, MapCardLayout.IsVenue(title, description));

    [Fact]
    public void Terms()
    {
        Assert.Equal("işaretli banknotları bul", MapCardLayout.FixTerms("işaretli faturaları bul"));
        Assert.Equal("Jason'ın deposuna dön", MapCardLayout.FixTerms("Jason'ın kapalı tutulmasına dön"));
        Assert.Equal("Bir stoplight papağan balığı yakala", MapCardLayout.FixTerms("Bir trafik ışığı papağan balığı yakala"));
    }

    [Fact]
    public void LayoutBelowCard()
    {
        var card = MapCard.Find(Fixtures.Load("gta6-harita-buckme"))!;
        string[] lines = ["BUCKME'YE NAKİT YATIR", "Yakında bir ATM bulmak için listeye bak", "Nakit yatır"];
        var item = MapCardLayout.Layout(card, lines, null);
        Assert.True(item.Card);
        Assert.True(item.Box.Top > card.Box.Bottom);
        Assert.Equal(3, item.Text.Split('\n').Length);
        Assert.True(item.Paragraphs);
        Assert.True(item.Box.Left <= card.Box.Left);
        var part = new Box(card.Box.Left + 0.02, card.Box.Top + 0.01, card.Box.Left + 0.08, card.Box.Top + 0.05);
        var withFrame = MapCardLayout.Layout(card, lines, part);
        Assert.True(withFrame.Box.Top > card.Box.Bottom);
        Assert.True(withFrame.Box.Left <= card.Box.Left);
    }

    [Fact]
    public void VenueTitleStaysEnglish()
    {
        var card = new MapCardText("HARBOR CUSTOMS", ["Get your car tuned here."], new Box(0.6, 0.4, 0.8, 0.5), 0.02);
        var item = MapCardLayout.Layout(card, ["HARBOR GÜMRÜK", "Arabanı burada ayarlat."], null);
        Assert.StartsWith("HARBOR CUSTOMS\n", item.Text);
    }

    sealed class Rig
    {
        public readonly ManualMsClock Clock = new(100_000);
        public readonly List<IReadOnlyList<ScreenItem>> Notes = [];
        public readonly List<string> Log = [];
        public MapReader Reader = null!;

        public Rig(OverlayServices services)
        {
            Reader = new MapReader(services with
            {
                Clock = Clock,
                Changed = () => { lock (Notes) Notes.Add(Reader.Items); },
                Log = l => { lock (Log) Log.Add(l); },
            });
        }

        public async Task Read(OcrReading r)
        {
            Reader.Process(r, BgraFrame.Blank(64, 36));
            if (Reader.Showing is { } t) await t;
        }
    }

    [Fact]
    public async Task ReaderShowsCardAndClears()
    {
        var rig = new Rig(new OverlayServices { Own = new PrefixTranslator("TR: ") });
        Assert.False(rig.Reader.IsOpen);
        await rig.Read(Fixtures.Load("gta6-harita-buckme"));
        Assert.True(rig.Reader.IsOpen);
        var item = Assert.Single(rig.Reader.Items);
        Assert.True(item.Card);
        Assert.StartsWith("TR: DEPOSİT CASH INTO BUCKME", item.Text);
        Assert.Contains("TR: Make a cash deposit", item.Text);
        Assert.True(rig.Reader.RecentlyOpen(MapReader.PhonePauseMs));
        for (var i = 0; i < MapReader.MissesToClear; i++)
        {
            Assert.Single(rig.Reader.Items);
            rig.Clock.Advance(MapReader.ReadEveryMs);
            rig.Reader.Process(OcrReading.Empty, null);
        }
        Assert.Empty(rig.Reader.Items);
        Assert.Empty(rig.Notes[^1]);
    }

    [Fact]
    public async Task ReaderPoolThenFallback()
    {
        var pool = new FakePool(l => l == "Deposit Cash Into Buckme" ? "BuckMe'ye nakit yatır" : null);
        var fallback = new PrefixTranslator("Cihaz ");
        var own = new PrefixTranslator("Own ");
        var card = MapCard.Find(Fixtures.Load("gta6-harita-buckme"))!;
        var rig = new Rig(new OverlayServices { Pool = pool.Ask, Fallback = fallback, Own = own });
        await rig.Read(Fixtures.Load("gta6-harita-buckme"));
        var req = Assert.Single(pool.Requests);
        Assert.Equal(3, req.Lines.Length);
        Assert.Equal("Deposit Cash Into Buckme", req.Lines[0]);
        Assert.Equal(card.Sentences, fallback.Requests.OrderBy(s => card.Sentences.ToList().IndexOf(s)));
        Assert.Equal(0, own.Calls);
        var item = Assert.Single(rig.Reader.Items);
        Assert.StartsWith("BUCKME'YE NAKİT YATIR", item.Text);
        Assert.Contains("Cihaz ", item.Text);
        Assert.Contains(rig.Log, l => l.StartsWith("harita kartı ", StringComparison.Ordinal) && l.EndsWith(" ms'de çevrildi; 1/3 parça hazırdı", StringComparison.Ordinal));
    }

    [Fact]
    public async Task BrokenShortCardNotShown()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        await rig.Read(R(L("RECENTER", 0.85, 0.85, 0.93, 0.87), L("SET DESTINATION", 0.85, 0.88, 0.95, 0.90),
            L("Bring the boat of", 0.50, 0.50, 0.72, 0.52)));
        Assert.Equal(0, own.Calls);
        Assert.Empty(rig.Reader.Items);
        await rig.Read(R(L("RECENTER", 0.85, 0.85, 0.93, 0.87), L("SET DESTINATION", 0.85, 0.88, 0.95, 0.90),
            L("Bring the boat back before the storm hits.", 0.50, 0.50, 0.72, 0.52)));
        Assert.Single(rig.Reader.Items);
    }

    [Fact]
    public async Task SameCardNotRetranslatedAndRemembered()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        await rig.Read(Fixtures.Load("gta6-harita-buckme"));
        var calls = own.Calls;
        await rig.Read(Fixtures.Load("gta6-harita-buckme"));
        Assert.Equal(calls, own.Calls);
        rig.Reader.Process(OcrReading.Empty, null);
        await rig.Read(Fixtures.Load("gta6-harita-buckme"));
        Assert.Equal(calls, own.Calls);
        Assert.Single(rig.Reader.Items);
    }

    [Fact]
    public async Task TurkishNotificationIgnored()
    {
        var own = new PrefixTranslator("TR: ");
        var rig = new Rig(new OverlayServices { Own = own });
        await rig.Read(R(L("RECENTER", 0.85, 0.85, 0.93, 0.87), L("SET DESTINATION", 0.85, 0.88, 0.95, 0.90),
            L("Arkadaşın çevrimiçi oldu şimdi oyna", 0.50, 0.50, 0.72, 0.52)));
        Assert.Equal(0, own.Calls);
    }

    [Fact]
    public void HalveAverages()
    {
        var f = BgraFrame.Blank(4, 2);
        f.SetPixel(0, 0, 10, 10, 10);
        f.SetPixel(1, 0, 11, 11, 11);
        var h = MapReader.Halve(f);
        Assert.Equal(2, h.Width);
        Assert.Equal(1, h.Height);
        Assert.Equal((10 + 11 + 0 + 0 + 2) / 4, h.Pixels[0]);
    }

    [Fact]
    public async Task OfferFrameEveryTwoSeconds()
    {
        var clock = new ManualMsClock(0);
        var ocr = new FuncReader(_ => new OcrReading(Fixtures.Load("gta6-harita-buckme").Lines
            .Select(l => l with { Box = l.Box!.Value.RelativeTo(MapReader.ReadArea) })));
        var reader = new MapReader(new OverlayServices { Clock = clock, Ocr = ocr, Own = new PrefixTranslator("TR: ") });
        reader.OfferFrame(BgraFrame.Blank(64, 36));
        await reader.Running!;
        reader.OfferFrame(BgraFrame.Blank(64, 36));
        Assert.Equal(1, ocr.Calls);
        await reader.Showing!;
        Assert.Single(reader.Items);
        clock.Advance(2000);
        reader.OfferFrame(BgraFrame.Blank(64, 36));
        await reader.Running!;
        Assert.Equal(2, ocr.Calls);
    }

    [RealFrameFact]
    public async Task RealBuckMeFrameCard()
    {
        var frame = SipsDecoder.Load("gta6-harita-buckme");
        var card = MapCard.Find(Fixtures.Load("gta6-harita-buckme"))!;
        var found = MapCard.FindFrame(frame, card.Box);
        var rig = new Rig(new OverlayServices { Own = new PrefixTranslator("TR: ") });
        rig.Reader.Process(Fixtures.Load("gta6-harita-buckme"), frame);
        await rig.Reader.Showing!;
        var item = Assert.Single(rig.Reader.Items);
        Assert.True(item.Box.Top > card.Box.Bottom || item.Box.Bottom < card.Box.Top);
        if (found is { } f) Assert.True(f.Width > card.Box.Width);
    }
}
