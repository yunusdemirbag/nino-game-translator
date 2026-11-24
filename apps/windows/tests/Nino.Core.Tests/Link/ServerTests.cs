// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using Nino.Core.Link;
using static Nino.Core.Tests.Link.LinkTestKit;

namespace Nino.Core.Tests.Link;

public class LegacyServerTests
{
    [Fact]
    public async Task SimpleRoutes()
    {
        using var server = new LegacySubtitleServer();
        var port = server.Start(0);

        Assert.Equal("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 14\r\nConnection: close\r\n\r\n{\"app\":\"nino\"}",
            await RawAsync(port, "GET /hello HTTP/1.1\r\n\r\n"));
        Assert.Equal("HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            await RawAsync(port, "OPTIONS /events HTTP/1.1\r\n\r\n"));
        Assert.StartsWith("HTTP/1.1 404 Not Found\r\n", await RawAsync(port, "POST /hello HTTP/1.1\r\n\r\n"));
        Assert.StartsWith("HTTP/1.1 404 Not Found\r\n", await RawAsync(port, "GET /Hello HTTP/1.1\r\n\r\n"));

        var obs = await RawAsync(port, "GET /obs?size=40 HTTP/1.1\r\n\r\n");
        Assert.StartsWith("HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-cache\r\n", obs);
        Assert.Contains("/events?viewer=obs", obs);
    }

    [Fact]
    public async Task StreamOpensWithRetryStyleAndRecentStarted()
    {
        var clock = new ManualClock(DateTimeOffset.UnixEpoch.AddDays(20000));
        using var server = new LegacySubtitleServer(clock);
        var port = server.Start(0);
        server.Send(new StyleChanged(new TvStyle { FontSize = 50 }));
        server.Send(new TranslationStarted());
        clock.Advance(TimeSpan.FromSeconds(19));

        using var tv = await SseReader.OpenAsync(port, "/events?model=LG+OLED55");
        var text = await tv.WaitForAsync("event: started");
        Assert.StartsWith("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\n"
            + "Connection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\nretry: 2000\n\nevent: style\ndata: {", text);
        Assert.Contains("\"fontSize\":50", text);

        using var obs = await SseReader.OpenAsync(port, "/events?viewer=obs");
        var obsText = await obs.WaitForAsync("event: style");
        await Task.Delay(100);
        Assert.DoesNotContain("started", obs.Text);

        clock.Advance(TimeSpan.FromSeconds(1));
        using var late = await SseReader.OpenAsync(port, "/events");
        await late.WaitForAsync("event: style");
        await Task.Delay(100);
        Assert.DoesNotContain("started", late.Text);
        Assert.Equal(2, server.TvCount);
    }

    [Fact]
    public async Task ModelIsReportedAndCountsChange()
    {
        using var server = new LegacySubtitleServer();
        var port = server.Start(0);
        var models = new List<string>();
        var counts = new List<int>();
        server.ModelReported += m => { lock (models) models.Add(m); };
        server.TvCountChanged += c => { lock (counts) counts.Add(c); };

        var tv = await SseReader.OpenAsync(port, "/events?model=Samsung%20QE65Q80C");
        await tv.WaitForAsync("retry: 2000");
        using var obs = await SseReader.OpenAsync(port, "/events?viewer=obs&model=X");
        await obs.WaitForAsync("retry: 2000");
        Assert.True(await EventuallyAsync(() => { lock (counts) return counts.Count >= 2; }));
        Assert.Equal(["Samsung QE65Q80C"], models);
        Assert.Equal(1, server.TvCount);

        tv.Dispose();
        Assert.True(await EventuallyAsync(() => server.TvCount == 0));
        Assert.True(await EventuallyAsync(() => { lock (counts) return counts.Last() == 0; }));
        lock (counts) Assert.Equal([1, 1, 0], counts);
    }

    [Fact]
    public async Task GateKeepsSubtitlesOffTheTv()
    {
        using var server = new LegacySubtitleServer();
        var port = server.Start(0);
        server.SubtitlesOnTv = false;
        using var tv = await SseReader.OpenAsync(port, "/events");
        using var obs = await SseReader.OpenAsync(port, "/events?viewer=obs");
        await tv.WaitForAsync("retry: 2000");
        await obs.WaitForAsync("retry: 2000");
        await EventuallyAsync(() => server.TvCount == 1);

        server.Send(new SubtitleShown("Merhaba", 4000));
        server.Send(new SubtitleCleared());
        server.Send(new TranslationStarted());

        var obsText = await obs.WaitForAsync("event: started");
        Assert.Contains("event: subtitle", obsText);
        Assert.Contains("\"text\":\"Merhaba\"", obsText);
        Assert.Contains("event: clear", obsText);
        var tvText = await tv.WaitForAsync("event: started");
        Assert.DoesNotContain("subtitle", tvText);
        Assert.DoesNotContain("event: clear", tvText);
    }

    [Fact]
    public async Task FramesArriveInOrder()
    {
        using var server = new LegacySubtitleServer();
        var port = server.Start(0);
        using var tv = await SseReader.OpenAsync(port, "/events");
        await tv.WaitForAsync("retry: 2000");
        await EventuallyAsync(() => server.TvCount == 1);
        for (var i = 0; i < 50; i++) server.Send(new SubtitleShown($"satır {i}", 1000));
        var text = await tv.WaitForAsync("satır 49");
        var positions = Enumerable.Range(0, 50).Select(i => text.IndexOf($"\"satır {i}\"", StringComparison.Ordinal)).ToList();
        Assert.Equal(positions.OrderBy(p => p), positions);
    }

    [Fact]
    public async Task BusyPortFallsBackAfterAttempts()
    {
        var blocker = new TcpListener(IPAddress.Any, 0);
        blocker.Start();
        var busy = ((IPEndPoint)blocker.LocalEndpoint).Port;
        var log = new List<string>();
        await using var output = new TvOutput(new TvOutputOptions
        {
            LegacyPort = busy, IngressPort = FreePort(), PortAttempts = 3, PortRetryDelay = TimeSpan.FromMilliseconds(10),
            Log = log.Add,
        });
        var port = await output.EnsureLegacyServerAsync();
        Assert.NotEqual(busy, port);
        Assert.NotEqual(0, port);
        Assert.Equal(port, output.LegacyPort);
        Assert.Single(log);
        Assert.StartsWith($"{busy} numaralı port kullanılamadı (", log[0]);
        Assert.EndsWith("; sistemin verdiği başka bir port deneniyor", log[0]);
        Assert.Equal(port, await output.EnsureLegacyServerAsync());
        blocker.Stop();
    }

    [Fact]
    public async Task FreedPortIsTakenOnALaterAttempt()
    {
        var blocker = new TcpListener(IPAddress.Any, 0);
        blocker.Start();
        var busy = ((IPEndPoint)blocker.LocalEndpoint).Port;
        var log = new List<string>();
        await using var output = new TvOutput(new TvOutputOptions
        {
            LegacyPort = busy, IngressPort = FreePort(), PortAttempts = 6, PortRetryDelay = TimeSpan.FromMilliseconds(150),
            Log = l => { lock (log) log.Add(l); },
        });
        var start = output.EnsureLegacyServerAsync();
        await Task.Delay(200);
        blocker.Stop();
        Assert.Equal(busy, await start);
        lock (log) Assert.Matches($"^altyazı sunucusu {busy}'de [2-6]\\. denemede açıldı$", Assert.Single(log));
    }
}

public class IngressTests
{
    static TvOutput NewOutput(int ingressPort, ManualClock? clock = null, LinkTimings? timings = null) => new(new TvOutputOptions
    {
        Identity = new SenderIdentity { Name = "Salon PC", Id = "abc123", Client = "nino-windows/4.0.0" },
        LegacyPort = 0,
        IngressPort = ingressPort,
        Clock = clock,
        Timings = timings,
        PortAttempts = 1,
    });

