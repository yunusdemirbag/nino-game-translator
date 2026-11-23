// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;

namespace Nino.Core.Tests.Link;

public class WireTests
{
    static string Data(string frame)
    {
        var line = frame.Split('\n').Single(l => l.StartsWith("data: ", StringComparison.Ordinal));
        return line["data: ".Length..];
    }

    [Theory]
    [InlineData(0.8, "0.8")]
    [InlineData(0.87499, "0.875")]
    [InlineData(1.2, "1")]
    [InlineData(-0.1, "0")]
    [InlineData(0.25, "0.25")]
    [InlineData(0.00005, "0")]
    [InlineData(0.00015, "0.0002")]
    public void FractionRounding(double value, string expected) =>
        Assert.Equal(expected, WireNumbers.Fraction(value).Text);

    [Theory]
    [InlineData(5.71, "5.7")]
    [InlineData(-0.35, "-0.4")]
    [InlineData(0.3, "0.3")]
    [InlineData(400.0, "400")]
    public void AngleRounding(double value, string expected) =>
        Assert.Equal(expected, WireNumbers.Angle(value)!.Value.Text);

    [Theory]
    [InlineData(0.29)]
    [InlineData(-0.2)]
    [InlineData(0)]
    public void SmallAngleIsOmitted(double value) => Assert.Null(WireNumbers.Angle(value));

    [Theory]
    [InlineData(0.6, "0.6")]
    [InlineData(0.955, "0.96")]
    [InlineData(1.5, "1")]
    [InlineData(-1, "0")]
    public void AlphaRounding(double value, string expected) =>
        Assert.Equal(expected, WireNumbers.Alpha(value).Text);

    [Fact]
    public void SubtitleFrameMatchesExample()
    {
        var e = new SubtitleShown("Merhaba", 4000, new Box(0.25, 0.8, 0.75, 0.87499));
        var frame = TvWire.LegacyFrame(e, 1234);
        Assert.StartsWith("event: subtitle\ndata: ", frame);
        Assert.EndsWith("\n\n", frame);
        Assert.Equal("{\"at\":1234,\"box\":{\"bottom\":0.875,\"left\":0.25,\"right\":0.75,\"top\":0.8},\"duration\":4000,\"text\":\"Merhaba\"}",
            Data(frame));
        Assert.DoesNotContain("replace", frame);

        var replaced = Data(TvWire.LegacyFrame(new SubtitleShown("Selam kaptan", 4000, Replace: true), 1));
        Assert.EndsWith("\"replace\":true,\"text\":\"Selam kaptan\"}", replaced);
    }

    [Fact]
    public void LettersAreNotEscaped()
    {
        var body = Data(TvWire.LegacyFrame(new SubtitleShown("Kapıyı aç: \"şimdi\"\nلا", 1000, Paragraphs: true), 0));
        Assert.Contains("\"text\":\"Kapıyı aç: \\\"şimdi\\\"\\nلا\"", body);
        Assert.Contains("\"paragraphs\":true", body);
        Assert.DoesNotContain("\\u", body);
    }

    [Fact]
    public void ScreenFrameMatchesExample()
    {
        var e = new ScreenShown([
            new ScreenItem(new Box(0.05, 0.3, 0.2, 0.4), "Harita\nAyarlar") { Line = 0.03 },
            new ScreenItem(new Box(0.4, 0.8, 0.6, 0.84), "Kapıyı aç.") { Line = 0.04 },
        ], 12000);
        var body = Data(TvWire.LegacyFrame(e, 0));
        Assert.Contains("\"duration\":12000", body);
        Assert.Contains("{\"box\":{\"bottom\":0.4,\"left\":0.05,\"right\":0.2,\"top\":0.3},\"line\":0.03,\"paragraphs\":true,\"text\":\"Harita\\nAyarlar\"}", body);
        Assert.Contains("{\"box\":{\"bottom\":0.84,\"left\":0.4,\"right\":0.6,\"top\":0.8},\"line\":0.04,\"text\":\"Kapıyı aç.\"}", body);
        Assert.DoesNotContain("overlay", body);
    }

