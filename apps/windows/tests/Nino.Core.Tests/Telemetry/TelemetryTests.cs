// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO.Compression;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json.Nodes;
using Nino.Core.Telemetry;
using Nino.Core.Tests.Data;

namespace Nino.Core.Tests.Telemetry;

public class TelemetryTests : IDisposable
{
    readonly TempFolder _tmp = new();
    readonly FakeClock _clock = new(DateTimeOffset.FromUnixTimeSeconds(1763300000));

    const string Install = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f";

    public void Dispose() => _tmp.Dispose();

    sealed class FakeSender : ITelemetrySender
    {
        public Queue<Func<TelemetryResponse>> Replies { get; } = new();
        public List<JsonObject> Bodies { get; } = [];

        public Task<TelemetryResponse> SendAsync(ReadOnlyMemory<byte> body, bool gzipped, CancellationToken ct)
        {
            Assert.True(gzipped);
            using var gz = new GZipStream(new MemoryStream(body.ToArray()), CompressionMode.Decompress);
            using var reader = new StreamReader(gz, Encoding.UTF8);
            Bodies.Add((JsonObject)JsonNode.Parse(reader.ReadToEnd())!);
            return Task.FromResult(Replies.Count > 0 ? Replies.Dequeue()() : new TelemetryResponse(200, null, "{\"ok\":true}"));
        }
    }

    static TelemetryContext Ctx(string platform = "windows") =>
        new(platform, "4.0.0", platform == "mac" ? "macOS 27.0" : "Windows 11 26100",
            platform == "mac" ? "Mac16,1" : "LENOVO 82JU", TvBrand.AndroidTv, TelemetryChannel.Release);

    TelemetryClient Client(FakeSender sender, string platform = "windows", Func<bool>? online = null) =>
        new(new TelemetryOptions(_tmp.Path, Install, () => Ctx(platform), sender) { Clock = _clock, IsOnline = online });

    static string FixturePath([CallerFilePath] string here = "") => Path.Combine(Path.GetDirectoryName(here)!, "events-v1.json");

    static DateTimeOffset T(long unix) => DateTimeOffset.FromUnixTimeSeconds(unix);

    [Fact]
    public void GovdeOrnekGovdeyleAyni()
    {
        var timings = new SessionTimings();
        foreach (var ms in new long[] { 35, 50, 50, 65, 70, 140 }) timings.Add(SessionTimings.Ocr, ms);
        foreach (var ms in new long[] { 1, 0, 2 }) timings.Add(SessionTimings.Cache, ms);
        timings.Add(SessionTimings.ProviderNamed("deepl"), 380);
        timings.Add(SessionTimings.ProviderNamed("deepl"), 600);
        foreach (var ms in new long[] { 200, 400, 600, 900 }) timings.Add(SessionTimings.Total, ms);
        timings.Add(SessionTimings.FirstFrame, 1900);

        var events = new[]
        {
            TelemetryEvent.Launch(T(1763300000), 640),
            TelemetryEvent.Crash(T(1763300000), "SIGSEGV", "ReadingPipeline.process", "3.9.0", 1820),
            TelemetryEvent.Ps5Connect(T(1763300012), "ps5.session.timeout", 15000, Ps5Route.Lan),
            TelemetryEvent.Ps5Connect(T(1763300040), "ok", 2840, Ps5Route.Lan),
            TelemetryEvent.TvConnect(T(1763300045), "ok", 420, TvBrand.AndroidTv, TvProtocol.Nino),
            TelemetryEvent.Error(T(1763300300), "tr.provider.http", 429, 3),
            TelemetryEvent.Ps5Drop(T(1763303000), "network_lost", 2950),
            TelemetryEvent.TvDrop(T(1763303100), "timeout", TvBrand.AndroidTv, 3050),
            TelemetryEvent.Session(T(1763303600), 3580, "gta-vi", SessionSource.RemotePlay, 412, timings),
        };
        var client = Client(new FakeSender(), "mac");
        var body = client.BuildBody("2f6c1c8e-8a43-4b9b-9a3e-1e5f0c7d9a10", events);
        var expected = JsonNode.Parse(File.ReadAllText(FixturePath()));
        Assert.True(JsonNode.DeepEquals(expected, body), body.ToJsonString());
    }

