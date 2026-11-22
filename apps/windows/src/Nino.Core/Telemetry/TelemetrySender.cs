// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.Http.Headers;

namespace Nino.Core.Telemetry;

/// <summary>Sunucunun cevabı.</summary>
/// <param name="Status">HTTP durum kodu.</param>
/// <param name="RetryAfter">429'daki <c>retry-after</c> (varsa).</param>
/// <param name="Body">Cevap gövdesi (varsa).</param>
public sealed record TelemetryResponse(int Status, TimeSpan? RetryAfter = null, string? Body = null);

/// <summary>
/// Gövdeyi <c>POST /v1/events</c>'e gönderen hizmet. Ağ hatasında hata fırlatır (istemci saklayıp yeniden dener).
/// </summary>
public interface ITelemetrySender
{
    /// <summary>Gövdeyi gönderir. <paramref name="gzipped"/> doğruysa <c>content-encoding: gzip</c>.</summary>
    Task<TelemetryResponse> SendAsync(ReadOnlyMemory<byte> body, bool gzipped, CancellationToken cancellationToken);
}

/// <summary><see cref="HttpClient"/> ile gönderici.</summary>
public sealed class HttpTelemetrySender(HttpClient http, Uri endpoint) : ITelemetrySender
{
    /// <summary>Havuz kök adresinden <c>/v1/events</c> adresi.</summary>
    public static Uri EndpointFor(Uri poolRoot) => new(poolRoot, "/v1/events");

    /// <inheritdoc />
    public async Task<TelemetryResponse> SendAsync(ReadOnlyMemory<byte> body, bool gzipped,
        CancellationToken cancellationToken)
    {
        using var content = new ReadOnlyMemoryContent(body);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        if (gzipped) content.Headers.ContentEncoding.Add("gzip");
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = content };
        using var response = await http.SendAsync(request, cancellationToken).ConfigureAwait(false);
        TimeSpan? retry = response.Headers.RetryAfter switch
        {
            { Delta: { } d } => d,
            { Date: { } date } => date - DateTimeOffset.UtcNow,
            _ => null,
        };
        var text = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        return new TelemetryResponse((int)response.StatusCode, retry, text);
    }
}
