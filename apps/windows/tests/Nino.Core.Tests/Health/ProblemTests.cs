// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Health;
using Nino.Core.Support;
using Nino.Core.Tests.Data;

namespace Nino.Core.Tests.Health;

public sealed class ProblemLogTests
{
    static readonly DateTimeOffset At = new(2026, 11, 22, 21, 4, 0, TimeSpan.Zero);

    [Fact]
    public void SupportLine_Example()
    {
        var r = new ProblemRecord
        {
            Date = At, Kind = ProblemKind.Ps5Dropped, Reason = "Unreachable", StreamedMinutes = 44.4,
            LossPerMinute = 12.2, StallsPerMinute = 0.43, Network = "wifi", Game = "GTA 6",
        };
        Assert.Equal($"22.11 21:04 {r.TurkishName} (Unreachable) · 44 dk oynandı · ağ wifi · kayıp 12/dk, durma 0.4/dk · GTA 6",
            r.SupportLine(TimeZoneInfo.Utc));
        var tv = new ProblemRecord { Date = At, Kind = ProblemKind.TvDropped };
        Assert.Equal("22.11 21:04 " + tv.TurkishName, tv.SupportLine(TimeZoneInfo.Utc));
    }

    [Fact]
    public void File_KeepsLast40_CamelCase_NoNulls()
    {
        using var temp = new TempFolder();
        var log = ProblemLog.InFolder(temp.Path);
        for (var i = 0; i < 45; i++)
            log.Add(new ProblemRecord { Date = At.AddMinutes(i), Kind = ProblemKind.NetworkLost, Network = "wifi", Game = "Şehir" });
        Assert.Equal(40, log.All.Count);
        Assert.Equal(At.AddMinutes(5), log.All[0].Date);
        var json = File.ReadAllText(temp.File(ProblemLog.FileName));
        Assert.Contains("\"kind\":\"networkLost\"", json);
        Assert.Contains("\"date\":", json);
        Assert.Contains("Şehir", json);
        Assert.DoesNotContain("reason", json);
        Assert.DoesNotContain("streamedMinutes", json);
        Assert.False(File.Exists(temp.File(ProblemLog.FileName + ".tmp")));

        var again = ProblemLog.InFolder(temp.Path);
        Assert.Equal(40, again.All.Count);
        Assert.Equal(log.All[^1].Id, again.All[^1].Id);
        Assert.Equal(3, again.Since(At.AddMinutes(42)).Count);
        Assert.Equal(At.AddMinutes(44), again.Newest(8)[0].Date);

        again.Clear();
        Assert.Empty(again.All);
        Assert.False(File.Exists(temp.File(ProblemLog.FileName)));
    }

    [Fact]
    public void BrokenFile_IsSilent()
    {
        using var temp = new TempFolder();
        File.WriteAllText(temp.File(ProblemLog.FileName), "{bozuk");
        Assert.Empty(ProblemLog.InFolder(temp.Path).All);
        var memory = ProblemLog.InFolder(null);
        memory.Add(new ProblemRecord { Kind = ProblemKind.TvDropped });
        Assert.Single(memory.All);
    }
}

/// <summary>Elle bitirilen beklemeler.</summary>
sealed class ManualDelays
{
    public readonly List<(TimeSpan Wait, TaskCompletionSource Done, CancellationToken Token)> Waits = [];

    public Task Delay(TimeSpan wait, CancellationToken token)
    {
        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        token.Register(() => tcs.TrySetCanceled());
        lock (Waits) Waits.Add((wait, tcs, token));
        return tcs.Task;
    }

    public IReadOnlyList<TimeSpan> Pending()
    {
        lock (Waits) return Waits.Where(w => !w.Done.Task.IsCompleted).Select(w => w.Wait).ToList();
    }

    public void FinishAll()
    {
        List<TaskCompletionSource> list;
        lock (Waits) list = Waits.Where(w => !w.Done.Task.IsCompleted).Select(w => w.Done).ToList();
        foreach (var t in list) t.TrySetResult();
    }
}

