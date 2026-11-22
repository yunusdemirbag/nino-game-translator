// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Diagnostics;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Core.Telemetry;
using Nino.RemotePlay;

namespace Nino.Shell.Tests;

public sealed class DiagnosticsWiringTests : IDisposable
{
    const string Install = "8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f";
    readonly string _data = Directory.CreateTempSubdirectory("nino-diag-shell-").FullName;
    readonly FakeTelemetrySender _sender = new();

    public void Dispose()
    {
        try { Directory.Delete(_data, recursive: true); } catch (IOException) { }
    }

    sealed class QuietProbe : IResourceProbe
    {
        public (double MemMB, double CpuPercent)? Read() => (300, 5);
    }

    NinoController Open(World w, Action<Action>? post = null) =>
        new(w.Services, w.Secrets, w.SettingsStore, w.Sleep, w.Text, post ?? (a => a()), new ShellOptions
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
                Install = Install,
                Clock = new TimersClock(w.Timers),
                RunLoop = false,
                ResourceProbe = new QuietProbe(),
            },
        });

    static World Ready()
    {
        var w = new World(new AppSettings { Output = SubtitleOutput.Tv }).WithPs5().WithTv();
        w.Services.Model.Installed = true;
        return w;
    }

    async Task<List<System.Text.Json.Nodes.JsonObject>> Diags(NinoController c)
    {
        await c.Telemetry!.Client.FlushAsync(ignoreBackoff: true);
        return _sender.Of("diag").ToList();
    }

    [Fact]
    public async Task Ps5DropThatDoesNotReturnIsReportedOnceWithCodesOnly()
    {
        var w = Ready();
        var c = Open(w);
        w.Timers.Advance(TimeSpan.FromSeconds(61));
        await c.StartAsync();
        var src = w.Services.Ps5Sessions[0];
        src.Status(SourceStatus.Streaming);
        src.Frame(World.Frame());
        w.Timers.Advance(TimeSpan.FromSeconds(10));
        var dropAt = w.Timers.Now;
        src.Status(SourceStatus.Down(DisconnectReason.Network, "10.0.0.5 zaman aşımı"));
        src.Status(SourceStatus.Connecting);
        w.Timers.Advance(TimeSpan.FromSeconds(181));
        w.Timers.Advance(TimeSpan.FromSeconds(301));

        var diag = Assert.Single(await Diags(c));
        Assert.Equal("ps5.no_return", (string?)diag["rule"]);
        Assert.Equal("network_lost", (string?)diag["cause"]);
        Assert.Equal("error", (string?)diag["sev"]);
        Assert.Equal((dropAt + TimeSpan.FromSeconds(180)).ToUnixTimeSeconds(), (long)diag["t"]!);
        Assert.Equal(1, (long)diag["state"]!["retries"]!);
        var codes = diag["trail"]!.AsArray().Select(s => (string?)s![1]).ToList();
        Assert.Contains("ps5.drop", codes);
        Assert.Contains("ps5.retry", codes);
        Assert.Equal("0.0.0", (string?)diag["ver"]!["core"]);
        Assert.Equal("lg", (string?)diag["tv"]!["brand"]);
        var all = diag.ToJsonString();
        Assert.DoesNotContain("10.0.0.5", all);
        Assert.DoesNotContain("192.168", all);
        Assert.DoesNotContain("PS5-789", all);
        await c.DisposeAsync();
    }

    [Fact]
    public async Task UserStopIsNotADiagnosis()
    {
        var w = Ready();
        var c = Open(w);
        w.Timers.Advance(TimeSpan.FromSeconds(61));
        await c.StartAsync();
        var src = w.Services.Ps5Sessions[0];
        src.Status(SourceStatus.Streaming);
        c.Stop();
        w.Timers.Advance(TimeSpan.FromSeconds(600));
        Assert.Empty(await Diags(c));
    }

    [Fact]
    public async Task TvReplacedThreeTimesIsFlappingReplaced()
    {
        var w = Ready();
        var c = Open(w);
        w.Timers.Advance(TimeSpan.FromSeconds(61));
        await c.StartAsync();
        var server = w.Services.Server;
        for (var i = 0; i < 3; i++)
        {
            server.LinkUp(i, TvLinkKind.AndroidTv);
            w.Timers.Advance(TimeSpan.FromSeconds(20));
            server.LinkDown(i, TvLinkKind.AndroidTv, TvLinkEndReason.Replaced);
        }
        c.Stop();
        await c.DisposeAsync();

        var diag = Assert.Single(await Diags(c));
        Assert.Equal("tv.flapping", (string?)diag["rule"]);
        Assert.Equal("replaced", (string?)diag["cause"]);
        Assert.Equal(3, (long)diag["state"]!["drops"]!);
        Assert.Equal("nino", (string?)diag["state"]!["proto"]);
        Assert.Equal(20, (long)diag["state"]!["avgUpSec"]!);
    }

    [Fact]
    public async Task RemoteConfigFromEventsResponseTurnsARuleOff()
    {
        var w = Ready();
        var c = Open(w);
        _sender.Answer = """{"ok":true,"accepted":1,"dropped":0,"config":{"telemetry":{"enabled":true,"diag":{"off":["tv.flapping"]}}}}""";
        await c.Telemetry!.Client.FlushAsync(ignoreBackoff: true);
        Assert.True(c.Diagnostics!.Config.IsOff("tv.flapping"));
        w.Timers.Advance(TimeSpan.FromSeconds(61));
        await c.StartAsync();
        for (var i = 0; i < 3; i++)
        {
            w.Services.Server.LinkUp(i, TvLinkKind.AndroidTv);
            w.Services.Server.LinkDown(i, TvLinkKind.AndroidTv, TvLinkEndReason.WriteFailed);
        }
        c.Stop();
        await c.DisposeAsync();
        Assert.Empty(await Diags(c));
    }

    [Fact]
    public async Task BlockedUiThreadIsAHangAndThePreviousRunIsReportedOnNextLaunch()
    {
        var w = new World();
        var queued = new List<Action>();
        var c = Open(w, a => { lock (queued) queued.Add(a); });
        w.Timers.Advance(TimeSpan.FromSeconds(70));
        var diag = Assert.Single(await Diags(c));
        Assert.Equal(("app.hang", "main_thread"), ((string?)diag["rule"], (string?)diag["cause"]));
        var alive = Path.Combine(_data, "telemetry", DiagHeartbeat.FileName);
        Assert.True(File.Exists(alive));
        // Canlı bildirilen askı damgada işaretli: süreç şimdi öldürülse bir sonraki açılış ikinci kez bildirmez.
        Assert.Contains("\"reported\":true", File.ReadAllText(alive));
        Assert.Null(new DiagHeartbeat(alive).TakePrevious());

        // Askıdayken süreç bitti: bir sonraki açılışta önceki çalışmanın askısı bildirilir.
        File.WriteAllText(Path.Combine(_data, "telemetry", DiagHeartbeat.FileName),
            $$"""{"alive":{{w.Timers.Now.ToUnixTimeSeconds()}},"ui":{{w.Timers.Now.ToUnixTimeSeconds() - 120}}}""");
        var w2 = new World();
        var next = Open(w2);
        var report = Assert.Single(next.Diagnostics!.Recent);
        Assert.Equal("app.hang", report.Rule);
        Assert.Equal(120, (long)report.Body["state"]!["blockedSec"]!);
        await next.DisposeAsync();
        Assert.False(File.Exists(Path.Combine(_data, "telemetry", DiagHeartbeat.FileName)));
    }

    [Theory]
    [InlineData(DisconnectReason.Network, "network_lost")]
    [InlineData(DisconnectReason.ConsoleAsleep, "ps5_standby")]
    [InlineData(DisconnectReason.InUse, "kicked")]
    [InlineData(DisconnectReason.Rejected, "ps5_closed")]
    [InlineData(DisconnectReason.Other, null)]
    public void Ps5Causes(DisconnectReason reason, string? cause) => Assert.Equal(cause, NinoController.Ps5Cause(reason));
}
