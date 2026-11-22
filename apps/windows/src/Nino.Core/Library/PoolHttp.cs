// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace Nino.Core.Library;

/// <summary>Havuz ve paket istekleri için küçük HTTP ve JSON yardımcıları.</summary>
internal static class PoolHttp
{
    /// <summary>ASCII dışını kaçışsız, <c>/</c>'yi kaçışlamadan yazan ayar.</summary>
    public static readonly JsonWriterOptions WriterOptions = new()
    {
        Encoder =
            JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    /// <summary>Yazıcıyla JSON üretir.</summary>
    public static byte[] Json(Action<Utf8JsonWriter> write)
    {
        using var ms = new MemoryStream();
        using (var writer = new Utf8JsonWriter(ms, WriterOptions)) write(writer);
        return ms.ToArray();
    }

    /// <summary>JSON metni.</summary>
    public static string JsonText(Action<Utf8JsonWriter> write) => Encoding.UTF8.GetString(Json(write));

    /// <summary>Yanıt: durum kodu ve gövde (ağ/zaman aşımı hatasında null).</summary>
    public sealed record Response(HttpStatusCode Status, byte[] Body, HttpResponseMessage Message)
    {
        public bool Ok => (int)Status is >= 200 and < 300;
    }

    /// <summary>İsteği zaman aşımıyla gönderir; ağ hatası, zaman aşımı ya da çağıranın iptali dışında hata atmaz.</summary>
    public static async Task<Response?> SendAsync(HttpClient http, HttpRequestMessage request, TimeSpan timeout,
        string appVersion, CancellationToken cancellationToken)
    {
        request.Headers.TryAddWithoutValidation("User-Agent", PoolEndpoint.UserAgent(appVersion));
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(timeout);
        try
        {
            var message = await http.SendAsync(request, HttpCompletionOption.ResponseContentRead, cts.Token).ConfigureAwait(false);
            var body = await message.Content.ReadAsByteArrayAsync(cts.Token).ConfigureAwait(false);
            return new Response(message.StatusCode, body, message);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException)
        {
            return null;
        }
        finally
        {
            request.Dispose();
        }
    }

    /// <summary>JSON gövdeli POST isteği.</summary>
    public static HttpRequestMessage Post(Uri uri, byte[] json) => new(HttpMethod.Post, uri)
    {
        Content = new ByteArrayContent(json) { Headers = { { "Content-Type", "application/json" } } },
    };

    /// <summary>JSON'u okur; değilse null.</summary>
    public static JsonDocument? Parse(byte[] body)
    {
        try { return JsonDocument.Parse(body); }
        catch (JsonException) { return null; }
    }

    /// <summary>Unix saniyesi (kesirli).</summary>
    public static double Unix(DateTimeOffset time) => time.ToUnixTimeMilliseconds() / 1000.0;

    /// <summary>Unix saniyesinden zaman.</summary>
    public static DateTimeOffset FromUnix(double seconds) => DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Round(seconds * 1000));
}