sealed class FakeNetwork(NetworkKind kind) : INetworkWatch
{
    public NetworkKind Kind = kind;
    public NetworkKind Read() => Kind;
    public event Action? Changed;
    public void Raise() => Changed?.Invoke();
}

sealed class FakeHost : IProblemWatcherHost
{
    readonly object _gate = new();
    public bool IsTranslating { get; set; } = true;
    public bool IsPictureArriving { get; set; } = true;
    public bool IsSendingToTv { get; set; } = true;
    public int ConnectedTvs { get; set; } = 1;
    public bool AutoReportEnabled { get; set; } = true;
    public string? Game { get; set; } = "GTA 6";
    public string? Title { get; set; } = "PS5 uzun süredir yanıt vermiyor";
    public readonly List<string> Logs = [];
    public int Changes;
    public string? CauseTitle(NetworkKind network) => Title;

    public ReportBody? BuildAutoReport(string text) => new()
    {
        Install = "install-1234", App = "1.0.0", Language = "tr", Text = text, Device = "app: 1.0.0",
    };

    public void Log(string line)
    {
        lock (_gate) Logs.Add(line);
    }

    public void ProblemsChanged() => Changes++;

    public void Post(Action action)
    {
        lock (_gate) action();
    }

    public string[] LogSnapshot()
    {
        lock (_gate) return Logs.ToArray();
    }
}

public sealed class ProblemWatcherTests
{
    static readonly DateTimeOffset Start = new(2026, 11, 22, 18, 0, 0, TimeSpan.Zero);

    sealed class World
    {
        public readonly FakeClock Clock = new(Start);
        public readonly FakeHost Host = new();
        public readonly ManualDelays Delays = new();
        public readonly FakeNetwork Network = new(NetworkKind.Wifi);
        public readonly HealthRecorder Recorder;
        public readonly ProblemLog Problems = ProblemLog.InFolder(null);
        public readonly List<ReportBody> Sent = [];
        public readonly AutoReporter Reporter;
        public readonly ProblemWatcher Watcher;

        public World()
        {
            Recorder = new HealthRecorder(Clock);
            Reporter = new AutoReporter(null, (b, _) =>
            {
                lock (Sent) Sent.Add(b);
                return Task.FromResult(new ReportResult(ReportStatus.Sent, "r-1"));
            }, Clock);
            Watcher = new ProblemWatcher(Host, Recorder, Problems, Reporter, Network, watchNetworkEvents: true,
                Delays.Delay, Clock);
            Watcher.Start();
            Recorder.SessionStarted();
            Watcher.SessionStarted();
            Recorder.Connecting();
            Recorder.PictureArrived();
        }

        public int SentCount
        {
            get { lock (Sent) return Sent.Count; }
        }
    }

    static void WaitFor(Func<bool> condition)
    {
        var until = DateTime.UtcNow.AddSeconds(5);
        while (!condition() && DateTime.UtcNow < until) Thread.Sleep(5);
        Assert.True(condition());
    }

    [Fact]
    public void Ps5NotBack_RecordsAndReportsOnce()
    {
        var w = new World();
        w.Clock.Advance(TimeSpan.FromMinutes(31));
        w.Recorder.Disconnected("Unreachable");
        w.Host.IsPictureArriving = false;
        w.Watcher.Ps5Dropped("Unreachable", wasStreaming: true);
        w.Watcher.Ps5Dropped("Unreachable", wasStreaming: false);
        Assert.Single(w.Problems.All);
        Assert.Equal(ProblemKind.Ps5Dropped, w.Problems.All[0].Kind);
        Assert.Equal([ProblemWatcher.Ps5NotBack], w.Delays.Pending());

        w.Delays.FinishAll();
        WaitFor(() => w.Problems.All.Count == 2);
        var last = w.Problems.All[^1];
        Assert.Equal(ProblemKind.Ps5Unreachable, last.Kind);
        Assert.Equal("Unreachable", last.Reason);
        Assert.Equal("wifi", last.Network);
        Assert.Equal("GTA 6", last.Game);
        WaitFor(() => w.SentCount == 1);
        var body = w.Sent[0];
        Assert.StartsWith("[Otomatik]", body.Text);
        Assert.Contains("Muhtemel sebep: PS5 uzun süredir yanıt vermiyor", body.Text);
        Assert.Contains("GTA 6", body.Text);
        Assert.Equal("auto", body.Kind);
        Assert.Null(body.Log);
        WaitFor(() => w.Host.LogSnapshot().Contains(ProblemWatcher.LogAutoSent));
        Assert.Contains(w.Host.LogSnapshot(), l => l.StartsWith("sorun: ") && l.Contains(new ProblemRecord { Kind = ProblemKind.Ps5Dropped }.TurkishName + " (Unreachable)"));
        Assert.Equal(2, w.Host.Changes);

        w.Watcher.SessionEnded();
        Thread.Sleep(30);
        Assert.Equal(1, w.SentCount);
    }

