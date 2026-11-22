// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;
using static Nino.Core.Tests.Phone.PhoneTestData;

namespace Nino.Core.Tests.Phone;

public class PhoneFinderTests
{
    const int W = 240, H = 135;

    // Doğrulanamadı: koyu temalı karede (koyu-rydeme) telefonun sağ çerçevesi (en büyük kanal ~80) 75/85 eşiklerinin
    // arasında kalıyor; sips çözümüyle bu karede telefon şeritleri komşu kovalara bölünüyor ve bulucu telefonu bulmuyor.
    // Eşikler birkaç birim oynatılınca (78/82 ya da 72/88) telefon ortası 0,685'te bulunuyor; yani fark büyük olasılıkla
    // JPG çözümünden (eski Windows WIC kullanıyordu). Tarif sabitleri değiştirilmedi; bulucuya dayalı bu sınamalar
    // Windows'ta WIC çözücüsüyle koşulmalı. Bulucusuz kısımlar aşağıda elle verilen şekille sınanıyor.
    const string DarkThemeSkip = "doğrulanamadı: koyu temada sips çözümüyle telefon bulunmuyor (Windows'ta WIC ile koşulmalı)";

    static PhoneShape? SearchMap(Func<int, int, bool> white, Func<int, int, bool>? dark = null) =>
        PhoneFinder.Search(W, H, white, dark ?? ((x, y) => !white(x, y)));

    [Fact]
    public void UprightPhone()
    {
        var p = SearchMap((x, y) => x is >= 139 and <= 190 && y is >= 27 and <= 115);
        Assert.NotNull(p);
        Assert.Equal(139.0 / 240, p!.Box.Left, 2);
        Assert.Equal(191.0 / 240, p.Box.Right, 2);
        Assert.Equal(27.0 / 135, p.Box.Top, 2);
        Assert.Equal(116.0 / 135, p.Box.Bottom, 2);
        Assert.Equal(0, p.Slant, 6);
    }

    [Fact]
    public void PhoneWithPhotoAndBubbleInside()
    {
        bool White(int x, int y) => x is >= 139 and <= 190 && y is >= 27 and <= 115
            && !(y is >= 40 and <= 75 && x is >= 144 and <= 185) && !(y is >= 95 and <= 108 && x is >= 160 and <= 186);
        Assert.NotNull(SearchMap(White));
    }

    [Fact]
    public void SlantedPhone()
    {
        static int Left(int y) => 99 - (int)Math.Round((y - 24) * 0.16, MidpointRounding.AwayFromZero);
        var p = SearchMap((x, y) => y is >= 24 and <= 105 && x >= Left(y) && x < Left(y) + 45);
        Assert.NotNull(p);
        Assert.InRange(p!.Slant * 240 / 135, -0.19, -0.13);
        Assert.Equal(24.0 / 135, p.Box.Top, 2);
        Assert.Equal(106.0 / 135, p.Box.Bottom, 2);
        Assert.InRange(p.CenterAt(p.Box.Top), (99 + 23) / 240.0 - 0.012, (99 + 23) / 240.0 + 0.012);
        Assert.InRange(p.CenterAt(p.Box.Bottom), (86 + 23) / 240.0 - 0.012, (86 + 23) / 240.0 + 0.012);
    }

    [Fact]
    public void NotFound()
    {
        static bool Phone(int x, int y) => x is >= 139 and <= 190 && y is >= 27 and <= 115;
        Assert.Null(SearchMap(Phone, (_, _) => false));
        Assert.Null(SearchMap((x, y) => x is >= 12 and <= 65 && y is >= 7 and <= 88));
        Assert.Null(SearchMap((x, y) => x is >= 100 and <= 150 && y is >= 0 and <= 68));
        Assert.Null(SearchMap((_, _) => false));
        Assert.Null(SearchMap((_, y) => y < 70));
        Assert.Null(SearchMap((x, y) => x is >= 150 and <= 220 && y is >= 110 and <= 134));
        Assert.Null(SearchMap((x, y) => y is >= 20 and <= 120 && x >= 100 + y * 7 % 23 && x <= 150 + y * 11 % 29));
    }

    [Fact]
    public void AngleOfSlant()
    {
        Assert.True(PhoneShape.Upright(new Box(0, 0, 1, 1)).AngleDegrees == 0);
        var a = new PhoneShape(new Box(0.5, 0.2, 0.7, 0.8), 0.5, -0.1, 0.2).AngleDegrees;
        Assert.InRange(a, 9, 11);
    }

    [Fact]
    public void BlankFrameHasNoPhone() => Assert.Null(PhoneFinder.Find(BgraFrame.Blank(0, 0)));

