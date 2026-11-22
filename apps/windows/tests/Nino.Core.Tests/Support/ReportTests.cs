// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.Json;
using Nino.Core.Health;
using Nino.Core.Support;
using Nino.Core.Tv;

namespace Nino.Core.Tests.Support;

public sealed class ReportBodyTests
{
    static ReportBody Body() => new()
    {
        Install = "install-1234", App = "  4.0.1-beta.2  ", Language = "tr", Text = "  Çeviri geç geliyor  ",
    };

    [Fact]
    public void Json_Fields()
    {
        var json = Body() with
        {
            Contact = "  ", Log = "", Device = " app: 1 ", Images = [SupportImage.Jpeg([0xfb, 0xff]), SupportImage.Jpeg([])],
        };
        var text = json.ToJsonText();
        using var doc = JsonDocument.Parse(text);
        var r = doc.RootElement;
        Assert.Equal(1, r.GetProperty("v").GetInt32());
        Assert.Equal("windows", r.GetProperty("platform").GetString());
        Assert.Equal("4.0.1-beta.2", r.GetProperty("app").GetString());
        Assert.Equal("Çeviri geç geliyor", r.GetProperty("text").GetString());
        Assert.False(r.TryGetProperty("contact", out _));
        Assert.False(r.TryGetProperty("log", out _));
        Assert.False(r.TryGetProperty("kind", out _));
        Assert.Equal("app: 1", r.GetProperty("device").GetString());
        Assert.Equal(1, r.GetProperty("images").GetArrayLength());
        Assert.Contains("\"data\":\"+/8=\"", text);
        Assert.Contains("Çeviri", text);
        Assert.Equal(0, JsonDocument.Parse((Body() with { Device = "" }).ToJsonText()).RootElement
            .GetProperty("images").GetArrayLength());
    }

    [Fact]
    public void Limits_AndSize()
    {
        var photo = new byte[900 * 1024];
        new Random(1).NextBytes(photo);
        var body = Body() with
        {
            Text = new string('ş', 5000),
            Contact = new string('c', 300),
            Log = "baş" + new string('ع', 60_000),
            Images = [SupportImage.Jpeg(photo), SupportImage.Jpeg(photo), SupportImage.Jpeg(photo), SupportImage.Jpeg(photo)],
            Device = new string('d', 700),
        };
        var bytes = body.ToJson();
        Assert.True(bytes.Length <= SupportLimits.ReportBodyBytes, bytes.Length.ToString());
        using var doc = JsonDocument.Parse(bytes);
        var r = doc.RootElement;
        Assert.Equal(4000, r.GetProperty("text").GetString()!.Length);
        Assert.Equal(200, r.GetProperty("contact").GetString()!.Length);
        Assert.Equal(60_000, r.GetProperty("log").GetString()!.Length);
        Assert.DoesNotContain("baş", r.GetProperty("log").GetString());
        Assert.Equal(3, r.GetProperty("images").GetArrayLength());
        Assert.Equal(600, r.GetProperty("device").GetString()!.Length);
    }

    [Fact]
    public void Parse_RoundTrip()
    {
        var body = Body() with { Kind = "auto", Images = [SupportImage.Jpeg([1, 2])], Device = "x" };
        using var doc = JsonDocument.Parse(body.ToJson());
        var back = ReportBody.Parse(doc.RootElement)!;
        Assert.Equal(body.ToJsonText(), back.ToJsonText());
    }

    [Fact]
    public void Utf16Cut_NoHalfCharacter()
    {
        var emoji = string.Concat(Enumerable.Repeat("😀", 3000));
        var text = SupportLimits.Head(emoji, 4000);
        Assert.True(text.Length <= 4000);
        Assert.False(char.IsHighSurrogate(text[^1]));
        Assert.Equal(3999, SupportLimits.Head("a" + emoji, 4000).Length);
    }
}

public sealed class ReportTextTests
{
    static readonly DateTimeOffset Now = new(2026, 11, 22, 21, 0, 0, TimeSpan.Zero);
    static readonly string[] Summary = ["ağ: ethernet, bu oturumda 2 kopma"];

