// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace Nino.Core.Tv;

/// <summary>Açık bir TV uzaktan kumanda bağlantısı (LG SSAP ya da Samsung).</summary>
public interface ITvRemote : IAsyncDisposable
{
    /// <summary>TV'nin bu bağlantıda verdiği anahtar/jeton (vermediyse boş).</summary>
    string Key { get; }

    /// <summary>TV'deki Nino'yu açılış parametreleriyle (JSON metni) açar.</summary>
    Task LaunchAsync(string parametersJson, CancellationToken ct = default);

    /// <summary>Önplandaki uygulamanın kimliği (Samsung söylemez: boş).</summary>
    Task<string> ForegroundAppAsync(CancellationToken ct = default);
}

/// <summary>WebSocket metin mesajlarını parça parça okuyup birleştiren yardımcı.</summary>
static class SocketText
{
    public static async Task<string?> ReceiveAsync(WebSocket socket, CancellationToken ct, int limit = 16 * 1024)
    {
        var buffer = new byte[4096];
        using var all = new MemoryStream();
        while (true)
        {
            var r = await socket.ReceiveAsync(buffer, ct).ConfigureAwait(false);
            if (r.MessageType == WebSocketMessageType.Close) return null;
            if (all.Length + r.Count <= limit * 64) all.Write(buffer, 0, r.Count);
            if (r.EndOfMessage) break;
        }
        return Encoding.UTF8.GetString(all.GetBuffer(), 0, (int)all.Length);
    }

    public static Task SendAsync(WebSocket socket, string text, CancellationToken ct) =>
        socket.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, ct);

    public static ClientWebSocket NewClient()
    {
        var ws = new ClientWebSocket();
        // TV'lerin kendinden imzalı sertifikası kabul edilir; bağlantı yalnız TV'nin adresine gider.
        ws.Options.RemoteCertificateValidationCallback = (_, _, _, _) => true;
        ws.Options.KeepAliveInterval = TimeSpan.Zero;
        return ws;
    }

    /// <summary>JSON dizgesi (yalnız tırnak, ters bölü ve denetim karakterleri kaçışlanır).</summary>
    public static string Json(string value)
    {
        var sb = new StringBuilder();
        Nino.Core.Link.WireObject.WriteString(sb, value);
        return sb.ToString();
    }

    public static string? Str(JsonElement e, string name) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;
}

/// <summary>LG webOS ikinci ekran (SSAP) bağlantısı.</summary>
public sealed class LgRemote : ITvRemote
{
    readonly WebSocket socket;
    readonly SemaphoreSlim one = new(1, 1);
    int nextId;

    LgRemote(WebSocket socket, string key)
    {
        this.socket = socket;
        Key = key;
    }

    public string Key { get; }

    public static TimeSpan ConnectTimeout { get; set; } = TimeSpan.FromSeconds(5);
    public static TimeSpan ApprovalTimeout { get; set; } = TimeSpan.FromSeconds(60);

    /// <summary>Denenecek uçlar sırasıyla: <c>wss://adres:3001</c>, <c>ws://adres:3000</c>.</summary>
    public static IReadOnlyList<Uri> Endpoints(string host) =>
        [new Uri($"wss://{host}:3001"), new Uri($"ws://{host}:3000")];

    /// <summary>Kayıt iletisi (<c>client-key</c> yalnız saklı anahtar varsa).</summary>
    public static string RegisterMessage(string? clientKey)
    {
        var key = string.IsNullOrEmpty(clientKey) ? "" : $",\"client-key\":{SocketText.Json(clientKey)}";
        return "{\"type\":\"register\",\"id\":\"register_0\",\"payload\":{\"forcePairing\":false,\"pairingType\":\"PROMPT\","
            + "\"manifest\":{\"manifestVersion\":1,\"appVersion\":\"1.0\",\"permissions\":[\"LAUNCH\",\"LAUNCH_WEBAPP\","
            + "\"APP_TO_APP\",\"READ_RUNNING_APPS\",\"READ_INSTALLED_APPS\"]}" + key + "}}";
    }

