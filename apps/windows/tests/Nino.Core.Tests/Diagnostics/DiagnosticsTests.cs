// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Core.Diagnostics;
using Nino.Core.Telemetry;

namespace Nino.Core.Tests.Diagnostics;

public sealed class DiagnosticsTests : IDisposable
{
    static readonly DateTimeOffset T0 = new(2026, 11, 22, 9, 0, 0, TimeSpan.Zero);
    readonly string _dir = Directory.CreateTempSubdirectory("nino-diag-").FullName;
    readonly FakeClock _clock = new(T0);
    readonly List<DiagReport> _reports = [];

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch (IOException) { }
    }

    DiagnosticsWatcher Watcher(DiagHostState? state = null, DiagDailyLimits? limits = null,
        IReadOnlyDictionary<string, double>? platform = null)
    {
        var w = new DiagnosticsWatcher(new DiagOptions
        {
            Clock = _clock,
            State = () => state ?? new DiagHostState(),
            Limits = limits,
            PlatformDefaults = platform,
        });
        w.Reported += _reports.Add;
        return w;
    }

    /// <summary>Saati saniye saniye ilerletip her saniyede Tick çağırır.</summary>
    void Run(DiagnosticsWatcher w, int seconds)
    {
        for (var i = 0; i < seconds; i++)
        {
            _clock.Advance(1);
            w.Tick();
        }
    }

    static void Errors(DiagnosticsWatcher w, int count, int http)
    {
        for (var i = 0; i < count; i++) w.TranslationResult(false, http);
    }

    // ---- İz ----

    [Fact]
    public void TrailKeepsTenMinutesAndAtMost200Steps()
    {
        var trail = new DiagTrail();
        for (var i = 0; i < 250; i++) trail.Add(T0 + TimeSpan.FromSeconds(i), "ps5.retry", i);
        Assert.Equal(200, trail.Count);
        var json = trail.ToJson(T0 + TimeSpan.FromSeconds(249));
        Assert.Equal(40, json.Count);
        Assert.Equal(-39, (long)json[0]![0]!);
        Assert.Equal(0, (long)json[^1]![0]!);
        Assert.Equal(249, (long)json[^1]![2]!);

        Assert.Empty(trail.Steps(T0 + TimeSpan.FromMinutes(30)));
    }

    [Fact]
    public void TrailSkipsBadCodesAndCoalesces()
    {
        var trail = new DiagTrail();
        trail.Add(T0, "bir hata oldu: C:\\Users\\x");
        trail.Add(T0, "192.168.0.110");
        trail.Add(T0, "tr.ok", coalesce: TimeSpan.FromSeconds(30));
        trail.Add(T0 + TimeSpan.FromSeconds(10), "tr.ok", coalesce: TimeSpan.FromSeconds(30));
        trail.Add(T0 + TimeSpan.FromSeconds(40), "tr.ok", coalesce: TimeSpan.FromSeconds(30));
        Assert.Equal(["tr.ok", "tr.ok"], trail.Steps(T0 + TimeSpan.FromSeconds(40)).Select(s => s.Code));
    }

    // ---- Gizlilik ve alan doğrulaması ----

    [Fact]
    public void PayloadDropsFreeTextAddressesAndPaths()
    {
        var trail = new JsonArray(
            new JsonArray(-10, "ps5.drop"),
            new JsonArray(-5, "C:\\Users\\yunus\\log.txt"),
            new JsonArray(-4, "10.0.0.5"),
            new JsonArray(5, "net.down"),
            new JsonArray(-4000, "net.down"),
            new JsonArray(-1, "tr.error", 429));
        var body = DiagPayload.Build(T0, "tr.errors", "quota", DiagSeverity.Warn,
            [
                new("net", "wifi"), new("memMB", 410), new("ok", true), new("ratio", 0.333),
                new("host", "192.168.0.110"), new("tvName", "Yunus'un TV'si"), new("path", "/home/u/x"),
                new("bad key", 1), new("mac", "aa:bb:cc:dd:ee:ff"), new("mac2", "AA-BB-CC-DD-EE-FF"),
                new("text", "Hello there"),
            ],
            trail, new DiagTv("androidtv", "TCL 98U95A", "4.0.0"), "gta-vi",
            [new("core", "1.0.0"), new("remoteplay", "bad version!")])!;
        var json = body.ToJsonString();
        foreach (var leak in new[] { "192.168", "10.0.0.5", "Yunus", "Users", "home", "aa:bb", "AA-BB", "Hello" })
            Assert.DoesNotContain(leak, json);

        var state = body["state"]!.AsObject();
        Assert.Equal(["net", "memMB", "ok", "ratio"], state.Select(kv => kv.Key));
        Assert.Equal(["ps5.drop", "tr.error"], body["trail"]!.AsArray().Select(s => (string)s![1]!));
        Assert.Equal("TCL 98U95A", (string)body["tv"]!["model"]!);
        Assert.Equal("gta-6", (string)body["game"]!); // takma ad asıl kimliğe çevrilir
        Assert.Equal(["core"], body["ver"]!.AsObject().Select(kv => kv.Key));
    }

    [Fact]
    public void InvalidRuleDropsEventAndBadCauseBecomesUnknown()
    {
        Assert.Null(DiagPayload.Build(T0, "PS5 koptu!", "x", DiagSeverity.Error, null, null, null, null, null));
        Assert.Null(TelemetryEvent.Diag(new JsonObject { ["k"] = "diag", ["t"] = 1, ["rule"] = "Bad Rule" }));
        var body = DiagPayload.Build(T0, "ps5.no_return", "sebep: ağ", DiagSeverity.Error, null, null, null, "Bad Game", null)!;
        Assert.Equal("unknown", (string)body["cause"]!);
        Assert.False(body.ContainsKey("game"));
        Assert.False(body.ContainsKey("tv"));
        Assert.Equal(DiagRules.Unknown, DiagRules.CauseOrUnknown("tv.flapping", "other"));
        Assert.Equal("replaced", DiagRules.CauseOrUnknown("tv.flapping", "replaced"));
    }

    [Fact]
    public void PayloadLimitsStateKeysTrailAndVersions()
    {
        var state = Enumerable.Range(0, 40).Select(i => new KeyValuePair<string, object?>("k" + i, i));
        var trail = new JsonArray(Enumerable.Range(0, 60).Select(i => (JsonNode)new JsonArray(-i, "net.change")).ToArray());
        var versions = Enumerable.Range(0, 9).Select(i => new KeyValuePair<string, string?>("c" + i, "1.0"));
        var body = DiagPayload.Build(T0, "app.hang", "main_thread", DiagSeverity.Error, state, trail, null, null, versions)!;
        Assert.Equal(30, body["state"]!.AsObject().Count);
        Assert.Equal(40, body["trail"]!.AsArray().Count);
        Assert.Equal(6, body["ver"]!.AsObject().Count);
    }

    [Fact]
    public void WatcherReportsNeverCarryText()
    {
        var w = Watcher(new DiagHostState { Provider = "deepl", Proto = "Salon TV 192.168.0.5" });
        _clock.Advance(100);
        w.SessionStarted();
        w.Note("C:\\Users\\yunus\\nino.log");
        w.Note("ps5.auth.expired");
        Errors(w, 10, 401);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal("auth", r.Cause);
        var json = r.Body.ToJsonString();
        Assert.DoesNotContain("Users", json);
        Assert.DoesNotContain("Salon", json);
        Assert.Contains("ps5.auth.expired", json);
        Assert.Equal("deepl", (string)r.Body["state"]!["provider"]!);
        Assert.Equal(401, (long)r.Body["state"]!["http"]!);
    }

    // ---- Uzak ayar ----

    [Fact]
    public void RemoteConfigTurnsRulesOffAndChangesLimits()
    {
        var c = DiagConfig.FromResponse("""
            {"config":{"telemetry":{"enabled":true,"diag":{"off":["ocr.silent","Bad Rule"],
              "limits":{"tr.slow.p90Ms":4000,"ps5NoReturnSec":60,"trErrorRate":50,"nope":1,"hangSec":-3}}}}}
            """)!;
        Assert.True(c.IsOff("ocr.silent"));
        Assert.Single(c.Off);
        Assert.Equal(4000, c[DiagLimitKeys.TrSlowP90Ms]);
        Assert.Equal(60, c[DiagLimitKeys.Ps5NoReturnSec]);
        Assert.Equal(0.5, c[DiagLimitKeys.TrErrorRate]);
        Assert.Equal(5, c[DiagLimitKeys.HangSec]);
        Assert.Null(DiagConfig.FromResponse("""{"telemetry":{"enabled":true}}"""));
        Assert.Null(DiagConfig.FromResponse("bozuk"));
    }

    [Fact]
    public void OffRuleDoesNotFireAndThresholdIsUsed()
    {
        var w = Watcher();
        w.ApplyRemoteConfigJson("""{"telemetry":{"diag":{"off":["tr.errors"],"limits":{"ps5NoReturnSec":60}}}}""");
        _clock.Advance(100);
        w.SessionStarted();
        Errors(w, 12, 429);
        w.Ps5Connected();
        w.Ps5Dropped("kicked");
        Run(w, 61);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("ps5.no_return", "kicked"), (r.Rule, r.Cause));
        Assert.Equal(160, (r.At - T0).TotalSeconds);
    }

    [Fact]
    public void PlatformDefaultIsUnderRemoteValue()
    {
        var w = Watcher(platform: new Dictionary<string, double> { ["memHighMB"] = 400 });
        Assert.Equal(400, w.Config[DiagLimitKeys.MemHighMB]);
        w.ApplyRemoteConfigJson("""{"telemetry":{"diag":{"limits":{"app.resources.memMB":900}}}}""");
        Assert.Equal(900, w.Config[DiagLimitKeys.MemHighMB]);
    }

    // ---- Susturma ----

    [Fact]
    public void FirstMinuteAfterLaunchIsQuiet()
    {
        var w = Watcher();
        w.SessionStarted();
        _clock.Advance(10);
        Errors(w, 12, 429);
        w.FlushPending();
        Assert.Empty(_reports);
    }

    [Fact]
    public void ClockJumpBetweenTicksCountsAsSleepEvenWithoutSignal()
    {
        // Linux uykuyu ancak uyandıktan sonra bildirir; aradaki ilk tik saat sıçramasını görüp susturmalı.
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        w.Ps5Connected();
        Run(w, 5);
        w.Ps5Dropped();
        _clock.Advance(3 * 3600);
        w.Tick();
        w.SystemSleeping();
        w.SystemWoke();
        Run(w, 125);
        w.FlushPending();
        var r = _reports.Select(x => $"{x.Rule}@{(x.At - T0).TotalSeconds}").ToList();
        Assert.True(r.Count == 0, string.Join(",", r));
    }

    [Fact]
    public void LateSleepSignalAloneStillSilences()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        w.Ps5Connected();
        Run(w, 5);
        _clock.Advance(2 * 3600);
        w.SystemSleeping();
        w.SystemWoke();
        w.Ps5Dropped();
        Run(w, 100);
        w.FlushPending();
        Assert.Empty(_reports);
    }

    [Fact]
    public void OfflineSilencesNonNetworkRulesButNotPs5()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        w.FrameRate(30);
        w.NetworkChanged("none");
        Run(w, 15 * 60 + 5);
        w.FlushPending();
        Assert.Empty(_reports);

        w.Ps5Connected();
        _clock.Advance(1);
        w.Ps5Dropped();
        Run(w, 181);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("ps5.no_return", "network_lost"), (r.Rule, r.Cause));
    }

    [Fact]
    public void BackgroundDoesNotSilenceTvFlappingButSleepDoes()
    {
        var w = Watcher(new DiagHostState { TvCount = 1, Proto = "nino" });
        _clock.Advance(100);
        w.SessionStarted();
        w.AppBackground();
        w.TvDropped("resume", 30);
        w.AppForeground();
        _clock.Advance(10);
        w.TvDropped("resume", 40);
        w.SystemSleeping();
        w.SystemWoke();
        _clock.Advance(10);
        w.TvDropped("resume", 50);
        w.FlushPending();
        Assert.Empty(_reports);

        _clock.Advance(130);
        w.AppBackground();
        w.TvDropped("replaced", 10);
        w.TvDropped("replaced", 20);
        w.TvDropped("closed", 30);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("tv.flapping", "replaced"), (r.Rule, r.Cause));
        Assert.Equal(3, (long)r.Body["state"]!["drops"]!);
        Assert.Equal(20, (long)r.Body["state"]!["avgUpSec"]!);
        Assert.Equal("nino", (string)r.Body["state"]!["proto"]!);
    }

    [Fact]
    public void MixedTvReasonsGiveMixed()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.TvDropped("timeout");
        w.TvDropped("closed");
        w.TvDropped("tv_closed");
        w.TvDropped("write_error");
        w.FlushPending();
        Assert.Equal("closed", Assert.Single(_reports).Cause);

        _reports.Clear();
        w.SessionStarted();
        w.TvDropped("timeout");
        w.TvDropped("write_error");
        w.TvDropped("network_lost");
        w.FlushPending();
        Assert.Equal("mixed", Assert.Single(_reports).Cause);
    }

    // ---- Öncelik ve sınırlar ----

    [Fact]
    public void SingleRootSendsOnlyTheHighestPriorityWithinFiveMinutes()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        w.Ps5Connected();
        w.Ps5Dropped();
        Errors(w, 10, 503);
        Run(w, 180);
        Assert.Empty(_reports);
        Run(w, 125);
        var r = Assert.Single(_reports);
        Assert.Equal("ps5.no_return", r.Rule);
        Assert.Contains(r.Body["trail"]!.AsArray(), s => (string)s![1]! == "diag.tr.errors");
    }

    [Fact]
    public void HangIsSentImmediately()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.UiBlocked(3);
        Assert.Empty(_reports);
        w.UiBlocked(6);
        var r = Assert.Single(_reports);
        Assert.Equal(("app.hang", "main_thread", "error"), (r.Rule, r.Cause, (string)r.Body["sev"]!));
        Assert.Equal(6, (long)r.Body["state"]!["blockedSec"]!);
    }

    [Fact]
    public void SameRuleOncePerSessionAndAgainInNextSession()
    {
        var w = Watcher();
        _clock.Advance(100);
        for (var session = 0; session < 3; session++)
        {
            w.SessionStarted();
            Errors(w, 10, 429);
            _clock.Advance(1);
            Errors(w, 10, 429);
            w.SessionStopped();
            Run(w, 301);
        }
        Assert.Equal(2, _reports.Count);
    }

    [Fact]
    public void DailyLimitsSurviveRestartAndRollOverAtServerDay()
    {
        var path = Path.Combine(_dir, DiagDailyLimits.FileName);
        var limits = new DiagDailyLimits(path);
        for (var i = 0; i < 2; i++) limits.Count("tr.errors", T0);
        for (var i = 0; i < 2; i++) limits.Count("ps5.no_return", T0);
        var reloaded = new DiagDailyLimits(path);
        Assert.False(reloaded.Allows("tr.errors", T0));
        Assert.True(reloaded.Allows("ocr.silent", T0));
        reloaded.Count("ocr.silent", T0);
        Assert.False(reloaded.Allows("app.hang", T0));
        // Türkiye saatiyle gece yarısı: 21:00 UTC.
        Assert.False(reloaded.Allows("app.hang", new DateTimeOffset(2026, 11, 22, 20, 59, 0, TimeSpan.Zero)));
        Assert.True(reloaded.Allows("app.hang", new DateTimeOffset(2026, 11, 22, 21, 0, 0, TimeSpan.Zero)));
    }

    // ---- Kurallar ----

    [Fact]
    public void SlowTranslationsWithProviderGiveProviderSlow()
    {
        var w = Watcher(new DiagHostState { Provider = "gemini" });
        _clock.Advance(100);
        w.SessionStarted();
        for (var i = 0; i < 19; i++) w.LineShown(4200, "provider", 3900, 150);
        Assert.Empty(_reports);
        w.LineShown(4200, "provider", 3900, 150);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("tr.slow", "provider_slow"), (r.Rule, r.Cause));
        Assert.Equal(4200, (long)r.Body["state"]!["p90"]!);
        Assert.Equal(1, (long)r.Body["state"]!["providerShare"]!);
    }

    [Fact]
    public void SlowLinesWithSlowOcrGiveDeviceBusy()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        for (var i = 0; i < 20; i++) w.LineShown(3500, "pack", null, 1800);
        w.FlushPending();
        Assert.Equal("device_busy", Assert.Single(_reports).Cause);
    }

    [Fact]
    public void OcrStallsThreeTimesInFiveMinutes()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        w.OcrStalled(11000);
        _clock.Advance(100);
        w.OcrFinished(12000, foundText: false);
        _clock.Advance(100);
        w.OcrStalled(15000);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("ocr.stalled", "ocr_hang"), (r.Rule, r.Cause));
    }

    [Fact]
    public void FramesStoppingWhileConnectedGivesFramesStoppedOrDecoder()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.SessionStarted();
        w.Ps5Connected();
        Run(w, 10);
        w.FrameSeen();
        Run(w, 29);
        Assert.Empty(_reports);
        Run(w, 1);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("ocr.stalled", "frames_stopped"), (r.Rule, r.Cause));
        Assert.Equal(140, (r.At - T0).TotalSeconds);

        _reports.Clear();
        w.SessionStarted();
        w.Ps5Connected();
        w.DecoderFailed();
        Run(w, 31);
        w.FlushPending();
        Assert.Equal("decoder", Assert.Single(_reports).Cause);
    }

    [Fact]
    public void ManualRegionGivesRegionWrong()
    {
        var w = Watcher(new DiagHostState { FrameLuma = 120, RegionManual = true });
        _clock.Advance(100);
        w.SessionStarted();
        w.FrameRate(60);
        Run(w, 900);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("ocr.silent", "region_wrong", "info"), (r.Rule, r.Cause, (string)r.Body["sev"]!));
        Assert.Equal("manual", (string)r.Body["state"]!["region"]!);
    }

    [Fact]
    public void MemoryHighForTwoMinutes()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.Resources(1600, 20);
        _clock.Advance(60);
        w.Resources(1700, 20);
        _clock.Advance(59);
        w.Resources(1700, 20);
        Assert.Empty(_reports);
        _clock.Advance(1);
        w.Resources(1800, 95);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("app.resources", "memory_high"), (r.Rule, r.Cause));
        Assert.Equal(1800, (long)r.Body["state"]!["memMB"]!);
        Assert.Contains(r.Body["trail"]!.AsArray(), s => (string)s![1]! == "mem.high");
    }

    [Fact]
    public void PackFailingThreeTimesInARow()
    {
        var w = Watcher();
        _clock.Advance(100);
        w.PackDownload("gta-vi", ok: false, http: 404);
        w.PackDownload("gta-vi", ok: false, http: 404);
        w.PackDownload("gta-vi", ok: true);
        w.PackDownload("gta-vi", ok: false, http: 404);
        w.PackDownload("gta-vi", ok: false, http: 404);
        Assert.Empty(_reports);
        w.PackDownload("gta-vi", ok: false, http: 404, sizeKB: 120);
        w.FlushPending();
        var r = Assert.Single(_reports);
        Assert.Equal(("pack.download", "http_4xx"), (r.Rule, r.Cause));
        Assert.Equal(3, (long)r.Body["state"]!["attempts"]!);
        Assert.DoesNotContain("gta-vi", r.Body["state"]!.ToJsonString());
    }

    [Fact]
    public void HeartbeatDetectsPreviousHang()
    {
        var path = Path.Combine(_dir, DiagHeartbeat.FileName);
        var beat = new DiagHeartbeat(path);
        beat.Beat(T0 + TimeSpan.FromSeconds(90), T0);
        Assert.Equal(90, beat.TakePrevious());
        Assert.False(File.Exists(path));
        beat.Beat(T0 + TimeSpan.FromSeconds(30), T0);
        Assert.Null(beat.TakePrevious());
        beat.Beat(T0, T0);
        beat.Stop();
        Assert.Null(beat.TakePrevious());

        var w = Watcher();
        w.PreviousRunHung(90);
        var r = Assert.Single(_reports);
        Assert.Equal("app.hang", r.Rule);
    }

    // ---- Ölçüm istemcisi ----

    [Fact]
    public void DiagIsExemptFromDailyEventLimit()
    {
        var client = new TelemetryClient(new TelemetryOptions(_dir, "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f",
            () => new TelemetryContext("windows", "4.0.0", "Windows 11 26100", "LENOVO 21AH", TvBrand.None, TelemetryChannel.Dev),
            new NullSender()) { Clock = _clock });
        client.ApplyRemoteConfig(TelemetryConfig.Default with { MaxPerDay = 0 });
        client.RecordError("ocr.failed");
        Assert.Equal(0, client.QueuedCount);
        var body = DiagPayload.Build(T0, "app.hang", "main_thread", DiagSeverity.Error, null, null, null, null, null)!;
        client.Record(new DiagReport("app.hang", "main_thread", DiagSeverity.Error, T0, body).ToTelemetryEvent()!);
        Assert.Equal(1, client.QueuedCount);

        string? seen = null;
        client.RemoteConfigReceived += j => seen = j;
        client.ApplyRemoteConfigJson("""{"telemetry":{"diag":{"off":["tr.slow"]}}}""");
        Assert.Contains("tr.slow", seen);
    }

    sealed class NullSender : ITelemetrySender
    {
        public Task<TelemetryResponse> SendAsync(ReadOnlyMemory<byte> body, bool gzipped, CancellationToken cancellationToken) =>
            Task.FromResult(new TelemetryResponse(200, null, null));
    }
}