    [Fact]
    public void KovaSinirlari()
    {
        Assert.Equal(19, TimingHistogram.BucketCount);
        Assert.Equal(0, TimingHistogram.BucketOf(5));
        Assert.Equal(1, TimingHistogram.BucketOf(6));
        Assert.Equal(17, TimingHistogram.BucketOf(10000));
        Assert.Equal(18, TimingHistogram.BucketOf(10001));
    }

    [Fact]
    public void AlanSuzgecleri()
    {
        var e = TelemetryEvent.Error(_clock.GetUtcNow(), "C:\\Users\\yunus\\dosya bulunamadı");
        Assert.Equal(TelemetryCodes.Invalid, e.Body["code"]!.GetValue<string>());
        var s = TelemetryEvent.Session(_clock.GetUtcNow(), 1, "Red Dead", SessionSource.Capture, 0, null);
        Assert.Equal("", s.Body["game"]!.GetValue<string>());
        var timings = new SessionTimings();
        timings.Add("Bad Name", 3);
        for (var i = 0; i < 30; i++) timings.Add("m" + i, 1);
        Assert.Equal(SessionTimings.MaxMetrics, timings.ToJson().Count);
        Assert.Equal("Windows 11 26100", TelemetryContext.WindowsOs(10, 0, 26100));
        Assert.Equal("dev", new TelemetryContext("windows", "4.0.0 (yerel)", "x", "y", TvBrand.None, TelemetryChannel.Dev).ToJson()["channel"]!.GetValue<string>());
        Assert.Equal("", new TelemetryContext("windows", "4.0.0 (yerel)", "x", "y", TvBrand.None, TelemetryChannel.Dev).ToJson()["app"]!.GetValue<string>());
    }

    [Fact]
    public async Task BasariliGonderimKuyruguBosaltirAyariUygular()
    {
        var sender = new FakeSender();
        sender.Replies.Enqueue(() => new TelemetryResponse(200, null,
            "{\"ok\":true,\"accepted\":2,\"dropped\":0,\"config\":{\"telemetry\":{\"enabled\":true,\"sample\":0,\"maxPerDay\":5,\"flushSeconds\":60}}}"));
        var client = Client(sender);
        client.AppLaunched("4.0.0", 500);
        client.RecordError("ocr.failed");
        Assert.Equal(FlushOutcome.Sent, await client.FlushAsync());
        Assert.Equal(0, client.PendingCount);
        var body = sender.Bodies.Single();
        Assert.Equal("windows", body["ctx"]!["platform"]!.GetValue<string>());
        Assert.Equal(Install, body["install"]!.GetValue<string>());
        Assert.Equal(2, body["events"]!.AsArray().Count);
        Assert.Equal(5, client.Config.MaxPerDay);
        Assert.Equal(60, client.Config.FlushSeconds);
    }

    [Fact]
    public async Task AyniHataBirlesir()
    {
        var sender = new FakeSender();
        var client = Client(sender);
        client.RecordError("tr.provider.http", 429);
        client.RecordError("tr.provider.http", 429);
        client.RecordError("tr.provider.http", 429);
        client.RecordError("tr.provider.http", 500);
        await client.FlushAsync();
        var events = sender.Bodies[0]["events"]!.AsArray();
        Assert.Equal(2, events.Count);
        Assert.Equal(3, events[0]!["n"]!.GetValue<int>());
        Assert.Null(events[1]!["n"]);
    }

