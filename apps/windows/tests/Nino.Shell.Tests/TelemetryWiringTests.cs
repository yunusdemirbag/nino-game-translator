// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO.Compression;
using System.Text.Json.Nodes;
using Nino.Core.Library;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Core.Telemetry;
using Nino.Core.Tv;
using Nino.RemotePlay;

namespace Nino.Shell.Tests;

/// <summary>Gövdeleri açıp saklayan sahte ölçüm göndericisi (ağ yok).</summary>
sealed class FakeTelemetrySender : ITelemetrySender
{
    public readonly List<JsonObject> Bodies = [];
    public int Status = 200;
    public string? Answer;

    public Task<TelemetryResponse> SendAsync(ReadOnlyMemory<byte> body, bool gzipped, CancellationToken cancellationToken)
    {
        using var input = new MemoryStream(body.ToArray());
        using var gzip = new GZipStream(input, CompressionMode.Decompress);
        lock (Bodies) Bodies.Add((JsonObject)JsonNode.Parse(gzip)!);
        return Task.FromResult(new TelemetryResponse(Status, null, Answer ?? """{"ok":true,"accepted":1,"dropped":0}"""));
    }

    public List<JsonObject> Events
    {
        get
        {
            lock (Bodies) return Bodies.SelectMany(b => b["events"]!.AsArray()).Cast<JsonObject>().ToList();
        }
    }

    public IEnumerable<JsonObject> Of(string kind) => Events.Where(e => (string?)e["k"] == kind);
}

/// <summary>Ölçüm saati elle ilerletilen zamanlayıcıyı izler.</summary>
sealed class TimersClock(ManualTimers timers) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => timers.Now;
}

public sealed class TelemetryWiringTests : IDisposable
{
    const string Install = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f";
    readonly string _data = Directory.CreateTempSubdirectory("nino-telemetry-").FullName;
    readonly FakeTelemetrySender _sender = new();

    public void Dispose()
    {
        try { Directory.Delete(_data, recursive: true); } catch (IOException) { }
    }

    string Marker => Path.Combine(_data, "telemetry", CrashMarker.FileName);

    NinoController Open(World w, string? install = Install) =>
        new(w.Services, w.Secrets, w.SettingsStore, w.Sleep, w.Text, a => a(), new ShellOptions
        {
            Timers = w.Timers,
            Logs = w.Logs,
            Browser = w.Browser,
            LogicalProcessors = 8,
            ProblemDelay = (_, ct) => Task.Delay(Timeout.Infinite, ct),
            Telemetry = new TelemetrySetup
            {
                DataFolder = _data,
                Platform = "windows",
                Os = TelemetryContext.WindowsOs(10, 0, 26100),
                Device = "LENOVO 21AH",
                Channel = TelemetryChannel.Dev,
                Sender = _sender,
                Install = install,
                Clock = new TimersClock(w.Timers),
                RunLoop = false,
            },
        });

    static World Ready()
    {
        var w = new World(new AppSettings { Output = SubtitleOutput.Tv }).WithPs5().WithTv();
        w.Services.Model.Installed = true;
        return w;
    }

    async Task Flush(NinoController c) => Assert.NotEqual(FlushOutcome.Skipped, await c.Telemetry!.Client.FlushAsync(ignoreBackoff: true));

    [Fact]
    public async Task LaunchCtxAndCleanExit()
    {
        var w = new World().WithTv();
        var c = Open(w);
        Assert.True(File.Exists(Marker));
        await Flush(c);
        var body = Assert.Single(_sender.Bodies);
        Assert.Equal(1, (int)body["v"]!);
        Assert.Equal(Install, (string?)body["install"]);
        Assert.True(Guid.TryParse((string?)body["batch"], out _));
        var ctx = body["ctx"]!.AsObject();
        Assert.Equal("windows", (string?)ctx["platform"]);
        Assert.Equal("0.0.0", (string?)ctx["app"]);
        Assert.Equal("Windows 11 26100", (string?)ctx["os"]);
        Assert.Equal("LENOVO 21AH", (string?)ctx["device"]);
        Assert.Equal("lg", (string?)ctx["tv"]);
        Assert.Equal("dev", (string?)ctx["channel"]);
        Assert.Equal(["launch"], _sender.Events.Select(e => (string?)e["k"]));

        await c.DisposeAsync();
        Assert.False(File.Exists(Marker));
    }