    [Fact]
    public async Task InfoAndOptions()
    {
        var port = FreePort();
        await using var output = NewOutput(port);
        Assert.True(await output.EnsureIngressAsync());

        var info = await RawAsync(port, "GET /nino/info HTTP/1.1\r\nHost: x\r\n\r\n");
        Assert.StartsWith("HTTP/1.1 200 OK\r\n", info);
        Assert.Contains("Content-Type: application/json\r\n", info);
        Assert.Contains("Access-Control-Allow-Origin: *\r\n", info);
        Assert.EndsWith("{\"app\":\"nino\",\"type\":\"info\",\"active\":false,\"id\":\"abc123\",\"name\":\"Salon PC\",\"role\":\"sender\",\"version\":1,\"versions\":[1]}", info);

        var options = await RawAsync(port, "OPTIONS * HTTP/1.1\r\n\r\n");
        Assert.StartsWith("HTTP/1.1 204 No Content\r\n", options);
        Assert.Contains("Access-Control-Allow-Methods: GET, OPTIONS\r\n", options);
        Assert.Contains("Access-Control-Allow-Headers: *\r\n", options);
        Assert.StartsWith("HTTP/1.1 404", await RawAsync(port, "GET /nino/other HTTP/1.1\r\n\r\n"));

        Assert.Contains("\"link\":\"ws://192.168.1.2:" + port + "/nino/ws\"", output.LaunchParameters("192.168.1.2"));
    }

