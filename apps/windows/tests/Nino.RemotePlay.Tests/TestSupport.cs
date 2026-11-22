// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay.Tests;

/// <summary>Yerel köprü yüklenemiyorsa (Mac'te derlenmediyse, DLL'siz derleme) atlanan test.</summary>
public sealed class NeedsNativeAttribute : FactAttribute
{
    public NeedsNativeAttribute()
    {
        if (NativeBridge.FindLibrary() is null)
            Skip = "nino_native bulunamadı";
    }
}

/// <summary>Yalnız yerel köprü yokken koşan test (köprü varsa atlanır).</summary>
public sealed class WithoutNativeAttribute : FactAttribute
{
    public WithoutNativeAttribute()
    {
        if (NativeBridge.FindLibrary() is not null)
            Skip = "nino_native var";
    }
}

/// <summary>Sahte köprü: arama yanıtları, kayıt sonucu ve oturumlar testten verilir.</summary>
sealed class FakeBridge : IRemotePlayBridge
{
    public Func<IReadOnlyList<string>, IReadOnlyList<FoundPs5>> OnDiscover { get; set; } = _ => [];
    public Func<int, BridgeRegistration>? OnRegister { get; set; }
    public List<string> RegisterErrorLines { get; } = [];
    public bool FailSessionStart { get; set; }
    public List<(BridgeSessionRequest Request, IBridgeSessionCallbacks Callbacks, FakeSession Session)> Sessions { get; } = [];
    public List<(string Host, ulong Credential)> Wakes { get; } = [];
    public int RegisterCalls;
    public int DiscoverCalls;

    public Exception? InitError { get; set; }

    public bool IsAvailable() => InitError is null;

    public void EnsureInitialized()
    {
        if (InitError is not null)
            throw InitError;
    }

    public IReadOnlyList<FoundPs5> Discover(IReadOnlyList<string> targets, int timeoutMs)
    {
        Interlocked.Increment(ref DiscoverCalls);
        return OnDiscover(targets);
    }

    public void Wake(string host, ulong credential)
    {
        lock (Wakes)
            Wakes.Add((host, credential));
    }

    public BridgeRegistration Register(string host, byte[] accountId, uint pin, Action<BridgeLogLevel, string>? log)
    {
        int n = Interlocked.Increment(ref RegisterCalls);
        foreach (string line in RegisterErrorLines)
            log?.Invoke(BridgeLogLevel.Error, line);
        return OnRegister?.Invoke(n) ?? new BridgeRegistration(1, 0);
    }

    public IBridgeSession? StartSession(BridgeSessionRequest request, IBridgeSessionCallbacks callbacks)
    {
        if (FailSessionStart)
        {
            callbacks.OnLog(BridgeLogLevel.Error, "Session init failed: Unknown");
            return null;
        }
        var session = new FakeSession();
        lock (Sessions)
            Sessions.Add((request, callbacks, session));
        return session;
    }

    public (BridgeSessionRequest Request, IBridgeSessionCallbacks Callbacks, FakeSession Session) LastSession
    {
        get
        {
            lock (Sessions)
                return Sessions[^1];
        }
    }

    public int SessionCount
    {
        get
        {
            lock (Sessions)
                return Sessions.Count;
        }
    }
}

sealed class FakeSession : IBridgeSession
{
    public List<byte[]> Passcodes { get; } = [];
    public int StopCalls;

    public int SendLoginPasscode(byte[] passcode)
    {
        lock (Passcodes)
            Passcodes.Add(passcode);
        return 0;
    }

    public void Stop() => Interlocked.Increment(ref StopCalls);
}

static class Wait
{
    public static bool Until(Func<bool> condition, int timeoutMs = 5000)
    {
        var until = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < until)
        {
            if (condition())
                return true;
            Thread.Sleep(10);
        }
        return condition();
    }

    /// <summary>Kuyruğun şimdiye kadarki işleri bitene dek bekler.</summary>
    public static void Drain(SerialQueue queue)
    {
        using var done = new ManualResetEventSlim();
        queue.Post(done.Set);
        Assert.True(done.Wait(5000), "queue did not drain");
    }
}

static class Samples
{
    public static byte[] Account => [1, 1, 1, 1, 1, 1, 1, 1];

    public static Ps5Console Console(string host = "192.168.1.70", string name = "PS5-123") =>
        new(host, name, "1a2b3c4d\0\0\0\0\0\0\0\0"u8.ToArray(), Enumerable.Repeat((byte)2, 16).ToArray());
}
