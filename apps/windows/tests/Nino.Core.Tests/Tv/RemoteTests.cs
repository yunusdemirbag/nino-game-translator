// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using Nino.Core.Link;
using Nino.Core.Tests.Link;
using Nino.Core.Tv;

namespace Nino.Core.Tests.Tv;

/// <summary>Sahte uzaktan kumanda: önplan yanıtlarını sırayla verir, açmaları sayar.</summary>
sealed class FakeRemote(FakeTvSide side, string key) : ITvRemote
{
    public string Key => key;

    public Task LaunchAsync(string parametersJson, CancellationToken ct = default)
    {
        lock (side) side.Launches.Add(parametersJson);
        return side.FailLaunch ? throw new TvRemoteException("launch", true) : Task.CompletedTask;
    }

    public Task<string> ForegroundAppAsync(CancellationToken ct = default)
    {
        lock (side)
        {
            if (side.Foreground.Count == 0) return Task.FromResult("");
            var next = side.Foreground.Dequeue();
            return next is null ? throw new TvRemoteException("closed") : Task.FromResult(next);
        }
    }

    public ValueTask DisposeAsync()
    {
        lock (side) side.Closed++;
        return ValueTask.CompletedTask;
    }
}

sealed class FakeTvSide
{
    public readonly List<string> Connects = [];
    public readonly List<string> Launches = [];
    public readonly Queue<string?> Foreground = new();
    public readonly Queue<bool> ConnectWorks = new();
    public readonly Queue<string> Tokens = new();
    public readonly List<string> KeysUsed = [];
    public bool FailLaunch;
    public int Closed;

    public Task<ITvRemote> Connect(string host, string key, CancellationToken ct)
    {
        lock (this)
        {
            Connects.Add(host);
            KeysUsed.Add(key);
            if (ConnectWorks.Count > 0 && !ConnectWorks.Dequeue()) throw new TvRemoteException(TvRemoteException.CannotConnect);
            var token = Tokens.Count > 0 ? Tokens.Dequeue() : "";
            return Task.FromResult<ITvRemote>(new FakeRemote(this, token));
        }
    }
}

public class RelocatorTests
{
    static readonly TvRecord Salon = new("Salon", "192.168.1.153", TvBrand.Lg);

    [Fact]
    public async Task WorkingAddressIsNotSearched()
    {
        var side = new FakeTvSide();
        var searches = 0;
        var r = new TvRelocator(Salon, side.Connect, (_, _) => { searches++; return Task.FromResult<IReadOnlyList<FoundTv>>([]); });
        await r.ConnectAsync("");
        Assert.Equal(0, searches);
    }

    [Fact]
    public async Task MovedTvIsFollowed()
    {
        var side = new FakeTvSide();
        side.ConnectWorks.Enqueue(false);
        var moved = new List<TvRecord>();
        var r = new TvRelocator(Salon, side.Connect,
            (_, _) => Task.FromResult<IReadOnlyList<FoundTv>>([new FoundTv("Salon", "192.168.1.230", TvBrand.Lg)]));
        r.Moved += moved.Add;
        await r.ConnectAsync("");
        Assert.Equal(["192.168.1.153", "192.168.1.230"], side.Connects);
        Assert.Equal("192.168.1.230", Assert.Single(moved).Host);
        await r.ConnectAsync("");
        Assert.Equal("192.168.1.230", side.Connects[^1]);
        Assert.Equal(3, side.Connects.Count);
    }

    [Fact]
    public async Task SearchesAtMostEveryThirtySeconds()
    {
        var side = new FakeTvSide();
        for (var i = 0; i < 10; i++) side.ConnectWorks.Enqueue(false);
        var clock = new ManualClock(DateTimeOffset.UnixEpoch);
        var searches = 0;
        var r = new TvRelocator(Salon, side.Connect,
            (_, _) => { searches++; return Task.FromResult<IReadOnlyList<FoundTv>>([]); }, clock);
        for (var i = 0; i < 5; i++)
        {
            await Assert.ThrowsAsync<TvRemoteException>(() => r.ConnectAsync(""));
            clock.Advance(TimeSpan.FromSeconds(5));
        }
        Assert.Equal(1, searches);
        clock.Advance(TimeSpan.FromSeconds(30));
        await Assert.ThrowsAsync<TvRemoteException>(() => r.ConnectAsync(""));
        Assert.Equal(2, searches);
    }