    [Fact]
    public void Ps5Back_CancelsTimer_NoReport()
    {
        var w = new World();
        w.Recorder.Disconnected("Unreachable");
        w.Watcher.Ps5Dropped("Unreachable", wasStreaming: true);
        w.Recorder.PictureArrived();
        w.Watcher.Ps5Back();
        Assert.Empty(w.Delays.Pending());
        w.Delays.FinishAll();
        Thread.Sleep(30);
        Assert.DoesNotContain(w.Problems.All, p => p.Kind == ProblemKind.Ps5Unreachable);
        Assert.Single(w.Problems.All);
    }

    [Fact]
    public void NetworkLost_CountedOnce_ReportedAtSessionEnd()
    {
        var w = new World();
        w.Network.Kind = NetworkKind.Offline;
        w.Network.Raise();
        w.Network.Raise();
        Assert.Single(w.Problems.All);
        Assert.Equal(ProblemKind.NetworkLost, w.Problems.All[0].Kind);
        Assert.Equal(1, w.Recorder.Snapshot().NetworkLosses);
        Assert.Equal(0, w.SentCount);
        w.Watcher.SessionEnded();
        WaitFor(() => w.SentCount == 1);
    }

    [Fact]
    public void CleanSession_AndSettingOff_SendNothing()
    {
        var w = new World();
        w.Watcher.SessionEnded();
        Thread.Sleep(30);
        Assert.Equal(0, w.SentCount);

        var off = new World();
        off.Host.AutoReportEnabled = false;
        off.Watcher.NetworkChanged(NetworkKind.Offline);
        off.Watcher.SessionEnded();
        Thread.Sleep(30);
        Assert.Single(off.Problems.All);
        Assert.Equal(0, off.SentCount);
    }

    [Fact]
    public void TvDropped_AfterTwentySeconds()
    {
        var w = new World();
        w.Host.ConnectedTvs = 0;
        w.Watcher.TvCountChanged(0);
        w.Host.ConnectedTvs = 1;
        w.Watcher.TvCountChanged(1);
        Assert.Empty(w.Delays.Pending());
        w.Delays.FinishAll();
        Thread.Sleep(20);
        Assert.Empty(w.Problems.All);

        w.Host.ConnectedTvs = 0;
        w.Watcher.TvCountChanged(0);
        Assert.Equal([ProblemWatcher.TvGone], w.Delays.Pending());
        w.Delays.FinishAll();
        WaitFor(() => w.Problems.All.Count == 1);
        Assert.Equal(ProblemKind.TvDropped, w.Problems.All[0].Kind);
        Assert.Equal(1, w.Recorder.Snapshot().TvDrops);
    }

    [Fact]
    public void NotTranslating_RecordsNothing()
    {
        var w = new World();
        w.Host.IsTranslating = false;
        w.Watcher.Ps5Dropped("Unreachable", wasStreaming: true);
        w.Watcher.NetworkChanged(NetworkKind.Offline);
        Assert.Empty(w.Problems.All);
        Assert.Empty(w.Delays.Pending());
    }

    [Fact]
    public void AutoReport_DefaultOn() => Assert.True(new Nino.Core.Settings.AppSettings().AutoReport);
}

