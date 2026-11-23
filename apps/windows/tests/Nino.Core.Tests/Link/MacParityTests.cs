// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Reading;
using Nino.Core.Settings;
using static Nino.Core.Tests.Link.LinkTestKit;
using LinkScreenItem = Nino.Core.Link.ScreenItem;

namespace Nino.Core.Tests.Link;

/// <summary>
/// Yeni protokol mesajları Mac (NinoCore) ile aynı mı. Beklenen dizgeler NinoCore'un altın testlerinden ve protokol
/// tarifinden birebir alındı. Mac anahtarların hepsini sıralı yazar (<c>type</c> alfabetik yerinde); Windows
/// <c>app</c>, <c>type</c>'ı başa koyar, gerisi sıralı. Karşılaştırma bu yüzden anahtar sırasından bağımsız, ama değerler
/// (sayıların yazımı dahil) bayt bayt.
/// </summary>
public class MacParityTests
{
    /// <summary>İki JSON aynı mı (anahtar sırası hariç; sayılar ham yazımıyla).</summary>
    static void SameJson(string mac, string windows)
    {
        using var a = JsonDocument.Parse(mac);
        using var b = JsonDocument.Parse(windows);
        Assert.True(Same(a.RootElement, b.RootElement), $"\nMac:     {mac}\nWindows: {windows}");
    }