    [Theory]
    [InlineData(404)]
    [InlineData(503)]
    [InlineData(401)]
    public async Task SunucuHazirDegilseAyniParcaSaklanirGeriCekilir(int status)
    {
        var sender = new FakeSender();
        sender.Replies.Enqueue(() => new TelemetryResponse(status));
        sender.Replies.Enqueue(() => new TelemetryResponse(status));
        var client = Client(sender);
        client.RecordError("ocr.failed");
        Assert.Equal(FlushOutcome.Deferred, await client.FlushAsync());
        Assert.Equal(1, client.PendingCount);
        Assert.Equal(_clock.GetUtcNow().ToUnixTimeSeconds() + 60, client.NextAttemptUnix);
        Assert.Equal(FlushOutcome.Skipped, await client.FlushAsync());
        _clock.Advance(TimeSpan.FromSeconds(61));
        Assert.Equal(FlushOutcome.Deferred, await client.FlushAsync());
        Assert.Equal(_clock.GetUtcNow().ToUnixTimeSeconds() + 120, client.NextAttemptUnix);
        _clock.Advance(TimeSpan.FromSeconds(121));

        // Yeniden açılışta da aynı parça kimliği.
        var reopened = Client(sender);
        Assert.Equal(FlushOutcome.Sent, await reopened.FlushAsync());
        Assert.Equal(3, sender.Bodies.Count);
        Assert.Single(sender.Bodies.Select(b => b["batch"]!.GetValue<string>()).Distinct());
        Assert.Equal(0, reopened.PendingCount);
    }

    [Fact]
    public async Task GeriCekilmeEnCokBirSaat()
    {
        var sender = new FakeSender();
        var client = Client(sender);
        client.RecordError("ocr.failed");
        for (var i = 0; i < 9; i++)
        {
            sender.Replies.Enqueue(() => new TelemetryResponse(500));
            await client.FlushAsync(ignoreBackoff: true);
        }
        Assert.Equal(_clock.GetUtcNow().ToUnixTimeSeconds() + 3600, client.NextAttemptUnix);
    }

    [Fact]
    public async Task HizSiniriRetryAfterKadarBekler()
    {
        var sender = new FakeSender();
        sender.Replies.Enqueue(() => new TelemetryResponse(429, TimeSpan.FromSeconds(300)));
        var client = Client(sender);
        client.RecordError("ocr.failed");
        Assert.Equal(FlushOutcome.Deferred, await client.FlushAsync());
        Assert.Equal(_clock.GetUtcNow().ToUnixTimeSeconds() + 300, client.NextAttemptUnix);
    }

    [Fact]
    public async Task BozukGovdeSilinir()
    {
        var sender = new FakeSender();
        sender.Replies.Enqueue(() => new TelemetryResponse(400));
        var client = Client(sender);
        client.RecordError("ocr.failed");
        Assert.Equal(FlushOutcome.Sent, await client.FlushAsync());
        Assert.Equal(0, client.PendingCount);
    }

    [Fact]
    public async Task CokBuyukParcaIkiyeBolunurTekOlaySilinir()
    {
        var sender = new FakeSender();
        sender.Replies.Enqueue(() => new TelemetryResponse(413));
        sender.Replies.Enqueue(() => new TelemetryResponse(413));
        var client = Client(sender);
        for (var i = 0; i < 4; i++) client.RecordError("ocr.failed" + i);
        await client.FlushAsync();
        Assert.Equal(0, client.PendingCount);
        Assert.Equal(4, sender.Bodies[0]["events"]!.AsArray().Count);
        Assert.Equal(2, sender.Bodies[1]["events"]!.AsArray().Count);
        Assert.Single(sender.Bodies[2]["events"]!.AsArray());
        Assert.Equal(5, sender.Bodies.Count);
        Assert.Equal(5, sender.Bodies.Select(b => b["batch"]!.GetValue<string>()).Distinct().Count());

        var single = new FakeSender();
        single.Replies.Enqueue(() => new TelemetryResponse(413));
        var c2 = new TelemetryClient(new TelemetryOptions(_tmp.File("b"), Install, () => Ctx(), single) { Clock = _clock });
        c2.RecordError("ocr.failed");
        await c2.FlushAsync();
        Assert.Equal(0, c2.PendingCount);
    }

    [Fact]
    public async Task ParcaEnCok300Olay()
    {
        var sender = new FakeSender();
        var client = Client(sender);
        client.ApplyRemoteConfig(TelemetryConfig.Default with { MaxPerDay = 5000 });
        for (var i = 0; i < 650; i++) client.RecordError("e" + i);
        await client.FlushAsync();
        Assert.Equal(new[] { 300, 300, 50 }, sender.Bodies.Select(b => b["events"]!.AsArray().Count));
    }