    [Fact]
    public void TrackerAdoptsTextBoxesThenExpires()
    {
        var clock = new ManualMsClock(0);
        var t = new PhoneTracker(clock);
        var black = Solid(960, 540, 0);
        t.Adopt(black, [new Box(0.60, 0.40, 0.75, 0.42), new Box(0.60, 0.60, 0.72, 0.62)]);
        clock.NowMs = 2000;
        Assert.NotNull(t.Locate(black));
        clock.NowMs = 3500;
        Assert.Null(t.Locate(black));
    }

    [Fact]
    public void EstimateFromBoxes()
    {
        var p = PhoneTracker.Estimate([new Box(0.60, 0.40, 0.75, 0.42)]);
        Assert.Equal(0.585, p.Box.Left, 6);
        Assert.Equal(0.795, p.Box.Right, 6);
        Assert.Equal(0.2, p.Box.Top, 6);
        Assert.Equal(0.82, p.Box.Bottom, 6);
    }

    // ---- Gerçek kareler ----

    [RealFrameTheory]
    [InlineData("gta6-telefon-donnie")]
    [InlineData("gta6-telefon-kenton")]
    [InlineData("gta6-telefon-shirley")]
    [InlineData("gta6-telefon-liste")]
    public void RealUprightPhones(string name)
    {
        var p = PhoneFinder.Find(SipsDecoder.Load(name));
        Assert.NotNull(p);
        Assert.InRange(p!.Box.Left, 0.57, 0.61);
        Assert.InRange(p.Box.Right, 0.77, 0.81);
        Assert.InRange(p.Box.Top, 0.17, 0.23);
        Assert.InRange(p.Box.Bottom, 0.79, 0.85);
    }

    [RealFrameFact]
    public void RealLoweredPhone()
    {
        var p = PhoneFinder.Find(SipsDecoder.Load("gta6-telefon-egik-alt"));
        Assert.NotNull(p);
        Assert.InRange(p!.Box.Top, 0.55, 0.61);
        Assert.True(p.Box.Bottom > 0.96);
        Assert.InRange(p.Box.CenterX, 0.49, 0.55);
    }

    [RealFrameFact(Skip = DarkThemeSkip)]
    public void RealDarkTheme()
    {
        var p = PhoneFinder.Find(SipsDecoder.Load("gta6-telefon-koyu-rydeme"));
        Assert.NotNull(p);
        Assert.InRange(p!.Box.CenterX, 0.66, 0.72);
    }

    [RealFrameFact]
    public void RealDarkThemeHasText()
    {
        var g = RgbGrid.Downscale(SipsDecoder.Load("gta6-telefon-koyu-rydeme"), 240, 135)!;
        var max = new int[240 * 135];
        for (var y = 0; y < 135; y++)
            for (var x = 0; x < 240; x++) max[y * 240 + x] = g.At(x, y).Max;
        Assert.True(PhoneFinder.HasDarkThemeText(RydemePhone, 240, 135, max));
    }

    [RealFrameFact]
    public void RealTrackerWithKnownDarkPhone()
    {
        var rydeme = SipsDecoder.Load("gta6-telefon-koyu-rydeme");
        var alt = SipsDecoder.Load("gta6-telefon-koyu-altpencere");
        var hoodie = SipsDecoder.Load("gta6-menu-kapusonlu");
        var clock = new ManualMsClock(0);
        PhoneShape? Finder(BgraFrame f) => ReferenceEquals(f, rydeme) ? RydemePhone : null;
        var t = new PhoneTracker(clock, Finder);
        Assert.Equal(RydemePhone, t.Locate(rydeme));
        clock.Advance(500);
        Assert.Equal(RydemePhone, t.Locate(alt));
        var t2 = new PhoneTracker(clock, Finder);
        t2.Locate(rydeme);
        clock.Advance(500);
        Assert.Null(t2.Locate(hoodie));
        Assert.Null(t2.Locate(alt));
    }

    [RealFrameFact]
    public void RealHoodieIsNotPhone() => Assert.Null(PhoneFinder.Find(SipsDecoder.Load("gta6-menu-kapusonlu")));

    [RealFrameFact(Skip = DarkThemeSkip)]
    public void RealTrackerKeepsDarkPhoneUntilOtherScreen()
    {
        var alt = SipsDecoder.Load("gta6-telefon-koyu-altpencere");
        Assert.Null(PhoneFinder.Find(alt));
        var clock = new ManualMsClock(0);
        var t = new PhoneTracker(clock);
        var found = t.Locate(SipsDecoder.Load("gta6-telefon-koyu-rydeme"));
        Assert.NotNull(found);
        clock.Advance(500);
        Assert.Equal(found, t.Locate(alt));

        var t2 = new PhoneTracker(clock);
        t2.Locate(SipsDecoder.Load("gta6-telefon-koyu-rydeme"));
        clock.Advance(500);
        Assert.Null(t2.Locate(SipsDecoder.Load("gta6-menu-kapusonlu")));
        Assert.Null(t2.Locate(alt));
    }