    [Fact]
    public void NewHostChoice()
    {
        Assert.Equal("192.168.1.230", TvRelocator.PickNewHost(Salon,
            [new FoundTv("Yatak odası", "192.168.1.40", TvBrand.Lg), new FoundTv("Salon", "192.168.1.230", TvBrand.Lg)]));
        Assert.Equal("192.168.1.230", TvRelocator.PickNewHost(Salon, [new FoundTv("LG TV", "192.168.1.230", TvBrand.Lg)]));
        Assert.Null(TvRelocator.PickNewHost(Salon, [new FoundTv("A", "192.168.1.40", TvBrand.Lg), new FoundTv("B", "192.168.1.41", TvBrand.Lg)]));
        Assert.Null(TvRelocator.PickNewHost(Salon, [new FoundTv("Salon", "192.168.1.153", TvBrand.Lg)]));
        Assert.Null(TvRelocator.PickNewHost(Salon, [new FoundTv("Salon", "192.168.1.2", TvBrand.Samsung)]));
    }
}

public class KeeperTests
{
    static TvFind NoTvs => (_, _) => Task.FromResult<IReadOnlyList<FoundTv>>([]);

    [Fact]
    public async Task LgReopensOnlyAfterTvInput()
    {
        var side = new FakeTvSide();
        foreach (var f in new[] { TvRecord.LgAppId, "com.webos.app.hdmi2", TvRecord.LgAppId, "netflix" }) side.Foreground.Enqueue(f);
        await using var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("LG", "1.2.3.4", TvBrand.Lg),
            LaunchParameters = () => "{\"server\":\"http://1.2.3.4:8787\"}",
            Connect = side.Connect, Find = NoTvs,
        });
        for (var i = 0; i < 4; i++) await keeper.RunOnceAsync();
        Assert.Equal(2, side.Launches.Count);
        Assert.Equal("{\"server\":\"http://1.2.3.4:8787\"}", side.Launches[^1]);
        Assert.Single(side.Connects);
    }

    [Fact]
    public async Task LgReconnectsAfterErrors()
    {
        var side = new FakeTvSide();
        side.ConnectWorks.Enqueue(false);
        side.Foreground.Enqueue(null);
        await using var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("LG", "1.2.3.4", TvBrand.Lg),
            LaunchParameters = () => "{}",
            Connect = side.Connect, Find = NoTvs,
        });
        await keeper.RunOnceAsync();
        Assert.Empty(side.Launches);
        await keeper.RunOnceAsync();
        Assert.Single(side.Launches);
        await keeper.RunOnceAsync();
        Assert.Equal(1, side.Closed);
        await keeper.RunOnceAsync();
        Assert.Equal(3, side.Connects.Count);
        Assert.Equal(2, side.Launches.Count);
    }

    [Fact]
    public async Task LgOwnInputs()
    {
        // TV kendi girişine geçince yeniden açılır; kullanıcının açtığı uygulamalara dokunulmaz.
        var side = new FakeTvSide();
        foreach (var f in new[] { "com.webos.app.externalinput.av1", "com.webos.app.livetv", "com.webos.app.livetvx" })
            side.Foreground.Enqueue(f);
        var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("LG", "h", TvBrand.Lg), LaunchParameters = () => "{}", Connect = side.Connect, Find = NoTvs,
        });
        for (var i = 0; i < 4; i++) await keeper.RunOnceAsync();
        Assert.Equal(3, side.Launches.Count);
    }

    [Fact]
    public async Task SamsungConnectsBrieflyAndRespectsTheWait()
    {
        var side = new FakeTvSide();
        var connected = false;
        var clock = new ManualClock(DateTimeOffset.UnixEpoch);
        await using var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("Samsung", "5.6.7.8", TvBrand.Samsung),
            LaunchParameters = () => "{}",
            TvAppConnected = () => connected,
            Connect = side.Connect, Find = NoTvs, Clock = clock,
        });
        await keeper.RunOnceAsync();
        Assert.Single(side.Connects);
        Assert.Single(side.Launches);
        Assert.Equal(1, side.Closed);

        await keeper.RunOnceAsync();
        Assert.Single(side.Connects);

        connected = true;
        clock.Advance(TimeSpan.FromSeconds(60));
        for (var i = 0; i < 5; i++) await keeper.RunOnceAsync();
        Assert.Single(side.Connects);

        connected = false;
        await keeper.RunOnceAsync();
        Assert.Equal(2, side.Launches.Count);

        await keeper.ReconnectAsync();
        await keeper.RunOnceAsync();
        Assert.Equal(3, side.Launches.Count);
    }

    [Fact]
    public async Task SamsungKeepsNewTokens()
    {
        var side = new FakeTvSide();
        foreach (var t in new[] { "", "88", "88", "" }) side.Tokens.Enqueue(t);
        var stored = new List<string>();
        var clock = new ManualClock(DateTimeOffset.UnixEpoch);
        await using var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("Samsung", "5.6.7.8", TvBrand.Samsung),
            LaunchParameters = () => "{}",
            KeyChanged = stored.Add,
            Connect = side.Connect, Find = NoTvs, Clock = clock,
        });
        for (var i = 0; i < 4; i++)
        {
            await keeper.RunOnceAsync();
            clock.Advance(TimeSpan.FromSeconds(31));
        }
        Assert.Equal(["88"], stored);
        Assert.Equal("88", keeper.Key);
        Assert.Equal(["", "", "88", "88"], side.KeysUsed);
    }

    [Fact]
    public async Task AndroidTvKeeperDoesNothing()
    {
        var side = new FakeTvSide();
        await using var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("Android TV", "", TvBrand.AndroidTv), LaunchParameters = () => "{}", Connect = side.Connect,
            Find = NoTvs,
        });
        await keeper.RunOnceAsync();
        Assert.Empty(side.Connects);
    }

    [Fact]
    public async Task LoopRunsAndStops()
    {
        var side = new FakeTvSide();
        var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = new TvRecord("LG", "h", TvBrand.Lg), LaunchParameters = () => "{}", Connect = side.Connect, Find = NoTvs,
            Interval = TimeSpan.FromMilliseconds(10),
        });
        keeper.Start();
        Assert.True(await LinkTestKit.EventuallyAsync(() => { lock (side) return side.Launches.Count >= 1; }));
        await keeper.StopAsync();
        Assert.False(keeper.IsRunning);
    }
}