    [Fact]
    public void KuyrukVeGunlukSinir()
    {
        var client = Client(new FakeSender());
        client.ApplyRemoteConfig(TelemetryConfig.Default with { MaxPerDay = 3 });
        for (var i = 0; i < 5; i++) client.RecordError("e" + i);
        client.Record(TelemetryEvent.Crash(_clock.GetUtcNow(), "SIGSEGV", null, "4.0.0", null));
        Assert.Equal(4, client.QueuedCount);
        _clock.Advance(TimeSpan.FromDays(1));
        client.RecordError("ertesi");
        Assert.Equal(5, client.QueuedCount);

        var big = new TelemetryClient(new TelemetryOptions(_tmp.File("q"), Install, () => Ctx(), new FakeSender()) { Clock = _clock });
        big.ApplyRemoteConfig(TelemetryConfig.Default with { MaxPerDay = 10_000 });
        big.Record(TelemetryEvent.Crash(_clock.GetUtcNow(), null, null, "4.0.0", null));
        for (var i = 0; i < 2100; i++) big.RecordError("e" + i);
        Assert.Equal(TelemetryClient.MaxQueue, big.QueuedCount);
    }

    [Fact]
    public async Task SunucuKapatirsaKuyrukSilinir()
    {
        var sender = new FakeSender();
        var client = Client(sender);
        client.RecordError("ocr.failed");
        client.ApplyRemoteConfigJson("{\"telemetry\":{\"enabled\":false}}");
        Assert.Equal(0, client.PendingCount);
        client.RecordError("ocr.failed");
        Assert.Equal(0, client.PendingCount);
        Assert.Equal(FlushOutcome.Skipped, await client.FlushAsync());
        Assert.Empty(sender.Bodies);
        Assert.False(File.Exists(_tmp.File("queue.json")));
    }

    [Fact]
    public async Task AgYoksaDenenmez()
    {
        var sender = new FakeSender();
        var client = Client(sender, online: () => false);
        client.RecordError("ocr.failed");
        Assert.Equal(FlushOutcome.Skipped, await client.FlushAsync());
        Assert.Empty(sender.Bodies);
    }

    [Fact]
    public void OrneklemeYalnizSureleriEtkiler()
    {
        var client = Client(new FakeSender());
        client.ApplyRemoteConfig(TelemetryConfig.Default with { Sample = 0 });
        var t = new SessionTimings();
        t.Add(SessionTimings.Ocr, 10);
        client.Record(TelemetryEvent.Session(_clock.GetUtcNow(), 10, "gta-v", SessionSource.RemotePlay, 3, t));
        client.RecordError("ocr.failed");
        Assert.Equal(2, client.QueuedCount);
        client.Persist();
        var queued = JsonNode.Parse(File.ReadAllText(_tmp.File("queue.json")))!["events"]!.AsArray();
        Assert.Null(queued[0]!["h"]);
        Assert.Equal(3, queued[0]!["lines"]!.GetValue<int>());

        Assert.True(TelemetryConfig.Default.SamplesTimings(Install));
        Assert.False((TelemetryConfig.Default with { Sample = 0 }).SamplesTimings(Install));
        var bucket = TelemetryConfig.Fnv1a32(Install) % 10000;
        Assert.Equal(TelemetryConfig.Fnv1a32(Install.ToUpperInvariant().ToLowerInvariant()), TelemetryConfig.Fnv1a32(Install));
        Assert.True((TelemetryConfig.Default with { Sample = (bucket + 1) / 10000.0 }).SamplesTimings(Install.ToUpperInvariant()));
        Assert.False((TelemetryConfig.Default with { Sample = bucket / 10000.0 }).SamplesTimings(Install));
        Assert.Equal(0x811C9DC5u, TelemetryConfig.Fnv1a32(""));
        Assert.Equal(0xE40C292Cu, TelemetryConfig.Fnv1a32("a"));
    }