    [RealFrameFact]
    public void RealDarkenedPhoneBrightened()
    {
        var frame = SipsDecoder.Load("gta6-telefon-karanlik");
        var p = PhoneFinder.Find(frame);
        Assert.NotNull(p);
        Assert.InRange(p!.Box.Left, 0.33, 0.39);
        Assert.InRange(p.Box.Right, 0.57, 0.63);
        var c = new BrightenedSampler(frame, p).At(0.44, 0.46);
        Assert.NotNull(c);
        Assert.True(c!.Value.B > c.Value.R + 15 && c.Value.B > 150, c.ToString());
    }

    /// <summary>koyu-rydeme karesindeki telefon (ızgarada elle ölçülmüş: x 139–190, y 40–103 / 240 × 135).</summary>
    static readonly PhoneShape RydemePhone = PhoneShape.Upright(new Box(0.579, 0.296, 0.792, 0.770));

    [RealFrameFact]
    public void RealDarkThemeNotBrightened()
    {
        var frame = SipsDecoder.Load("gta6-telefon-koyu-rydeme");
        var p = RydemePhone;
        var y = p.Box.CenterY;
        var x = p.CenterAt(y);
        Assert.Equal(new FrameSampler(frame).At(x, y)!.Value.R, new BrightenedSampler(frame, p).At(x, y)!.Value.R);
    }

    [RealFrameFact]
    public void RealLuciaPhotoChat()
    {
        var p = PhoneFinder.Find(SipsDecoder.Load("gta6-telefon-lucia-foto"));
        Assert.NotNull(p);
        Assert.InRange(p!.Box.CenterX, 0.43, 0.51);
        var content = PhoneScreen.Read(Fixtures.Load("gta6-telefon-lucia-foto"), p);
        Assert.True(content.IsChat);
        Assert.Equal("Lucia", content.Title);
    }

    [RealFrameFact]
    public void RealBrianChat()
    {
        var p = PhoneFinder.Find(SipsDecoder.Load("gta6-telefon-brian-parlama"));
        Assert.NotNull(p);
        var reading = Fixtures.Load("gta6-telefon-brian-parlama");
        Assert.False(PhoneScreen.IsChatList(reading));
        var content = PhoneScreen.Read(reading, p!);
        Assert.True(content.IsChat);
        Assert.DoesNotContain(content.Messages, m => m.Text == "Brian");
        Assert.Contains(content.Messages, m => m.Text.StartsWith("Remember, you get your hands", StringComparison.Ordinal));
    }

    [RealFrameFact]
    public void RealSlantedBlueChatSides()
    {
        var frame = SipsDecoder.Load("gta6-telefon-egik-mavi");
        var p = PhoneFinder.Find(frame);
        Assert.NotNull(p);
        var reading = Fixtures.Load("gta6-telefon-egik-mavi");
        Assert.False(PhoneScreen.IsChatList(reading));
        var content = PhoneScreen.Read(reading, p!);
        Assert.True(content.IsChat);
        var tr = content.Messages.Select(m => "TR " + m.Text).ToArray();
        var items = PhoneLayout.ChatPanel(content.Messages, tr, p!, new BrightenedSampler(frame, p!), content.Title);
        var floor = items.Single(i => i.Backdrop);
        var bubbles = items.Where(i => !i.Backdrop).ToArray();
        var minLeft = bubbles.Min(b => b.Box.Left);
        ScreenItem Of(string start) => bubbles.First(b => b.Source.StartsWith(start, StringComparison.OrdinalIgnoreCase));
        Assert.True(Of("Shit went sideways").Box.Left > minLeft + 0.02);
        Assert.True(Of("will do").Box.Left > minLeft + 0.02);
        Assert.Equal(minLeft, Of("Ah crap").Box.Left, 3);
        Assert.Equal(minLeft, Of("Remember").Box.Left, 3);
        Assert.True(floor.Box.Left <= minLeft);
    }

    [RealFrameFact]
    public void RealListReadingsAreNotChatLists()
    {
        foreach (var n in new[] { "gta6-telefon-brian-parlama", "gta6-telefon-lucia-foto", "gta6-telefon-egik-mavi", "gta6-telefon-yakin-alt" })
            Assert.False(PhoneScreen.IsChatList(Fixtures.Load(n)), n);
    }
}