public class PairingTests
{
    [Fact]
    public async Task LgLaunchFailureStillPairs()
    {
        var side = new FakeTvSide { FailLaunch = true };
        side.Tokens.Enqueue("key-1");
        var r = await TvPairing.PairAsync(new TvRecord("LG", "h", TvBrand.Lg), null, "{}", side.Connect);
        Assert.Equal(new PairResult("key-1", false), r);
    }

    [Fact]
    public async Task SamsungKeepsSavedTokenAndCountsAsLaunched()
    {
        var side = new FakeTvSide { FailLaunch = true };
        var r = await TvPairing.PairAsync(new TvRecord("Samsung", "h", TvBrand.Samsung), "55", "{}", side.Connect);
        Assert.Equal(new PairResult("55", true), r);
        Assert.Equal(["55"], side.KeysUsed);
    }

    [Fact]
    public async Task AndroidTvNeedsNothing()
    {
        var side = new FakeTvSide();
        Assert.Equal(new PairResult("", true), await TvPairing.PairAsync(new TvRecord("Android TV", "", TvBrand.AndroidTv), null, "{}", side.Connect));
        Assert.Empty(side.Connects);
    }
}

public class RemoteProtocolTests
{
    [Fact]
    public void LgRegisterMessage()
    {
        Assert.Equal("{\"type\":\"register\",\"id\":\"register_0\",\"payload\":{\"forcePairing\":false,\"pairingType\":\"PROMPT\","
            + "\"manifest\":{\"manifestVersion\":1,\"appVersion\":\"1.0\",\"permissions\":[\"LAUNCH\",\"LAUNCH_WEBAPP\",\"APP_TO_APP\","
            + "\"READ_RUNNING_APPS\",\"READ_INSTALLED_APPS\"]}}}", LgRemote.RegisterMessage(null));
        Assert.EndsWith(",\"client-key\":\"abc\"}}", LgRemote.RegisterMessage("abc"));
    }

