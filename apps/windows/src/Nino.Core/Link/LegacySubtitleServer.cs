// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading.Channels;

namespace Nino.Core.Link;

/// <summary>
/// Eski TV uygulamaları ve OBS için 8787 altyazı sunucusu: elle konuşulan HTTP + SSE (<c>/events</c>), OBS sayfası
/// (<c>/obs</c>) ve <c>/hello</c>. Düz <see cref="TcpListener"/> üzerindedir (yönetici izni ya da URL ACL gerekmez).
/// </summary>
public sealed class LegacySubtitleServer : IDisposable
{
    /// <summary>Varsayılan port.</summary>
    public const int DefaultPort = 8787;

    /// <summary>Kalp atışı (SSE <c>ping</c>) aralığı.</summary>
    public static readonly TimeSpan DefaultPingInterval = TimeSpan.FromSeconds(15);

    static readonly TimeSpan StartedReplayWindow = TimeSpan.FromSeconds(20);
    const string PingText = ": ping\n\nevent: ping\ndata: {}\n\n";
    const string StartedFrame = "event: started\ndata: {}\n\n";

    /// <summary>SSE akışının açılışı (başlıklar ve <c>retry</c>), ilk yazmada tek parça.</summary>
    const string StreamHead = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\n"
        + "Connection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\nretry: 2000\n\n";

    readonly TimeProvider clock;
    readonly TimeSpan pingEvery;
    readonly object gate = new();
    readonly List<Client> clients = [];
    TcpListener? listener;
    ITimer? pingTimer;
    CancellationTokenSource? life;
    string? lastStyleFrame;
    DateTimeOffset? startedAt;
    bool stopping;
    volatile bool subtitlesOnTv = true;

    /// <param name="clock">Saat (<c>at</c> alanı ve <c>started</c> tekrarı için).</param>
    /// <param name="pingInterval">Ping aralığı; verilmezse 15 sn (testler kısaltır).</param>
    public LegacySubtitleServer(TimeProvider? clock = null, TimeSpan? pingInterval = null)
    {
        this.clock = clock ?? TimeProvider.System;
        pingEvery = pingInterval ?? DefaultPingInterval;
    }

    /// <summary>Testler için: istemci akışını sarmalar (yazma hatası taklidi).</summary>
    internal Func<Stream, Stream>? WrapStream { get; init; }

    /// <summary>Bağlı TV sayısı (OBS izleyicileri hariç) değişti; izleyici bağlanınca da çağrılır.</summary>
    public event Action<int>? TvCountChanged;

    /// <summary>TV istemcisi <c>?model=</c> ile modelini söyledi (akış açılmadan önce).</summary>
    public event Action<string>? ModelReported;

    /// <summary>Bir TV'nin akışı açıldı (OBS izleyicisi hariç; herhangi bir iş parçacığında).</summary>
    public event Action<LegacyTvClient>? TvConnected;

    /// <summary>
    /// Bağlanmış bir TV'nin akışı bitti: <see cref="TvLinkEndReason.Closed"/> (TV kapattı / koptu),
    /// <see cref="TvLinkEndReason.WriteFailed"/>, <see cref="TvLinkEndReason.Stopped"/> (<see cref="Stop"/>) ya da
    /// <see cref="TvLinkEndReason.Error"/>.
    /// </summary>
    public event Action<LegacyTvClient, TvLinkEndReason>? TvDropped;

    /// <summary>Gerçekten dinlenen port; açılmadıysa 0.</summary>
    public int Port { get; private set; }

    public bool IsRunning => listener is not null;

    /// <summary>Kapalıyken altyazı olayları yalnız OBS'e gider; <c>started</c>/<c>stopped</c>/<c>ping</c> herkese.</summary>
    public bool SubtitlesOnTv
    {
        get => subtitlesOnTv;
        set => subtitlesOnTv = value;
    }

    /// <summary>Listedeki izleyici olmayan istemciler.</summary>
    public int TvCount
    {
        get { lock (gate) return clients.Count(c => !c.Viewer); }
    }

    /// <summary>Verilen portta (0: işletim sisteminin seçtiği boş port) dinlemeye başlar. Port doluysa hata fırlatır.</summary>
    public int Start(int port)
    {
        lock (gate)
        {
            if (listener is not null) return Port;
            var l = HttpWire.Listen(port);
            listener = l;
            stopping = false;
            Port = ((System.Net.IPEndPoint)l.LocalEndpoint).Port;
            life = new CancellationTokenSource();
            pingTimer = clock.CreateTimer(_ => Broadcast(PingText, subtitleEvent: false), null, pingEvery, pingEvery);
            _ = AcceptLoopAsync(l, life.Token);
            return Port;
        }
    }

