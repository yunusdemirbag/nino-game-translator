// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;
using Nino.Core.Link;
using static Nino.Core.Tests.Link.LinkTestKit;

namespace Nino.Core.Tests.Link;

/// <summary>TV bağlanma/kopma olayları, nedenleri ve canlılık (kalp atışı) kuralları.</summary>
public class LinkEventTests
{
    const string Welcome = "{\"app\":\"nino\",\"type\":\"welcome\",\"version\":1,\"name\":\"Salon\",\"model\":\"OLED55C3\",\"appVersion\":\"3.2\"}";

    /// <summary>Olayları ve günlük satırlarını toplayan TV çıkışı.</summary>
    sealed class Watched : IAsyncDisposable
    {
        public readonly TvOutput Output;
        public readonly List<TvLinkConnected> Up = [];
        public readonly List<TvLinkDropped> Down = [];
        public readonly List<string> Log = [];
        public readonly int Port = FreePort();

        public Watched(ManualClock? clock = null, LinkTimings? timings = null)
        {
            Output = new TvOutput(new TvOutputOptions
            {
                Identity = new SenderIdentity { Name = "Salon PC", Id = "abc123", Client = "nino-windows/4.0.0" },
                LegacyPort = 0,
                IngressPort = Port,
                Clock = clock,
                Timings = timings,
                PortAttempts = 1,
                Log = line => { lock (Log) Log.Add(line); },
            });
            Output.TvConnected += e => { lock (Up) Up.Add(e); };
            Output.TvDropped += e => { lock (Down) Down.Add(e); };
        }

        public TvLinkDropped[] Drops
        {
            get { lock (Down) return Down.ToArray(); }
        }

        public string[] Lines
        {
            get { lock (Log) return Log.ToArray(); }
        }

        public async Task<SocketPeer> WelcomedTvAsync()
        {
            var tv = await ConnectTvAsync(Port);
            await tv.WaitForTypeAsync("hello");
            await tv.SendAsync(Welcome);
            Assert.True(await EventuallyAsync(() => { lock (Up) return Up.Count > 0; }));
            return tv;
        }

        public async Task<TvLinkDropped> DropAsync()
        {
            Assert.True(await EventuallyAsync(() => Drops.Length > 0));
            return Drops[0];
        }

        public ValueTask DisposeAsync() => Output.DisposeAsync();
    }

    [Fact]
    public void LivenessDefaults()
    {
        Assert.Equal(TimeSpan.FromSeconds(5), LinkTimings.Default.PingEvery);
        Assert.Equal(TimeSpan.FromSeconds(15), LinkTimings.Default.SilenceLimit);
        Assert.Equal(TimeSpan.FromSeconds(5), LinkTimings.Default.WelcomeTimeout);
        Assert.Equal(TimeSpan.FromSeconds(15), LegacySubtitleServer.DefaultPingInterval);
    }

    [Fact]
    public async Task ConnectedTvGetsPingsAndIsLoggedWithModelAndVersion()
    {
        await using var w = new Watched(timings: new LinkTimings { PingEvery = TimeSpan.FromMilliseconds(40) });
        await w.Output.EnsureIngressAsync();
        await using var tv = await w.WelcomedTvAsync();
        var up = Assert.Single(w.Up);
        Assert.Equal(TvLinkKind.WebTv, up.Kind);
        Assert.Equal(w.Port, up.Port);
        Assert.Equal("127.0.0.1", up.Address);
        Assert.Equal("OLED55C3", up.Model);
        Assert.Equal("3.2", up.AppVersion);
        Assert.Contains($"TV bağlandı ({w.Port} web TV, OLED55C3, uygulama 3.2): 127.0.0.1", w.Lines);

        var ping = await tv.WaitForTypeAsync("ping", skip: 2);
        Assert.Matches("^\\{\"app\":\"nino\",\"type\":\"ping\",\"t\":\\d+\\}$", ping);
        Assert.Empty(w.Drops);
    }

