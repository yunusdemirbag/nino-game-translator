// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;

namespace Nino.Core.Tests.Support;

/// <summary>Ağa çıkmayan sahte HTTP: istekleri kaydeder, verilen cevabı döner.</summary>
sealed class StubHandler(Func<HttpRequestMessage, string, HttpResponseMessage> respond) : HttpMessageHandler
{
    public readonly List<(HttpRequestMessage Request, string Body)> Requests = [];

    public static StubHandler Json(HttpStatusCode status, string body) =>
        new((_, _) => new HttpResponseMessage(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") });

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
        lock (Requests) Requests.Add((request, body));
        return respond(request, body);
    }
}

/// <summary>Hep hata fırlatan sahte HTTP (ağ yok).</summary>
sealed class OfflineHandler : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
        throw new HttpRequestException("ağ yok");
}
