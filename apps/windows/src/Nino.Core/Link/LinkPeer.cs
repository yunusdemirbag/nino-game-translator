// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;

namespace Nino.Core.Link;

/// <summary>Yeni protokolün zamanlamaları (testler kısaltır).</summary>
public sealed record LinkTimings
{
    /// <summary><c>hello</c>'dan sonra <c>welcome</c> bekleme süresi.</summary>
    public TimeSpan WelcomeTimeout { get; init; } = TimeSpan.FromSeconds(5);

    /// <summary>Göndericinin <c>ping</c> aralığı.</summary>
    public TimeSpan PingEvery { get; init; } = TimeSpan.FromSeconds(5);

    /// <summary>TV'den bu kadar hiçbir şey gelmezse bağlantı kopmuş sayılır.</summary>
    public TimeSpan SilenceLimit { get; init; } = TimeSpan.FromSeconds(15);

    public static LinkTimings Default { get; } = new();
}

/// <summary>TV'nin <c>welcome</c>'da söylediği bilgiler.</summary>
public sealed record TvLinkInfo(string Name, string? Model, string? AppVersion, string Address);

/// <summary>Bir bağlantının nasıl bittiği.</summary>
public enum LinkEnd
{
    /// <summary>Kapandı, koptu ya da sustu; yeniden bağlanılabilir.</summary>
    Closed,
    /// <summary>5 sn içinde <c>welcome</c> gelmedi.</summary>
    NoWelcome,
    /// <summary>TV bu sürümü desteklemiyor; <see cref="LinkPeer.SuggestedVersion"/> ortak sürüm (yoksa null).</summary>
    VersionUnsupported,
    /// <summary>Başka bir gönderici TV'yi aldı.</summary>
    Replaced,
    /// <summary><see cref="LinkTimings.SilenceLimit"/> boyunca TV'den hiçbir şey gelmedi.</summary>
    Silent,
    /// <summary>TV'ye yazılamadı.</summary>
    WriteFailed,
    /// <summary>Bağlantıyı biz bitirdik (<see cref="LinkPeer.Stop"/> ya da iptal).</summary>
    Stopped,
    /// <summary>Sınıflanamayan hata (bozuk ya da çok büyük mesaj, beklenmeyen istisna).</summary>
    Failed,
}

