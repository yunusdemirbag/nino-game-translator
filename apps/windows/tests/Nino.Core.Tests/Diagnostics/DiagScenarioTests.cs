// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using Nino.Core.Diagnostics;

namespace Nino.Core.Tests.Diagnostics;

/// <summary>Elle ilerletilen saat.</summary>
sealed class FakeClock(DateTimeOffset start) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = start;

    public override DateTimeOffset GetUtcNow() => Now;

    public void Advance(double seconds) => Now += TimeSpan.FromSeconds(seconds);
}

/// <summary>
/// Ölçüm oturumunun senaryoları (Fixtures/Diagnostics/diag-scenarios.json): zaman çizelgesi sahte saatle saniye saniye
/// oynatılır (her saniyede o anın adımları, sonra Tick; son adımda durulur), beklenen bildirimlerle karşılaştırılır.
/// </summary>
public sealed class DiagScenarioTests
{
    static readonly DateTimeOffset T0 = new(2026, 11, 22, 9, 0, 0, TimeSpan.Zero);

    static string FixturePath([CallerFilePath] string here = "") =>
        Path.Combine(Path.GetDirectoryName(here)!, "..", "Fixtures", "Diagnostics", "diag-scenarios.json");

    static JsonArray Scenarios() => JsonNode.Parse(File.ReadAllText(FixturePath()))!["scenarios"]!.AsArray();

    public static TheoryData<string> Names()
    {
        var data = new TheoryData<string>();
        foreach (var s in Scenarios()) data.Add((string)s!["name"]!);
        return data;
    }

    [Fact]
    public void AllNineScenariosArePresent() => Assert.Equal(9, Scenarios().Count);

    [Theory]
    [MemberData(nameof(Names))]
    public void ScenarioProducesExpectedReports(string name)
    {
        var scenario = Scenarios().Single(s => (string)s!["name"]! == name)!.AsObject();
        var (reports, _) = Play(scenario);
        var expected = scenario["expect"]!.AsArray()
            .Select(e => ((long)e!["at"]!, (string)e["rule"]!, (string)e["cause"]!, (string)e["sev"]!)).ToList();
        var actual = reports.Select(r => ((long)(r.At - T0).TotalSeconds, r.Rule, r.Cause, (string)r.Body["sev"]!)).ToList();
        Assert.Equal(expected, actual);
        foreach (var r in reports) Assert.Equal((r.At).ToUnixTimeSeconds(), (long)r.Body["t"]!);
    }

    [Fact]
    public void Ps5NetworkScenarioCarriesStateAndTrail()
    {
        var scenario = Scenarios()[0]!.AsObject();
        var (reports, _) = Play(scenario);
        var body = Assert.Single(reports).Body;
        Assert.Equal("diag", (string)body["k"]!);
        var state = body["state"]!.AsObject();
        Assert.Equal("none", (string)state["net"]!);
        Assert.Equal("down", (string)state["ps5"]!);
        Assert.Equal(13, (long)state["sessionMin"]!);
        Assert.Equal(2, (long)state["retries"]!);
        var trail = body["trail"]!.AsArray();
        Assert.All(trail, s => Assert.InRange((long)s![0]!, -3600, 0));
        Assert.Equal(["net.down", "ps5.drop", "ps5.retry", "ps5.retry"],
            trail.Select(s => (string)s![1]!).Where(c => c != "session.start"));
        Assert.Equal(-181, (long)trail.Single(s => (string)s![1]! == "net.down")![0]!);
        Assert.Equal(2, (long)trail.Last()![2]!);
    }

    internal static (List<DiagReport> Reports, DiagnosticsWatcher Watcher) Play(JsonObject scenario)
    {
        var clock = new FakeClock(T0);
        var fixedState = scenario["state"] as JsonObject;
        var watcher = new DiagnosticsWatcher(new DiagOptions
        {
            Clock = clock,
            State = () => new DiagHostState
            {
                FrameLuma = fixedState?["frameLuma"] is JsonValue l ? l.GetValue<double>() : null,
                FrameSame = fixedState?["frameSame"] is JsonValue s ? s.GetValue<bool>() : null,
                RegionManual = fixedState?["region"] is JsonValue r ? r.GetValue<string>() == "manual" : null,
            },
        });
        var reports = new List<DiagReport>();
        watcher.Reported += reports.Add;
        var drops = (scenario["dropCodes"] as JsonArray)?.Select(d => (string)d!).ToList() ?? [];
        var dropIndex = 0;
        var steps = scenario["timeline"]!.AsArray()
            .Select(s => ((long)s![0]!, (string)s[1]!, s.AsArray().Count > 2 ? (double?)s[2]!.GetValue<double>() : null))
            .ToList();
        var end = steps.Max(s => s.Item1);
        var ps5Up = false;
        for (long t = 0; t <= end; t++)
        {
            clock.Now = T0 + TimeSpan.FromSeconds(t);
            foreach (var (_, code, n) in steps.Where(s => s.Item1 == t))
            {
                Apply(watcher, code, n, () => dropIndex < drops.Count ? drops[dropIndex++] : null);
                if (code == "ps5.connect") ps5Up = true;
                if (code is "ps5.drop" or "session.stop") ps5Up = false;
            }
            // PS5 bağlıyken kareler gelir (zaman çizelgesi kareleri tek tek yazmaz).
            if (ps5Up) watcher.FrameSeen();
            watcher.Tick();
        }
        watcher.FlushPending();
        return (reports, watcher);
    }

    static void Apply(DiagnosticsWatcher w, string code, double? n, Func<string?> nextDrop)
    {
        switch (code)
        {
            case "session.start": w.SessionStarted(); break;
            case "session.stop": w.SessionStopped(); break;
            case "ps5.connect": w.Ps5Connected(); break;
            case "ps5.drop": w.Ps5Dropped(); break;
            case "ps5.retry": w.Ps5Retry((int)(n ?? 1)); break;
            case "ps5.frame": w.FrameRate(n ?? 0); break;
            case "tv.connect": w.TvConnected(); break;
            case "tv.drop": w.TvDropped(nextDrop()); break;
            case "net.down": w.NetworkChanged("none"); break;
            case "net.up": w.NetworkChanged("wifi"); break;
            case "sys.sleep": w.SystemSleeping(); break;
            case "sys.wake": w.SystemWoke(); break;
            case "ocr.text": w.OcrText(); break;
            case "ocr.empty": w.OcrEmpty(); break;
            case "tr.ok": w.TranslationResult(true); break;
            case "tr.error": w.TranslationResult(false, n is { } h ? (int)h : null); break;
            default: w.Note(code, n); break;
        }
    }
}