    [Fact]
    public void SendProblems_WithCauseAndRecent()
    {
        var problems = new[]
        {
            new ProblemRecord { Date = Now.AddDays(-4), Kind = ProblemKind.TvDropped },
            new ProblemRecord { Date = Now.AddHours(-1), Kind = ProblemKind.NetworkLost, Network = "offline" },
        };
        var text = ReportText.Build(false, "  ", "TV uyku kipinde", problems, Summary, Now, TimeZoneInfo.Utc);
        Assert.StartsWith(ReportText.SendProblemsHeader + "\n\n" + ReportText.FindingsTitle + "\nMuhtemel sebep: TV uyku kipinde\nYakın zamandaki sorunlar:\n• ", text);
        Assert.Contains(problems[1].TurkishName, text);
        Assert.DoesNotContain(problems[0].TurkishName, text);
        Assert.EndsWith("\n" + Summary[0], text);
    }

    [Fact]
    public void UserText_FirstAndAutoHeader()
    {
        Assert.StartsWith("Çeviri geç geliyor\n\n" + ReportText.FindingsTitle,
            ReportText.Build(false, " Çeviri geç geliyor ", null, [], Summary, Now, TimeZoneInfo.Utc));
        var auto = ReportText.Build(true, "yok sayılır", null, [], [], Now, TimeZoneInfo.Utc);
        Assert.Equal(ReportText.AutoHeader + "\n\n" + ReportText.FindingsTitle, auto);
    }

    [Fact]
    public void AtMost12Problems_And4000()
    {
        var problems = Enumerable.Range(0, 20)
            .Select(i => new ProblemRecord { Date = Now.AddMinutes(-i), Kind = ProblemKind.TvDropped }).ToList();
        var text = ReportText.Build(false, null, null, problems, [], Now, TimeZoneInfo.Utc);
        Assert.Equal(12, text.Split('\n').Count(l => l.StartsWith("• ")));
        var emoji = ReportText.Build(false, string.Concat(Enumerable.Repeat("😀", 3000)), null, [], Summary, Now,
            TimeZoneInfo.Utc);
        Assert.True(emoji.Length <= 4000);
        Assert.False(char.IsHighSurrogate(emoji[^1]));
    }
}

public sealed class ReportClientTests
{
    static readonly Uri Root = new("https://pool.example/");

    static ReportBody Body() => new() { Install = "install-1234", App = "1.0", Language = "tr", Text = "t" };

    [Fact]
    public async Task Sent_ReadsId_AndHeaders()
    {
        var handler = StubHandler.Json(HttpStatusCode.OK, """{"ok":true,"id":"r-1"}""");
        var client = new ReportClient(new HttpClient(handler), Root);
        var result = await client.SendAsync(Body());
        Assert.Equal(ReportStatus.Sent, result.Status);
        Assert.Equal("r-1", result.Id);
        var (request, body) = handler.Requests.Single();
        Assert.Equal("https://pool.example/v1/reports", request.RequestUri!.ToString());
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("application/json; charset=utf-8", request.Content!.Headers.ContentType!.ToString());
        Assert.Empty(request.Headers.UserAgent);
        Assert.Contains("\"install\":\"install-1234\"", body);
    }

