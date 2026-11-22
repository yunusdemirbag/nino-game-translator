// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Core.Tests.Link;
using static Nino.Core.Tests.Compat.CompatFixtures;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// 8787 sunucusunun kablo baytları eski uygulamanınkiyle aynı mı. Fikstürler eski sunucunun aynı olay dizisi için
/// gönderdiği baytlardır; değişken tek alan <c>at</c> (gönderme anı) fikstürde 0'a çevrildi, burada da saat Unix
/// başlangıcında durur.
/// </summary>
public class LegacyWireCompatTests
{
    const string Get = "GET {0} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n";

    /// <summary>Kaçış ayrımı için zor metin: tırnak, ters bölü, denetim karakterleri, ayraçlar, emoji, Türkçe, Arapça.</summary>
    public const string Tricky = "Tırnak \" ters\\bölü\nyeni satır\ttab \u001b esc \u007f del \u00a0nbsp \u2028ls \u2029ps 😀 <b>&+' ğüşıöçİ مرحبا";

    static TvStyle Style(int fontSize, int bottom, SubtitlePlacement placement, int background, bool bold, SubtitleTextColor color,
        SubtitleDisplayMode mode, bool stack, SubtitleBackgroundShape shape, SubtitleFont font, bool watermark, bool? autoSize) =>
        TvStyle.From(new SubtitleStyle
        {
            FontSize = fontSize, BottomPercent = bottom, Placement = placement, Background = background, Bold = bold, TextColor = color,
            DisplayMode = mode, StackPrevious = stack, BackgroundShape = shape, Font = font, Watermark = watermark, AutoSize = autoSize,
        });

    static TvStyle StyleA() => Style(46, 12, SubtitlePlacement.Cover, 40, true, SubtitleTextColor.Yellow, SubtitleDisplayMode.Overlay,
        false, SubtitleBackgroundShape.Band, SubtitleFont.Rounded, false, null);

    static TvStyle StyleB() => Style(58, 3, SubtitlePlacement.Fixed, 150, false, SubtitleTextColor.White, SubtitleDisplayMode.InApp,
        true, SubtitleBackgroundShape.Fit, SubtitleFont.System, true, null);

    static TvStyle StyleC() => Style(36, 7, SubtitlePlacement.Above, -5, false, SubtitleTextColor.White, SubtitleDisplayMode.InApp,
        true, SubtitleBackgroundShape.Fit, SubtitleFont.Modern, true, false);

    // Eski uygulamada satır yüksekliği her öğede vardı; yeni uygulama da her öğe için verir.
    static ScreenItem[] Items() =>
    [
        new(new Box(0.12345, 0.0, 0.87505, 1.2), "Birinci\nikinci " + Tricky)
        {
            Line = 0.044449, Plain = true, Italic = true, Fill = "#e9e9ec", Ink = "#101010", Angle = 1.25, Alpha = 0.285, Side = true,
            Backdrop = true, Card = true,
        },
        new(new Box(-0.1, 0.33335, 0.5, 0.66665), "İki") { Line = 0.00005, Angle = 0.29, Alpha = 0.005 },
        new(new Box(0.1, 0.2, 0.3, 0.4), "Üç") { Line = 0.05, Angle = -0.35, Alpha = 1.5, Fill = "" },
        new(new Box(0.1, 0.2, 0.3, 0.4), "Dört") { Line = 0.05, Angle = 0.3, Alpha = 0.125 },
        new(new Box(0.1, 0.2, 0.3, 0.4), "Beş") { Line = 0.05, Angle = -0.25, Alpha = 0.995 },
        new(new Box(0.1, 0.2, 0.3, 0.4), "Altı") { Line = 0.05, Angle = 2.45, Alpha = 0.0 },
    ];

    /// <summary>Ham bağlantı: gelen bütün baytlar.</summary>
    sealed class Raw : IDisposable
    {
        readonly TcpClient tcp = new();
        readonly MemoryStream all = new();
        Task? pump;

        public static async Task<Raw> OpenAsync(int port, string request)
        {
            var r = new Raw();
            await r.tcp.ConnectAsync(IPAddress.Loopback, port);
            await r.tcp.GetStream().WriteAsync(Encoding.ASCII.GetBytes(request));
            r.pump = r.PumpAsync();
            return r;
        }

        async Task PumpAsync()
        {
            var buffer = new byte[65536];
            try
            {
                int n;
                while ((n = await tcp.GetStream().ReadAsync(buffer)) > 0)
                    lock (all) all.Write(buffer, 0, n);
            }
            catch (Exception) { }
        }

        public byte[] Bytes
        {
            get { lock (all) return all.ToArray(); }
        }

        public string Text => Encoding.UTF8.GetString(Bytes);

        public async Task WaitCountAsync(string fragment, int count)
        {
            var until = DateTime.UtcNow + LinkTestKit.Wait;
            while (DateTime.UtcNow < until)
            {
                var text = Text;
                int n = 0, i = 0;
                while ((i = text.IndexOf(fragment, i, StringComparison.Ordinal)) >= 0)
                {
                    n++;
                    i += fragment.Length;
                }
                if (n >= count) return;
                await Task.Delay(5);
            }
            throw new TimeoutException($"{fragment} ×{count} gelmedi: {Text}");
        }

        public Task ClosedAsync() => pump!.WaitAsync(LinkTestKit.Wait);

        public void Dispose() => tcp.Dispose();
    }