    [Fact]
    public async Task WebTvGetsHelloThenCatchUpAndBroadcasts()
    {
        var port = FreePort();
        await using var output = NewOutput(port);
        await output.EnsureIngressAsync();
        var infos = new List<TvLinkInfo>();
        output.TvInfoReported += i => { lock (infos) infos.Add(i); };

        output.Send(new StyleChanged(new TvStyle { FontSize = 52 }));
        output.Send(new TranslationStarted());
        output.Send(new SubtitleShown("Buraya gel.", 60000));

        await using var tv = await ConnectTvAsync(port);
        var hello = await tv.WaitForTypeAsync("hello");
        Assert.Equal("{\"app\":\"nino\",\"type\":\"hello\",\"active\":true,\"client\":\"nino-windows/4.0.0\",\"device\":\"Windows\",\"version\":1}", hello);
        Assert.Equal(0, output.TvCount);

        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"LG\",\"model\":\"OLED55\",\"appVersion\":\"1.2\"}");
        var show = await tv.WaitForTypeAsync("show");
        Assert.Equal("{\"app\":\"nino\",\"type\":\"state\",\"active\":true}", await tv.WaitForTypeAsync("state"));
        var order = tv.Received.Select(TypeOf).ToList();
        Assert.Equal(["hello", "style", "started", "show", "state"], order);
        Assert.Contains("\"id\":1", show);
        Assert.Contains("\"text\":\"Buraya gel.\"", show);
        Assert.True(await EventuallyAsync(() => output.TvCount == 1));
        Assert.True(await EventuallyAsync(() => { lock (infos) return infos.Any(i => i.Model == "OLED55" && i.AppVersion == "1.2"); }));

        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"ping\",\"t\":1732233600000}");
        Assert.Equal("{\"app\":\"nino\",\"type\":\"pong\",\"t\":1732233600000}", await tv.WaitForTypeAsync("pong"));

        output.Send(new SubtitleCleared());
        Assert.Equal("{\"app\":\"nino\",\"type\":\"clear\",\"id\":1}", await tv.WaitForTypeAsync("clear"));

        await using var second = await ConnectTvAsync(port);
        await second.WaitForTypeAsync("hello");
        await second.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"Samsung\"}");
        await second.WaitForTypeAsync("started");
        Assert.True(await EventuallyAsync(() => output.TvCount == 2));
        Assert.DoesNotContain("show", second.Received.Select(TypeOf));

        output.Send(new RegionShown("q", "Fenerciyi bul"));
        await tv.WaitForTypeAsync("region");
        await second.WaitForTypeAsync("region");

        output.Send(new TranslationStopped());
        await second.WaitForTypeAsync("stopped");
    }

    [Fact]
    public async Task GateAppliesToWebTvs()
    {
        var port = FreePort();
        await using var output = NewOutput(port);
        await output.EnsureIngressAsync();
        await using var tv = await ConnectTvAsync(port);
        await tv.WaitForTypeAsync("hello");
        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"LG\"}");
        Assert.True(await EventuallyAsync(() => output.TvCount == 1));

        output.SubtitlesOnTv = false;
        await tv.WaitForTypeAsync("region-clear");
        output.Send(new SubtitleShown("Gizli", 5000));
        output.Send(new TranslationStarted());
        await tv.WaitForTypeAsync("started");
        Assert.DoesNotContain("show", tv.Received.Select(TypeOf));

        output.SubtitlesOnTv = true;
        var show = await tv.WaitForTypeAsync("show");
        Assert.Contains("Gizli", show);
    }

    [Fact]
    public async Task SilentTvIsDropped()
    {
        var port = FreePort();
        var timings = new LinkTimings
        {
            WelcomeTimeout = TimeSpan.FromMilliseconds(300), PingEvery = TimeSpan.FromMilliseconds(50),
            SilenceLimit = TimeSpan.FromMilliseconds(300),
        };
        await using var output = NewOutput(port, timings: timings);
        await output.EnsureIngressAsync();

        await using var mute = await ConnectTvAsync(port);
        await mute.WaitForTypeAsync("hello");
        Assert.True(await EventuallyAsync(() => mute.Closed));

        await using var tv = await ConnectTvAsync(port);
        await tv.WaitForTypeAsync("hello");
        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"LG\"}");
        await tv.WaitForTypeAsync("ping");
        Assert.True(await EventuallyAsync(() => output.TvCount == 1));
        Assert.True(await EventuallyAsync(() => tv.Closed));
        Assert.True(await EventuallyAsync(() => output.TvCount == 0));
    }
}

