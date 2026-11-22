// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Nino.Core.Library;

namespace Nino.Core.Support;

/// <summary>Sorun bildiriminin sonucu.</summary>
public enum ReportStatus
{
    Sent,
    Limited,
    TooLarge,
    Rejected,
    Failed,
}

/// <summary>Gönderim sonucu; gönderildiyse sunucunun verdiği kimlik, sınırdaysa bekleme süresi.</summary>
public sealed record ReportResult(ReportStatus Status, string? Id = null, TimeSpan? RetryAfter = null)
{
    public static ReportResult Failed { get; } = new(ReportStatus.Failed);
}

/// <summary>Destek sunucusunun adresleri: havuz kök adresi + <c>/v1/reports</c> ya da <c>/v1/assistant</c>.</summary>
public static class SupportEndpoints
{
    public const string Reports = "v1/reports";
    public const string Assistant = "v1/assistant";

    /// <summary>Kök adresten uç nokta; kök yoksa yok.</summary>
    public static Uri? For(Uri? root, string relative) => root is null ? null : PoolEndpoint.Combine(root, relative);

    /// <summary>Veri klasöründen kök (ortam değişkeni → <c>pool\endpoint.txt</c> → canlı).</summary>
    public static Uri RootFromDataFolder(string dataFolder) => PoolEndpoint.Resolve(dataFolder);
}

/// <summary>Destek isteklerinin ortak HTTP gönderimi (User-Agent yok, <c>charset=utf-8</c>).</summary>
internal static class SupportHttp
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(60);

    internal sealed record Reply(HttpStatusCode Status, byte[] Body, TimeSpan? RetryAfter);

    /// <summary>JSON gövdeyi gönderir. Ağ hatası ya da zaman aşımı null; yalnız dışarıdan iptal fırlatır.</summary>
    public static async Task<Reply?> PostAsync(HttpClient http, Uri uri, byte[] json, TimeProvider clock,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(HttpMethod.Post, uri);
        var content = new ByteArrayContent(json);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json") { CharSet = "utf-8" };
        request.Content = content;
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(Timeout);
        try
        {
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseContentRead, cts.Token)
                .ConfigureAwait(false);
            var body = await response.Content.ReadAsByteArrayAsync(cts.Token).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            return new Reply(response.StatusCode, body, RetryAfter(response, clock));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException
                                      or InvalidOperationException)
        {
            return null;
        }
    }

    /// <summary>Retry-After: süre ya da tarih − şimdi (eksiye düşmez).</summary>
    public static TimeSpan? RetryAfter(HttpResponseMessage response, TimeProvider clock)
    {
        var header = response.Headers.RetryAfter;
        if (header is null) return null;
        if (header.Delta is { } delta) return delta;
        if (header.Date is { } date)
        {
            var wait = date - clock.GetUtcNow();
            return wait < TimeSpan.Zero ? TimeSpan.Zero : wait;
        }
        return null;
    }

    /// <summary>Gövde bir nesneyse içindeki dizge alanı.</summary>
    public static string? StringField(byte[] body, string name)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                   && doc.RootElement.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String
                ? p.GetString()
                : null;
        }
        catch (JsonException) { return null; }
    }
}

/// <summary><c>POST /v1/reports</c> istemcisi. İstisna fırlatmaz (yalnız dışarıdan iptal edilince).</summary>
public sealed class ReportClient(HttpClient http, Uri? root, TimeProvider? clock = null)
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;

    /// <summary>Bildirimi gönderir.</summary>
    public async Task<ReportResult> SendAsync(ReportBody body, CancellationToken cancellationToken = default)
    {
        if (SupportEndpoints.For(root, SupportEndpoints.Reports) is not { } uri) return ReportResult.Failed;
        var reply = await SupportHttp.PostAsync(http, uri, body.ToJson(), _clock, cancellationToken).ConfigureAwait(false);
        return reply is null ? ReportResult.Failed : Map(reply.Status, reply.Body, reply.RetryAfter);
    }

    /// <summary>Cevap eşlemesi: 200 gönderildi (gövdede <c>id</c>), 429 sınır, 413 çok büyük, 400 reddedildi.</summary>
    internal static ReportResult Map(HttpStatusCode status, byte[] body, TimeSpan? retryAfter) => (int)status switch
    {
        200 => new ReportResult(ReportStatus.Sent, SupportHttp.StringField(body, "id")),
        429 => new ReportResult(ReportStatus.Limited, RetryAfter: retryAfter),
        413 => new ReportResult(ReportStatus.TooLarge),
        400 => new ReportResult(ReportStatus.Rejected),
        _ => ReportResult.Failed,
    };
}