    /// <summary>Dinleyiciyi ve bütün bağlantıları kapatır ("TV sayısı değişti" bildirilmez).</summary>
    public void Stop()
    {
        Client[] all;
        lock (gate)
        {
            stopping = true;
            pingTimer?.Dispose();
            pingTimer = null;
            life?.Cancel();
            try { listener?.Stop(); } catch (Exception) { }
            listener = null;
            Port = 0;
            all = clients.ToArray();
            clients.Clear();
        }
        foreach (var c in all) c.Close();
        foreach (var c in all)
            if (c.Info is { } info) RaiseDropped(info, TvLinkEndReason.Stopped);
    }

    public void Dispose() => Stop();

    /// <summary>Olayı bağlı istemcilere yollar (kapı kuralıyla). Son stil ve başlama anı saklanır.</summary>
    public void Send(TvEvent e)
    {
        var frame = TvWire.LegacyFrame(e, clock.GetUtcNow().ToUnixTimeMilliseconds());
        lock (gate)
        {
            if (e is StyleChanged) lastStyleFrame = frame;
            if (e is TranslationStarted) startedAt = clock.GetUtcNow();
        }
        Broadcast(frame, TvWire.IsSubtitleEvent(e));
    }

    void Broadcast(string text, bool subtitleEvent)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        Client[] targets;
        lock (gate) targets = clients.ToArray();
        var toTv = subtitlesOnTv || !subtitleEvent;
        foreach (var c in targets)
            if (toTv || c.Viewer) c.Enqueue(bytes);
    }

    async Task AcceptLoopAsync(TcpListener l, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient tcp;
            try { tcp = await l.AcceptTcpClientAsync(ct).ConfigureAwait(false); }
            catch (Exception) { break; }
            HttpWire.Tune(tcp.Client);
            _ = HandleAsync(tcp, ct);
        }
    }

    async Task HandleAsync(TcpClient tcp, CancellationToken ct)
    {
        try
        {
            var stream = tcp.GetStream();
            var head = await HttpHead.ReadAsync(stream, 64 * 1024, 8 * 1024, ct).ConfigureAwait(false);
            if (head is null)
            {
                tcp.Dispose();
                return;
            }
            if (head.Method == "OPTIONS")
                await StatusAsync(tcp, "204 No Content", "").ConfigureAwait(false);
            else if (head.Method == "GET" && head.Path == "/events")
                await StreamAsync(tcp, head).ConfigureAwait(false);
            else if (head.Method == "GET" && head.Path == "/obs")
                await FileAsync(tcp, ObsPage.Bytes, "text/html; charset=utf-8").ConfigureAwait(false);
            else if (head.Method == "GET" && head.Path == "/hello")
                await StatusAsync(tcp, "200 OK", "{\"app\":\"nino\"}").ConfigureAwait(false);
            else
                await StatusAsync(tcp, "404 Not Found", "").ConfigureAwait(false);
        }
        catch (Exception)
        {
            tcp.Dispose();
        }
    }

    static async Task StatusAsync(TcpClient tcp, string status, string body)
    {
        using (tcp)
        {
            var text = $"HTTP/1.1 {status}\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: {body.Length}\r\n"
                + $"Connection: close\r\n\r\n{body}";
            var stream = tcp.GetStream();
            await stream.WriteAsync(Encoding.ASCII.GetBytes(text)).ConfigureAwait(false);
            await stream.FlushAsync().ConfigureAwait(false);
        }
    }

    static async Task FileAsync(TcpClient tcp, byte[] bytes, string contentType)
    {
        using (tcp)
        {
            var head = $"HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Type: {contentType}\r\n"
                + $"Cache-Control: no-cache\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
            var stream = tcp.GetStream();
            await stream.WriteAsync(Encoding.ASCII.GetBytes(head)).ConfigureAwait(false);
            await stream.WriteAsync(bytes).ConfigureAwait(false);
            await stream.FlushAsync().ConfigureAwait(false);
        }
    }

    async Task StreamAsync(TcpClient tcp, HttpHead head)
    {
        var viewer = head.Target.Contains("viewer=obs", StringComparison.Ordinal);
        if (!viewer && ParseModel(head.Query) is { } model)
        {
            try { ModelReported?.Invoke(model); } catch (Exception) { }
        }

        var stream = WrapStream is { } wrap ? wrap(tcp.GetStream()) : tcp.GetStream();
        var client = new Client(tcp, stream, viewer, this);
        var sb = new StringBuilder(StreamHead);
        lock (gate)
        {
            if (stopping)
            {
                tcp.Dispose();
                return;
            }
            clients.Add(client);
            if (lastStyleFrame is not null) sb.Append(lastStyleFrame);
            if (!viewer && startedAt is { } at && clock.GetUtcNow() - at < StartedReplayWindow) sb.Append(StartedFrame);
        }

        try
        {
            await stream.WriteAsync(Encoding.UTF8.GetBytes(sb.ToString())).ConfigureAwait(false);
            await stream.FlushAsync().ConfigureAwait(false);
        }
        catch (Exception)
        {
            Remove(client, TvLinkEndReason.WriteFailed);
            return;
        }
        NotifyCount();
        if (!viewer)
        {
            LegacyTvClient? info = null;
            lock (gate)
            {
                if (!stopping && clients.Contains(client))
                {
                    info = new LegacyTvClient(TvLinkReasons.NextId(), RemoteAddress(tcp), ParseModel(head.Query), clock.GetUtcNow());
                    client.Info = info;
                }
            }
            if (info is not null)
            {
                try { TvConnected?.Invoke(info); } catch (Exception) { }
            }
        }
        client.StartWriting();

        var sink = new byte[1024];
        var reason = TvLinkEndReason.Closed;
        try
        {
            while (await stream.ReadAsync(sink).ConfigureAwait(false) > 0) { }
        }
        catch (Exception e) when (e is not (IOException or SocketException or ObjectDisposedException))
        {
            reason = TvLinkEndReason.Error;
        }
        catch (Exception) { }
        Remove(client, reason);
    }

    /// <summary>İstemciyi bir kez çıkarır; ilk çıkaran sebebi belirler (ikinci çıkarma bildirim üretmez).</summary>
    void Remove(Client client, TvLinkEndReason reason)
    {
        bool removed;
        lock (gate) removed = !stopping && clients.Remove(client);
        client.Close();
        if (!removed) return;
        NotifyCount();
        if (client.Info is { } info) RaiseDropped(info, reason);
    }

    void RaiseDropped(LegacyTvClient info, TvLinkEndReason reason)
    {
        try { TvDropped?.Invoke(info, reason); } catch (Exception) { }
    }

    static string RemoteAddress(TcpClient tcp)
    {
        try
        {
            if (tcp.Client.RemoteEndPoint is System.Net.IPEndPoint ep)
                return (ep.Address.IsIPv4MappedToIPv6 ? ep.Address.MapToIPv4() : ep.Address).ToString();
        }
        catch (Exception) { }
        return "";
    }

    void NotifyCount()
    {
        var count = TvCount;
        try { TvCountChanged?.Invoke(count); } catch (Exception) { }
    }

    /// <summary>
    /// <c>model=</c> sorgusu: ilk tam adlı çift, <c>+</c> boşluk, yüzde kodu çözülür; harf, rakam, boşluk ve
    /// <c>. - _ ( )</c> kalır, kırpılır, en çok 60 karakter. Boşsa <c>null</c>.
    /// </summary>
    public static string? ParseModel(string query)
    {
        foreach (var pair in query.Split('&'))
        {
            var eq = pair.IndexOf('=');
            var name = eq >= 0 ? pair[..eq] : pair;
            if (name != "model") continue;
            string decoded;
            try { decoded = Uri.UnescapeDataString((eq >= 0 ? pair[(eq + 1)..] : "").Replace('+', ' ')); }
            catch (Exception) { return null; }
            var kept = new string(decoded.Where(c =>
                char.IsLetterOrDigit(c) || c is ' ' or '.' or '-' or '_' or '(' or ')').ToArray()).Trim();
            if (kept.Length == 0) return null;
            return kept.Length > 60 ? kept[..60] : kept;
        }
        return null;
    }

    sealed class Client(TcpClient tcp, Stream stream, bool viewer, LegacySubtitleServer owner)
    {
        readonly Channel<byte[]> queue = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions { SingleReader = true });

        public bool Viewer => viewer;

        /// <summary>Akışı açılmış TV (izleyici ve açılamayan akış için null).</summary>
        public LegacyTvClient? Info { get; set; }

        public void Enqueue(byte[] bytes) => queue.Writer.TryWrite(bytes);

        public void StartWriting() => _ = WriteLoopAsync();

        async Task WriteLoopAsync()
        {
            try
            {
                await foreach (var bytes in queue.Reader.ReadAllAsync().ConfigureAwait(false))
                {
                    await stream.WriteAsync(bytes).ConfigureAwait(false);
                    await stream.FlushAsync().ConfigureAwait(false);
                }
            }
            catch (Exception)
            {
                owner.Remove(this, TvLinkEndReason.WriteFailed);
            }
        }

        public void Close()
        {
            queue.Writer.TryComplete();
            try { tcp.Dispose(); } catch (Exception) { }
        }
    }
}

/// <summary>8787'ye bağlanmış bir TV (adres yalnız günlük içindir).</summary>
public sealed record LegacyTvClient(long Id, string Address, string? Model, DateTimeOffset ConnectedAt);

/// <summary>Gömülü OBS tarayıcı kaynağı sayfası.</summary>
public static class ObsPage
{
    static readonly Lazy<byte[]> bytes = new(() =>
    {
        using var s = typeof(ObsPage).Assembly.GetManifestResourceStream("link/obs.html")
            ?? throw new InvalidOperationException("OBS sayfası gömülü değil");
        using var m = new MemoryStream();
        s.CopyTo(m);
        return m.ToArray();
    });

    public static byte[] Bytes => bytes.Value;
}