    /// <summary>
    /// Kayıt sırasında gelen ileti: <c>registered</c> → anahtar; <c>error</c> → protokol hatası; başkası (TV soruyu
    /// gösterdi) → <c>null</c> (beklemeye devam).
    /// </summary>
    public static string? ParseRegisterReply(string json)
    {
        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(json);
            root = doc.RootElement.Clone();
        }
        catch (JsonException) { return null; }
        switch (SocketText.Str(root, "type"))
        {
            case "registered":
                var key = root.TryGetProperty("payload", out var p) ? SocketText.Str(p, "client-key") : null;
                return string.IsNullOrEmpty(key) ? throw new TvRemoteException(TvRemoteException.BadResponse, true) : key;
            case "error":
                throw new TvRemoteException(SocketText.Str(root, "error") ?? "register", true);
            default:
                return null;
        }
    }

    /// <summary>
    /// Uçları sırayla dener; kayıt aşamasındaki protokol hatasında öteki uç denenmez. Hiçbiri olmazsa
    /// "cannot connect".
    /// </summary>
    public static async Task<LgRemote> ConnectAsync(string host, string? clientKey, CancellationToken ct = default,
        IReadOnlyList<Uri>? endpoints = null)
    {
        foreach (var uri in endpoints ?? Endpoints(host))
        {
            ct.ThrowIfCancellationRequested();
            var ws = SocketText.NewClient();
            try
            {
                using (var connect = CancellationTokenSource.CreateLinkedTokenSource(ct))
                {
                    connect.CancelAfter(ConnectTimeout);
                    await ws.ConnectAsync(uri, connect.Token).ConfigureAwait(false);
                }
                await SocketText.SendAsync(ws, RegisterMessage(clientKey), ct).ConfigureAwait(false);
                using var approval = CancellationTokenSource.CreateLinkedTokenSource(ct);
                approval.CancelAfter(ApprovalTimeout);
                while (true)
                {
                    string? text;
                    try { text = await SocketText.ReceiveAsync(ws, approval.Token).ConfigureAwait(false); }
                    catch (OperationCanceledException) when (ct.IsCancellationRequested is false)
                    {
                        throw new TvRemoteException(TvRemoteException.Timeout, true);
                    }
                    if (text is null) throw new TvRemoteException(TvRemoteException.Closed, true);
                    if (ParseRegisterReply(text) is { } key) return new LgRemote(ws, key);
                }
            }
            catch (TvRemoteException)
            {
                ws.Dispose();
                throw;
            }
            catch (Exception) when (!ct.IsCancellationRequested)
            {
                ws.Dispose();
            }
        }
        ct.ThrowIfCancellationRequested();
        throw new TvRemoteException(TvRemoteException.CannotConnect);
    }

    /// <summary>Tek seferde bir istek; aynı kimlikli yanıta kadar öteki iletiler atlanır.</summary>
    public async Task<JsonElement> RequestAsync(string uri, string? payloadJson = null, CancellationToken ct = default)
    {
        await one.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            var id = $"req_{++nextId}";
            var payload = payloadJson is null ? "" : $",\"payload\":{payloadJson}";
            await SocketText.SendAsync(socket,
                $"{{\"type\":\"request\",\"id\":\"{id}\",\"uri\":{SocketText.Json(uri)}{payload}}}", ct).ConfigureAwait(false);
            while (true)
            {
                var text = await SocketText.ReceiveAsync(socket, ct).ConfigureAwait(false)
                    ?? throw new TvRemoteException(TvRemoteException.Closed);
                JsonElement root;
                try
                {
                    using var doc = JsonDocument.Parse(text);
                    root = doc.RootElement.Clone();
                }
                catch (JsonException) { continue; }
                if (SocketText.Str(root, "id") != id) continue;
                if (SocketText.Str(root, "type") == "error")
                    throw new TvRemoteException(SocketText.Str(root, "error") ?? uri, true);
                return root.TryGetProperty("payload", out var p) ? p.Clone() : JsonDocument.Parse("{}").RootElement.Clone();
            }
        }
        finally
        {
            one.Release();
        }
    }

    public async Task LaunchAsync(string parametersJson, CancellationToken ct = default)
    {
        var payload = $"{{\"id\":\"{TvRecord.LgAppId}\",\"params\":{parametersJson}}}";
        var reply = await RequestAsync("ssap://system.launcher/launch", payload, ct).ConfigureAwait(false);
        if (reply.ValueKind == JsonValueKind.Object && reply.TryGetProperty("returnValue", out var rv)
            && rv.ValueKind == JsonValueKind.False)
            throw new TvRemoteException(SocketText.Str(reply, "errorText") ?? "launch", true);
    }

    public async Task<string> ForegroundAppAsync(CancellationToken ct = default)
    {
        var reply = await RequestAsync("ssap://com.webos.applicationManager/getForegroundAppInfo", null, ct).ConfigureAwait(false);
        return SocketText.Str(reply, "appId") ?? "";
    }

    public async ValueTask DisposeAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(1));
            if (socket.State == WebSocketState.Open)
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, cts.Token).ConfigureAwait(false);
        }
        catch (Exception) { }
        socket.Dispose();
    }
}

/// <summary>Samsung uzaktan kumanda iletisinin anlamı.</summary>
public enum SamsungEventKind { Ignore, Connected, Unauthorized, TimedOut }

/// <summary>Samsung Tizen uzaktan kumanda WebSocket'i (8002).</summary>
public sealed class SamsungRemote : ITvRemote
{
    /// <summary>Bugünkü (ve önceki) istemci adı.</summary>
    public const string ClientName = nameof(Nino);

    readonly WebSocket socket;

    SamsungRemote(WebSocket socket, string key)
    {
        this.socket = socket;
        Key = key;
    }

    public string Key { get; }

    public static TimeSpan ApprovalTimeout { get; set; } = TimeSpan.FromSeconds(60);