    [Fact]
    public async Task CokmeIsaretiSonrakiAcilistaCokmeOlayiOlur()
    {
        var sender = new FakeSender();
        var first = Client(sender);
        first.AppLaunched("3.9.0");
        _clock.Advance(TimeSpan.FromSeconds(1820));
        try { ThrowFromNino(); }
        catch (Exception e) { first.Marker.RecordCrash(e); }

        _clock.Advance(TimeSpan.FromSeconds(30));
        var second = Client(sender);
        second.AppLaunched("4.0.0");
        await second.FlushAsync();
        var events = sender.Bodies.Last()["events"]!.AsArray();
        var crash = events.Single(e => e!["k"]!.GetValue<string>() == "crash")!;
        Assert.Equal("System.InvalidOperationException", crash["code"]!.GetValue<string>());
        Assert.Equal("3.9.0", crash["ver"]!.GetValue<string>());
        Assert.Equal(1820, crash["up"]!.GetValue<long>());
        Assert.Equal("TelemetryTests.ThrowFromNino", crash["where"]!.GetValue<string>());

        second.AppExiting();
        var third = Client(sender);
        third.AppLaunched("4.0.0");
        await third.FlushAsync();
        Assert.DoesNotContain(sender.Bodies.Last()["events"]!.AsArray(), e => e!["k"]!.GetValue<string>() == "crash");
    }

    [Fact]
    public async Task BilinmeyenCokmeUncleanExit()
    {
        var sender = new FakeSender();
        Client(sender).AppLaunched("4.0.0");
        var next = Client(sender);
        next.AppLaunched("4.0.1");
        await next.FlushAsync();
        var crash = sender.Bodies.Last()["events"]!.AsArray().Single(e => e!["k"]!.GetValue<string>() == "crash")!;
        Assert.Equal("unclean_exit", crash["code"]!.GetValue<string>());
        Assert.Equal("4.0.0", crash["ver"]!.GetValue<string>());
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void ThrowFromNino() => throw new InvalidOperationException("iletisi asla gitmez: C:\\Users\\x");

    [Fact]
    public async Task DonguEsikDolunancaGonderirIptalleBiter()
    {
        var sender = new FakeSender();
        var client = Client(sender);
        using var cts = new CancellationTokenSource();
        var loop = client.RunAsync(cts.Token);
        for (var i = 0; i < TelemetryClient.FlushThreshold; i++) client.RecordError("e" + i);
        for (var i = 0; i < 200 && sender.Bodies.Count == 0; i++) await Task.Delay(10);
        Assert.Single(sender.Bodies);
        cts.Cancel();
        await loop.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public void KuyrukHemenDiskeYazilir()
    {
        var client = Client(new FakeSender());
        client.RecordError("a.one");
        _clock.Advance(TimeSpan.FromSeconds(1));
        client.RecordError("a.two");
        Assert.Equal(2, Client(new FakeSender()).QueuedCount);
    }

    [Fact]
    public async Task Yalniz200Ve400Siler()
    {
        var sender = new FakeSender();
        sender.Replies.Enqueue(() => new TelemetryResponse(204));
        var client = Client(sender);
        client.RecordError("ocr.failed");
        Assert.Equal(FlushOutcome.Deferred, await client.FlushAsync());
        Assert.Equal(1, client.PendingCount);
        sender.Replies.Enqueue(() => new TelemetryResponse(503, TimeSpan.FromSeconds(30)));
        await client.FlushAsync(ignoreBackoff: true);
        Assert.Equal(_clock.GetUtcNow().ToUnixTimeSeconds() + 30, client.NextAttemptUnix);
    }

    [Fact]
    public void UzakAyarOkuma()
    {
        var c = TelemetryConfig.FromResponse("{\"telemetry\":{\"enabled\":true,\"sample\":0.5,\"maxPerDay\":1000,\"flushSeconds\":600}}", TelemetryConfig.Default)!;
        Assert.Equal(0.5, c.Sample);
        Assert.Null(TelemetryConfig.FromResponse("{\"ok\":true}", TelemetryConfig.Default));
        Assert.Null(TelemetryConfig.FromResponse("bozuk", TelemetryConfig.Default));
        Assert.Equal(1, TelemetryConfig.FromResponse("{\"telemetry\":{\"sample\":7}}", TelemetryConfig.Default)!.Sample);
    }
}