    [Fact]
    public void PhoneAndMapOverlayMatchesExample()
    {
        var box = new Box(0.1, 0.1, 0.2, 0.2);
        var e = new ScreenShown([
            new ScreenItem(box, "Lucia") { Fill = "#f5f5f6", Alpha = 0.6, Backdrop = true },
            new ScreenItem(box, "Keyfin yerinde mi?") { Fill = "#acccfe", Ink = "#2c2c2e", Alpha = 0.95, Side = true, Angle = 5.71 },
            new ScreenItem(box, "ÇİÇEK AL") { Card = true },
        ], 120000, Overlay: true);
        var body = Data(TvWire.LegacyFrame(e, 0));
        Assert.Contains("\"overlay\":true", body);
        Assert.Contains("\"alpha\":0.6,\"backdrop\":true,", body);
        Assert.Contains("\"fill\":\"#f5f5f6\"", body);
        Assert.Contains("\"alpha\":0.95,\"angle\":5.7,", body);
        Assert.Contains("\"ink\":\"#2c2c2e\"", body);
        Assert.Contains("\"side\":true", body);
        Assert.Contains("\"card\":true", body);
        Assert.DoesNotContain("frost", body);
    }

    [Fact]
    public void RegionFramesMatchExamples()
    {
        Assert.Equal("{\"box\":{\"bottom\":0.12,\"left\":0.7,\"right\":0.95,\"top\":0.05},\"id\":\"q\",\"line\":0.03,\"text\":\"Fenerciyi bul\"}",
            Data(TvWire.LegacyFrame(new RegionShown("q", "Fenerciyi bul", new Box(0.7, 0.05, 0.95, 0.12), 0.03), 0)));
        Assert.Equal("{\"id\":\"q\",\"text\":\"\"}", Data(TvWire.LegacyFrame(new RegionShown("q", ""), 0)));
        Assert.Equal("event: region-clear\ndata: {}\n\n", TvWire.LegacyFrame(new RegionsCleared(), 0));
        Assert.Equal("event: screen-clear\ndata: {}\n\n", TvWire.LegacyFrame(new ScreenCleared(), 0));
        Assert.Equal("event: clear\ndata: {}\n\n", TvWire.LegacyFrame(new SubtitleCleared(), 0));
        Assert.Equal("event: started\ndata: {}\n\n", TvWire.LegacyFrame(new TranslationStarted(), 0));
        Assert.Equal("event: stopped\ndata: {}\n\n", TvWire.LegacyFrame(new TranslationStopped(), 0));
    }

    [Fact]
    public void StyleMatchesExample()
    {
        var saved = new SubtitleStyle
        {
            FontSize = 58, BottomPercent = 10, Placement = SubtitlePlacement.Above, Background = 40, Bold = true,
            TextColor = SubtitleTextColor.Yellow, DisplayMode = SubtitleDisplayMode.Overlay, StackPrevious = true,
            BackgroundShape = SubtitleBackgroundShape.Band,
        };
        var body = Data(TvWire.LegacyFrame(new StyleChanged(TvStyle.From(saved)), 0));
        foreach (var part in new[] { "\"fontSize\":58", "\"bottomPercent\":10", "\"placement\":\"above\"", "\"background\":40",
                     "\"bold\":true", "\"textColor\":\"yellow\"", "\"displayMode\":\"overlay\"", "\"stackPrevious\":true",
                     "\"backgroundShape\":\"band\"", "\"autoSize\":false" })
            Assert.Contains(part, body);
        Assert.DoesNotContain("theme", body);

        var defaults = Data(TvWire.LegacyFrame(new StyleChanged(TvStyle.From(new SubtitleStyle())), 0));
        Assert.Contains("\"font\":\"condensed\"", defaults);
        Assert.Contains("\"watermark\":true", defaults);
        Assert.Contains("\"autoSize\":true", defaults);
        Assert.StartsWith("{\"autoSize\"", defaults);
    }

    [Theory]
    [InlineData(SubtitlePlacement.Cover, 40, 100)]
    [InlineData(SubtitlePlacement.Cover, 60, 60)]
    [InlineData(SubtitlePlacement.Cover, 140, 100)]
    [InlineData(SubtitlePlacement.Fixed, 40, 40)]
    [InlineData(SubtitlePlacement.Below, -5, 0)]
    public void StyleBackgroundRule(SubtitlePlacement placement, int saved, int expected) =>
        Assert.Equal(expected, TvStyle.From(new SubtitleStyle { Placement = placement, Background = saved }).Background);