    [Fact]
    public async Task TvClosingIsClosed()
    {
        await using var w = new Watched();
        await w.Output.EnsureIngressAsync();
        var tv = await w.WelcomedTvAsync();
        await tv.Socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, CancellationToken.None);
        var drop = await w.DropAsync();
        Assert.Equal(TvLinkEndReason.Closed, drop.Reason);
        Assert.Equal("closed", drop.Code);
        Assert.True(drop.WasConnected);
        Assert.Equal(w.Up[0].Id, drop.Id);
        Assert.True(await EventuallyAsync(() => w.Lines.Any(l => l.StartsWith($"TV koptu ({w.Port} web TV): TV bağlantıyı kapattı [closed]"))));
        await tv.DisposeAsync();
    }

    [Fact]
    public async Task SilentTvIsSilenceAfterFifteenSecondsOnTheClock()
    {
        var clock = new ManualClock(DateTimeOffset.UnixEpoch.AddDays(20000));
        await using var w = new Watched(clock, new LinkTimings { PingEvery = TimeSpan.FromMilliseconds(30) });
        await w.Output.EnsureIngressAsync();
        await using var tv = await w.WelcomedTvAsync();

        // Saat ilerlemedikçe TV cevap vermese de bağlı kalır (pinge rağmen).
        await tv.WaitForTypeAsync("ping", skip: 3);
        clock.Advance(TimeSpan.FromSeconds(14));
        await Task.Delay(150);
        Assert.Empty(w.Drops);

        clock.Advance(TimeSpan.FromSeconds(2));
        var drop = await w.DropAsync();
        Assert.Equal(TvLinkEndReason.Silence, drop.Reason);
        Assert.Equal(TimeSpan.FromSeconds(16), drop.After);
        Assert.Contains(w.Lines, l => l == $"TV koptu ({w.Port} web TV): 15 sn sessizlik [silence], 16 sn bağlı kaldı: 127.0.0.1");
        Assert.True(await EventuallyAsync(() => tv.Closed));
    }

    [Fact]
    public async Task MissingWelcomeIsHandshakeAndLoggedOncePerStreak()
    {
        await using var w = new Watched(timings: new LinkTimings { WelcomeTimeout = TimeSpan.FromMilliseconds(100) });
        await w.Output.EnsureIngressAsync();
        for (var i = 0; i < 2; i++)
        {
            await using var mute = await ConnectTvAsync(w.Port);
            await mute.WaitForTypeAsync("hello");
            Assert.True(await EventuallyAsync(() => w.Drops.Length == i + 1));
        }
        Assert.All(w.Drops, d =>
        {
            Assert.Equal(TvLinkEndReason.Handshake, d.Reason);
            Assert.False(d.WasConnected);
            Assert.Equal(TvLinkReasons.NoWelcome, d.Detail);
        });
        Assert.Empty(w.Up);
        Assert.Single(w.Lines, l => l.Contains("[handshake]", StringComparison.Ordinal));
        Assert.Contains(w.Lines, l => l.StartsWith($"TV ile el sıkışılamadı ({w.Port} web TV): welcome gelmedi [handshake]"));

        // Bağlantı olunca seri biter; sonraki el sıkışma hatası yine yazılır.
        await using var tv = await w.WelcomedTvAsync();
        await using var old = await ConnectTvAsync(w.Port);
        await old.WaitForTypeAsync("hello");
        await old.SendAsync("{\"app\":\"nino\",\"type\":\"error\",\"code\":\"version_unsupported\",\"versions\":[]}");
        Assert.True(await EventuallyAsync(() => w.Drops.Length == 3));
        Assert.Equal(TvLinkReasons.VersionUnsupported, w.Drops[2].Detail);
        Assert.Equal(2, w.Lines.Count(l => l.Contains("[handshake]", StringComparison.Ordinal)));
    }

    [Fact]
    public async Task ReplacedTvIsReplaced()
    {
        await using var w = new Watched();
        await w.Output.EnsureIngressAsync();
        await using var tv = await w.WelcomedTvAsync();
        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"error\",\"code\":\"replaced\"}");
        Assert.Equal(TvLinkEndReason.Replaced, (await w.DropAsync()).Reason);
    }

    [Fact]
    public async Task OversizedMessageIsError()
    {
        await using var w = new Watched();
        await w.Output.EnsureIngressAsync();
        await using var tv = await w.WelcomedTvAsync();
        await tv.SendAsync("{\"app\":\"nino\",\"type\":\"x\",\"pad\":\"" + new string('a', 600 * 1024) + "\"}");
        var drop = await w.DropAsync();
        Assert.Equal(TvLinkEndReason.Error, drop.Reason);
        Assert.Equal("error", drop.Code);
    }

    [Fact]
    public async Task ClosingTheOutputIsStopped()
    {
        var w = new Watched();
        await w.Output.EnsureStartedAsync();
        await using var tv = await w.WelcomedTvAsync();
        using var legacyTv = await SseReader.OpenAsync(w.Output.LegacyPort, "/events");
        Assert.True(await EventuallyAsync(() => { lock (w.Up) return w.Up.Count == 2; }));
        await w.DisposeAsync();
        Assert.True(await EventuallyAsync(() => w.Drops.Length == 2));
        Assert.All(w.Drops, d => Assert.Equal(TvLinkEndReason.Stopped, d.Reason));
        Assert.Equal([TvLinkKind.Legacy, TvLinkKind.WebTv], w.Drops.Select(d => d.Kind).Order());
        Assert.Contains(w.Lines, l => l.StartsWith($"TV bağlantısı kapatıldı ({w.Port} web TV): Nino kapattı [stopped]"));
    }

    [Theory]
    [InlineData(LinkEnd.Closed, TvLinkEndReason.Closed)]
    [InlineData(LinkEnd.Silent, TvLinkEndReason.Silence)]
    [InlineData(LinkEnd.WriteFailed, TvLinkEndReason.WriteFailed)]
    [InlineData(LinkEnd.Replaced, TvLinkEndReason.Replaced)]
    [InlineData(LinkEnd.Stopped, TvLinkEndReason.Stopped)]
    [InlineData(LinkEnd.NoWelcome, TvLinkEndReason.Handshake)]
    [InlineData(LinkEnd.VersionUnsupported, TvLinkEndReason.Handshake)]
    [InlineData(LinkEnd.Failed, TvLinkEndReason.Error)]
    public void EndsMapToReasons(LinkEnd end, TvLinkEndReason reason) => Assert.Equal(reason, TvOutput.ReasonOf(end));

    [Fact]
    public void ReasonCodesAreFixed() =>
        Assert.Equal(["closed", "write_failed", "silence", "handshake", "replaced", "stopped", "error"],
            Enum.GetValues<TvLinkEndReason>().Select(TvLinkReasons.Code));

    // ---- LinkPeer, sahte WebSocket ile ----

    /// <summary>Mesajları elle verilen, gönderme hatası taklit edilebilen WebSocket.</summary>
    sealed class FakeSocket : WebSocket
    {
        readonly Channel<object> inbox = Channel.CreateUnbounded<object>();
        public readonly List<string> Sent = [];
        public bool FailSends;
        WebSocketState state = WebSocketState.Open;

        public void Deliver(string text) => inbox.Writer.TryWrite(text);
        public void Throw(Exception e) => inbox.Writer.TryWrite(e);

        public override WebSocketCloseStatus? CloseStatus => null;
        public override string? CloseStatusDescription => null;
        public override WebSocketState State => state;
        public override string? SubProtocol => null;
        public override void Abort() => state = WebSocketState.Aborted;
        public override Task CloseAsync(WebSocketCloseStatus s, string? d, CancellationToken ct) { state = WebSocketState.Closed; return Task.CompletedTask; }
        public override Task CloseOutputAsync(WebSocketCloseStatus s, string? d, CancellationToken ct) { state = WebSocketState.CloseSent; return Task.CompletedTask; }
        public override void Dispose() => state = WebSocketState.Closed;

        public override async Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken ct)
        {
            var item = await inbox.Reader.ReadAsync(ct);
            if (item is Exception e) throw e;
            var bytes = Encoding.UTF8.GetBytes((string)item);
            bytes.CopyTo(buffer.Array!, buffer.Offset);
            return new WebSocketReceiveResult(bytes.Length, WebSocketMessageType.Text, true);
        }

        public override Task SendAsync(ArraySegment<byte> buffer, WebSocketMessageType type, bool end, CancellationToken ct)
        {
            if (FailSends) throw new WebSocketException(WebSocketError.ConnectionClosedPrematurely);
            lock (Sent) Sent.Add(Encoding.UTF8.GetString(buffer.Array!, buffer.Offset, buffer.Count));
            return Task.CompletedTask;
        }
    }

    [Fact]
    public async Task WriteFailureIsWriteFailed()
    {
        var socket = new FakeSocket();
        var peer = new LinkPeer(socket, "10.0.0.9");
        socket.Deliver(Welcome);
        var run = peer.RunAsync("Windows", "nino-windows/4.0.0", 1, p =>
        {
            socket.FailSends = true;
            p.Send("{\"app\":\"nino\",\"type\":\"started\"}");
        }, CancellationToken.None);
        Assert.Equal(LinkEnd.WriteFailed, await run.WaitAsync(Wait));
        Assert.NotNull(peer.ReadyAt);
    }

    [Fact]
    public async Task UnexpectedReceiveErrorIsFailedAndResetIsClosed()
    {
        var socket = new FakeSocket();
        var peer = new LinkPeer(socket, "10.0.0.9");
        socket.Deliver(Welcome);
        var run = peer.RunAsync("Windows", "c", 1, null, CancellationToken.None);
        socket.Throw(new InvalidOperationException("bozuk"));
        Assert.Equal(LinkEnd.Failed, await run.WaitAsync(Wait));

        var reset = new FakeSocket();
        var second = new LinkPeer(reset, "10.0.0.9");
        reset.Deliver(Welcome);
        var run2 = second.RunAsync("Windows", "c", 1, null, CancellationToken.None);
        reset.Throw(new WebSocketException(WebSocketError.ConnectionClosedPrematurely));
        Assert.Equal(LinkEnd.Closed, await run2.WaitAsync(Wait));
    }

    [Fact]
    public async Task StopBeforeAndAfterWelcomeIsStopped()
    {
        var socket = new FakeSocket();
        var peer = new LinkPeer(socket, "10.0.0.9");
        var run = peer.RunAsync("Windows", "c", 1, null, CancellationToken.None);
        await Task.Delay(50);
        peer.Stop();
        Assert.Equal(LinkEnd.Stopped, await run.WaitAsync(Wait));

        var ready = new FakeSocket();
        var second = new LinkPeer(ready, "10.0.0.9");
        ready.Deliver(Welcome);
        using var cts = new CancellationTokenSource();
        var run2 = second.RunAsync("Windows", "c", 1, _ => cts.CancelAfter(50), cts.Token);
        Assert.Equal(LinkEnd.Stopped, await run2.WaitAsync(Wait));
    }

    // ---- Eski 8787 ----

    /// <summary>Okuması gerçek akıştan, yazması istenince hata veren akış.</summary>
    sealed class BreakableStream(Stream inner) : Stream
    {
        public volatile bool Broken;
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => inner.Flush();
        public override Task FlushAsync(CancellationToken ct) => Broken ? throw new IOException("kırık") : inner.FlushAsync(ct);
        public override int Read(byte[] buffer, int offset, int count) => inner.Read(buffer, offset, count);
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct = default) => inner.ReadAsync(buffer, ct);
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count)
        {
            if (Broken) throw new IOException("kırık");
            inner.Write(buffer, offset, count);
        }
        public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken ct = default) =>
            Broken ? throw new IOException("kırık") : inner.WriteAsync(buffer, ct);
    }

    [Fact]
    public async Task LegacyHeartbeatIsWrittenRegularlyAndAWriteFailureDropsTheListener()
    {
        var streams = new List<BreakableStream>();
        using var server = new LegacySubtitleServer(pingInterval: TimeSpan.FromMilliseconds(40))
        {
            WrapStream = s =>
            {
                var b = new BreakableStream(s);
                lock (streams) streams.Add(b);
                return b;
            },
        };
        var up = new List<LegacyTvClient>();
        var down = new List<(LegacyTvClient Tv, TvLinkEndReason Reason)>();
        server.TvConnected += c => { lock (up) up.Add(c); };
        server.TvDropped += (c, r) => { lock (down) down.Add((c, r)); };
        var port = server.Start(0);

        using var tv = await SseReader.OpenAsync(port, "/events?model=LG+OLED55C1");
        var text = await tv.WaitForAsync("event: ping\ndata: {}\n\n: ping\n\nevent: ping");
        Assert.Contains(": ping\n\nevent: ping\ndata: {}\n\n", text);
        Assert.True(await EventuallyAsync(() => { lock (up) return up.Count == 1; }));
        Assert.Equal("LG OLED55C1", up[0].Model);
        Assert.Equal("127.0.0.1", up[0].Address);

        lock (streams) streams[0].Broken = true;
        Assert.True(await EventuallyAsync(() => { lock (down) return down.Count == 1; }));
        Assert.Equal(TvLinkEndReason.WriteFailed, down[0].Reason);
        Assert.Equal(up[0].Id, down[0].Tv.Id);
        Assert.Equal(0, server.TvCount);
        await Task.Delay(100);
        lock (down) Assert.Single(down);
    }

    [Fact]
    public async Task LegacyTvClosingIsClosedAndObsIsNotATv()
    {
        var lines = new List<string>();
        await using var output = new TvOutput(new TvOutputOptions
        {
            LegacyPort = 0, IngressPort = FreePort(), PortAttempts = 1,
            Log = l => { lock (lines) lines.Add(l); },
        });
        var down = new List<TvLinkDropped>();
        var up = new List<TvLinkConnected>();
        output.TvConnected += e => { lock (up) up.Add(e); };
        output.TvDropped += e => { lock (down) down.Add(e); };
        var port = await output.EnsureLegacyServerAsync();

        using (var obs = await SseReader.OpenAsync(port, "/events?viewer=obs"))
            await obs.WaitForAsync("retry: 2000");
        var tv = await SseReader.OpenAsync(port, "/events?model=Samsung%20QE65Q80C");
        await tv.WaitForAsync("retry: 2000");
        Assert.True(await EventuallyAsync(() => { lock (up) return up.Count == 1; }));
        Assert.Equal(TvLinkKind.Legacy, up[0].Kind);
        Assert.Equal(TimeSpan.Zero, up[0].Took);
        Assert.Contains($"TV bağlandı ({port}, Samsung QE65Q80C): 127.0.0.1", lines);

        tv.Dispose();
        Assert.True(await EventuallyAsync(() => { lock (down) return down.Count == 1; }));
        Assert.Equal(TvLinkEndReason.Closed, down[0].Reason);
        Assert.Equal("Samsung QE65Q80C", down[0].Model);
        await Task.Delay(100);
        lock (up) Assert.Single(up);
        lock (down) Assert.Single(down);
    }
}