    static bool Same(JsonElement a, JsonElement b)
    {
        if (a.ValueKind != b.ValueKind) return false;
        switch (a.ValueKind)
        {
            case JsonValueKind.Object:
                var pa = a.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal).ToList();
                var pb = b.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal).ToList();
                return pa.Count == pb.Count && pa.Zip(pb).All(x => x.First.Name == x.Second.Name && Same(x.First.Value, x.Second.Value));
            case JsonValueKind.Array:
                var ea = a.EnumerateArray().ToList();
                var eb = b.EnumerateArray().ToList();
                return ea.Count == eb.Count && ea.Zip(eb).All(x => Same(x.First, x.Second));
            case JsonValueKind.String: return a.GetString() == b.GetString();
            case JsonValueKind.Number: return a.GetRawText() == b.GetRawText();
            default: return true;
        }
    }

    static string LegacyData(TvEvent e, long at)
    {
        var frame = TvWire.LegacyFrame(e, at);
        return frame.Split('\n').Single(l => l.StartsWith("data: ", StringComparison.Ordinal))["data: ".Length..];
    }

    // ---- show ----

    [Fact]
    public void ShowExtrasMatchMac()
    {
        var e = new SubtitleShown("Selam", 2000, new Box(0.1, 0.8, 0.9, 0.95), Paragraphs: true, Replace: true)
        {
            Light = 0.42,
            Cover = "QUJD",
        };
        SameJson("{\"app\":\"nino\",\"box\":{\"bottom\":0.95,\"left\":0.1,\"right\":0.9,\"top\":0.8},\"cover\":\"QUJD\",\"durationMs\":2000,"
            + "\"id\":3,\"light\":0.42,\"paragraphs\":true,\"position\":\"bottom\",\"replace\":true,\"text\":\"Selam\",\"type\":\"show\"}",
            TvWire.LinkMessage(e, 3));
        // Eski 8787: yeni alanlar yok, bayt bayt eskisi.
        Assert.Equal("{\"at\":5,\"box\":{\"bottom\":0.95,\"left\":0.1,\"right\":0.9,\"top\":0.8},\"duration\":2000,\"paragraphs\":true,"
            + "\"replace\":true,\"text\":\"Selam\"}", LegacyData(e, 5));
    }

    [Fact]
    public void BoxIsClampedAndRoundedLikeMac()
    {
        var e = new SubtitleShown("x", 0, new Box(-0.2, 0.123456, 1.7, 0.5)) { Light = 0.4567 };
        SameJson("{\"app\":\"nino\",\"box\":{\"bottom\":0.5,\"left\":0,\"right\":1,\"top\":0.1235},\"durationMs\":0,\"id\":1,"
            + "\"light\":0.46,\"position\":\"bottom\",\"text\":\"x\",\"type\":\"show\"}", TvWire.LinkMessage(e, 1));
    }

    [Theory]
    [InlineData(0.12345, "0.1235")] // Mac: kayan noktalı, yarıda sıfırdan uzağa (8787: 0.1234)
    [InlineData(0.00005, "0.0001")]
    [InlineData(-0.3, "0")]
    [InlineData(1.00001, "1")]
    public void LinkUnitMatchesMacRounding(double value, string expected) =>
        Assert.Equal(expected, WireNumbers.LinkUnit(value).Text);

    [Fact]
    public void SpeakerIsSentSeparately()
    {
        var e = new SubtitleShown("BRENNA: Kapıyı tut.", 0, Source: "BRENNA: Hold the door.") { Speaker = "BRENNA" };
        SameJson("{\"app\":\"nino\",\"durationMs\":0,\"id\":7,\"position\":\"bottom\",\"source\":\"BRENNA: Hold the door.\","
            + "\"speaker\":\"BRENNA\",\"text\":\"Kapıyı tut.\",\"type\":\"show\"}", TvWire.LinkMessage(e, 7));
    }

    [Fact]
    public void NoSpeakerKeepsOldJson()
    {
        SameJson("{\"app\":\"nino\",\"durationMs\":0,\"id\":1,\"position\":\"bottom\",\"text\":\"Selam\",\"type\":\"show\"}",
            TvWire.LinkMessage(new SubtitleShown("Selam", 0), 1));
        Assert.DoesNotContain("speaker", TvWire.LinkMessage(new SubtitleShown("Selam", 0) { Speaker = "  " }, 1));
        // Metin adla başlamıyorsa ad gönderilmez, metin tam kalır.
        var odd = TvWire.LinkMessage(new SubtitleShown("Kapıyı tut.", 0) { Speaker = "BRENNA" }, 1);
        Assert.DoesNotContain("speaker", odd);
        Assert.Contains("\"text\":\"Kapıyı tut.\"", odd);
    }

    [Fact]
    public void LongSpeakerIsClipped()
    {
        var name = new string('A', 80);
        var json = TvWire.LinkMessage(new SubtitleShown(name + ": x y", 0) { Speaker = name }, 1);
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(TvSpeaker.MaxLength, doc.RootElement.GetProperty("speaker").GetString()!.Length);
        Assert.Equal("x y", doc.RootElement.GetProperty("text").GetString());
    }

    [Fact]
    public void LegacyGetsPrefixedSingleText()
    {
        Assert.Equal("{\"at\":1732233600000,\"duration\":2500,\"text\":\"BRENNA: Kapıyı tut.\"}",
            LegacyData(new SubtitleShown("BRENNA: Kapıyı tut.", 2500) { Speaker = "BRENNA" }, 1732233600000));
        // Bilgisayar penceresi de adıyla görür.
        Assert.Equal("BRENNA: Kapıyı tut.", TvWire.Local(new SubtitleShown("BRENNA: Kapıyı tut.", 2500) { Speaker = "BRENNA" })!.Text);
    }

    [Fact]
    public void SpeakerSplitRulesMatchMac()
    {
        Assert.Equal(("Kapıyı tut.", "BRENNA"), TvSpeaker.Split("BRENNA: Kapıyı tut.", "BRENNA: Hold the door.", true));
        // İki konuşan: adlar metinde kalır.
        Assert.Equal(("A: Evet.\nB: Hayır.", null), TvSpeaker.Split("A: Evet.\nB: Hayır.", "ANNA: Yes.\nBO: No.", true));
        // Çeviri adla başlamıyor (paket çevirisi): bölünmez.
        Assert.Equal(("Kapıyı tut.", null), TvSpeaker.Split("Kapıyı tut.", "BRENNA: Hold the door.", true));
        // Adsız satır; ayar kapalı.
        Assert.Null(TvSpeaker.Split("Selam.", "Hi.", true).Speaker);
        Assert.Null(TvSpeaker.Split("BRENNA: Kapıyı tut.", "BRENNA: Hold the door.", false).Speaker);
        // Tam genişlikli iki nokta da ayırır; adın ardında harf yoksa bölünmez.
        Assert.Equal(("Kapıyı tut.", "BRENNA"), TvSpeaker.Split("BRENNA：Kapıyı tut.", "BRENNA: Hold the door.", true));
        Assert.Null(TvSpeaker.Split("BRENNA: ...", "BRENNA: Hold the door.", true).Speaker);
    }

    [Fact]
    public void PositionRule()
    {
        Assert.Equal("top", TvPosition.For(AreaPreset.Top, new Region()));
        Assert.Equal("top", TvPosition.For(AreaPreset.Custom, new Region(0.05, 0.45, 0.1, 0.9)));
        Assert.Equal("bottom", TvPosition.For(AreaPreset.Bottom, new Region()));
        Assert.Equal("bottom", TvPosition.For(AreaPreset.Full, new Region(0, 1, 0, 1)));
        Assert.Contains("\"position\":\"top\"", TvWire.LinkMessage(new SubtitleShown("x", 0) { Position = TvPosition.Top }, 1));
        // Eski 8787'de konum yok.
        Assert.DoesNotContain("position", LegacyData(new SubtitleShown("x", 1000) { Position = TvPosition.Top }, 0));
    }

    [Fact]
    public void ParagraphsFollowTheFlagOnly()
    {
        // Windows okuması iki satırlık diyalogu "\n" ile birleştirir: satır sonu tek başına paragraf düzeni açmaz.
        Assert.DoesNotContain("paragraphs", TvWire.LinkMessage(new SubtitleShown("A\nB", 1000), 1));
        Assert.Contains("\"paragraphs\":true", TvWire.LinkMessage(new SubtitleShown("A\nB", 1000, Paragraphs: true), 1));
        Assert.DoesNotContain("paragraphs", LegacyData(new SubtitleShown("A\nB", 1000), 0));
    }

    // ---- simgeler ----

    [Fact]
    public void IconsOnShowMatchMac()
    {
        var e = new SubtitleShown("Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut", 0) { Icons = [new LinkIcon("T1", "dpad-right")] };
        SameJson("{\"app\":\"nino\",\"durationMs\":0,\"icons\":[{\"id\":\"T1\",\"name\":\"dpad-right\"}],\"id\":2,\"position\":\"bottom\","
            + "\"text\":\"Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut\",\"type\":\"show\"}", TvWire.LinkMessage(e, 2));
        // Boş liste alan yazmaz; eski 8787 okunur metin görür, simge alanı yok.
        Assert.DoesNotContain("icons", TvWire.LinkMessage(new SubtitleShown("Selam", 0) { Icons = [] }, 1));
        Assert.Equal("{\"at\":0,\"duration\":1000,\"text\":\"Ortağınla etkileşime geçmek için [→] basılı tut\"}",
            LegacyData(e with { DurationMs = 1000 }, 0));
        Assert.Equal("Ortağınla etkileşime geçmek için [→] basılı tut", TvWire.Local(e)!.Text);
    }

    [Fact]
    public void InvalidIconsAreDropped()
    {
        var e = new SubtitleShown("x ⟦T3⟧", 0)
        {
            Icons = [new LinkIcon("X1", "cross"), new LinkIcon("T2"), new LinkIcon("T3", "circle")],
        };
        Assert.Contains("\"icons\":[{\"id\":\"T3\",\"name\":\"circle\"}]", TvWire.LinkMessage(e, 1));
        var many = Enumerable.Range(1, 10).Select(i => new LinkIcon("T" + i, "cross")).ToList();
        Assert.Equal(LinkIcon.MaxCount, LinkIcon.Encode(many)!.Count);
        Assert.Null(LinkIcon.Encode([new LinkIcon("T1", Png: new string('A', LinkIcon.MaxPngLength + 1))]));
    }

    [Fact]
    public void IconsOnScreenItemAndRegion()
    {
        var item = new LinkScreenItem(new Box(0.3, 0.9, 0.7, 0.95), "⟦T1⟧ bas") { Icons = [new LinkIcon("T1", Png: "iVBORw0KGgo=")] };
        var screen = new ScreenShown([item], 120000, Overlay: true);
        Assert.Contains("\"icons\":[{\"id\":\"T1\",\"png\":\"iVBORw0KGgo=\"}]", TvWire.LinkMessage(screen));
        var legacy = LegacyData(screen, 0);
        Assert.DoesNotContain("icons", legacy);
        Assert.Contains("\"text\":\"[■] bas\"", legacy);

        var region = new RegionShown("a", "⟦T1⟧ bas") { Icons = [new LinkIcon("T1", "cross")] };
        SameJson("{\"app\":\"nino\",\"icons\":[{\"id\":\"T1\",\"name\":\"cross\"}],\"id\":\"a\",\"text\":\"⟦T1⟧ bas\",\"type\":\"region\"}",
            TvWire.LinkMessage(region));
        Assert.Equal("{\"id\":\"a\",\"text\":\"[✕] bas\"}", LegacyData(region, 0));
    }

    [Fact]
    public void PlaceholderHelpersMatchMac()
    {
        Assert.Equal(["T1", "T12"], IconPlaceholders.Ids("a ⟦T1⟧ b ⟦T12⟧ ⟦Arabana⟧ ⟦3⟧"));
        IReadOnlyList<LinkIcon> icons = [new LinkIcon("T1", "dpad-right"), new LinkIcon("T2", Png: "AAAA")];
        Assert.Equal("Bas [→] ya da [■]", IconPlaceholders.Readable("Bas ⟦T1⟧ ya da ⟦T2⟧", icons));
        Assert.Equal("⟦Arabana⟧ git", IconPlaceholders.Readable("⟦Arabana⟧ git ⟦T3⟧", icons));
        Assert.Equal("[L2]", new LinkIcon("T1", "L2").Readable);
        Assert.Equal("[OPTIONS]", new LinkIcon("T1", "options").Readable);

        Assert.Equal("Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut",
            IconPlaceholders.Ensure("Ortağınla etkileşime geçmek için tuşu basılı tut", ["T1"], "tr"));
        Assert.Equal("Ortağınla etkileşime geçmek için ⟦T1⟧ basılı tut",
            IconPlaceholders.Ensure("Ortağınla etkileşime geçmek için basılı tut", ["T1"], "tr"));
        Assert.Equal("Kapıyı açmak için ⟦T1⟧ bas.", IconPlaceholders.Ensure("Kapıyı açmak için bas.", ["T1"], "tr"));
        Assert.Equal("Sandığı kapat ⟦T1⟧.", IconPlaceholders.Ensure("Sandığı kapat.", ["T1"], "tr"));
        Assert.Equal("⟦T1⟧ tuşunu basılı tut", IconPlaceholders.Ensure("⟦T1⟧ tuşunu basılı tut", ["T1"], "tr"));
        Assert.Equal("Halte die ⟦T1⟧ gedrückt", IconPlaceholders.Ensure("Halte die Taste gedrückt", ["T1"], "de"));
        Assert.Equal("⟦T1⟧ Mantén para interactuar", IconPlaceholders.Ensure("Mantén para interactuar", ["T1"], "es"));
    }

    // ---- screen / style / state ----

    [Fact]
    public void ScreenExampleMatchesProtocol()
    {
        var e = new ScreenShown([new LinkScreenItem(new Box(0.1, 0.1, 0.4, 0.2), "Görev") { Line = 0.03, Plain = true }], 120000,
            Overlay: true);
        SameJson("{\"app\":\"nino\",\"type\":\"screen\",\"durationMs\":120000,\"overlay\":true,\"items\":[{\"box\":{\"left\":0.1,"
            + "\"top\":0.1,\"right\":0.4,\"bottom\":0.2},\"line\":0.03,\"text\":\"Görev\",\"plain\":true}]}", TvWire.LinkMessage(e));
        var frost = new ScreenShown([new LinkScreenItem(new Box(0, 0, 1, 1), "a") { Frost = true }], 1000);
        Assert.Contains("\"frost\":true", TvWire.LinkMessage(frost));
        Assert.DoesNotContain("frost", LegacyData(frost, 0));
    }

    [Fact]
    public void DefaultStyleMatchesMacThirteenFields()
    {
        var link = TvWire.LinkMessage(new StyleChanged(TvStyle.From(new SubtitleStyle())));
        SameJson("{\"app\":\"nino\",\"autoSize\":true,\"background\":100,\"backgroundShape\":\"fit\",\"bold\":false,\"bottomPercent\":7,"
            + "\"displayMode\":\"inApp\",\"font\":\"condensed\",\"fontSize\":46,\"placement\":\"cover\",\"stackPrevious\":true,"
            + "\"textColor\":\"white\",\"theme\":\"classic\",\"type\":\"style\",\"watermark\":true}", link);
        // Eski 8787'de tema yok (değişmedi).
        Assert.DoesNotContain("theme", LegacyData(new StyleChanged(new TvStyle()), 0));
    }

    [Fact]
    public void StateMessageMatchesMac()
    {
        SameJson("{\"active\":false,\"app\":\"nino\",\"type\":\"state\"}", TvWire.StateMessage(false));
        Assert.Equal("{\"app\":\"nino\",\"type\":\"state\",\"active\":true}", TvWire.StateMessage(true));
    }

    // ---- cover ----

    [Fact]
    public void OversizedCoverIsDropped()
    {
        var small = new SubtitleShown("x", 1000) { Cover = "QUJD" };
        Assert.Same(small, TvWire.FitShow(small, 1));
        var big = new SubtitleShown("x", 1000) { Cover = new string('A', TvWire.MaxMessageBytes) };
        var fitted = TvWire.FitShow(big, 1);
        Assert.Null(fitted.Cover);
        Assert.DoesNotContain("cover", TvWire.LinkMessage(fitted, 1));
        Assert.DoesNotContain("cover", LegacyData(small, 0));
    }

    [Fact]
    public void FrostExpandsLikeMac()
    {
        Assert.Equal(new Box(0, 0.865, 0.54, 1), Round(FrostCover.Expanded(new Box(0.01, 0.9, 0.5, 0.99))));
        static Box Round(Box b) => new(Math.Round(b.Left, 6), Math.Round(b.Top, 6), Math.Round(b.Right, 6), Math.Round(b.Bottom, 6));
    }

    static BgraFrame Gradient(int width, int height)
    {
        var f = BgraFrame.Blank(width, height);
        for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
            f.SetPixel(x, y, (byte)(x * 255 / Math.Max(1, width - 1)), 80, (byte)(y * 255 / Math.Max(1, height - 1)));
        return f;
    }

    [Fact]
    public void FrostRendersSmallBlurredImage()
    {
        var frame = Gradient(1280, 720);
        var image = FrostCover.Render(frame, new Box(0.3, 0.8, 0.7, 0.9))!;
        Assert.True(image.Width <= FrostCover.MaxWidth);
        // Kesilen yer: (0,26–0,74) × (0,765–0,935) → 614 × 123 piksel, 360'a küçültülür.
        Assert.Equal(360, image.Width);
        Assert.Equal(72, image.Height);

        // Düz gri: bulanıklık değiştirmez, renk ayarı (parlaklık −0,12, karşıtlık ×0,9) uygular.
        var gray = BgraFrame.Filled(200, 100, 128);
        var g = FrostCover.Render(gray, new Box(0.2, 0.2, 0.8, 0.8))!;
        var expected = (byte)Math.Round(Math.Clamp((128 / 255.0 - 0.12 - 0.5) * 0.9 + 0.5, 0, 1) * 255);
        Assert.All(Enumerable.Range(0, g.Width * g.Height), i => Assert.Equal(expected, g.Pixels[i * 4 + 1]));
        Assert.Equal(255, g.Pixels[3]);

        // Bulanık: komşu pikseller arasında sert geçiş kalmaz.
        var edge = BgraFrame.Blank(400, 100);
        for (var y = 0; y < 100; y++) for (var x = 200; x < 400; x++) edge.SetPixel(x, y, 255, 255, 255);
        var e = FrostCover.Render(edge, new Box(0.1, 0.1, 0.9, 0.9))!;
        var row = e.Height / 2 * e.Width;
        var maxStep = Enumerable.Range(1, e.Width - 1).Max(x => Math.Abs(e.Pixels[(row + x) * 4] - e.Pixels[(row + x - 1) * 4]));
        Assert.True(maxStep < 20, $"en büyük adım {maxStep}");
    }

    [Fact]
    public void FrostUsesEncoderAndQuality()
    {
        var frame = Gradient(640, 360);
        int? quality = null;
        var b64 = FrostCover.Make(frame, new Box(0.2, 0.8, 0.8, 0.9), (img, q) => { quality = q; return [1, 2, 3]; });
        Assert.Equal("AQID", b64);
        Assert.Equal(55, quality);
        Assert.Null(FrostCover.Make(frame, new Box(0.2, 0.8, 0.8, 0.9), (_, _) => null));
    }

    // ---- okuma hattından TV olayı ----

    [Fact]
    public void BuilderAddsSpeakerPositionSourceAndCover()
    {
        var frame = Gradient(320, 180);
        var showNames = true;
        var builder = new TvShowBuilder(new TvShowOptions
        {
            ShowSpeakerNames = () => showNames,
            Position = () => TvPosition.Top,
            LastFrame = () => frame,
            EncodeJpeg = (_, _) => [7],
        });
        var show = new SubtitleShow("BRENNA: Kapıyı tut.", 4000, new Box(0.3, 0.8, 0.7, 0.9), Replace: true)
        {
            Source = "BRENNA: Hold the door.",
        };
        var e = builder.Build(show);
        Assert.Equal("BRENNA: Kapıyı tut.", e.Text);
        Assert.Equal("BRENNA", e.Speaker);
        Assert.Equal("top", e.Position);
        Assert.Equal("Bw==", e.Cover);
        Assert.True(e.Replace);
        SameJson("{\"app\":\"nino\",\"box\":{\"bottom\":0.9,\"left\":0.3,\"right\":0.7,\"top\":0.8},\"cover\":\"Bw==\",\"durationMs\":4000,"
            + "\"id\":9,\"position\":\"top\",\"replace\":true,\"source\":\"BRENNA: Hold the door.\",\"speaker\":\"BRENNA\","
            + "\"text\":\"Kapıyı tut.\",\"type\":\"show\"}", TvWire.LinkMessage(e, 9));

        showNames = false;
        Assert.Null(builder.Build(show).Speaker);
        // Kutusuz altyazıda zemin yok.
        Assert.Null(builder.Build(show with { Box = null }).Cover);
    }

    [Fact]
    public void BuilderWithoutEncoderSendsNoCover()
    {
        var builder = new TvShowBuilder(new TvShowOptions { LastFrame = () => Gradient(64, 36) });
        var e = builder.Build(new SubtitleShow("Selam", 1000, new Box(0.1, 0.8, 0.9, 0.9)));
        Assert.Null(e.Cover);
        Assert.Equal("bottom", e.Position);
    }

    // ---- gönderme kuralları (47800 girişi) ----

    static TvOutput NewOutput(int port, ManualClock? clock = null) => new(new TvOutputOptions
    {
        Identity = new SenderIdentity { Name = "Salon PC", Id = "abc123", Client = "nino-windows/4.0.0" },
        LegacyPort = 0,
        IngressPort = port,
        Clock = clock,
        PortAttempts = 1,
    });

    static async Task<SocketPeer> ReadyTvAsync(int port)
    {
        var tv = await ConnectTvAsync(port);
        await tv.WaitForTypeAsync("hello");
        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"LG\"}");
        await tv.WaitForTypeAsync("state");
        return tv;
    }

    [Fact]
    public async Task SenderStateFollowsTranslationAndGate()
    {
        var port = FreePort();
        await using var output = NewOutput(port);
        await output.EnsureIngressAsync();
        Assert.Contains("\"active\":false", await RawAsync(port, "GET /nino/info HTTP/1.1\r\n\r\n"));

        await using var tv = await ReadyTvAsync(port);
        Assert.Contains("\"active\":false", (await tv.WaitForTypeAsync("hello")));
        Assert.Equal(TvWire.StateMessage(false), await tv.WaitForTypeAsync("state"));

        output.Send(new TranslationStarted());
        Assert.Equal(TvWire.StateMessage(true), await tv.WaitForTypeAsync("state", skip: 1));
        Assert.True(output.SenderActive);
        Assert.Contains("\"active\":true", await RawAsync(port, "GET /nino/info HTTP/1.1\r\n\r\n"));
        var types = tv.Received.Select(TypeOf).ToList();
        Assert.True(types.IndexOf("started") < types.LastIndexOf("state"));

        // "Altyazı yalnız bilgisayarda": boşta sayılır (state kapıdan bağımsız gider).
        output.SubtitlesOnTv = false;
        Assert.Equal(TvWire.StateMessage(false), await tv.WaitForTypeAsync("state", skip: 2));
        output.SubtitlesOnTv = true;
        Assert.Equal(TvWire.StateMessage(true), await tv.WaitForTypeAsync("state", skip: 3));

        output.Send(new TranslationStopped());
        Assert.Equal(TvWire.StateMessage(false), await tv.WaitForTypeAsync("state", skip: 4));
        // Aynı durum yeniden yollanmaz.
        output.Send(new TranslationStopped());
        await Task.Delay(100);
        Assert.Equal(5, tv.Received.Count(m => TypeOf(m) == "state"));
    }

    [Fact]
    public async Task StyleGoesOnlyWhenChanged()
    {
        var port = FreePort();
        await using var output = NewOutput(port);
        await output.EnsureIngressAsync();
        await using var tv = await ReadyTvAsync(port);

        output.Send(new StyleChanged(new TvStyle { FontSize = 50 }));
        output.Send(new StyleChanged(new TvStyle { FontSize = 50 }));
        output.Send(new StyleChanged(new TvStyle { FontSize = 52 }));
        Assert.Contains("\"fontSize\":52", await tv.WaitForTypeAsync("style", skip: 1));
        await Task.Delay(100);
        Assert.Equal(2, tv.Received.Count(m => TypeOf(m) == "style"));

        // Yeni bağlanana son görünüm bir kez.
        await using var late = await ReadyTvAsync(port);
        Assert.Single(late.Received, m => TypeOf(m) == "style");
    }

    [Fact]
    public async Task StartedIsReplayedOnlyWithinTwentySeconds()
    {
        var port = FreePort();
        var clock = new ManualClock(DateTimeOffset.UnixEpoch.AddDays(20000));
        await using var output = NewOutput(port, clock);
        await output.EnsureIngressAsync();
        output.Send(new TranslationStarted());
        clock.Advance(TimeSpan.FromSeconds(19));

        await using var early = await ReadyTvAsync(port);
        Assert.Contains("started", early.Received.Select(TypeOf));

        clock.Advance(TimeSpan.FromSeconds(2));
        await using var late = await ReadyTvAsync(port);
        Assert.DoesNotContain("started", late.Received.Select(TypeOf));
        // Sürdüğünü durum söyler.
        Assert.Equal(TvWire.StateMessage(true), await late.WaitForTypeAsync("state"));
    }

    [Fact]
    public async Task ShowOverIngressCarriesNewFields()
    {
        var port = FreePort();
        await using var output = NewOutput(port);
        await output.EnsureIngressAsync();
        await using var tv = await ReadyTvAsync(port);
        output.Send(new SubtitleShown("BRENNA: Kapıyı tut.", 3000, Source: "BRENNA: Hold the door.")
        {
            Speaker = "BRENNA",
            Position = TvPosition.Top,
            Cover = "QUJD",
        });
        var show = await tv.WaitForTypeAsync("show");
        Assert.Contains("\"speaker\":\"BRENNA\"", show);
        Assert.Contains("\"text\":\"Kapıyı tut.\"", show);
        Assert.Contains("\"position\":\"top\"", show);
        Assert.Contains("\"cover\":\"QUJD\"", show);
    }
}