public class ConnectorTests
{
    sealed class NoTvs : ILinkTvLocator
    {
        public int Calls;
        public Task<IReadOnlyList<string>> FindAsync(CancellationToken ct)
        {
            Interlocked.Increment(ref Calls);
            return Task.FromResult<IReadOnlyList<string>>([]);
        }
    }

    /// <summary>Android TV gibi 47800'de dinleyen küçük sunucu.</summary>
    sealed class FakeAndroidTv : IDisposable
    {
        readonly TcpListener listener = new(IPAddress.Loopback, 0);
        public readonly List<SocketPeer> Peers = [];
        public int Port => listener.LocalEndpoint is IPEndPoint ep ? ep.Port : 0;

        public FakeAndroidTv()
        {
            listener.Start();
            _ = AcceptAsync();
        }

        async Task AcceptAsync()
        {
            while (true)
            {
                TcpClient tcp;
                try { tcp = await listener.AcceptTcpClientAsync(); } catch (Exception) { return; }
                var stream = tcp.GetStream();
                var head = await HttpHead.ReadAsync(stream, 65536, 4096, CancellationToken.None);
                var accept = HttpWire.WebSocketAccept(head!.Header("Sec-WebSocket-Key")!);
                await stream.WriteAsync(Encoding.ASCII.GetBytes(
                    $"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\n\r\n"));
                var ws = WebSocket.CreateFromStream(stream, new WebSocketCreationOptions { IsServer = true });
                var peer = new SocketPeer(ws);
                lock (Peers) Peers.Add(peer);
                peer.StartReading();
            }
        }

        public SocketPeer? Latest
        {
            get { lock (Peers) return Peers.LastOrDefault(); }
        }

        public int Count
        {
            get { lock (Peers) return Peers.Count; }
        }

        public void Dispose() => listener.Stop();
    }

    [Fact]
    public async Task ConnectsReconnectsAndStopsWhenReplaced()
    {
        using var tv = new FakeAndroidTv();
        var locator = new NoTvs();
        await using var output = new TvOutput(new TvOutputOptions
        {
            IngressPort = tv.Port,
            Locator = locator,
            ConnectorBackoff = [TimeSpan.FromMilliseconds(50)],
        });
        var states = new List<LinkConnectorState>();
        output.AndroidTvStateChanged += s => { lock (states) states.Add(s); };
        output.Send(new TranslationStarted());
        output.ConnectAndroidTv("127.0.0.1");

        Assert.True(await EventuallyAsync(() => tv.Latest is not null));
        var first = tv.Latest!;
        Assert.Contains("\"device\":\"Windows\"", await first.WaitForTypeAsync("hello"));
        // Giden bağlantının hello'su gönderici durumu taşımaz (yalnız 47800 girişi; Mac ile aynı).
        Assert.DoesNotContain("active", await first.WaitForTypeAsync("hello"));
        await first.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"Salon\",\"model\":\"Sony\"}");
        await first.WaitForTypeAsync("started");
        Assert.True(await EventuallyAsync(() => output.TvCount == 1));

        output.Send(new SubtitleShown("Selam", 3000));
        Assert.Contains("Selam", await first.WaitForTypeAsync("show"));

