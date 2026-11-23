// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;

namespace Nino.Core.Link;

/// <summary>Gönderici girişinin kimliği (<c>/nino/info</c> ve <c>hello</c>).</summary>
public sealed record SenderIdentity
{
    /// <summary>Bilgisayar adı (<c>info.name</c>).</summary>
    public string Name { get; init; } = Environment.MachineName;

    /// <summary>İlk açılışta üretilip saklanan kalıcı kimlik (gizli değil).</summary>
    public string Id { get; init; } = "";

    /// <summary><c>hello.device</c>.</summary>
    public string Device { get; init; } = "Windows";

    /// <summary><c>hello.client</c>, ör. <c>nino-windows/4.0.0</c>.</summary>
    public string Client { get; init; } = "nino-windows/0.0.0";
}

/// <summary>
/// Gönderici girişi (ters yön): LG/Samsung web TV'leri <c>ws://&lt;bilgisayar&gt;:47800/nino/ws</c> ile bağlanır.
/// <c>GET /nino/info</c> (<c>role:"sender"</c>), <c>OPTIONS</c> 204 ve <c>GET /nino/ws</c> sunar; yalnız özel
/// adreslerden gelen bağlantı kabul edilir. Birden çok TV aynı anda bağlanabilir; her mesaj hepsine gider.
/// </summary>
public sealed class LinkIngress : IDisposable
{
    /// <summary>Varsayılan port.</summary>
    public const int DefaultPort = 47800;

    readonly SenderIdentity identity;
    readonly LinkTimings timings;
    readonly TimeProvider clock;
    readonly object gate = new();
    readonly List<LinkPeer> peers = [];
    TcpListener? listener;
    CancellationTokenSource? life;

    public LinkIngress(SenderIdentity identity, LinkTimings? timings = null, TimeProvider? clock = null)
    {
        this.identity = identity;
        this.timings = timings ?? LinkTimings.Default;
        this.clock = clock ?? TimeProvider.System;
    }

    /// <summary><c>welcome</c> almış TV'lerin listesi değişti.</summary>
    public event Action<IReadOnlyList<TvLinkInfo>>? DisplaysChanged;

    /// <summary>
    /// Yeni bir TV hazır oldu (<c>welcome</c> geldi): buradan hazırlık mesajları (<see cref="LinkPeer.Send"/>) verilir.
    /// </summary>
    public Action<LinkPeer>? OnReady { get; set; }

    /// <summary>Bir TV hazır oldu (hazırlık mesajlarından sonra; herhangi bir iş parçacığında).</summary>
    public event Action<LinkPeer>? PeerConnected;

    /// <summary>Bir TV bağlantısı bitti (hazır olmamış olabilir; <see cref="LinkPeer.ReadyAt"/>).</summary>
    public event Action<LinkPeer, LinkEnd>? PeerEnded;

    /// <summary>Dinlenen port; açılmadıysa 0.</summary>
    public int Port { get; private set; }

    public bool IsRunning => listener is not null;

    /// <summary><c>welcome</c> almış TV'ler.</summary>
    public IReadOnlyList<TvLinkInfo> Displays
    {
        get { lock (gate) return peers.Where(p => p.IsReady).Select(p => p.Info!).ToList(); }
    }

    public int TvCount => Displays.Count;

    /// <summary>Dinlemeye başlar; port doluysa hata fırlatır.</summary>
    public int Start(int port = DefaultPort)
    {
        lock (gate)
        {
            if (listener is not null) return Port;
            var l = HttpWire.Listen(port);
            listener = l;
            Port = ((IPEndPoint)l.LocalEndpoint).Port;
            life = new CancellationTokenSource();
            _ = AcceptLoopAsync(l, life.Token);
            return Port;
        }
    }

    public void Stop()
    {
        LinkPeer[] all;
        lock (gate)
        {
            life?.Cancel();
            try { listener?.Stop(); } catch (Exception) { }
            listener = null;
            Port = 0;
            all = peers.ToArray();
            peers.Clear();
        }
        foreach (var p in all) p.Stop();
    }

    public void Dispose() => Stop();

    /// <summary>Mesajı hazır olan bütün TV'lere yollar.</summary>
    public void Broadcast(string message)
    {
        LinkPeer[] targets;
        lock (gate) targets = peers.Where(p => p.IsReady).ToArray();
        foreach (var p in targets) p.Send(message);
    }

    /// <summary>
    /// Gönderici etkin mi (çeviri sürüyor ve altyazı TV'ye gidiyor). <c>/nino/info</c> ve <c>hello</c> bunu
    /// <c>active</c> olarak taşır; değişince <see cref="TvOutput"/> bağlı TV'lere <c>state</c> yollar.
    /// </summary>
    public bool Active { get => Volatile.Read(ref active); set => Volatile.Write(ref active, value); }

    bool active;