    [Theory]
    [InlineData(429, ReportStatus.Limited)]
    [InlineData(413, ReportStatus.TooLarge)]
    [InlineData(400, ReportStatus.Rejected)]
    [InlineData(500, ReportStatus.Failed)]
    [InlineData(503, ReportStatus.Failed)]
    public async Task StatusMapping(int code, ReportStatus expected)
    {
        var handler = new StubHandler((_, _) =>
        {
            var r = new HttpResponseMessage((HttpStatusCode)code) { Content = new StringContent("{}") };
            r.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(90));
            return r;
        });
        var result = await new ReportClient(new HttpClient(handler), Root).SendAsync(Body());
        Assert.Equal(expected, result.Status);
        if (expected == ReportStatus.Limited) Assert.Equal(TimeSpan.FromSeconds(90), result.RetryAfter);
    }

    [Fact]
    public async Task Offline_AndNoRoot_Fail()
    {
        Assert.Equal(ReportStatus.Failed, (await new ReportClient(new HttpClient(new OfflineHandler()), Root).SendAsync(Body())).Status);
        Assert.Equal(ReportStatus.Failed, (await new ReportClient(new HttpClient(new OfflineHandler()), null).SendAsync(Body())).Status);
        using var cts = new CancellationTokenSource();
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new ReportClient(new HttpClient(StubHandler.Json(HttpStatusCode.OK, "{}")), Root).SendAsync(Body(), cts.Token));
    }

    [FactWithoutEnvironment("NINO_POOL_URL")]
    public void RootFromDataFolder()
    {
        using var temp = new Nino.Core.Tests.Data.TempFolder();
        Directory.CreateDirectory(temp.File("pool"));
        File.WriteAllText(temp.File("pool", "endpoint.txt"), " http://127.0.0.1:9/ ");
        Assert.Equal("http://127.0.0.1:9/v1/assistant",
            SupportEndpoints.For(SupportEndpoints.RootFromDataFolder(temp.Path), SupportEndpoints.Assistant)!.ToString());
        File.WriteAllText(temp.File("pool", "endpoint.txt"), "ftp://x");
        Assert.Equal("https://nino-pool.y-demirbag2506.workers.dev/v1/reports",
            SupportEndpoints.For(SupportEndpoints.RootFromDataFolder(temp.Path), SupportEndpoints.Reports)!.ToString());
    }
}

public sealed class DeviceLinesTests
{
    [Fact]
    public void Tv()
    {
        Assert.Equal("LG webOS · uygulama 4.1.2 · bağlantı var", DeviceLines.Tv(TvBrand.Lg, null, "4.1.2", null, true));
        Assert.Equal("Samsung Tizen · Samsung QN55S90D · bağlantı var",
            DeviceLines.Tv(TvBrand.Samsung, "Samsung QN55S90D", null, null, true));
        Assert.Equal("Android TV · uygulama 4.0.1-beta.2 · bağlantı var",
            DeviceLines.Tv(TvBrand.AndroidTv, null, " 4.0.1-beta.2 ", null, true));
        Assert.Equal("LG webOS · bağlantı yok", DeviceLines.Tv(TvBrand.Lg, null, "10.0.0.42 | y", null, false));
        Assert.Equal("LG webOS · uygulama 1.2 · bağlantı yok", DeviceLines.Tv(TvBrand.Lg, "", null, "1.2", false));
        Assert.Null(DeviceLines.Tv(null, "x", "1", null, true));
    }

    [Theory]
    [InlineData("XboxSeriesX", "Xbox Series X")]
    [InlineData("XboxOne", "Xbox One")]
    [InlineData("Xbox", "Xbox")]
    [InlineData("Salon konsolu", "Xbox")]
    [InlineData("", "Xbox")]
    [InlineData(null, "Xbox")]
    public void XboxModel(string? value, string expected) => Assert.Equal(expected, DeviceLines.XboxModel(value));

    [Fact]
    public void Console()
    {
        Assert.Equal("HDMI kartı", DeviceLines.Console(ConsoleRoute.CaptureCard));
        Assert.Equal("Xbox · pencereden okuma", DeviceLines.Console(ConsoleRoute.GameWindow, Nino.Core.Settings.GameConsole.Xbox));
        Assert.Equal("PS5 · pencereden okuma", DeviceLines.Console(ConsoleRoute.GameWindow));
        Assert.Equal("Xbox Series X · uzaktan oynatma", DeviceLines.Console(ConsoleRoute.XboxStream, xboxModel: "XboxSeriesX"));
        Assert.Equal("PS5 · Remote Play uygulamasından (chiaki-ng)",
            DeviceLines.Console(ConsoleRoute.RemotePlayWindow, remotePlayApp: Nino.Core.Settings.RemotePlayApp.Chiaki));
        Assert.Equal("PS5 · Remote Play uygulamasından", DeviceLines.Console(ConsoleRoute.RemotePlayWindow));
        Assert.Equal("kullanıcının seçtiği pencere", DeviceLines.Console(ConsoleRoute.ChosenWindow));
        Assert.Equal("PS5 · Remote Play", DeviceLines.Console(ConsoleRoute.Ps5RemotePlay));
    }

