// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using Nino.Core.Data;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Translation.Tests.Online;

public class DeepLTests
{
    static FakeHandler Server() => new(r =>
    {
        var texts = r.Json.GetProperty("text").EnumerateArray().Select(t => "[tr] " + t.GetString()).ToArray();
        return FakeHandler.Json(FakeHandler.Encode(new { translations = texts.Select(t => new { text = t }) }));
    });

    static DeepLTranslator Create(FakeHandler server, string key = "abc", string target = "tr", ITranslator? fallback = null,
        TranslationCache? cache = null, Glossary? glossary = null, TimeProvider? clock = null) =>
        new(key, target, fallback, cache ?? new TranslationCache(null), glossary is null ? null : () => glossary,
            server.Client(), clock);

    static string? Context(SentRequest r) => r.Json.TryGetProperty("context", out var c) ? c.GetString() : null;

    [Fact]
    public async Task IstekBicimiVeBaglam()
    {
        var server = Server();
        var t = Create(server, "free-key:fx");
        Assert.Equal("MARCO: [tr] Cut the engine.", (await t.TranslateAsync("MARCO: Cut the engine.")).Text);
        var r = server.Requests[0];
        Assert.Equal(HttpMethod.Post, r.Method);
        Assert.Equal("https://api-free.deepl.com/v2/translate", r.Url);
        Assert.Equal("DeepL-Auth-Key free-key:fx", r.Headers["Authorization"]);
        Assert.Equal("Cut the engine.", r.Json.GetProperty("text")[0].GetString());
        Assert.Equal("TR", r.Json.GetProperty("target_lang").GetString());
        Assert.Equal("EN", r.Json.GetProperty("source_lang").GetString());
        Assert.Equal("prefer_less", r.Json.GetProperty("formality").GetString());
        Assert.Null(Context(r));
        Assert.StartsWith("{\"text\":[\"Cut the engine.\"],\"source_lang\":\"EN\",\"target_lang\":\"TR\",\"formality\"", r.Body);
        await t.TranslateAsync("Keep low.");
        Assert.Equal("MARCO: Cut the engine.", Context(server.Requests[1]));
        Assert.Equal("deepl", t.EngineName);
    }

    [Fact]
    public async Task OnbellekVeUcretliAdres()
    {
        var server = Server();
        var t = Create(server);
        await t.TranslateAsync("Who sent you?");
        await t.TranslateAsync("Who sent you?");
        Assert.Single(server.Requests);
        Assert.StartsWith("https://api.deepl.com/", server.Requests[0].Url);
    }

    [Fact]
    public async Task BaglamSonUcSatir()
    {
        var server = Server();
        var t = Create(server);
        foreach (var line in new[] { "One.", "Two.", "Two.", "Three.", "Four.", "Five." }) await t.TranslateAsync(line);
        Assert.Equal(5, server.Requests.Count);
        Assert.Equal([null, "One.", "One.\nTwo.", "One.\nTwo.\nThree.", "Two.\nThree.\nFour."],
            server.Requests.Select(Context));

        var s2 = Server();
        var t2 = Create(s2);
        foreach (var line in new[] { "Is it locked?", "Not anymore.", "Is it locked?", "Then go in." }) await t2.TranslateAsync(line);
        Assert.Equal(3, s2.Requests.Count);
        Assert.Equal("Is it locked?\nNot anymore.\nIs it locked?", Context(s2.Requests[2]));
    }

    [Fact]
    public async Task KaliciOnbellekParcalar()
    {
        var path = Path.Combine(Path.GetTempPath(), "nino-deepl-" + Guid.NewGuid().ToString("N"), "v1-deepl-en-tr.jsonl");
        var s1 = Server();
        await Create(s1, cache: new TranslationCache(path)).TranslateAsync("MARCO: Open the hatch. Keep low.");
        var s2 = Server();
        var t2 = Create(s2, cache: new TranslationCache(path));
        Assert.Equal("MARCO: [tr] Open the hatch. [tr] Keep low.", (await t2.TranslateAsync("MARCO: Open the hatch. Keep low.")).Text);
        Assert.Empty(s2.Requests);
        await t2.TranslateAsync("Keep low. Run!");
        Assert.Single(s2.Requests);
        Assert.Equal(["Run!"], s2.Requests[0].Json.GetProperty("text").EnumerateArray().Select(e => e.GetString()));
    }