    [Fact]
    public void LgRegisterReplies()
    {
        Assert.Equal("k", LgRemote.ParseRegisterReply("{\"type\":\"registered\",\"payload\":{\"client-key\":\"k\"}}"));
        Assert.Null(LgRemote.ParseRegisterReply("{\"type\":\"response\",\"payload\":{\"pairingType\":\"PROMPT\"}}"));
        Assert.Equal("bad response", Assert.Throws<TvRemoteException>(() => LgRemote.ParseRegisterReply("{\"type\":\"registered\"}")).Reason);
        Assert.Equal("denied", Assert.Throws<TvRemoteException>(() => LgRemote.ParseRegisterReply("{\"type\":\"error\",\"error\":\"denied\"}")).Reason);
        Assert.Equal("register", Assert.Throws<TvRemoteException>(() => LgRemote.ParseRegisterReply("{\"type\":\"error\"}")).Reason);
        Assert.Equal(["wss://h:3001/", "ws://h:3000/"], LgRemote.Endpoints("h").Select(u => u.ToString()));
    }

    [Fact]
    public void SamsungMessages()
    {
        const string bare = "wss://192.168.1.20:8002/api/v2/channels/samsung.remote.control?name=Tmlubw==";
        Assert.Equal(bare, SamsungRemote.Url("192.168.1.20", "Nino", null));
        Assert.Equal(bare + "&token=123", SamsungRemote.Url("192.168.1.20", "Nino", "123"));
        Assert.Equal((SamsungEventKind.Connected, "55"), SamsungRemote.ParseEvent("{\"event\":\"ms.channel.connect\",\"data\":{\"token\":\"55\"}}"));
        Assert.Equal((SamsungEventKind.Connected, ""), SamsungRemote.ParseEvent("{\"event\":\"ms.channel.connect\",\"data\":{}}"));
        Assert.Equal(SamsungEventKind.Ignore, SamsungRemote.ParseEvent("{\"event\":\"ms.channel.ready\"}").Kind);
        Assert.Equal(SamsungEventKind.Ignore, SamsungRemote.ParseEvent("not json").Kind);
        Assert.Equal(SamsungEventKind.Unauthorized, SamsungRemote.ParseEvent("{\"event\":\"ms.channel.unauthorized\"}").Kind);
        Assert.Equal(SamsungEventKind.TimedOut, SamsungRemote.ParseEvent("{\"event\":\"ms.channel.timeOut\"}").Kind);
        Assert.Equal("{\"method\":\"ms.channel.emit\",\"params\":{\"event\":\"ed.apps.launch\",\"to\":\"host\",\"data\":{\"appId\":\"NinoTVApps.Nino\","
            + "\"action_type\":\"DEEP_LINK\",\"metaTag\":\"{\\\"server\\\":\\\"http://1.2.3.4:8787\\\"}\"}}}",
            SamsungRemote.LaunchMessage("{\"server\":\"http://1.2.3.4:8787\"}"));
        Assert.Equal(("Nino", true), SamsungRemote.ChooseClientName(null, false));
        Assert.Equal(("Eski", false), SamsungRemote.ChooseClientName("Eski", true));
        Assert.Equal(("Nino", false), SamsungRemote.ChooseClientName("Nino", true));
    }