/// <summary>
/// Gönderici tarafından tek bir WebSocket bağlantısı (her iki yön için aynı): ilk mesaj olarak <c>hello</c> yollar,
/// <c>welcome</c> bekler, 5 sn'de bir <c>ping</c> atar, TV'nin <c>ping</c>'ine <c>pong</c> döner, 15 sn sessiz TV'yi
/// kapatır. Mesajlar tek kuyruktan sırayla gider.
/// </summary>
public sealed class LinkPeer : IAsyncDisposable
{
    readonly WebSocket socket;
    readonly string address;
    readonly LinkTimings timings;
    readonly TimeProvider clock;
    readonly Channel<string> outbox = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true });
    readonly CancellationTokenSource stop = new();
    long lastHeardTicks;
    int cause = -1;

    /// <summary>512 KB'ı aşan mesajın yerine dönen işaret (gönderen bağlantı hata sayılır).</summary>
    static readonly string Oversized = new('\0', 1);

    public LinkPeer(WebSocket socket, string address, LinkTimings? timings = null, TimeProvider? clock = null)
    {
        this.socket = socket;
        this.address = address;
        this.timings = timings ?? LinkTimings.Default;
        this.clock = clock ?? TimeProvider.System;
    }

    /// <summary>Karşı tarafın adresi.</summary>
    public string Address => address;

    /// <summary>Bağlantı (ve <see cref="TvLinkReasons"/> olayları) kimliği.</summary>
    public long Id { get; } = TvLinkReasons.NextId();

    /// <summary><see cref="RunAsync"/>'in başladığı an.</summary>
    public DateTimeOffset? StartedAt { get; private set; }

    /// <summary><c>welcome</c>'ın geldiği an (hazır olduysa).</summary>
    public DateTimeOffset? ReadyAt { get; private set; }

    /// <summary><c>welcome</c> geldiyse TV bilgisi.</summary>
    public TvLinkInfo? Info { get; private set; }

    public bool IsReady => Info is not null && !stop.IsCancellationRequested;

    /// <summary><c>version_unsupported</c> geldiyse ortak en büyük sürüm (yoksa null).</summary>
    public int? SuggestedVersion { get; private set; }

    /// <summary>
    /// Bağlantıyı yürütür ve bitince nasıl bittiğini döner. <paramref name="onReady"/> <c>welcome</c>'dan hemen sonra,
    /// mesaj gönderilmeden önce çağrılır (hazırlık mesajlarını <see cref="Send"/> ile kuyruğa koyar).
    /// </summary>
    public async Task<LinkEnd> RunAsync(string device, string client, int version, Action<LinkPeer>? onReady,
        CancellationToken ct)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct, stop.Token);
        var token = linked.Token;
        StartedAt = clock.GetUtcNow();
        Touch();
        try
        {
            var hello = new WireObject { ["version"] = version, ["device"] = device, ["client"] = client };
            await SendNowAsync(TvWire.Envelope("hello", hello), token).ConfigureAwait(false);

            using (var welcomeWait = CancellationTokenSource.CreateLinkedTokenSource(token))
            {
                welcomeWait.CancelAfter(timings.WelcomeTimeout);
                while (Info is null)
                {
                    string? text;
                    try { text = await ReceiveAsync(welcomeWait.Token).ConfigureAwait(false); }
                    catch (OperationCanceledException) when (!token.IsCancellationRequested) { return LinkEnd.NoWelcome; }
                    if (text is null) return LinkEnd.Closed;
                    if (ReferenceEquals(text, Oversized)) return LinkEnd.Failed;
                    var end = HandleBeforeWelcome(text, version);
                    if (end is { } e) return e;
                }
            }

            ReadyAt = clock.GetUtcNow();
            onReady?.Invoke(this);
            var writer = WriteLoopAsync(token);
            var pinger = PingLoopAsync(token);
            var result = await ReadLoopAsync(token).ConfigureAwait(false);
            // Okuma kendiliğinden bittiyse (kapanış, kopma, replaced) onun sonucu; iptalle bittiyse ilk sebep.
            var ending = token.IsCancellationRequested ? Cause() : result;
            stop.Cancel();
            try { await Task.WhenAll(writer, pinger).ConfigureAwait(false); } catch (Exception) { }
            return ending;
        }
        catch (Exception e)
        {
            if (token.IsCancellationRequested) return Cause();
            return e is WebSocketException or IOException ? LinkEnd.Closed : LinkEnd.Failed;
        }
        finally
        {
            stop.Cancel();
            outbox.Writer.TryComplete();
            await CloseAsync().ConfigureAwait(false);
        }
    }

    /// <summary>Mesajı kuyruğa koyar (hazır değilse de; hazırlıkta sırayla gider).</summary>
    public void Send(string message) => outbox.Writer.TryWrite(message);

    /// <summary>Bağlantıyı bitirir (bitiş: <see cref="LinkEnd.Stopped"/>).</summary>
    public void Stop() => EndWith(LinkEnd.Stopped);

    /// <summary>İlk bitiş sebebini kaydeder ve bağlantıyı durdurur (sonrakiler yok sayılır).</summary>
    void EndWith(LinkEnd end)
    {
        Interlocked.CompareExchange(ref cause, (int)end, -1);
        try { stop.Cancel(); } catch (ObjectDisposedException) { }
    }

    /// <summary>İptalle biten bağlantının sebebi (kayıtlı sebep yoksa biz durdurduk).</summary>
    LinkEnd Cause()
    {
        var c = Volatile.Read(ref cause);
        return c >= 0 ? (LinkEnd)c : LinkEnd.Stopped;
    }

    public async ValueTask DisposeAsync()
    {
        stop.Cancel();
        await CloseAsync().ConfigureAwait(false);
        socket.Dispose();
    }

    LinkEnd? HandleBeforeWelcome(string text, int version)
    {
        if (!TryParse(text, out var type, out var root)) return null;
        switch (type)
        {
            case "welcome":
                Info = new TvLinkInfo(
                    StringField(root, "name") ?? "",
                    StringField(root, "model"),
                    StringField(root, "appVersion"),
                    address);
                return null;
            case "error":
                var code = StringField(root, "code");
                if (code == "version_unsupported")
                {
                    SuggestedVersion = CommonVersion(root, version);
                    return LinkEnd.VersionUnsupported;
                }
                return code == "replaced" ? LinkEnd.Replaced : LinkEnd.Closed;
            case "ping":
                Send(Pong(root));
                return null;
            default:
                return null;
        }
    }

    async Task<LinkEnd> ReadLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            string? text;
            try { text = await ReceiveAsync(ct).ConfigureAwait(false); }
            catch (Exception e)
            {
                if (ct.IsCancellationRequested) return LinkEnd.Stopped;
                return e is WebSocketException or IOException ? LinkEnd.Closed : LinkEnd.Failed;
            }
            if (text is null) return LinkEnd.Closed;
            if (ReferenceEquals(text, Oversized)) return LinkEnd.Failed;
            if (!TryParse(text, out var type, out var root)) continue;
            if (type == "ping") Send(Pong(root));
            else if (type == "error" && StringField(root, "code") == "replaced") return LinkEnd.Replaced;
        }
        return LinkEnd.Closed;
    }

    async Task WriteLoopAsync(CancellationToken ct)
    {
        try
        {
            await foreach (var message in outbox.Reader.ReadAllAsync(ct).ConfigureAwait(false))
                await SendNowAsync(message, ct).ConfigureAwait(false);
        }
        catch (Exception)
        {
            if (!ct.IsCancellationRequested) EndWith(LinkEnd.WriteFailed);
        }
    }

    async Task PingLoopAsync(CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                await Task.Delay(timings.PingEvery, clock, ct).ConfigureAwait(false);
                var silent = clock.GetUtcNow().UtcTicks - Interlocked.Read(ref lastHeardTicks);
                if (silent > timings.SilenceLimit.Ticks)
                {
                    EndWith(LinkEnd.Silent);
                    return;
                }
                var ping = new WireObject { ["t"] = clock.GetUtcNow().ToUnixTimeMilliseconds() };
                Send(TvWire.Envelope("ping", ping));
            }
        }
        catch (OperationCanceledException) { }
    }

    async Task SendNowAsync(string message, CancellationToken ct) =>
        await socket.SendAsync(Encoding.UTF8.GetBytes(message), WebSocketMessageType.Text, true, ct).ConfigureAwait(false);

    /// <summary>Bir mesaj: kapanışta <c>null</c>, 512 KB'ı aşan mesajda <see cref="Oversized"/>.</summary>
    async Task<string?> ReceiveAsync(CancellationToken ct)
    {
        var buffer = new byte[8192];
        using var all = new MemoryStream();
        while (true)
        {
            var r = await socket.ReceiveAsync(buffer, ct).ConfigureAwait(false);
            if (r.MessageType == WebSocketMessageType.Close) return null;
            all.Write(buffer, 0, r.Count);
            if (all.Length > 512 * 1024) return Oversized;
            if (r.EndOfMessage) break;
        }
        Touch();
        return Encoding.UTF8.GetString(all.GetBuffer(), 0, (int)all.Length);
    }

    void Touch() => Interlocked.Exchange(ref lastHeardTicks, clock.GetUtcNow().UtcTicks);

    async Task CloseAsync()
    {
        try
        {
            if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(1));
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, cts.Token).ConfigureAwait(false);
            }
        }
        catch (Exception) { }
        try { socket.Abort(); } catch (Exception) { }
    }

    static string Pong(JsonElement root)
    {
        var o = new WireObject();
        if (root.TryGetProperty("t", out var t) && t.ValueKind == JsonValueKind.Number)
            o["t"] = new RawNumber(t.GetRawText());
        return TvWire.Envelope("pong", o);
    }

    static bool TryParse(string text, out string type, out JsonElement root)
    {
        type = "";
        root = default;
        try
        {
            using var doc = JsonDocument.Parse(text);
            root = doc.RootElement.Clone();
        }
        catch (JsonException) { return false; }
        if (root.ValueKind != JsonValueKind.Object) return false;
        type = StringField(root, "type") ?? "";
        return true;
    }

    static string? StringField(JsonElement root, string name) =>
        root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary><c>versions</c> listesinde bizim desteklediğimiz (≤ <paramref name="ours"/>) en büyük sürüm.</summary>
    static int? CommonVersion(JsonElement root, int ours)
    {
        if (!root.TryGetProperty("versions", out var list) || list.ValueKind != JsonValueKind.Array) return null;
        int? best = null;
        foreach (var v in list.EnumerateArray())
            if (v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var n) && n >= 1 && n <= TvWire.ProtocolVersion
                && n != ours && (best is null || n > best))
                best = n;
        return best;
    }
}
