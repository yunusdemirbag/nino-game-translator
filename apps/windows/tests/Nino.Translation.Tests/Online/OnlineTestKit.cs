// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using System.Text.Json;
using Nino.Core.Translation;

namespace Nino.Translation.Tests.Online;

/// <summary>Gönderilen istek.</summary>
internal sealed record SentRequest(HttpMethod Method, string Url, Dictionary<string, string> Headers, string Body,
    string? ContentType)
{
    public JsonElement Json => JsonDocument.Parse(Body).RootElement;
}

/// <summary>Sahte sunucu: her isteği kaydeder, yanıtı işlevden alır.</summary>
internal sealed class FakeHandler(Func<SentRequest, CancellationToken, Task<HttpResponseMessage>> respond)
    : HttpMessageHandler
{
    public List<SentRequest> Requests { get; } = [];

    public FakeHandler(Func<SentRequest, HttpResponseMessage> respond) : this((r, _) => Task.FromResult(respond(r))) { }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var headers = request.Headers.ToDictionary(h => h.Key, h => string.Join(",", h.Value), StringComparer.OrdinalIgnoreCase);
        var body = request.Content == null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
        var sent = new SentRequest(request.Method, request.RequestUri!.ToString(), headers, body,
            request.Content?.Headers.ContentType?.ToString());
        lock (Requests) Requests.Add(sent);
        return await respond(sent, cancellationToken);
    }

    public HttpClient Client() => new(this);

    public static HttpResponseMessage Json(string json, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, mediaType: "application/json") };

    public static string Encode(object value) => JsonSerializer.Serialize(value,
        new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
}

/// <summary>Sahte yedek: <c>yerel: </c> + metin.</summary>
internal sealed class FakeFallback(Func<string, string>? map = null) : ITranslator
{
    public List<string> Calls { get; } = new();
    public string EngineName => "yerel";
    public bool SupportsPretranslation => false;
    public bool SupportsBatch => false;

    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        Calls.Add(text);
        return Task.FromResult(TranslationResult.FromEngine(map?.Invoke(text) ?? "yerel: " + text));
    }

    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) => this.TranslateOneByOneAsync(texts, cancellationToken);
}

internal sealed class TestClock : TimeProvider
{
    DateTimeOffset _now = new(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset GetUtcNow() => _now;
    public void Advance(TimeSpan by) => _now += by;
}

/// <summary>Yapay zekâ sahte yanıtları.</summary>
internal static class AiFake
{
    /// <summary>İletinin son satırındaki diziyi okur.</summary>
    public static List<string> Sentences(SentRequest r, AiService service)
    {
        var message = Message(r, service);
        var last = message.Split('\n')[^1];
        return JsonSerializer.Deserialize<List<string>>(last)!;
    }

    public static string Message(SentRequest r, AiService service)
    {
        var j = r.Json;
        return service switch
        {
            AiService.Gemini => j.GetProperty("contents")[0].GetProperty("parts")[0].GetProperty("text").GetString()!,
            AiService.Claude => j.GetProperty("messages")[0].GetProperty("content").GetString()!,
            _ => j.GetProperty("messages").EnumerateArray().Last().GetProperty("content").GetString()!,
        };
    }

    public static HttpResponseMessage Reply(AiService service, string text) => FakeHandler.Json(service switch
    {
        AiService.Gemini => FakeHandler.Encode(new { candidates = new[] { new { content = new { parts = new[] { new { text } } } } } }),
        AiService.Claude => FakeHandler.Encode(new { content = new[] { new { type = "text", text } } }),
        _ => FakeHandler.Encode(new { choices = new[] { new { message = new { content = text } } } }),
    });

    /// <summary>Her cümleye <c>[tr] </c> ekleyen sunucu.</summary>
    public static FakeHandler Echoing(AiService service, string prefix = "[tr] ") =>
        new(r => Reply(service, FakeHandler.Encode(Sentences(r, service).Select(s => prefix + s).ToArray())));
}
