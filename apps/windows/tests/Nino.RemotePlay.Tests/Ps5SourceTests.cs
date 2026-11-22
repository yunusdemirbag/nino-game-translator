// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay.Tests;

public class Ps5SourceTests
{
    sealed class Harness : IDisposable
    {
        public FakeBridge Bridge { get; } = new();
        public Ps5Source Source { get; }
        public List<SourceStatus> Statuses { get; } = [];
        public List<string> Lines { get; } = [];
        public List<Ps5Console> Moves { get; } = [];
        readonly RemotePlayLog log = RemotePlayLog.Silent();

        public Harness(Ps5Console? console = null, string? passcode = null, bool awake = true)
        {
            var c = console ?? Samples.Console();
            Bridge.OnDiscover = targets => targets.Contains(c.Host) ? [new FoundPs5(c.Host, c.Name, awake)] : [];
            log.LineAdded += l => { lock (Lines) Lines.Add(l); };
            Source = new Ps5Source(new Ps5SourceOptions
            {
                Console = c,
                AccountId = Samples.Account,
                LoginPasscode = passcode,
                Bridge = Bridge,
                Log = log,
                MoveSearchTargets = () => ["192.168.1.2", "192.168.1.3"],
            });
            Source.StatusChanged += s => { lock (Statuses) Statuses.Add(s); };
            Source.ConsoleMoved += m => { lock (Moves) Moves.Add(m); };
        }

        public SourceStatus[] Snapshot()
        {
            lock (Statuses)
                return Statuses.ToArray();
        }

        public bool WaitFor(Func<SourceStatus, bool> match, int ms = 5000) =>
            Wait.Until(() => Snapshot().Any(match), ms);

        public bool HasLine(string text)
        {
            lock (Lines)
                return Lines.Any(l => l.Contains(text, StringComparison.Ordinal));
        }

        public void Dispose() => Source.Dispose();
    }

    [Fact]
    public void StaleGenerationEventsEmitNothing()
    {
        using var h = new Harness();
        using var gate = new ManualResetEventSlim();
        h.Source.Queue.Post(() => gate.Wait(5000));
        h.Source.Start();
        var fake = new FakeSession();
        var box = h.Source.InstallBoxForTest(h.Source.CurrentGeneration, fake);
        box.OnEvent(BridgeEvent.Connected, 0, null);
        box.OnEvent(BridgeEvent.LoginPasscode, 0, null);
        box.OnEvent(BridgeEvent.Quit, BridgeQuit.Network, null);
        h.Source.Stop();
        gate.Set();
        Wait.Drain(h.Source.Queue);
        Assert.Empty(h.Snapshot());
        Assert.True(Wait.Until(() => Volatile.Read(ref fake.StopCalls) == 1));
        Assert.Equal(0, h.Bridge.SessionCount);
    }

    [Fact]
    public void StopDoesNotBlock()
    {
        using var h = new Harness();
        using var gate = new ManualResetEventSlim();
        h.Source.Start();
        h.Source.Queue.Post(() => gate.Wait(5000));
        var watch = Stopwatch.StartNew();
        h.Source.Stop();
        watch.Stop();
        gate.Set();
        Assert.True(watch.ElapsedMilliseconds < 200, $"stop took {watch.ElapsedMilliseconds} ms");
    }

    [Fact]
    public void ConnectsAndStreams()
    {
        using var h = new Harness();
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        var (request, callbacks, _) = h.Bridge.LastSession;
        Assert.Equal("192.168.1.70", request.Host);
        Assert.Equal(Ps5Source.MaxFps, request.MaxFps);
        Assert.Equal(16, request.RegistKey.Length);
        Assert.Equal(Samples.Account, request.AccountId);
        callbacks.OnEvent(BridgeEvent.Connected, 0, null);
        Assert.True(h.WaitFor(s => s.Phase == SourcePhase.Streaming));
        Assert.Equal(SourcePhase.Connecting, h.Snapshot()[0].Phase);
        Assert.True(h.HasLine("[nino] PS5 oturumu: PS5-123 192.168.1.70 uyanık"));
    }

    [Fact]
    public unsafe void FramesAreDelivered()
    {
        using var h = new Harness();
        var frames = new List<VideoFrame>();
        h.Source.FrameArrived += f => { lock (frames) frames.Add(f); };
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        var cb = h.Bridge.LastSession.Callbacks;
        byte[] px = [10, 20, 30, 255, 0, 0, 0, 0];
        fixed (byte* p = px)
            cb.OnFrame(p, 1, 1, 8);
        Assert.True(Wait.Until(() => { lock (frames) return frames.Count == 1; }));
        lock (frames)
            Assert.Equal(new byte[] { 10, 20, 30, 255 }, frames[0].Bgra);
    }