    /// <summary>Bağlantı adresi; ad UTF-8 base64 (URL kodlanmaz), jeton varsa eklenir.</summary>
    public static string Url(string host, string name, string? token, int port = 8002, string scheme = "wss")
    {
        var url = $"{scheme}://{host}:{port}/api/v2/channels/samsung.remote.control?name={Convert.ToBase64String(Encoding.UTF8.GetBytes(name))}";
        return string.IsNullOrEmpty(token) ? url : url + "&token=" + token;
    }

    /// <summary>
    /// İstemci adı: depodaki doluysa o; değilse "Nino" (saklı jeton varsa "önceki ad" da bugün "Nino"). İkinci değer:
    /// depoya yazılmalı mı.
    /// </summary>
    public static (string Name, bool Store) ChooseClientName(string? stored, bool hasSavedToken)
    {
        if (!string.IsNullOrEmpty(stored)) return (stored, false);
        _ = hasSavedToken; // önceki ad da "Nino"
        return (ClientName, stored != ClientName);
    }

    /// <summary>Gelen iletinin anlamı ve (bağlanınca) jeton.</summary>
    public static (SamsungEventKind Kind, string Token) ParseEvent(string text)
    {
        try
        {
            using var doc = JsonDocument.Parse(text);
            var root = doc.RootElement;
            switch (SocketText.Str(root, "event"))
            {
                case "ms.channel.connect":
                    var token = root.TryGetProperty("data", out var d) ? SocketText.Str(d, "token") : null;
                    return (SamsungEventKind.Connected, token ?? "");
                case "ms.channel.unauthorized": return (SamsungEventKind.Unauthorized, "");
                case "ms.channel.timeOut": return (SamsungEventKind.TimedOut, "");
                default: return (SamsungEventKind.Ignore, "");
            }
        }
        catch (JsonException)
        {
            return (SamsungEventKind.Ignore, "");
        }
    }

    /// <summary>Uygulama açma iletisi; <paramref name="metaTag"/> parametrelerin JSON metni.</summary>
    public static string LaunchMessage(string metaTag) =>
        "{\"method\":\"ms.channel.emit\",\"params\":{\"event\":\"ed.apps.launch\",\"to\":\"host\",\"data\":{\"appId\":\""
        + TvRecord.SamsungAppId + "\",\"action_type\":\"DEEP_LINK\",\"metaTag\":" + SocketText.Json(metaTag) + "}}}";

    /// <summary>Bağlanır ve TV'nin onayını bekler (toplam 60 sn).</summary>
    public static async Task<SamsungRemote> ConnectAsync(string host, string name, string? token,
        CancellationToken ct = default, Uri? endpoint = null)
    {
        var ws = SocketText.NewClient();
        using var total = CancellationTokenSource.CreateLinkedTokenSource(ct);
        total.CancelAfter(ApprovalTimeout);
        try
        {
            await ws.ConnectAsync(endpoint ?? new Uri(Url(host, name, token)), total.Token).ConfigureAwait(false);
            while (true)
            {
                var text = await SocketText.ReceiveAsync(ws, total.Token).ConfigureAwait(false)
                    ?? throw new TvRemoteException(TvRemoteException.CannotConnect);
                var (kind, newToken) = ParseEvent(text);
                switch (kind)
                {
                    case SamsungEventKind.Connected: return new SamsungRemote(ws, newToken);
                    case SamsungEventKind.Unauthorized: throw new TvRemoteException(TvRemoteException.Rejected, true);
                    case SamsungEventKind.TimedOut: throw new TvRemoteException(TvRemoteException.CannotConnect, true);
                }
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested is false)
        {
            ws.Dispose();
            throw new TvRemoteException(TvRemoteException.Timeout);
        }
        catch (TvRemoteException)
        {
            ws.Dispose();
            throw;
        }
        catch (Exception e) when (!ct.IsCancellationRequested)
        {
            ws.Dispose();
            throw new TvRemoteException(TvRemoteException.CannotConnect, inner: e);
        }
        catch
        {
            ws.Dispose();
            throw;
        }
    }

    public async Task LaunchAsync(string parametersJson, CancellationToken ct = default)
    {
        if (socket.State != WebSocketState.Open) throw new TvRemoteException(TvRemoteException.Closed);
        await SocketText.SendAsync(socket, LaunchMessage(parametersJson), ct).ConfigureAwait(false);
    }

    public Task<string> ForegroundAppAsync(CancellationToken ct = default) =>
        socket.State == WebSocketState.Open
            ? Task.FromResult("")
            : Task.FromException<string>(new TvRemoteException(TvRemoteException.Closed));

    public async ValueTask DisposeAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(1));
            if (socket.State == WebSocketState.Open)
                await socket.CloseOutputAsync(WebSocketCloseStatus.NormalClosure, null, cts.Token).ConfigureAwait(false);
        }
        catch (Exception) { }
        socket.Dispose();
    }
}
