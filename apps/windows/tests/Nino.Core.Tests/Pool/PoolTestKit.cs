// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;

namespace Nino.Core.Tests.Pool;

/// <summary>Kaydedilen istek.</summary>
internal sealed record SeenRequest(HttpMethod Method, Uri Uri, string Body, HttpRequestMessage Message);

/// <summary>Sahte sunucu: yanıtı işlev üretir; istekleri kaydeder. Ağa çıkmaz.</summary>
internal sealed class FakeServer : HttpMessageHandler
{
    readonly Func<SeenRequest, Task<HttpResponseMessage>> _respond;
    public List<SeenRequest> Requests { get; } = [];

    public FakeServer(Func<SeenRequest, HttpResponseMessage> respond) : this(r => Task.FromResult(respond(r))) { }

    public FakeServer(Func<SeenRequest, Task<HttpResponseMessage>> respond) => _respond = respond;

    public HttpClient Client() => new(this) { Timeout = Timeout.InfiniteTimeSpan };

    protected override async Task<HttpResponseMessage>
        SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(ct);
        var seen = new SeenRequest(request.Method, request.RequestUri!, body, request);
        lock (Requests) Requests.Add(seen);
        return await _respond(seen).WaitAsync(ct);
    }

    public static HttpResponseMessage Json(string json, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(json,
            Encoding.UTF8, "application/json") };

    public static HttpResponseMessage Bytes(byte[] bytes) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };

    public static HttpResponseMessage Status(HttpStatusCode status) => new(status) { Content = new StringContent("") };

    public static HttpResponseMessage Fail() => throw new HttpRequestException("çevrimdışı");
}

/// <summary>Elle ilerletilen saat (zamanlayıcılar gerçek zamanlı).</summary>
internal sealed class PoolClock(double unixSeconds) : TimeProvider
{
    DateTimeOffset _now = DateTimeOffset.FromUnixTimeMilliseconds((long)(unixSeconds * 1000));

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(double seconds) => _now += TimeSpan.FromSeconds(seconds);
}

internal static class PoolTemp
{
    public static string Folder()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-pool-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }
}
