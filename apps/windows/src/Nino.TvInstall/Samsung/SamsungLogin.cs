// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace Nino.TvInstall.Samsung;

/// <summary>Samsung hesabıyla girişin sonucu. Jeton günlüğe asla yazılmaz.</summary>
public sealed record SamsungAccount(string AccessToken, string UserId, string EmailAddress);

/// <summary>
/// Samsung hesabıyla tarayıcıda giriş: localhost:4794'te geri dönüşü bekleyen küçük dinleyici.
/// </summary>
public sealed class SamsungLogin
{
    public const int DefaultPort = 4794;
    public const string State = "accountcheckdogeneratedstatetext";
    public const string CallbackPath = "/signin/callback";
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(10);
    const int MaxHeaderBytes = 1024 * 1024;

    /// <summary>Tarayıcıda açılacak giriş adresi.</summary>
    public static string SignInUrl(int port = DefaultPort) =>
        "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate?locale=&clientId=v285zxnl3h" +
        "&redirect_uri=" + Uri.EscapeDataString($"http://localhost:{port}{CallbackPath}") +
        $"&state={State}&tokenType=TOKEN";

    public int Port { get; init; } = DefaultPort;
    public TimeSpan Timeout { get; init; } = DefaultTimeout;

    /// <summary>
    /// Dinleyiciyi açar, adresi <paramref name="openUrl"/>'e verir ve geri dönüşü bekler.
    /// Hata: <see cref="TvInstallFailure.LoginFailed"/>.
    /// </summary>
    public async Task<SamsungAccount> RunAsync(Action<string> openUrl, CancellationToken ct = default)
    {
        var listeners = new List<TcpListener>();
        try
        {
            foreach (var address in new[] { IPAddress.Loopback, IPAddress.IPv6Loopback })
            {
                try
                {
                    var l = new TcpListener(address, Port);
                    l.Start();
                    listeners.Add(l);
                }
                catch (SocketException e) when (address.Equals(IPAddress.IPv6Loopback) &&
                                                e.SocketErrorCode != SocketError.AddressAlreadyInUse)
                {
                    // IPv6 yoksa yalnız IPv4 yeter.
                }
            }
        }
        catch (SocketException e)
        {
            foreach (var l in listeners) l.Stop();
            throw new TvInstallException(TvInstallFailure.LoginFailed,
                $"oturum dönüşünü dinlemek için localhost:{Port} kullanılamadı (portu başka bir Nino tutuyor olabilir): {e.Message}", e);
        }

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(Timeout);
        var done = new TaskCompletionSource<SamsungAccount>(TaskCreationOptions.RunContinuationsAsynchronously);
        string? lastReason = null;
        try
        {
            openUrl(SignInUrl(Port));
            var loops = listeners.Select(l => AcceptLoopAsync(l, done, r => lastReason = r, cts.Token)).ToList();
            try
            {
                return await done.Task.WaitAsync(cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested is false)
            {
                var minutes = (int)Math.Round(Timeout.TotalMinutes);
                var msg = $"giriş {minutes} dakika içinde tamamlanmadı";
                if (lastReason is not null) msg += $"; Samsung'dan dönen istekte hesap bilgisi bulunamadı ({lastReason})";
                throw new TvInstallException(TvInstallFailure.LoginFailed, msg);
            }
        }
        finally
        {
            cts.Cancel();
            foreach (var l in listeners) l.Stop();
        }
    }

    static async Task AcceptLoopAsync(TcpListener listener, TaskCompletionSource<SamsungAccount> done,
        Action<string> reason, CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && !done.Task.IsCompleted)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync(ct).ConfigureAwait(false); }
            catch (Exception) { return; }
            _ = Task.Run(async () =>
            {
                using (client)
                {
                    try { await HandleAsync(client.GetStream(), done, reason, ct).ConfigureAwait(false); }
                    catch (Exception e) when (e is IOException or SocketException or OperationCanceledException) { }
                }
            }, CancellationToken.None);
        }
    }

    static async Task HandleAsync(NetworkStream stream, TaskCompletionSource<SamsungAccount> done,
        Action<string> reason, CancellationToken ct)
    {
        var (method, path, body) = await ReadRequestAsync(stream, ct).ConfigureAwait(false);
        if (method is null) return;
        if (method == "POST" && path.StartsWith(CallbackPath, StringComparison.Ordinal))
        {
            var account = ParseCallback(body);
            if (account is not null)
            {
                const string page = "<!doctype html><html><head><meta charset=\"utf-8\"><title>Nino</title></head>" +
                                    "<body style=\"font-family:system-ui;text-align:center;padding:48px\">" +
                                    "<h2>Giriş tamam / Signed in</h2>" +
                                    "<p>Bu sekmeyi kapatıp Nino'ya dönebilirsiniz.<br>You can close this tab and return to Nino.</p>" +
                                    "</body></html>";
                await WriteAsync(stream, "200 OK", "text/html; charset=utf-8", page, ct).ConfigureAwait(false);
                done.TrySetResult(account);
                return;
            }
            reason(FailureReason(body));
            await WriteAsync(stream, "400 Bad Request", "text/plain; charset=utf-8", "Not found", ct).ConfigureAwait(false);
            return;
        }
        await WriteAsync(stream, "404 Not Found", "text/plain; charset=utf-8", "Not found", ct).ConfigureAwait(false);
    }

    static async Task<(string? Method, string Path, string Body)> ReadRequestAsync(NetworkStream stream, CancellationToken ct)
    {
        var buffer = new List<byte>();
        var chunk = new byte[8192];
        int headerEnd;
        while (true)
        {
            headerEnd = IndexOf(buffer, "\r\n\r\n"u8);
            if (headerEnd >= 0) break;
            if (buffer.Count > MaxHeaderBytes) return (null, "", "");
            var n = await stream.ReadAsync(chunk, ct).ConfigureAwait(false);
            if (n == 0) return (null, "", "");
            buffer.AddRange(chunk.AsSpan(0, n));
        }
        var head = Encoding.ASCII.GetString(buffer.GetRange(0, headerEnd).ToArray());
        var lines = head.Split("\r\n");
        var first = lines[0].Split(' ');
        if (first.Length < 2) return (null, "", "");
        var length = 0;
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon > 0 && line[..colon].Trim().Equals("Content-Length", StringComparison.OrdinalIgnoreCase))
                int.TryParse(line[(colon + 1)..].Trim(), out length);
        }
        length = Math.Clamp(length, 0, MaxHeaderBytes);
        var bodyStart = headerEnd + 4;
        while (buffer.Count - bodyStart < length)
        {
            var n = await stream.ReadAsync(chunk, ct).ConfigureAwait(false);
            if (n == 0) break;
            buffer.AddRange(chunk.AsSpan(0, n));
        }
        var available = Math.Min(length, buffer.Count - bodyStart);
        var body = Encoding.UTF8.GetString(buffer.GetRange(bodyStart, available).ToArray());
        return (first[0], first[1], body);
    }

    static int IndexOf(List<byte> data, ReadOnlySpan<byte> needle)
    {
        for (var i = 0; i + needle.Length <= data.Count; i++)
        {
            var ok = true;
            for (var j = 0; j < needle.Length && ok; j++) ok = data[i + j] == needle[j];
            if (ok) return i;
        }
        return -1;
    }

    static async Task WriteAsync(NetworkStream stream, string status, string type, string body, CancellationToken ct)
    {
        var bytes = Encoding.UTF8.GetBytes(body);
        var head = $"HTTP/1.1 {status}\r\nContent-Type: {type}\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head), ct).ConfigureAwait(false);
        await stream.WriteAsync(bytes, ct).ConfigureAwait(false);
        await stream.FlushAsync(ct).ConfigureAwait(false);
    }

    static IEnumerable<(string Key, string Value)> Fields(string body) =>
        body.Split('&', StringSplitOptions.RemoveEmptyEntries).Select(p =>
        {
            var eq = p.IndexOf('=');
            return eq < 0 ? (p, "") : (p[..eq], p[(eq + 1)..]);
        });

    /// <summary>Geri dönüş gövdesinden hesabı çıkarır; geçersizse null.</summary>
    public static SamsungAccount? ParseCallback(string body)
    {
        string? state = null, code = null;
        foreach (var (key, value) in Fields(body))
        {
            if (key == "state" && state is null) state = WebUtility.UrlDecode(value);
            else if (key == "code" && code is null) code = SafeUnescape(value);
        }
        if (state != State || string.IsNullOrEmpty(code)) return null;
        try
        {
            using var doc = JsonDocument.Parse(code);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var token = Str(root, "access_token");
            var user = Str(root, "userId");
            if (string.IsNullOrEmpty(token) || string.IsNullOrEmpty(user)) return null;
            return new SamsungAccount(token, user, Str(root, "inputEmailID") ?? "");
        }
        catch (JsonException) { return null; }
    }

    static string SafeUnescape(string value)
    {
        try { return Uri.UnescapeDataString(value); }
        catch (UriFormatException) { return value; }
    }

    static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>Hesapsız geri dönüşün sebebi: alan adları; error/error_description/error_code/state değerleriyle. En çok 200 karakter.</summary>
    public static string FailureReason(string body)
    {
        var parts = Fields(body).Select(f =>
            f.Key is "error" or "error_description" or "error_code" or "state"
                ? $"{f.Key}={WebUtility.UrlDecode(f.Value)}"
                : f.Key);
        var text = string.Join(", ", parts);
        if (text.Length == 0) text = "boş gövde";
        return text.Length > 200 ? text[..200] : text;
    }
}