    [Fact]
    public void LinkMessagesCarryIdsAndEnvelope()
    {
        var show = TvWire.LinkMessage(new SubtitleShown("Buraya gel.", 4000, Source: "Come here."), showId: 7);
        Assert.StartsWith("{\"app\":\"nino\",\"type\":\"show\",", show);
        Assert.Contains("\"id\":7", show);
        Assert.Contains("\"durationMs\":4000", show);
        Assert.Contains("\"position\":\"bottom\"", show);
        Assert.Contains("\"source\":\"Come here.\"", show);
        Assert.DoesNotContain("\"at\"", show);
        Assert.DoesNotContain("\"duration\"", show);

        Assert.Equal("{\"app\":\"nino\",\"type\":\"clear\",\"id\":7}", TvWire.LinkMessage(new SubtitleCleared(), 7));
        Assert.Equal("{\"app\":\"nino\",\"type\":\"clear\"}", TvWire.LinkMessage(new SubtitleCleared()));
        Assert.Equal("{\"app\":\"nino\",\"type\":\"stopped\"}", TvWire.LinkMessage(new TranslationStopped()));

        var screen = TvWire.LinkMessage(new ScreenShown([], 120000, true));
        Assert.Contains("\"durationMs\":120000", screen);
        Assert.Contains("\"overlay\":true", screen);
    }

    [Fact]
    public void LargeScreenIsTrimmedFromTheEnd()
    {
        var items = Enumerable.Range(0, 200)
            .Select(i => new ScreenItem(new Box(0.1, 0.1, 0.2, 0.2), $"Öğe {i} " + new string('x', 80)) { Line = 0.03 })
            .ToArray();
        var fitted = TvWire.FitScreen(new ScreenShown(items, 120000, true), out var dropped);
        Assert.True(dropped > 0);
        Assert.Equal(200 - dropped, fitted.Items.Count);
        Assert.Equal("Öğe 0 " + new string('x', 80), fitted.Items[0].Text);
        Assert.True(TvWire.ByteCount(TvWire.LinkMessage(fitted)) <= TvWire.CompactMessageBytes);

        var small = TvWire.FitScreen(new ScreenShown(items.Take(3).ToArray(), 1000), out var none);
        Assert.Equal(0, none);
        Assert.Equal(3, small.Items.Count);
    }

    [Fact]
    public void LocalEventsMatchExamples()
    {
        var output = new TvOutput();
        var seen = new List<LocalSubtitleEvent>();
        output.LocalEvent += seen.Add;
        var box = new Box(0.7, 0.05, 0.95, 0.12);

        output.Send(new SubtitleShown("Merhaba", 4000, Paragraphs: true));
        output.Send(new SubtitleCleared());
        output.Send(new ScreenShown([new ScreenItem(box, "Harita\nEnvanter"), new ScreenItem(box, "Ayrıl")], 12000));
        output.Send(new ScreenCleared());
        output.Send(new ScreenShown([new ScreenItem(box, "Lucia")], 120000, Overlay: true));
        output.Send(new RegionShown("q", "Fenerciyi bul", box, 0.03));
        output.Send(new RegionShown("q", ""));
        output.Send(new RegionsCleared());
        output.Send(new StyleChanged(new TvStyle()));
        output.Send(new TranslationStarted());

        Assert.Equal(
        [
            new LocalSubtitleEvent(LocalEventKind.Subtitle, "Merhaba", 4000, Paragraphs: true),
            new LocalSubtitleEvent(LocalEventKind.Clear),
            new LocalSubtitleEvent(LocalEventKind.Screen, "Harita\nEnvanter\nAyrıl", 12000, Paragraphs: true),
            new LocalSubtitleEvent(LocalEventKind.ScreenClear),
            new LocalSubtitleEvent(LocalEventKind.Region, "Fenerciyi bul", RegionId: "q", Box: box),
            new LocalSubtitleEvent(LocalEventKind.Region, "", RegionId: "q"),
            new LocalSubtitleEvent(LocalEventKind.RegionClear),
        ], seen.Where(e => e.Kind != LocalEventKind.Overlay));
        var overlay = Assert.Single(seen, e => e.Kind == LocalEventKind.Overlay);
        Assert.Equal(120000, overlay.DurationMs);
        Assert.Equal("", overlay.Text);
        Assert.Equal("Lucia", Assert.Single(overlay.Items!).Text);
    }