    [Fact]
    public void NetworkQuitIsRetried()
    {
        using var h = new Harness();
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        var first = h.Bridge.LastSession;
        first.Callbacks.OnEvent(BridgeEvent.Connected, 0, null);
        first.Callbacks.OnEvent(BridgeEvent.Quit, BridgeQuit.Network, null);
        Assert.True(h.WaitFor(s => s is { Phase: SourcePhase.Disconnected, Reason: DisconnectReason.Network }));
        Assert.True(Wait.Until(() => Volatile.Read(ref first.Session.StopCalls) == 1));
        // İlk gecikme 2 sn.
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 2, 6000));
        Assert.True(h.HasLine("Oturum kapandı: neden 3 (Network)"));
    }

    [Fact]
    public void UnansweredSearchMakesNotFound()
    {
        using var h = new Harness();
        h.Bridge.OnDiscover = _ => [];
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        Assert.True(h.HasLine("192.168.1.70 keşif isteğine cevap vermedi; bağlantı yine de deneniyor"));
        h.Bridge.LastSession.Callbacks.OnEvent(BridgeEvent.Quit, BridgeQuit.Network, null);
        Assert.True(h.WaitFor(s => s is { Reason: DisconnectReason.NotFound, Detail: "192.168.1.70" }));
    }

    [Fact]
    public void RegistrationRejectionGivesUp()
    {
        using var h = new Harness();
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        var cb = h.Bridge.LastSession.Callbacks;
        cb.OnLog(BridgeLogLevel.Error, "Reported Application Reason: 0x80108b26 (unknown)");
        cb.OnEvent(BridgeEvent.Quit, BridgeQuit.Other, SessionRules.UnknownSessionRequestError);
        Assert.True(h.WaitFor(s => s.Reason == DisconnectReason.RegistrationInvalid));
        Thread.Sleep(2500);
        Assert.Equal(1, h.Bridge.SessionCount); // yeniden denenmez
    }

    [Fact]
    public void UnknownSessionRequestWithoutHintIsUncodedRejection()
    {
        using var h = new Harness();
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        h.Bridge.LastSession.Callbacks.OnEvent(BridgeEvent.Quit, BridgeQuit.Other, SessionRules.UnknownSessionRequestError);
        Assert.True(h.WaitFor(s => s is { Reason: DisconnectReason.Rejected, Detail: null }));
    }

    [Fact]
    public void MissingPasscodeStops()
    {
        using var h = new Harness();
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        var s = h.Bridge.LastSession;
        s.Callbacks.OnEvent(BridgeEvent.LoginPasscode, 0, null);
        Assert.True(h.WaitFor(x => x.Reason == DisconnectReason.LoginPasscode));
        Assert.True(Wait.Until(() => Volatile.Read(ref s.Session.StopCalls) == 1));
        Thread.Sleep(2500);
        Assert.Equal(1, h.Bridge.SessionCount);
    }

    [Fact]
    public void StoredPasscodeIsSentOnceThenIncorrect()
    {
        using var h = new Harness(passcode: " 1234 ");
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        var s = h.Bridge.LastSession;
        s.Callbacks.OnEvent(BridgeEvent.LoginPasscode, 0, null);
        Assert.True(Wait.Until(() => { lock (s.Session.Passcodes) return s.Session.Passcodes.Count == 1; }));
        lock (s.Session.Passcodes)
            Assert.Equal(new byte[] { 0x31, 0x32, 0x33, 0x34 }, s.Session.Passcodes[0]);
        s.Callbacks.OnEvent(BridgeEvent.LoginPasscode, 1, null);
        Assert.True(h.WaitFor(x => x.Reason == DisconnectReason.LoginPasscodeIncorrect));
        lock (s.Session.Passcodes)
            Assert.Single(s.Session.Passcodes);
    }

    [Fact]
    public void SessionStartFailureRetriesWithLastError()
    {
        using var h = new Harness();
        h.Bridge.FailSessionStart = true;
        h.Source.Start();
        Assert.True(h.WaitFor(s => s is { Reason: DisconnectReason.Other, Detail: "Session init failed: Unknown" }));
        Assert.True(h.HasLine("PS5 oturumu açılamadı (192.168.1.70): Session init failed: Unknown"));
    }

    [Fact]
    public void MovedConsoleIsFollowed()
    {
        var c = Samples.Console();
        using var h = new Harness(c);
        h.Bridge.OnDiscover = targets => targets.Contains("192.168.1.3") ? [new FoundPs5("192.168.1.3", c.Name, true)] : [];
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
        Assert.Equal("192.168.1.3", h.Bridge.LastSession.Request.Host);
        Assert.Equal("192.168.1.3", h.Source.Console.Host);
        lock (h.Moves)
            Assert.Equal("192.168.1.3", Assert.Single(h.Moves).Host);
        Assert.True(h.HasLine("PS5 yeni adreste: 192.168.1.70 -> 192.168.1.3"));
    }

    [Fact]
    public void RestingConsoleIsWokenWithRegistKeyCredential()
    {
        var c = Samples.Console();
        using var h = new Harness(c, awake: false);
        int searches = 0;
        h.Bridge.OnDiscover = targets =>
            targets.Contains(c.Host) ? [new FoundPs5(c.Host, c.Name, Interlocked.Increment(ref searches) > 1)] : [];
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1, 8000));
        lock (h.Bridge.Wakes)
            Assert.Equal(("192.168.1.70", 0x1a2b3c4dUL), Assert.Single(h.Bridge.Wakes));
        Assert.True(h.HasLine("dinlenmede, uyandırılıyor"));
    }

    [Fact]
    public void MissingLibraryFailsStartAndLeavesNothingRunning()
    {
        using var h = new Harness();
        h.Bridge.InitError = new NativeLibraryMissingException("test");
        Assert.Throws<NativeLibraryMissingException>(h.Source.Start);
        Wait.Drain(h.Source.Queue);
        Assert.Empty(h.Snapshot());
        h.Bridge.InitError = null;
        h.Source.Start();
        Assert.True(Wait.Until(() => h.Bridge.SessionCount == 1));
    }

    [Fact]
    public void ReconnectNowWhileStoppedDoesNothing()
    {
        using var h = new Harness();
        h.Source.ReconnectNow();
        Wait.Drain(h.Source.Queue);
        Assert.Equal(0, h.Bridge.SessionCount);
        Assert.Empty(h.Snapshot());
    }

    [Fact]
    public void SourceNeedsEightByteAccount() =>
        Assert.Throws<ArgumentException>(() => new Ps5Source(new Ps5SourceOptions
        {
            Console = Samples.Console(),
            AccountId = [1, 2, 3, 4],
            Bridge = new FakeBridge(),
        }));

    [NeedsNative]
    public void NativeSessionToLoopbackReportsDisconnect()
    {
        var statuses = new List<SourceStatus>();
        var console = new Ps5Console("127.0.0.1", "PS5", Enumerable.Repeat((byte)0x31, 16).ToArray(),
                                     Enumerable.Repeat((byte)0x01, 16).ToArray());
        var source = new Ps5Source(new Ps5SourceOptions
        {
            Console = console,
            AccountId = Samples.Account,
            Bridge = NativeBridge.Shared,
            MoveSearchTargets = () => ["127.0.0.1"],
        });
        source.StatusChanged += s => { lock (statuses) statuses.Add(s); };
        source.Start();
        Assert.True(Wait.Until(() => { lock (statuses) return statuses.Any(s => s.Phase == SourcePhase.Disconnected); }, 15000));
        lock (statuses)
            Assert.NotEqual(DisconnectReason.Stopped, statuses.First(s => s.Phase == SourcePhase.Disconnected).Reason);
        var watch = Stopwatch.StartNew();
        source.Stop();
        Assert.True(watch.ElapsedMilliseconds < 200);
        source.Dispose();
        Thread.Sleep(3000); // bekleyen yeniden deneme çökmemeli
    }

    [WithoutNative]
    public void MissingNativeLibraryGivesClearError()
    {
        Assert.False(NativeBridge.Shared.IsAvailable());
        var e = Assert.Throws<NativeLibraryMissingException>(NativeBridge.Shared.EnsureInitialized);
        Assert.Contains("nino_native", e.Message);
        var source = new Ps5Source(new Ps5SourceOptions { Console = Samples.Console(), AccountId = Samples.Account });
        Assert.Throws<NativeLibraryMissingException>(source.Start);
        source.Dispose();
    }

    [NeedsNative]
    public void NativeInitIsRepeatable()
    {
        NativeBridge.Shared.EnsureInitialized();
        NativeBridge.Shared.EnsureInitialized();
        Assert.True(NativeBridge.Shared.IsAvailable());
    }
}
