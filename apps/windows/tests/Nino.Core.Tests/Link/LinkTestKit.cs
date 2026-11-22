// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using Nino.Core.Link;

namespace Nino.Core.Tests.Link;

/// <summary>İleri alınabilen saat (zamanlayıcılar gerçek saatle çalışır).</summary>
sealed class ManualClock(DateTimeOffset start) : TimeProvider
{
    DateTimeOffset now = start;

    public override DateTimeOffset GetUtcNow() => now;

    public void Advance(TimeSpan by) => now += by;
}

/// <summary>Ağ testleri için küçük yardımcılar (yalnız 127.0.0.1).</summary>
static class LinkTestKit
{
    public static readonly TimeSpan Wait = TimeSpan.FromSeconds(5);

    public static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    /// <summary>Ham HTTP isteği gönderip bütün cevabı (bağlantı kapanana kadar) okur.</summary>
    public static async Task<string> RawAsync(int port, string request)
    {
        using var tcp = new TcpClient();
        await tcp.ConnectAsync(IPAddress.Loopback, port);
        var stream = tcp.GetStream();
        await stream.WriteAsync(Encoding.ASCII.GetBytes(request));
        using var cts = new CancellationTokenSource(Wait);
        var all = new MemoryStream();
        var buffer = new byte[4096];
        int n;
        while ((n = await stream.ReadAsync(buffer, cts.Token)) > 0) all.Write(buffer, 0, n);
        return Encoding.UTF8.GetString(all.ToArray());
    }

    /// <summary>Açık kalan bir SSE akışı.</summary>
    public sealed class SseReader : IDisposable
    {
        readonly TcpClient tcp = new();
        readonly StringBuilder text = new();
        Task? pump;

        public static async Task<SseReader> OpenAsync(int port, string target)
        {
            var r = new SseReader();
            await r.tcp.ConnectAsync(IPAddress.Loopback, port);
            await r.tcp.GetStream().WriteAsync(Encoding.ASCII.GetBytes($"GET {target} HTTP/1.1\r\nHost: x\r\n\r\n"));
            r.pump = r.PumpAsync();
            return r;
        }

        async Task PumpAsync()
        {
            var buffer = new byte[4096];
            try
            {
                int n;
                while ((n = await tcp.GetStream().ReadAsync(buffer)) > 0)
                    lock (text) text.Append(Encoding.UTF8.GetString(buffer, 0, n));
            }
            catch (Exception) { }
        }

        public string Text
        {
            get { lock (text) return text.ToString(); }
        }

        public async Task<string> WaitForAsync(string fragment)
        {
            var until = DateTime.UtcNow + Wait;
            while (DateTime.UtcNow < until)
            {
                if (Text.Contains(fragment, StringComparison.Ordinal)) return Text;
                await Task.Delay(10);
            }
            throw new TimeoutException($"'{fragment}' gelmedi; gelen: {Text}");
        }

        public void Dispose() => tcp.Dispose();
    }

    /// <summary>Gelen mesajları biriktiren WebSocket ucu (TV rolü).</summary>
    public sealed class SocketPeer(WebSocket socket) : IAsyncDisposable
    {
        readonly List<string> received = [];
        Task? pump;

        public WebSocket Socket => socket;

        public void StartReading() => pump = PumpAsync();

        async Task PumpAsync()
        {
            var buffer = new byte[65536];
            try
            {
                while (true)
                {
                    var all = new MemoryStream();
                    WebSocketReceiveResult r;
                    do
                    {
                        r = await socket.ReceiveAsync(buffer, CancellationToken.None);
                        if (r.MessageType == WebSocketMessageType.Close) return;
                        all.Write(buffer, 0, r.Count);
                    } while (!r.EndOfMessage);
                    lock (received) received.Add(Encoding.UTF8.GetString(all.ToArray()));
                }
            }
            catch (Exception) { }
        }

        public List<string> Received
        {
            get { lock (received) return received.ToList(); }
        }

        public bool Closed => pump is { IsCompleted: true };

        public async Task<string> WaitForTypeAsync(string type, int skip = 0)
        {
            var until = DateTime.UtcNow + Wait;
            while (DateTime.UtcNow < until)
            {
                var match = Received.Where(m => TypeOf(m) == type).Skip(skip).FirstOrDefault();
                if (match is not null) return match;
                await Task.Delay(10);
            }
            throw new TimeoutException($"'{type}' gelmedi; gelen: {string.Join(" | ", Received)}");
        }

        public Task SendAsync(string text) =>
            socket.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, CancellationToken.None);

        public async ValueTask DisposeAsync()
        {
            try { socket.Abort(); } catch (Exception) { }
            socket.Dispose();
            if (pump is not null) await pump;
        }
    }

    public static string? TypeOf(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty("type", out var t) ? t.GetString() : null;
        }
        catch (JsonException) { return null; }
    }

    public static async Task<bool> EventuallyAsync(Func<bool> condition)
    {
        var until = DateTime.UtcNow + Wait;
        while (DateTime.UtcNow < until)
        {
            if (condition()) return true;
            await Task.Delay(10);
        }
        return condition();
    }

    /// <summary>Web TV gibi girişe bağlanır ve okumaya başlar.</summary>
    public static async Task<SocketPeer> ConnectTvAsync(int port)
    {
        var ws = new ClientWebSocket();
        await ws.ConnectAsync(new Uri($"ws://127.0.0.1:{port}/nino/ws"), CancellationToken.None);
        var peer = new SocketPeer(ws);
        peer.StartReading();
        return peer;
    }
}