    [Fact]
    public async Task EveryEventMatchesOldBytes()
    {
        var clock = new ManualClock(DateTimeOffset.UnixEpoch);
        using var server = new LegacySubtitleServer(clock);
        var port = server.Start(0);
        string? model = null;
        server.ModelReported += m => model = m;

        using var tv = await Raw.OpenAsync(port, string.Format(Get, "/events?model=Samsung%20QE65+Q80C%3Cx%3E%F0%9F%98%80"));
        await tv.WaitCountAsync("retry: 2000\n\n", 1);
        var frames = 0;
        async Task Step(TvEvent e)
        {
            server.Send(e);
            frames++;
            await tv.WaitCountAsync("\n\n", frames + 1);
        }

        await Step(new StyleChanged(StyleA()));
        await Step(new StyleChanged(StyleB()));
        await Step(new StyleChanged(StyleC()));
        await Step(new SubtitleShown("Merhaba dünya"));
        await Step(new SubtitleShown(Tricky, 4200, new Box(0.12345, 0.62, 0.87505, 0.97), Paragraphs: true, Replace: true));
        await Step(new SubtitleShown("Kutu sınırda", 0, new Box(-0.5, 0.000049, 1.00001, 0.99995)));
        await Step(new SubtitleCleared());
        await Step(new TranslationStarted());
        await Step(new ScreenShown(Items(), 9000));
        await Step(new ScreenShown([Items()[1]], 3000, Overlay: true));
        await Step(new ScreenShown([], 1000));
        await Step(new ScreenCleared());
        await Step(new RegionShown("area1", "Görev: \"Kasaya\" git", new Box(0.7, 0.05, 0.98, 0.25), 0.03125));
        await Step(new RegionShown("area2", ""));
        await Step(new RegionsCleared());
        await Step(new StyleChanged(StyleA()));
        SameBytes(OldBytes("sse", "tv-all-events.bin"), tv.Bytes, "bütün olaylar");
        Assert.Equal(OldText("sse", "tv-all-events.model.txt"), model);

        // Geç bağlanan TV: açılışta son stil ve (20 sn içinde) started.
        using var late = await Raw.OpenAsync(port, string.Format(Get, "/events"));
        await late.WaitCountAsync("event: started", 1);
        await Task.Delay(100);
        SameBytes(OldBytes("sse", "tv-late-join.bin"), late.Bytes, "geç bağlanan TV");

        // OBS izleyicisi: son stil, started yok.
        using var obs = await Raw.OpenAsync(port, string.Format(Get, "/events?viewer=obs"));
        await obs.WaitCountAsync("event: style", 1);
        await Task.Delay(150);
        SameBytes(OldBytes("sse", "obs-join.bin"), obs.Bytes, "OBS açılışı");

        // Kapı kapalı: TV yalnız started alır, OBS hepsini.
        server.SubtitlesOnTv = false;
        int lateLength = late.Bytes.Length, obsLength = obs.Bytes.Length;
        server.Send(new SubtitleShown("Yalnız OBS görür", 2000));
        server.Send(new RegionShown("area1", "x"));
        server.Send(new SubtitleCleared());
        server.Send(new StyleChanged(StyleC()));
        server.Send(new TranslationStarted());
        await late.WaitCountAsync("event: started", 2);
        await obs.WaitCountAsync("event: started", 1);
        await Task.Delay(150);
        SameBytes(OldBytes("sse", "gate-tv.bin"), late.Bytes[lateLength..], "kapı kapalı: TV");
        SameBytes(OldBytes("sse", "gate-obs.bin"), obs.Bytes[obsLength..], "kapı kapalı: OBS");
    }

    [Theory]
    [InlineData("hello", "GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")]
    [InlineData("notfound", "GET /nope HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")]
    [InlineData("options", "OPTIONS /events HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")]
    [InlineData("post-events", "POST /events HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n")]
    public async Task OneShotAnswersMatchOldBytes(string name, string request)
    {
        using var server = new LegacySubtitleServer();
        var port = server.Start(0);
        using var r = await Raw.OpenAsync(port, request);
        await r.ClosedAsync();
        SameBytes(OldBytes("sse", name + ".bin"), r.Bytes, name);
    }

    [Fact]
    public async Task ObsPageHeadMatchesOld()
    {
        using var server = new LegacySubtitleServer();
        var port = server.Start(0);
        using var r = await Raw.OpenAsync(port, string.Format(Get, "/obs"));
        await r.ClosedAsync();
        var bytes = r.Bytes;
        var text = Encoding.ASCII.GetString(bytes);
        var split = text.IndexOf("\r\n\r\n", StringComparison.Ordinal) + 4;
        var body = bytes[split..];
        // Başlıklar eskisiyle aynı (yalnız uzunluk sayfaya göre değişir); sayfanın kendisi yeni uygulamanın sayfasıdır.
        var oldHead = OldText("sse", "obs-head.txt");
        Assert.Equal(System.Text.RegularExpressions.Regex.Replace(oldHead, "Content-Length: \\d+", "Content-Length: " + body.Length),
            text[..split]);
        var oldBody = OldText("sse", "obs-body.sha256.txt").Split(' ');
        Assert.True(body.Length > 1000, "OBS sayfası boş");
        _ = oldBody; // eski sayfanın özeti yalnız kayıt için (sayfa yeniden yazıldı, aynı olması beklenmez)
        _ = SHA256.HashData(body);
    }

    [Fact]
    public async Task PingFrameMatchesOld()
    {
        using var server = new LegacySubtitleServer(pingInterval: TimeSpan.FromMilliseconds(150));
        var port = server.Start(0);
        using var r = await Raw.OpenAsync(port, string.Format(Get, "/events"));
        await r.WaitCountAsync("event: ping", 1);
        var text = r.Text;
        var start = text.IndexOf(": ping", StringComparison.Ordinal);
        var end = text.IndexOf("event: ping\ndata: {}\n\n", StringComparison.Ordinal) + 22;
        SameText(OldText("sse", "ping.txt"), text[start..end], "ping");
    }
}