    [Fact]
    public void LocalOverlayKeepsItemFlagsAndSubtitleKeepsBox()
    {
        var box = new Box(0.2, 0.86, 0.8, 0.92);
        var items = new[]
        {
            new ScreenItem(new Box(0.3, 0.2, 0.57, 0.85), "Lucia") { Fill = "#f5f5f6", Alpha = 0.6, Backdrop = true },
            new ScreenItem(new Box(0.31, 0.5, 0.45, 0.53), "Motoru tamir ettin mi?")
                { Fill = "#acccfe", Ink = "#2c2c2e", Alpha = 0.95, Side = true },
            new ScreenItem(new Box(0.55, 0.6, 0.8, 0.7), "ÇİÇEK AL") { Card = true },
        };
        var overlay = TvWire.Local(new ScreenShown(items, 120000, Overlay: true))!;
        Assert.Equal(LocalEventKind.Overlay, overlay.Kind);
        Assert.Equal(3, overlay.Items!.Count);
        Assert.True(overlay.Items[0].Backdrop);
        Assert.Equal("#2c2c2e", overlay.Items[1].Ink);
        Assert.True(overlay.Items[1].Side);
        Assert.True(overlay.Items[2].Card);
        Assert.Null(TvWire.Local(new ScreenShown(items, 12000))!.Items);
        Assert.Equal(box, TvWire.Local(new SubtitleShown("Merhaba", 4000, box))!.Box);
    }

    [Theory]
    [InlineData("model=Samsung%20QE65Q80C", "Samsung QE65Q80C")]
    [InlineData("model=LG+OLED55<C1>", "LG OLED55C1")]
    [InlineData("model=%20%20", null)]
    [InlineData("app=1&model=%E0", "E0")]
    [InlineData("modelx=A", null)]
    [InlineData("", null)]
    public void ModelQuery(string query, string? expected) =>
        Assert.Equal(expected, LegacySubtitleServer.ParseModel(query));

    [Fact]
    public void LongModelIsCut() =>
        Assert.Equal(60, LegacySubtitleServer.ParseModel("model=" + new string('A', 80))!.Length);

    [Fact]
    public void WebSocketAcceptMatchesRfc() =>
        Assert.Equal("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", HttpWire.WebSocketAccept("dGhlIHNhbXBsZSBub25jZQ=="));

    [Theory]
    [InlineData("192.168.1.5", true)]
    [InlineData("10.0.0.1", true)]
    [InlineData("172.16.0.1", true)]
    [InlineData("172.31.255.1", true)]
    [InlineData("172.32.0.1", false)]
    [InlineData("169.254.3.3", true)]
    [InlineData("127.0.0.1", true)]
    [InlineData("8.8.8.8", false)]
    [InlineData("::1", true)]
    [InlineData("::ffff:192.168.0.2", true)]
    [InlineData("2001:db8::1", false)]
    public void IngressAddressFilter(string address, bool allowed) =>
        Assert.Equal(allowed, HttpWire.IsPrivateOrLocal(System.Net.IPAddress.Parse(address)));

    [Fact]
    public void LaunchParametersCarryBothAddresses()
    {
        var output = new TvOutput();
        Assert.Equal("{\"server\":\"http://192.168.1.34:8787\"}", output.LaunchParameters("192.168.1.34"));
        Assert.Equal("http://127.0.0.1:8787", output.ServerAddress(null));
        Assert.Equal("ws://192.168.1.34:47800/nino/ws", output.LinkAddress("192.168.1.34"));
        Assert.Equal(("http://localhost:8787/obs", (string?)"http://192.168.1.34:8787/obs"), output.ObsAddresses("192.168.1.34"));
        Assert.Null(output.ObsAddresses(null).Network);
    }

    [Fact]
    public void TvInfoRecognisesSenders()
    {
        Assert.True(LinkTvLocator.IsTvInfo("{\"app\":\"nino\",\"type\":\"info\",\"version\":1,\"name\":\"Salon\"}"));
        Assert.False(LinkTvLocator.IsTvInfo("{\"app\":\"nino\",\"type\":\"info\",\"role\":\"sender\"}"));
        Assert.False(LinkTvLocator.IsTvInfo("{\"app\":\"other\"}"));
        Assert.False(LinkTvLocator.IsTvInfo("<html>"));
    }
}