    [Fact]
    public void Status()
    {
        Assert.StartsWith("çeviri durdu, PS5: Connecting,",
            DeviceLines.StatusForStream(false, "PS5", "Connecting", null, null, null, null));
        Assert.StartsWith("çeviri sürüyor, PS5: Disconnected (Timeout 0x8001a2c3)",
            DeviceLines.StatusForStream(true, "PS5", "Disconnected", "Timeout", "0x8001a2c3", null, null));
        Assert.Equal("çeviri sürüyor, PS5: Disconnected (Unreachable), oyun: bilinmiyor",
            DeviceLines.StatusForStream(true, "PS5", "Disconnected", "Unreachable", "10.0.0.8", null, null));
        Assert.Equal("çeviri sürüyor, PS5: Connecting, en son kopuş: NetworkLost, oyun: Lantern Coast",
            DeviceLines.StatusForStream(true, "PS5", "Connecting", null, null, "NetworkLost", "Lantern Coast"));
        Assert.DoesNotContain("son kopuş",
            DeviceLines.StatusForStream(true, "PS5", "Connecting", null, null, "PS5-321 10.0.0.77", null));
        Assert.StartsWith("çeviri sürüyor, pencere: Searching", DeviceLines.StatusForWindow(true, "Searching", null, null));
        Assert.StartsWith("çeviri sürüyor, kart: Waiting", DeviceLines.StatusForCard(true, "Waiting", null, null));
        Assert.StartsWith("çeviri sürüyor, Xbox: Disconnected (Busy)",
            DeviceLines.StatusForStream(true, "Xbox", "Disconnected", "Busy", null, null, null));
    }

    [Fact]
    public void Lines_OrderAndSummary_NoPrivateData()
    {
        var lines = DeviceLines.Lines("0.1.0", "ACER N22C5", "Windows 11 (22631)", null, "PS5 · Remote Play",
            DeviceLines.StatusForStream(true, "PS5", "Disconnected", "Unreachable", "10.0.0.42", null, null));
        Assert.Equal(["app", "device", "system", "console", "status"], lines.Select(l => l.Id));
        var summary = Nino.Core.Data.DeviceInfo.Summary(lines);
        Assert.StartsWith("app: 0.1.0 | device: ACER N22C5 | system: Windows 11 (22631) | console: ", summary);
        Assert.DoesNotContain("10.0.0", summary);
    }
}

public sealed class PhotoFitTests
{
    sealed class FakeEncoder(int width, int height, Func<int, int, int, int> size) : IJpegEncoder
    {
        public readonly List<(int W, int H, int Q)> Tries = [];
        public int Width => width;
        public int Height => height;

        public byte[]? Encode(int w, int h, int quality)
        {
            Tries.Add((w, h, quality));
            return new byte[size(w, h, quality)];
        }
    }

    [Theory]
    [InlineData(3840, 2160, 1600, 900)]
    [InlineData(1080, 2400, 720, 1600)]
    [InlineData(800, 600, 800, 600)]
    public void FitSize(int w, int h, int ew, int eh) => Assert.Equal((ew, eh), PhotoFit.FitSize(w, h, 1600));

    [Fact]
    public void Order_QualityThenSize()
    {
        var enc = new FakeEncoder(3840, 2160, (w, _, q) => w * q * 10);
        var bytes = PhotoFit.Fit(enc, 600_000);
        Assert.NotNull(bytes);
        Assert.Equal([(1600, 900, 70), (1600, 900, 55), (1600, 900, 40), (1280, 720, 70), (1280, 720, 55), (1280, 720, 40)], enc.Tries);
        Assert.Null(PhotoFit.Fit(new FakeEncoder(3840, 2160, (_, _, _) => 10_000_000), SupportLimits.ReportPhotoBytes));
    }

    [Fact]
    public void Extensions()
    {
        Assert.True(PhotoFit.IsImageFile(@"C:\a\b.HEIC"));
        Assert.False(PhotoFit.IsImageFile("a.txt"));
        Assert.Equal("*.png;*.jpg;*.jpeg;*.heic;*.heif;*.webp;*.bmp;*.gif;*.tif;*.tiff", PhotoFit.FilterPattern);
    }
}