    [Fact]
    public async Task PreviousRunCrashedIsReportedWithCrashedVersion()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Marker)!);
        File.WriteAllText(Marker, """{"ver":"0.9.1","start":1763300000,"seen":1763300090,"code":"System.NullReferenceException","where":"NinoController.OnFrame"}""");
        var c = Open(new World());
        await Flush(c);
        var crash = Assert.Single(_sender.Of("crash"));
        Assert.Equal("0.9.1", (string?)crash["ver"]);
        Assert.Equal("System.NullReferenceException", (string?)crash["code"]);
        Assert.Equal("NinoController.OnFrame", (string?)crash["where"]);
        Assert.Equal(90, (long)crash["up"]!);
        Assert.Equal(["crash", "launch"], _sender.Events.Select(e => (string?)e["k"]));
    }

    [Fact]
    public async Task CrashAtRuntimeWritesOnlyTheClassToTheMarker()
    {
        var c = Open(new World());
        try { throw new InvalidOperationException("C:\\Users\\yunus\\gizli yol"); }
        catch (InvalidOperationException e) { c.Telemetry!.RecordCrash(e); }
        var text = File.ReadAllText(Marker);
        Assert.Contains("System.InvalidOperationException", text);
        Assert.DoesNotContain("yunus", text);
        Assert.DoesNotContain("gizli", text);
        await Task.CompletedTask;
    }

    [Fact]
    public async Task SessionPs5ConnectDropAndTimings()
    {
        var w = Ready();
        var c = Open(w);
        await c.StartAsync();
        var src = w.Services.Ps5Sessions[0];
        w.Timers.Advance(TimeSpan.FromMilliseconds(2840));
        src.Status(SourceStatus.Streaming);
        w.Services.ReaderFactory.Text = "Lower the bridge";
        for (var i = 0; i < 12 && c.History.Count == 0; i++)
        {
            src.Frame(World.Frame());
            await c.WaitForReadingAsync();
            w.Timers.Advance(TimeSpan.FromMilliseconds(400));
        }
        Assert.Single(c.History);
        w.Timers.Advance(TimeSpan.FromSeconds(60));
        src.Status(SourceStatus.Down(DisconnectReason.Network, "10.0.0.5 zaman aşımı"));
        w.Timers.Advance(TimeSpan.FromSeconds(5));
        c.Stop();
        await Flush(c);

        var connect = Assert.Single(_sender.Of("ps5_connect"));
        Assert.Equal("ok", (string?)connect["r"]);
        Assert.Equal(2840, (long)connect["ms"]!);
        Assert.Equal("lan", (string?)connect["via"]);

        var drop = Assert.Single(_sender.Of("ps5_drop"));
        Assert.Equal("network_lost", (string?)drop["code"]);
        Assert.InRange((long)drop["after"]!, 60, 70);

        var session = Assert.Single(_sender.Of("session"));
        Assert.Equal("remoteplay", (string?)session["src"]);
        Assert.Equal(1, (long)session["lines"]!);
        Assert.InRange((long)session["dur"]!, 65, 75);
        var h = session["h"]!.AsObject();
        foreach (var metric in new[] { "ocr", "tr.provider", "tr.provider:free", "tr.total", "first_frame", "first_subtitle" })
            Assert.True(h.ContainsKey(metric), metric);
        Assert.Equal(2840, (long)h["first_frame"]!["sum"]!);
        foreach (var (_, node) in h)
        {
            var n = (long)node!["n"]!;
            Assert.Equal(n, node["h"]!.AsArray().Sum(x => (long)x!));
        }

        // Hiçbir olayda ayrıntı metni, adres ya da altyazı yok.
        var all = string.Join("\n", _sender.Bodies.Select(b => b.ToJsonString()));
        Assert.DoesNotContain("10.0.0.5", all);
        Assert.DoesNotContain("Lower the bridge", all);
        Assert.DoesNotContain("192.168.1", all);
        Assert.DoesNotContain("PS5-789", all);
    }

    [Fact]
    public async Task FailedConnectAndUserStopIsNotADrop()
    {
        var w = Ready();
        var c = Open(w);
        await c.StartAsync();
        w.Timers.Advance(TimeSpan.FromMilliseconds(1500));
        w.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.ConsoleAsleep));
        c.Stop();

        await c.StartAsync();
        w.Services.Ps5Sessions[1].Status(SourceStatus.Streaming);
        c.Stop();
        await Flush(c);

        Assert.Equal(["ps5.session.standby", "ok"], _sender.Of("ps5_connect").Select(e => (string?)e["r"]));
        Assert.Equal(1500, (long)_sender.Of("ps5_connect").First()["ms"]!);
        Assert.Empty(_sender.Of("ps5_drop"));
        Assert.Equal(2, _sender.Of("session").Count());
    }

    [Fact]
    public async Task TvConnectDropWithRealReasonAndStopIsNotADrop()
    {
        var w = Ready();
        var c = Open(w);
        await c.StartAsync();
        var server = w.Services.Server;
        w.Timers.Advance(TimeSpan.FromMilliseconds(420));
        server.LinkUp(1, TvLinkKind.Legacy, model: "LG OLED55C1");
        w.Timers.Advance(TimeSpan.FromSeconds(30));
        server.LinkDown(1, TvLinkKind.Legacy, TvLinkEndReason.Silence);
        w.Timers.Advance(TimeSpan.FromSeconds(2));
        server.LinkUp(2, TvLinkKind.Legacy);
        w.Timers.Advance(TimeSpan.FromSeconds(5));
        server.LinkDown(2, TvLinkKind.Legacy, TvLinkEndReason.Stopped);
        server.LinkUp(3, TvLinkKind.Legacy);
        c.Stop();
        server.LinkDown(3, TvLinkKind.Legacy, TvLinkEndReason.Closed);
        await Flush(c);

        var connects = _sender.Of("tv_connect").ToList();
        Assert.Equal(3, connects.Count);
        Assert.All(connects, e => Assert.Equal("ok", (string?)e["r"]));
        Assert.Equal(420, (long)connects[0]["ms"]!);
        Assert.Equal("lg", (string?)connects[0]["brand"]);
        Assert.Equal("legacy", (string?)connects[0]["proto"]);
        Assert.Equal(2000, (long)connects[1]["ms"]!);
        var drop = Assert.Single(_sender.Of("tv_drop"));
        Assert.Equal("timeout", (string?)drop["code"]);
        Assert.Equal(30, (long)drop["after"]!);
        Assert.Equal("lg", (string?)drop["brand"]);

        var all = string.Join("\n", _sender.Bodies.Select(b => b.ToJsonString()));
        Assert.DoesNotContain("192.168.1.50", all);
        Assert.DoesNotContain("OLED55", all);
    }

    [Fact]
    public async Task TvLinkBrandComesFromTheRouteThenTheSavedTv()
    {
        var w = Ready();
        var c = Open(w);
        await c.StartAsync();
        var server = w.Services.Server;
        server.LinkUp(1, TvLinkKind.WebTv, tookMs: 80);
        server.LinkUp(2, TvLinkKind.AndroidTv, tookMs: 150);
        w.Timers.Advance(TimeSpan.FromSeconds(12));
        server.LinkDown(1, TvLinkKind.WebTv, TvLinkEndReason.WriteFailed);
        server.LinkDown(2, TvLinkKind.AndroidTv, TvLinkEndReason.Replaced);
        c.Stop();
        await Flush(c);

        var connects = _sender.Of("tv_connect").ToList();
        Assert.Equal(["lg", "androidtv"], connects.Select(e => (string?)e["brand"]));
        Assert.Equal(["nino", "nino"], connects.Select(e => (string?)e["proto"]));
        Assert.Equal(150, (long)connects[1]["ms"]!);
        var drops = _sender.Of("tv_drop").ToList();
        Assert.Equal(["write_error", "replaced"], drops.Select(e => (string?)e["code"]));
        Assert.Equal(["lg", "androidtv"], drops.Select(e => (string?)e["brand"]));
        Assert.All(drops, e => Assert.Equal(12, (long)e["after"]!));
    }

    [Fact]
    public async Task HandshakeFailureIsAFailedConnectOncePerAttempt()
    {
        var w = Ready();
        var c = Open(w);
        await c.StartAsync();
        var server = w.Services.Server;
        w.Timers.Advance(TimeSpan.FromSeconds(5));
        for (var i = 0; i < 3; i++)
            server.LinkDown(10 + i, TvLinkKind.AndroidTv, TvLinkEndReason.Handshake, wasConnected: false, detail: TvLinkReasons.NoWelcome);
        server.LinkUp(20, TvLinkKind.AndroidTv);
        server.LinkDown(20, TvLinkKind.AndroidTv, TvLinkEndReason.Closed);
        server.LinkDown(21, TvLinkKind.WebTv, TvLinkEndReason.Handshake, wasConnected: false, detail: TvLinkReasons.VersionUnsupported);
        c.Stop();
        await Flush(c);

        var connects = _sender.Of("tv_connect").ToList();
        Assert.Equal(["tv.connect.timeout", "ok", "tv.protocol.mismatch"], connects.Select(e => (string?)e["r"]));
        Assert.Equal(5000, (long)connects[0]["ms"]!);
        Assert.Equal("androidtv", (string?)connects[0]["brand"]);
        Assert.Equal("closed", (string?)Assert.Single(_sender.Of("tv_drop"))["code"]);
    }

    [Fact]
    public async Task TvConnectOutsideTranslationUsesTheLinkHandshakeTime()
    {
        var w = Ready();
        var c = Open(w);
        w.Services.Server.LinkUp(7, TvLinkKind.WebTv, tookMs: 95);
        w.Services.Server.LinkDown(7, TvLinkKind.WebTv, TvLinkEndReason.Closed);
        await Flush(c);
        Assert.Equal(95, (long)Assert.Single(_sender.Of("tv_connect"))["ms"]!);
        Assert.Empty(_sender.Of("tv_drop"));
    }

    [Theory]
    [InlineData(TvLinkEndReason.Closed, "closed")]
    [InlineData(TvLinkEndReason.WriteFailed, "write_error")]
    [InlineData(TvLinkEndReason.Silence, "timeout")]
    [InlineData(TvLinkEndReason.Replaced, "replaced")]
    [InlineData(TvLinkEndReason.Error, "other")]
    public void TvDropCodes(TvLinkEndReason reason, string code)
    {
        Assert.Equal(code, NinoController.DropCode(reason));
        Assert.Equal(code, TelemetryText.Code(code));
    }

    [Fact]
    public async Task RemoteConfigFromPoolStopsAndClearsQueue()
    {
        var w = new World();
        using var http = new HttpClient(new ConfigHandler());
        w.Services.PoolService = new TranslationPool(new TranslationPoolOptions(Path.Combine(_data, "pool-translations"),
            new Uri("http://127.0.0.1:9/"), "0.0.0", http), "tr", sharePool: false);
        var c = Open(w, install: null);
        Assert.Equal(w.Services.PoolService.InstallId, c.Telemetry!.Client.BuildBody("b", [])["install"]!.ToString());
        Assert.Equal(1, c.Telemetry.Client.PendingCount);
        await w.Services.PoolService.RefreshConfigAsync(force: true);
        Assert.False(c.Telemetry.Client.Config.Enabled);
        Assert.Equal(0, c.Telemetry.Client.PendingCount);
        Assert.Equal(FlushOutcome.Skipped, await c.Telemetry.Client.FlushAsync(ignoreBackoff: true));
        Assert.Empty(_sender.Bodies);
    }

    sealed class ConfigHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                Content = new StringContent("""{"downloads":5,"telemetry":{"enabled":false,"sample":1,"maxPerDay":1000,"flushSeconds":600}}"""),
            });
    }

    [Fact]
    public void NoSenderNoTelemetry()
    {
        var w = new World();
        var c = new NinoController(w.Services, w.Secrets, w.SettingsStore, w.Sleep, w.Text, a => a(), new ShellOptions
        {
            Timers = w.Timers,
            ProblemDelay = (_, ct) => Task.Delay(Timeout.Infinite, ct),
            Telemetry = new TelemetrySetup { DataFolder = _data, Platform = "windows", Os = "Windows 11 26100", Device = "x" },
        });
        Assert.Null(c.Telemetry);
        Assert.False(File.Exists(Marker));
    }

    [Theory]
    [InlineData(DisconnectReason.ConsoleAsleep, "ps5.session.standby", "standby")]
    [InlineData(DisconnectReason.InUse, "ps5.session.busy", "kicked")]
    [InlineData(DisconnectReason.Network, "ps5.session.timeout", "network_lost")]
    [InlineData(DisconnectReason.Rejected, "ps5.auth.rejected", "ps5_closed")]
    [InlineData(DisconnectReason.Other, "ps5.other", "other")]
    public void ReasonCodes(DisconnectReason reason, string connect, string drop)
    {
        Assert.Equal(connect, NinoController.ConnectCode(reason));
        Assert.Equal(drop, NinoController.DropCode(reason));
        Assert.Equal(connect, TelemetryText.Code(connect));
    }
}