public sealed class AutoReporterTests
{
    static readonly DateTimeOffset Day1 = new(2026, 11, 22, 10, 0, 0, TimeSpan.Zero);

    static ReportBody Body(string text = "t") => new()
    {
        Install = "install-1234", App = "1.0.0", Language = "tr", Text = text, Contact = "a@b", Log = "günlük",
        Images = [SupportImage.Jpeg([1, 2, 3])],
    };

    [Fact]
    public async Task ThreePerDay_LimitPersists()
    {
        using var temp = new TempFolder();
        var clock = new FakeClock(Day1);
        var sent = new List<string>();
        Task<ReportResult> Send(ReportBody b, CancellationToken _)
        {
            sent.Add(b.ToJsonText());
            return Task.FromResult(new ReportResult(ReportStatus.Sent));
        }
        var reporter = AutoReporter.InFolder(temp.Path, Send, clock);
        var results = new List<bool>();
        for (var i = 0; i < 5; i++) results.Add(await reporter.SendAsync(Body("t" + i)));
        Assert.Equal([true, true, true, false, false], results);
        Assert.Equal(3, sent.Count);
        using (var doc = JsonDocument.Parse(sent[0]))
        {
            var root = doc.RootElement;
            Assert.Equal("auto", root.GetProperty("kind").GetString());
            Assert.False(root.TryGetProperty("log", out _));
            Assert.False(root.TryGetProperty("contact", out _));
            Assert.Equal(0, root.GetProperty("images").GetArrayLength());
        }
        var fresh = AutoReporter.InFolder(temp.Path, Send, clock);
        Assert.False(fresh.CanSendToday);
        Assert.False(await fresh.SendAsync(Body()));
        clock.Advance(TimeSpan.FromHours(24));
        Assert.True(await fresh.SendAsync(Body()));
        var file = File.ReadAllText(temp.File(AutoReporter.FileName));
        Assert.Contains("\"Day\":\"2026-11-23\"", file);
        Assert.Contains("\"Sent\":1", file);
        Assert.DoesNotContain("Pending", file);
    }

    [Fact]
    public async Task Offline_PendingSentNextLaunchOnce()
    {
        using var temp = new TempFolder();
        var clock = new FakeClock(Day1);
        var offline = AutoReporter.InFolder(temp.Path, (_, _) => throw new HttpRequestException("yok"), clock);
        Assert.False(await offline.SendAsync(Body()));
        Assert.True(offline.HasPending);

        var count = 0;
        var next = AutoReporter.InFolder(temp.Path, (_, _) =>
        {
            count++;
            return Task.FromResult(new ReportResult(ReportStatus.Sent));
        }, clock);
        Assert.True(next.HasPending);
        Assert.True(await next.SendPendingAsync());
        Assert.False(await next.SendPendingAsync());
        Assert.Equal(1, count);
        Assert.False(AutoReporter.InFolder(temp.Path, (_, _) => Task.FromResult(ReportResult.Failed), clock).HasPending);
    }

    [Fact]
    public void NeverEndingSend_PendingSeenByNewObject()
    {
        using var temp = new TempFolder();
        var clock = new FakeClock(Day1);
        var never = new TaskCompletionSource<ReportResult>();
        var reporter = AutoReporter.InFolder(temp.Path, (_, _) => never.Task, clock);
        var task = reporter.SendAsync(Body());
        Assert.False(task.IsCompleted);
        Assert.True(AutoReporter.InFolder(temp.Path, (_, _) => never.Task, clock).HasPending);
    }

    [Fact]
    public async Task Rejected_NotRetried()
    {
        using var temp = new TempFolder();
        var clock = new FakeClock(Day1);
        var reporter = AutoReporter.InFolder(temp.Path,
            (_, _) => Task.FromResult(new ReportResult(ReportStatus.Rejected)), clock);
        Assert.False(await reporter.SendAsync(Body()));
        Assert.False(reporter.HasPending);
        Assert.False(AutoReporter.InFolder(temp.Path, (_, _) => Task.FromResult(ReportResult.Failed), clock).HasPending);
    }
}