    /// <summary><c>/nino/info</c> gövdesi.</summary>
    public string InfoJson() => TvWire.Envelope("info", new WireObject
    {
        ["version"] = TvWire.ProtocolVersion,
        ["versions"] = new List<object> { TvWire.ProtocolVersion },
        ["name"] = identity.Name,
        ["id"] = identity.Id,
        ["role"] = "sender",
        ["active"] = Active,
    });

    async Task AcceptLoopAsync(TcpListener l, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient tcp;
            try { tcp = await l.AcceptTcpClientAsync(ct).ConfigureAwait(false); }
            catch (Exception) { return; }
            var remote = (tcp.Client.RemoteEndPoint as IPEndPoint)?.Address;
            if (!HttpWire.IsPrivateOrLocal(remote))
            {
                tcp.Dispose();
                continue;
            }
            HttpWire.Tune(tcp.Client);
            _ = HandleAsync(tcp, remote!, ct);
        }
    }

    async Task HandleAsync(TcpClient tcp, IPAddress remote, CancellationToken ct)
    {
        try
        {
            var stream = tcp.GetStream();
            HttpHead? head;
            using (var headWait = CancellationTokenSource.CreateLinkedTokenSource(ct))
            {
                headWait.CancelAfter(TimeSpan.FromSeconds(10));
                head = await HttpHead.ReadAsync(stream, 64 * 1024, 4096, headWait.Token).ConfigureAwait(false);
            }
            if (head is null)
            {
                tcp.Dispose();
                return;
            }

            if (head.Method == "OPTIONS")
            {
                await WriteAndCloseAsync(tcp, "204 No Content", "Access-Control-Allow-Origin: *\r\n"
                    + "Access-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\n", "")
                    .ConfigureAwait(false);
            }
            else if (head.Method == "GET" && head.Path == "/nino/info")
            {
                await WriteAndCloseAsync(tcp, "200 OK",
                    "Content-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n", InfoJson()).ConfigureAwait(false);
            }
            else if (head.Method == "GET" && head.Path == "/nino/ws" && head.Header("Sec-WebSocket-Key") is { Length: > 0 } key
                && (head.Header("Upgrade") ?? "").Contains("websocket", StringComparison.OrdinalIgnoreCase))
            {
                var accept = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                    + $"Sec-WebSocket-Accept: {HttpWire.WebSocketAccept(key)}\r\n\r\n";
                await stream.WriteAsync(Encoding.ASCII.GetBytes(accept), ct).ConfigureAwait(false);
                await stream.FlushAsync(ct).ConfigureAwait(false);
                var ws = WebSocket.CreateFromStream(HttpWire.WithPrefix(stream, head.Leftover),
                    new WebSocketCreationOptions { IsServer = true, KeepAliveInterval = TimeSpan.Zero });
                await RunPeerAsync(ws, remote, ct).ConfigureAwait(false);
                tcp.Dispose();
            }
            else
            {
                await WriteAndCloseAsync(tcp, "404 Not Found", "Access-Control-Allow-Origin: *\r\n", "").ConfigureAwait(false);
            }
        }
        catch (Exception)
        {
            tcp.Dispose();
        }
    }

    async Task RunPeerAsync(WebSocket ws, IPAddress remote, CancellationToken ct)
    {
        var address = remote.IsIPv4MappedToIPv6 ? remote.MapToIPv4().ToString() : remote.ToString();
        var peer = new LinkPeer(ws, address, timings, clock);
        lock (gate) peers.Add(peer);
        var end = LinkEnd.Stopped;
        try
        {
            end = await peer.RunAsync(identity.Device, identity.Client, TvWire.ProtocolVersion, p =>
            {
                try { OnReady?.Invoke(p); } catch (Exception) { }
                Notify();
                try { PeerConnected?.Invoke(p); } catch (Exception) { }
            }, ct, () => Active).ConfigureAwait(false);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            end = LinkEnd.Failed;
        }
        finally
        {
            bool removed;
            lock (gate) removed = peers.Remove(peer);
            await peer.DisposeAsync().ConfigureAwait(false);
            if (removed && peer.Info is not null) Notify();
            try { PeerEnded?.Invoke(peer, end); } catch (Exception) { }
        }
    }

    void Notify()
    {
        var list = Displays;
        try { DisplaysChanged?.Invoke(list); } catch (Exception) { }
    }

    static async Task WriteAndCloseAsync(TcpClient tcp, string status, string headers, string body)
    {
        using (tcp)
        {
            var bytes = Encoding.UTF8.GetBytes(body);
            var head = $"HTTP/1.1 {status}\r\n{headers}Content-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
            var stream = tcp.GetStream();
            await stream.WriteAsync(Encoding.ASCII.GetBytes(head)).ConfigureAwait(false);
            await stream.WriteAsync(bytes).ConfigureAwait(false);
            await stream.FlushAsync().ConfigureAwait(false);
        }
    }
}