        await first.DisposeAsync();
        Assert.True(await EventuallyAsync(() => tv.Count == 2));
        var second = tv.Latest!;
        await second.WaitForTypeAsync("hello");
        await second.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"Salon\"}");
        Assert.Contains("Selam", await second.WaitForTypeAsync("show"));

        await second.SendAsync("{\"app\":\"nino\",\"type\":\"error\",\"code\":\"replaced\"}");
        Assert.True(await EventuallyAsync(() => { lock (states) return states.Contains(LinkConnectorState.Replaced); }));
        await Task.Delay(300);
        Assert.Equal(2, tv.Count);
        Assert.Equal(0, output.TvCount);
        Assert.Equal(0, locator.Calls);

        output.ConnectAndroidTv("127.0.0.1");
        Assert.True(await EventuallyAsync(() => tv.Count == 3));
    }

    [Fact]
    public async Task AndroidTvSearchAndReplacementAreLogged()
    {
        // Kullanıcı bildirimi: TV bağlantısı gidince günlükte iz yoktu. Arama bir kez yazılır (her 8 sn'lik denemede değil).
        var log = new List<string>();
        var locator = new NoTvs();
        await using (var output = new TvOutput(new TvOutputOptions
        {
            Locator = locator,
            ConnectorBackoff = [TimeSpan.FromMilliseconds(30)],
            Log = l => { lock (log) log.Add(l); },
        }))
        {
            // Kayıtlı adres yok: her döngü doğrudan arar (Windows'ta kapalı porta bağlanma ~2 sn sürüyordu).
            output.ConnectAndroidTv(null);
            Assert.True(await EventuallyAsync(() => locator.Calls >= 3));
            lock (log)
                Assert.Single(log, l => l.Contains("Android TV aranıyor") && l.Contains("(yok)"));
        }

        using var tv = new FakeAndroidTv();
        log.Clear();
        await using var second = new TvOutput(new TvOutputOptions
        {
            IngressPort = tv.Port,
            Locator = new NoTvs(),
            ConnectorBackoff = [TimeSpan.FromMilliseconds(50)],
            Log = l => { lock (log) log.Add(l); },
        });
        second.Send(new TranslationStarted());
        second.ConnectAndroidTv("127.0.0.1");
        Assert.True(await EventuallyAsync(() => tv.Latest is not null));
        await tv.Latest!.WaitForTypeAsync("hello");
        await tv.Latest.SendAsync("{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"Salon\"}");
        await tv.Latest.WaitForTypeAsync("started");
        await tv.Latest.SendAsync("{\"app\":\"nino\",\"type\":\"error\",\"code\":\"replaced\"}");
        Assert.True(await EventuallyAsync(() => { lock (log) return log.Any(l => l.Contains("başka bir gönderici")); }));
    }

    [Fact]
    public async Task UnsupportedVersionWithoutCommonOneAsksForUpdate()
    {
        using var tv = new FakeAndroidTv();
        await using var connector = new LinkConnector(new SenderIdentity(), new NoTvs(), port: tv.Port);
        var states = new List<LinkConnectorState>();
        connector.StateChanged += s => { lock (states) states.Add(s); };
        connector.Start("127.0.0.1");
        Assert.True(await EventuallyAsync(() => tv.Latest is not null));
        await tv.Latest!.WaitForTypeAsync("hello");
        await tv.Latest.SendAsync("{\"app\":\"nino\",\"type\":\"error\",\"code\":\"version_unsupported\",\"versions\":[2]}");
        Assert.True(await EventuallyAsync(() => connector.State == LinkConnectorState.UpdateRequired));
    }

    [Fact]
    public async Task MissingWelcomeClosesAndSearches()
    {
        using var tv = new FakeAndroidTv();
        var locator = new NoTvs();
        await using var connector = new LinkConnector(new SenderIdentity(), locator,
            new LinkTimings { WelcomeTimeout = TimeSpan.FromMilliseconds(100) }, port: tv.Port)
        {
            Backoff = [TimeSpan.FromMilliseconds(20)],
        };
        connector.Start("127.0.0.1");
        Assert.True(await EventuallyAsync(() => tv.Count >= 2));
        Assert.Equal(0, locator.Calls);

        connector.Start(null);
        Assert.True(await EventuallyAsync(() => locator.Calls > 0));
    }
}