    /// <summary>127.0.0.1'de tek bağlantılık sahte WebSocket sunucusu; gelen her metne betikteki yanıtları verir.</summary>
    static async Task<(int Port, Task<List<string>> Received)> FakeWsServerAsync(Func<string, IEnumerable<string>> reply,
        IEnumerable<string>? greeting = null)
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        var task = Task.Run(async () =>
        {
            var got = new List<string>();
            using var tcp = await l.AcceptTcpClientAsync();
            l.Stop();
            var stream = tcp.GetStream();
            var head = await HttpHead.ReadAsync(stream, 65536, 4096, CancellationToken.None);
            await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                + $"Sec-WebSocket-Accept: {HttpWire.WebSocketAccept(head!.Header("Sec-WebSocket-Key")!)}\r\n\r\n"));
            using var ws = WebSocket.CreateFromStream(stream, new WebSocketCreationOptions { IsServer = true });
            foreach (var g in greeting ?? []) await ws.SendAsync(Encoding.UTF8.GetBytes(g), WebSocketMessageType.Text, true, default);
            var buffer = new byte[65536];
            try
            {
                while (true)
                {
                    var r = await ws.ReceiveAsync(buffer, default);
                    if (r.MessageType == WebSocketMessageType.Close) break;
                    var text = Encoding.UTF8.GetString(buffer, 0, r.Count);
                    got.Add(text);
                    foreach (var answer in reply(text))
                    {
                        var bytes = Encoding.UTF8.GetBytes(answer);
                        // Parça parça gönder: istemci birleştirmeli.
                        var half = bytes.Length / 2;
                        await ws.SendAsync(bytes.AsMemory(0, half), WebSocketMessageType.Text, false, default);
                        await ws.SendAsync(bytes.AsMemory(half), WebSocketMessageType.Text, true, default);
                    }
                }
            }
            catch (Exception) { }
            return got;
        });
        return (port, task);
    }

    [Fact]
    public async Task LgPairsLaunchesAndAsksForeground()
    {
        var (port, received) = await FakeWsServerAsync(text =>
        {
            if (text.Contains("\"register\"")) return ["{\"type\":\"response\",\"id\":\"register_0\",\"payload\":{\"pairingType\":\"PROMPT\"}}",
                "{\"type\":\"registered\",\"id\":\"register_0\",\"payload\":{\"client-key\":\"ck1\"}}"];
            if (text.Contains("system.launcher/launch")) return ["{\"type\":\"response\",\"id\":\"other\"}",
                "{\"type\":\"response\",\"id\":\"req_1\",\"payload\":{\"returnValue\":true}}"];
            if (text.Contains("getForegroundAppInfo")) return ["{\"type\":\"response\",\"id\":\"req_2\",\"payload\":{\"appId\":\"com.webos.app.hdmi2\"}}"];
            return [];
        });
        var closedPort = LinkTestKit.FreePort();
        await using (var lg = await LgRemote.ConnectAsync("127.0.0.1", null, endpoints:
                         [new Uri($"ws://127.0.0.1:{closedPort}"), new Uri($"ws://127.0.0.1:{port}")]))
        {
            Assert.Equal("ck1", lg.Key);
            await lg.LaunchAsync("{\"server\":\"http://1.2.3.4:8787\"}");
            Assert.Equal("com.webos.app.hdmi2", await lg.ForegroundAppAsync());
        }
        var got = await received;
        Assert.Contains("\"uri\":\"ssap://system.launcher/launch\",\"payload\":{\"id\":\"com.ninotranslator.tv\",\"params\":{\"server\":\"http://1.2.3.4:8787\"}}", got[1]);
        Assert.Contains("\"id\":\"req_2\"", got[2]);
    }

    [Fact]
    public async Task LgProtocolErrorDoesNotTryTheOtherEndpoint()
    {
        var (port, _) = await FakeWsServerAsync(_ => ["{\"type\":\"error\",\"error\":\"denied\"}"]);
        var e = await Assert.ThrowsAsync<TvRemoteException>(() => LgRemote.ConnectAsync("127.0.0.1", "k", endpoints:
            [new Uri($"ws://127.0.0.1:{port}"), new Uri("ws://127.0.0.1:1")]));
        Assert.Equal("denied", e.Reason);
    }

    [Fact]
    public async Task LgNothingReachableMeansCannotConnect()
    {
        var e = await Assert.ThrowsAsync<TvRemoteException>(() => LgRemote.ConnectAsync("127.0.0.1", null, endpoints:
            [new Uri("ws://127.0.0.1:1"), new Uri($"ws://127.0.0.1:{LinkTestKit.FreePort()}")]));
        Assert.Equal("cannot connect", e.Reason);
    }

    [Fact]
    public async Task SamsungConnectsAndLaunches()
    {
        var (port, received) = await FakeWsServerAsync(_ => [],
            ["{\"event\":\"ms.channel.ready\"}", "{\"event\":\"ms.channel.connect\",\"data\":{\"token\":\"77\"}}"]);
        await using (var tv = await SamsungRemote.ConnectAsync("127.0.0.1", "Nino", null, endpoint: new Uri($"ws://127.0.0.1:{port}/")))
        {
            Assert.Equal("77", tv.Key);
            Assert.Equal("", await tv.ForegroundAppAsync());
            await tv.LaunchAsync("{\"server\":\"x\"}");
        }
        Assert.Contains("ed.apps.launch", Assert.Single(await received));
    }

    [Fact]
    public async Task SamsungRefusalIsRejected()
    {
        var (port, _) = await FakeWsServerAsync(_ => [], ["{\"event\":\"ms.channel.unauthorized\"}"]);
        var e = await Assert.ThrowsAsync<TvRemoteException>(() =>
            SamsungRemote.ConnectAsync("127.0.0.1", "Nino", null, endpoint: new Uri($"ws://127.0.0.1:{port}/")));
        Assert.Equal("rejected", e.Reason);
    }
}