    [Fact]
    public async Task SunucuHatasiYedek()
    {
        var bad = new FakeHandler(_ => FakeHandler.Json("{}", HttpStatusCode.BadGateway));
        var cache = new TranslationCache(null);
        var fallback = new FakeFallback();
        var t = Create(bad, fallback: fallback, cache: cache);
        OnlineFailure? seen = null;
        t.FailureChanged += f => seen = f;
        Assert.Equal("yerel: Run!", (await t.TranslateAsync("Run!")).Text);
        Assert.False(cache.TryGet("Run!", out var _));
        Assert.Equal(OnlineFailure.Unreachable, seen);
        var fixedT = Create(Server(), cache: cache);
        Assert.Equal("[tr] Run!", (await fixedT.TranslateAsync("Run!")).Text);
    }

    [Fact]
    public async Task KotaBittiBekleme()
    {
        var quota = new FakeHandler(_ => FakeHandler.Json("{}", (HttpStatusCode)456));
        var t = Create(quota, fallback: new FakeFallback());
        Assert.Equal("yerel: Run!", (await t.TranslateAsync("Run!")).Text);
        Assert.Equal(OnlineFailure.QuotaExhausted, t.LastFailure);
        Assert.Equal("yerel: Swim!", (await t.TranslateAsync("Swim!")).Text);
        Assert.Single(quota.Requests);
    }

    [Fact]
    public async Task YedekYoksaIndirmeGerekli()
    {
        var bad = new FakeHandler(_ => FakeHandler.Json("{}", HttpStatusCode.InternalServerError));
        var t = Create(bad);
        var e = await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Run!"));
        Assert.Equal(UnavailableReason.DownloadRequired, e.Reason);
    }

    [Fact]
    public async Task TerimEtiketi()
    {
        var server = Server();
        var t = Create(server, glossary: Glossary.General);
        var result = (await t.TranslateAsync("Raven began to fight. Feed the raven & run.")).Text;
        var r = server.Requests[0].Json;
        Assert.Equal(["<x>Raven</x> began to fight.", "Feed the raven &amp; run."],
            r.GetProperty("text").EnumerateArray().Select(e => e.GetString()));
        Assert.Equal("xml", r.GetProperty("tag_handling").GetString());
        Assert.Equal("x", r.GetProperty("ignore_tags")[0].GetString());
        Assert.DoesNotContain("<x>", result);
        Assert.Contains("& run.", result);

        await t.TranslateAsync("Keep low & quiet.");
        var plain = server.Requests[1].Json;
        Assert.Equal("Keep low & quiet.", plain.GetProperty("text")[0].GetString());
        Assert.False(plain.TryGetProperty("tag_handling", out var _));

        var ar = Server();
        var tar = Create(ar, target: "ar", glossary: Glossary.General);
        await tar.TranslateAsync("Raven began to fight.");
        var j = ar.Requests[0].Json;
        Assert.Equal("Raven began to fight.", j.GetProperty("text")[0].GetString());
        Assert.Equal("AR", j.GetProperty("target_lang").GetString());
        Assert.False(j.TryGetProperty("formality", out var _));
        Assert.False(j.TryGetProperty("tag_handling", out var _));
    }

    [Fact]
    public async Task Kullanim()
    {
        var ok = new FakeHandler(_ => FakeHandler.Json("""{"character_count":1200,"character_limit":500000}"""));
        var r = await DeepLTranslator.CheckUsageAsync("key", ok.Client());
        Assert.Equal(new DeepLUsageResult(KeyCheckStatus.Valid, 1200, 500000), r);
        Assert.EndsWith("/v2/usage", ok.Requests[0].Url);
        Assert.Equal(HttpMethod.Get, ok.Requests[0].Method);

        var forbidden = new FakeHandler(_ => FakeHandler.Json("{}", HttpStatusCode.Forbidden));
        Assert.Equal(KeyCheckStatus.InvalidKey, (await DeepLTranslator.CheckUsageAsync("key", forbidden.Client())).Status);
        var full = new FakeHandler(_ => FakeHandler.Json("""{"character_count":500000,"character_limit":500000}"""));
        Assert.Equal(KeyCheckStatus.QuotaExhausted, (await DeepLTranslator.CheckUsageAsync("key", full.Client())).Status);
        Assert.Equal(KeyCheckStatus.InvalidKey, (await DeepLTranslator.CheckUsageAsync("  ", ok.Client())).Status);
        var down = new FakeHandler(_ => throw new HttpRequestException("ağ yok"));
        Assert.Equal(KeyCheckStatus.Unreachable, (await DeepLTranslator.CheckUsageAsync("key", down.Client())).Status);
    }
}
