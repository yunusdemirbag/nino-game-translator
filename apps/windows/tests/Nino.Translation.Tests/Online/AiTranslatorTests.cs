// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Translation.Tests.Online;

public class AiTranslatorTests
{
    static AiTranslator Create(AiService service, FakeHandler server, string model = "", ITranslator? fallback = null,
        TranslationCache? cache = null, Func<string?>? game = null, LocalServer? local = null, RequestBudget? budget = null,
        TimeProvider? clock = null, string target = "tr", string key = "key-123") =>
        new(service, model, key, target, fallback, cache ?? new TranslationCache(null), server.Client(), game, local,
            budget, clock);

    static readonly LocalServer Ollama = LocalServer.Create("http://localhost:11434/v1", "qwen2.5:7b")!;

    [Fact]
    public async Task GeminiIstegi()
    {
        var server = AiFake.Echoing(AiService.Gemini);
        var t = Create(AiService.Gemini, server, "gemini-3.5-flash-lite");
        Assert.Equal("MARCO: [tr] Open the hatch.", (await t.TranslateAsync("MARCO: Open the hatch.")).Text);
        var r = server.Requests[0];
        Assert.Equal("https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent", r.Url);
        Assert.Equal("key-123", r.Headers["x-goog-api-key"]);
        Assert.False(r.Headers.ContainsKey("Authorization"));
        Assert.Equal("application/json; charset=utf-8", r.ContentType);
        Assert.Equal(AiPrompts.Instruction("tr"), r.Json.GetProperty("systemInstruction").GetProperty("parts")[0].GetProperty("text").GetString());
        Assert.Equal(1024, r.Json.GetProperty("generationConfig").GetProperty("maxOutputTokens").GetInt32());
        Assert.False(r.Json.GetProperty("generationConfig").TryGetProperty("thinkingConfig", out var _));
        var message = AiFake.Message(r, AiService.Gemini);
        Assert.EndsWith("[\"Open the hatch.\"]", message);
        Assert.DoesNotContain("MARCO", message);
        Assert.Equal("gemini:gemini-3.5-flash-lite", t.EngineName);
    }

    [Fact]
    public async Task OpenAiVeClaudeGovdeleri()
    {
        var o = AiFake.Echoing(AiService.OpenAi);
        await Create(AiService.OpenAi, o, "gpt-6-luna").TranslateAsync("Run!");
        var oj = o.Requests[0].Json;
        Assert.Equal("gpt-6-luna", oj.GetProperty("model").GetString());
        Assert.Equal("none", oj.GetProperty("reasoning_effort").GetString());
        Assert.Equal(1024, oj.GetProperty("max_completion_tokens").GetInt32());
        Assert.Equal(["developer", "user"], oj.GetProperty("messages").EnumerateArray().Select(m => m.GetProperty("role").GetString()));
        Assert.Equal("Bearer key-123", o.Requests[0].Headers["Authorization"]);

        var c = AiFake.Echoing(AiService.Claude);
        await Create(AiService.Claude, c, "claude-haiku-5-5").TranslateAsync("Run!");
        var cr = c.Requests[0];
        Assert.Equal("https://api.anthropic.com/v1/messages", cr.Url);
        Assert.Equal("key-123", cr.Headers["x-api-key"]);
        Assert.Equal("2023-06-01", cr.Headers["anthropic-version"]);
        Assert.Equal("claude-haiku-5-5", cr.Json.GetProperty("model").GetString());
        Assert.Equal(1024, cr.Json.GetProperty("max_tokens").GetInt32());
        Assert.Equal(AiPrompts.Instruction("tr"), cr.Json.GetProperty("system").GetString());
        Assert.False(cr.Json.TryGetProperty("temperature", out var _));
        Assert.Equal("low", cr.Json.GetProperty("output_config").GetProperty("effort").GetString());
        Assert.Equal("disabled", cr.Json.GetProperty("thinking").GetProperty("type").GetString());

        var c2 = AiFake.Echoing(AiService.Claude);
        await Create(AiService.Claude, c2, "claude-sonnet-5-5").TranslateAsync("Run!");
        Assert.Equal("between_tools", c2.Requests[0].Json.GetProperty("thinking").GetProperty("type").GetString());
        var o2 = AiFake.Echoing(AiService.OpenAi);
        await Create(AiService.OpenAi, o2, "gpt-6.1-terra").TranslateAsync("Run!");
        Assert.Equal("none", o2.Requests[0].Json.GetProperty("reasoning_effort").GetString());
        var g2 = AiFake.Echoing(AiService.Gemini);
        await Create(AiService.Gemini, g2, "gemini-3.6-flash").TranslateAsync("Run!");
        Assert.Equal("LOW", g2.Requests[0].Json.GetProperty("generationConfig").GetProperty("thinkingConfig").GetProperty("thinkingLevel").GetString());

        Assert.Equal("gpt-6-luna", Create(AiService.OpenAi, o, "gpt-4o").Model);
        Assert.Equal("gemini-3.5-flash-lite", Create(AiService.Gemini, o, "").Model);
        Assert.Equal("claude-haiku-5-5", Create(AiService.Claude, o, "yok").Model);
        Assert.Equal("openai:gpt-6-luna", Create(AiService.OpenAi, o, "gpt-6-luna").EngineName);
    }

    [Fact]
    public async Task YerelModelIstegi()
    {
        var server = AiFake.Echoing(AiService.Local);
        var t = Create(AiService.Local, server, local: Ollama, key: "");
        Assert.Equal("MARCO: [tr] Open the hatch.", (await t.TranslateAsync("MARCO: Open the hatch.")).Text);
        var r = server.Requests[0];
        Assert.Equal("http://localhost:11434/v1/chat/completions", r.Url);
        Assert.Equal("application/json; charset=utf-8", r.ContentType);
        Assert.False(r.Headers.ContainsKey("Authorization"));
        Assert.Equal(["max_tokens", "messages", "model", "stream", "temperature"],
            r.Json.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal));
        Assert.Equal("qwen2.5:7b", r.Json.GetProperty("model").GetString());
        Assert.Equal(["system", "user"], r.Json.GetProperty("messages").EnumerateArray().Select(m => m.GetProperty("role").GetString()));
        Assert.Equal("local:localhost:11434/qwen2.5:7b", t.EngineName);

        var lm = LocalServer.Create(LocalServer.LmStudioUrl, "qwen2.5-7b-instruct")!;
        var s2 = AiFake.Echoing(AiService.Local);
        await Create(AiService.Local, s2, local: lm, key: " studio-key ").TranslateAsync("Run!");
        Assert.Equal("http://localhost:1234/v1/chat/completions", s2.Requests[0].Url);
        Assert.Equal("Bearer studio-key", s2.Requests[0].Headers["Authorization"]);
    }

    [Fact]
    public async Task DusunenModelVeDuzMetin()
    {
        var think = new FakeHandler(_ => AiFake.Reply(AiService.Local, "<think>hmm</think>\n\n[\"Koş!\"]"));
        Assert.Equal("Koş!", (await Create(AiService.Local, think, local: Ollama).TranslateAsync("Run!")).Text);
        var plain = new FakeHandler(_ => AiFake.Reply(AiService.Local, "Koş!"));
        Assert.Equal("Koş!", (await Create(AiService.Local, plain, local: Ollama).TranslateAsync("Run!")).Text);
        var bare = new FakeHandler(_ => AiFake.Reply(AiService.Local, "[Kapağı aç., Eğilin.]"));
        Assert.Equal("Kapağı aç. Eğilin.", (await Create(AiService.Local, bare, local: Ollama).TranslateAsync("Open the hatch. Keep low.")).Text);
    }

    [Fact]
    public async Task YerelSunucuHatalari()
    {
        var down = new FakeHandler(_ => throw new HttpRequestException("kapalı"));
        var t = Create(AiService.Local, down, local: Ollama, fallback: new FakeFallback());
        Assert.Equal("yerel: Run!", (await t.TranslateAsync("Run!")).Text);
        Assert.Equal(OnlineFailure.Unreachable, t.LastFailure);

        var missing = new FakeHandler(_ => FakeHandler.Json("""{"error":"model \"qwen2.5:7b\" not found, try pulling it first"}""", HttpStatusCode.NotFound));
        var t2 = Create(AiService.Local, missing, local: Ollama, fallback: new FakeFallback());
        Assert.Equal("yerel: Run!", (await t2.TranslateAsync("Run!")).Text);
        Assert.Equal(OnlineFailure.ModelRejected, t2.LastFailure);
    }

    [Fact]
    public async Task BaglamSatirlari()
    {
        var server = AiFake.Echoing(AiService.Claude);
        var t = Create(AiService.Claude, server, "claude-haiku-5-5");
        foreach (var line in new[] { "Red.", "Blue.", "Blue.", "Green.", "Gold.", "Gray." }) await t.TranslateAsync(line);
        Assert.Equal(5, server.Requests.Count);
        var messages = server.Requests.Select(r => AiFake.Message(r, AiService.Claude)).ToList();
        Assert.DoesNotContain("English: ", messages[0]);
        Assert.Contains("English: Red.\nTurkish: [tr] Red.", messages[1]);
        Assert.Contains("English: Blue.\nTurkish: [tr] Blue.\nEnglish: Green.", messages[4]);
        Assert.Contains("Gold.", messages[4].Split("\n\n")[0]);
        Assert.DoesNotContain("Red.", messages[4]);
        Assert.DoesNotContain("Gray.", messages[4].Split("\n\n")[0]);
    }

    [Fact]
    public async Task TekIstekteCumleler()
    {
        var server = AiFake.Echoing(AiService.Gemini);
        var t = Create(AiService.Gemini, server);
        Assert.Equal("[tr] Open the hatch. [tr] Keep low.\nNORA: [tr] Yes, captain.",
            (await t.TranslateAsync("Open the hatch. Keep low.\nNORA: Yes, captain.")).Text);
        Assert.Single(server.Requests);
        Assert.EndsWith("[\"Open the hatch.\",\"Keep low.\",\"Yes, captain.\"]", AiFake.Message(server.Requests[0], AiService.Gemini));
    }

    [Fact]
    public async Task OyunAdi()
    {
        var server = AiFake.Echoing(AiService.Gemini);
        string? game = null;
        var t = Create(AiService.Gemini, server, game: () => game);
        await t.TranslateAsync("Run!");
        Assert.DoesNotContain("Game:", AiFake.Message(server.Requests[0], AiService.Gemini));
        game = "Harbor Lights";
        await t.TranslateAsync("Hide!");
        Assert.StartsWith("Game: Harbor Lights\n\n", AiFake.Message(server.Requests[1], AiService.Gemini));
    }

    [Fact]
    public async Task OyunluOnbellek()
    {
        var server = AiFake.Echoing(AiService.Gemini);
        var cache = new TranslationCache(null);
        string? game = "One";
        var t = Create(AiService.Gemini, server, cache: cache, game: () => game);
        await t.TranslateAsync("Keep low.");
        game = "Two";
        await t.TranslateAsync("Keep low. Run!");
        Assert.Equal(2, server.Requests.Count);
        Assert.EndsWith("[\"Keep low.\",\"Run!\"]", AiFake.Message(server.Requests[1], AiService.Gemini));
        await t.TranslateAsync("Run!");
        Assert.Equal(2, server.Requests.Count);

        var old = new TranslationCache(null);
        old.Store("Keep low.", "Önceki çeviri.");
        var s2 = AiFake.Echoing(AiService.Gemini);
        string? g2 = null;
        var t2 = Create(AiService.Gemini, s2, cache: old, game: () => g2);
        Assert.Equal("Önceki çeviri.", (await t2.TranslateAsync("Keep low.")).Text);
        g2 = "   ";
        Assert.Equal("Önceki çeviri.", (await t2.TranslateAsync("Keep low.")).Text);
        g2 = "  One  ";
        Assert.Equal("[tr] Keep low.", (await t2.TranslateAsync("Keep low.")).Text);
        Assert.StartsWith("Game: One\n", AiFake.Message(s2.Requests[0], AiService.Gemini));
        g2 = "One";
        await t2.TranslateAsync("Keep low.");
        Assert.Single(s2.Requests);
        g2 = null;
        Assert.Equal("Önceki çeviri.", (await t2.TranslateAsync("Keep low.")).Text);
    }

    [Fact]
    public async Task YankiDenetimi()
    {
        var server = new FakeHandler(r => AiFake.Reply(AiService.Local,
            FakeHandler.Encode(AiFake.Sentences(r, AiService.Local).ToArray())));
        var t = Create(AiService.Local, server, local: Ollama, fallback: new FakeFallback());
        Assert.Equal("Nora: yerel: You really came back here?", (await t.TranslateAsync("Nora: You really came back here?")).Text);
        await t.TranslateAsync("Nora: You really came back here?");
        Assert.Equal(2, server.Requests.Count);

        var s2 = new FakeHandler(r => AiFake.Reply(AiService.Local, FakeHandler.Encode(AiFake.Sentences(r, AiService.Local).ToArray())));
        var t2 = Create(AiService.Local, s2, local: Ollama, fallback: new FakeFallback(s => s));
        Assert.Equal("Victor Hale.", (await t2.TranslateAsync("Victor Hale.")).Text);
        await t2.TranslateAsync("Victor Hale.");
        Assert.Single(s2.Requests);
    }

    [Fact]
    public async Task KotaHatasi()
    {
        var server = new FakeHandler(_ => FakeHandler.Json("quota", (HttpStatusCode)429));
        var cache = new TranslationCache(null);
        var t = Create(AiService.Gemini, server, fallback: new FakeFallback(), cache: cache);
        var changes = new List<OnlineFailure?>();
        t.FailureChanged += f => changes.Add(f);
        Assert.Equal("yerel: Run!", (await t.TranslateAsync("Run!")).Text);
        Assert.Equal("yerel: Swim!", (await t.TranslateAsync("Swim!")).Text);
        Assert.Single(server.Requests);
        Assert.Equal([OnlineFailure.QuotaExhausted], changes);
        Assert.False(cache.TryGet("Run!", out var _));
    }

    public static TheoryData<string> FailureKinds => ["503", "timeout", "empty", "daily", "minute"];

    [Theory]
    [MemberData(nameof(FailureKinds))]
    public async Task OnbellekVeBekleme(string kind)
    {
        var server = new FakeHandler(async (_, ct) =>
        {
            switch (kind)
            {
                case "503": return FakeHandler.Json("{}", HttpStatusCode.ServiceUnavailable);
                case "timeout": await Task.Delay(Timeout.Infinite, ct); return null!;
                case "empty": return FakeHandler.Json("{}");
                case "daily": return FakeHandler.Json(FakeHandler.Encode(new { error = new { details = new[] { new { violations = new[] { new { quotaId = "GenerateRequestsPerDayPerProjectPerModel-FreeTier", quotaValue = 20 } } } } } }), (HttpStatusCode)429);
                default: return FakeHandler.Json(FakeHandler.Encode(new { error = new { details = new object[] { new { violations = new[] { new { quotaId = "GenerateRequestsPerMinutePerProjectPerModel-FreeTier", quotaValue = 10 } } }, new { retryDelay = "30s" } } } }), (HttpStatusCode)429);
            }
        });
        var cache = new TranslationCache(null);
        cache.Store("Run!", "Koş!");
        cache.Store("Hide!", "Saklan!");
        var fallback = new FakeFallback();
        var t = Create(AiService.Gemini, server, fallback: fallback, cache: cache);
        t.LineTimeout = TimeSpan.FromMilliseconds(100);
        Assert.Equal("yerel: Duck!", (await t.TranslateAsync("Duck!")).Text);
        var failure = t.LastFailure;
        var requests = server.Requests.Count;
        fallback.Calls.Clear();
        Assert.Equal("MARCO: Koş! Saklan!", (await t.TranslateAsync("MARCO: Run! Hide!")).Text);
        Assert.Empty(fallback.Calls);
        Assert.Equal(failure, t.LastFailure);
        Assert.Equal("yerel: Run! Duck!", (await t.TranslateAsync("Run! Duck!")).Text);
        Assert.Equal(requests, server.Requests.Count);
        Assert.False(cache.TryGet("Run! Duck!", out var _));
    }

    [Fact]
    public async Task IptalEdilenIstek()
    {
        var first = true;
        var server = new FakeHandler(async (r, ct) =>
        {
            if (first)
            {
                first = false;
                await Task.Delay(Timeout.Infinite, ct);
            }
            return AiFake.Reply(AiService.Local, FakeHandler.Encode(AiFake.Sentences(r, AiService.Local).Select(s => "[tr] " + s).ToArray()));
        });
        var fallback = new FakeFallback();
        var cache = new TranslationCache(null);
        var t = Create(AiService.Local, server, local: Ollama, fallback: fallback, cache: cache);
        OnlineFailure? changed = null;
        t.FailureChanged += f => changed = f;
        using var cts = new CancellationTokenSource(100);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => t.TranslateAsync("Lower the bridge.", cts.Token));
        Assert.Empty(fallback.Calls);
        Assert.False(cache.TryGet("Lower the bridge.", out var _));
        Assert.Null(changed);
        Assert.Equal("[tr] Run!", (await t.TranslateAsync("Run!")).Text);
        var message = AiFake.Message(server.Requests[1], AiService.Local);
        Assert.Contains("English: Lower the bridge.", message);
        Assert.DoesNotContain("Turkish:", message);
    }

    [Fact]
    public async Task DakikalikButce()
    {
        var clock = new TestClock();
        var server = AiFake.Echoing(AiService.Gemini);
        var budget = new RequestBudget(1, clock);
        var t = Create(AiService.Gemini, server, fallback: new FakeFallback(), budget: budget, clock: clock);
        Assert.Equal("[tr] Run!", (await t.TranslateAsync("Run!")).Text);
        Assert.False(t.LastLineHitMinuteLimit);
        Assert.Equal("yerel: Swim!", (await t.TranslateAsync("Swim!")).Text);
        Assert.True(t.LastLineHitMinuteLimit);
        Assert.Null(t.LastFailure);
        Assert.Equal("[tr] Run!", (await t.TranslateAsync("Run!")).Text);

        var s2 = AiFake.Echoing(AiService.Gemini);
        await Create(AiService.Gemini, s2, budget: new RequestBudget(1, clock), clock: clock).TranslateAsync("Open the hatch. Keep low. Run!");
        Assert.Single(s2.Requests);

        var minute = new FakeHandler(_ => FakeHandler.Json(FakeHandler.Encode(new { error = new { details = new object[] { new { violations = new[] { new { quotaId = "GenerateRequestsPerMinutePerProjectPerModel-FreeTier", quotaValue = 5 } } }, new { retryDelay = "10s" } } } }), (HttpStatusCode)429));
        var b3 = new RequestBudget(15, clock);
        var t3 = Create(AiService.Gemini, minute, fallback: new FakeFallback(), budget: b3, clock: clock);
        Assert.Equal("yerel: Run!", (await t3.TranslateAsync("Run!")).Text);
        Assert.Equal("yerel: Swim!", (await t3.TranslateAsync("Swim!")).Text);
        Assert.Single(minute.Requests);
        Assert.Null(t3.LastFailure);
        Assert.True(t3.LastLineHitMinuteLimit);
        Assert.Equal(5, b3.Limit);

        var daily = new FakeHandler(_ => FakeHandler.Json(FakeHandler.Encode(new { error = new { details = new[] { new { violations = new[] { new { quotaId = "GenerateRequestsPerDayPerProjectPerModel-FreeTier", quotaValue = 20 } } } } } }), (HttpStatusCode)429));
        var t4 = Create(AiService.Gemini, daily, fallback: new FakeFallback());
        await t4.TranslateAsync("Run!");
        Assert.Equal(OnlineFailure.QuotaExhausted, t4.LastFailure);
    }

    [Fact]
    public void KayanPencere()
    {
        var clock = new TestClock();
        var b = new RequestBudget(3, clock);
        Assert.True(b.TryAcquire());
        clock.Advance(TimeSpan.FromSeconds(20));
        Assert.True(b.TryAcquire());
        Assert.True(b.TryAcquire());
        Assert.False(b.TryAcquire());
        clock.Advance(TimeSpan.FromSeconds(39));
        Assert.False(b.TryAcquire());
        clock.Advance(TimeSpan.FromSeconds(1));
        Assert.True(b.TryAcquire());
        Assert.False(b.TryAcquire());
        b.Lower(1);
        Assert.Equal(1, b.Limit);
        b.Lower(50);
        Assert.Equal(1, b.Limit);
        b.Lower(0);
        Assert.Equal(1, b.Limit);
    }

    [Fact]
    public async Task GercekKayitZamanCizelgesi()
    {
        var clock = new TestClock();
        var start = clock.GetUtcNow();
        var server = AiFake.Echoing(AiService.Gemini);
        var budget = new RequestBudget(15, clock);
        var t = Create(AiService.Gemini, server, fallback: new FakeFallback(), budget: budget, clock: clock);
        var changes = 0;
        t.FailureChanged += _ => changes++;
        var times = new[] { 21734, 30010, 35159, 36602, 37585, 38121, 40015, 43233, 45500, 49720, 51248, 54432, 56567, 60607,
            63772, 68160, 76612, 77354, 80223, 81879, 82560, 87568, 88425, 88661, 93364, 98714 };
        var cloud = 0;
        var local = 0;
        for (var i = 0; i < times.Length; i++)
        {
            clock.Advance(start.AddMilliseconds(times[i]) - clock.GetUtcNow());
            var text = (await t.TranslateAsync($"Line number {i} here.")).Text;
            if (text.StartsWith("yerel:", StringComparison.Ordinal))
            {
                local++;
                Assert.True(t.LastLineHitMinuteLimit);
            }
            else
            {
                cloud++;
                Assert.False(t.LastLineHitMinuteLimit);
            }
        }
        Assert.Equal(18, cloud);
        Assert.Equal(8, local);
        Assert.Equal(0, changes);
    }

    [Fact]
    public async Task EkraniCevirTopluTekIstek()
    {
        var clock = new TestClock();
        var server = AiFake.Echoing(AiService.Gemini);
        var budget = new RequestBudget(15, clock);
        for (var i = 0; i < 15; i++) budget.TryAcquire();
        var t = Create(AiService.Gemini, server, budget: budget, clock: clock);
        var texts = Enumerable.Range(0, 20).Select(i => $"Menu item {i}").ToList();
        var results = await t.TranslateBatchAsync(texts);
        Assert.Equal(texts.Select(x => "[tr] " + x), results);
        Assert.Single(server.Requests);
        Assert.Equal(8192, server.Requests[0].Json.GetProperty("generationConfig").GetProperty("maxOutputTokens").GetInt32());
        await t.TranslateBatchAsync(texts);
        Assert.Single(server.Requests);

        var s45 = AiFake.Echoing(AiService.Gemini);
        var many = Enumerable.Range(0, 45).Select(i => $"Text {i}").ToList();
        Assert.Equal(many.Select(x => "[tr] " + x), await Create(AiService.Gemini, s45).TranslateBatchAsync(many));
        Assert.Equal(2, s45.Requests.Count);
        Assert.DoesNotContain("English: ", AiFake.Message(s45.Requests[0], AiService.Gemini));
    }

    [Fact]
    public async Task EkraniCevirHatalar()
    {
        var bad = new FakeHandler(_ => FakeHandler.Json("{}", HttpStatusCode.InternalServerError));
        var changes = new List<OnlineFailure?>();
        var t = Create(AiService.Claude, bad, fallback: new FakeFallback());
        t.FailureChanged += f => changes.Add(f);
        Assert.Equal(["yerel: Check the radio", "yerel: Follow the river"], await t.TranslateBatchAsync(["Check the radio", "Follow the river"]));
        Assert.Equal([OnlineFailure.Unreachable], changes);

        var t2 = Create(AiService.Claude, bad);
        var e = await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t2.TranslateBatchAsync(["Check the radio"]));
        Assert.Equal(UnavailableReason.DownloadRequired, e.Reason);
        Assert.Equal(OnlineFailure.Unreachable, t2.LastFailure);

        var shortList = new FakeHandler(_ => AiFake.Reply(AiService.Gemini, "[\"[tr] bir\"]"));
        Assert.Equal(["yerel: one", "yerel: two"], await Create(AiService.Gemini, shortList, fallback: new FakeFallback()).TranslateBatchAsync(["one", "two"]));

        var bare = new FakeHandler(_ => AiFake.Reply(AiService.Local, "[Telsize bak., Nehri izle.]"));
        var t3 = Create(AiService.Local, bare, local: Ollama, game: () => "Night Ferry");
        Assert.Equal(["Telsize bak.", "Nehri izle."], await t3.TranslateBatchAsync(["Check the radio.", "Follow the river."]));
        Assert.StartsWith("Game: Night Ferry\n\n", AiFake.Message(bare.Requests[0], AiService.Local));
    }

    [Fact]
    public async Task EkraniCevirOyunluOnbellek()
    {
        var server = new FakeHandler(r =>
        {
            var game = AiFake.Message(r, AiService.Gemini).Split('\n')[0];
            var reply = game == "Game: Cave game" ? "Yarasa gitti." : "Sopa gitti.";
            return AiFake.Reply(AiService.Gemini, FakeHandler.Encode(new[] { reply }));
        });
        string? game = "Cave game";
        var t = Create(AiService.Gemini, server, game: () => game);
        Assert.Equal(["Yarasa gitti."], await t.TranslateBatchAsync(["The bat is gone."]));
        Assert.StartsWith("Game: Cave game\n", AiFake.Message(server.Requests[0], AiService.Gemini));
        await t.TranslateBatchAsync(["The bat is gone."]);
        Assert.Single(server.Requests);
        game = "Baseball game";
        Assert.Equal(["Sopa gitti."], await t.TranslateBatchAsync(["The bat is gone."]));
        game = "Cave game";
        Assert.Equal(["Yarasa gitti."], await t.TranslateBatchAsync(["The bat is gone."]));
        Assert.Equal(2, server.Requests.Count);

        var s2 = AiFake.Echoing(AiService.Gemini);
        var g = "One";
        var reads = 0;
        var t2 = Create(AiService.Gemini, s2, game: () =>
        {
            reads++;
            var current = g;
            g = "Two";
            return current;
        });
        var texts = Enumerable.Range(0, 41).Select(i => $"Screen text {i}").ToList();
        await t2.TranslateBatchAsync(texts);
        Assert.Equal(1, reads);
        Assert.Equal(2, s2.Requests.Count);
        Assert.All(s2.Requests, r => Assert.StartsWith("Game: One\n", AiFake.Message(r, AiService.Gemini)));
        g = "One";
        var t3 = Create(AiService.Gemini, s2, game: () => g);
        await t3.TranslateBatchAsync(texts);
        Assert.Equal(4, s2.Requests.Count);
    }

    [Fact]
    public async Task AnahtarDeneme()
    {
        var ok = AiFake.Echoing(AiService.Claude);
        var valid = await AiKeyCheck.RunAsync(AiService.Claude, "claude-haiku-5-5", "k", "tr", ok.Client());
        var sample = AiKeyCheck.SampleLine;
        var colon = sample.IndexOf(": ", StringComparison.Ordinal);
        Assert.Equal(new KeyCheckResult(KeyCheckStatus.Valid, sample[..(colon + 2)] + "[tr] " + sample[(colon + 2)..]), valid);
        Assert.Equal("[\"" + sample[(colon + 2)..] + "\"]", AiFake.Message(ok.Requests[0], AiService.Claude).Split('\n')[^1]);

        foreach (var service in new[] { AiService.Gemini, AiService.OpenAi, AiService.Claude, AiService.Local })
        {
            var denied = new FakeHandler(_ => FakeHandler.Json("""{"error":"bad key secret-key-999"}""", HttpStatusCode.Unauthorized));
            var r = await AiKeyCheck.RunAsync(service, "", "secret-key-999", "tr", denied.Client(), Ollama);
            Assert.Equal(KeyCheckStatus.InvalidKey, r.Status);
            Assert.Null(r.Sample);
            Assert.DoesNotContain("secret-key-999", r.ToString());
        }

        var slow = new FakeHandler(async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return null!;
        });
        using (var timeoutHttp = slow.Client())
        {
            var task = AiKeyCheck.RunAsync(AiService.Gemini, "", "k", "tr", timeoutHttp);
            Assert.Equal(KeyCheckStatus.Unreachable, (await task).Status);
        }

        Assert.Equal(KeyCheckStatus.InvalidKey, (await AiKeyCheck.RunAsync(AiService.Claude, "", "   ", "tr", ok.Client())).Status);

        var minute = new FakeHandler(_ => FakeHandler.Json(FakeHandler.Encode(new { error = new { details = new object[] { new { violations = new[] { new { quotaId = "GenerateRequestsPerMinutePerProjectPerModel-FreeTier", quotaValue = 5 } } }, new { retryDelay = "10s" } } } }), (HttpStatusCode)429));
        Assert.Equal(KeyCheckStatus.QuotaExhausted, (await AiKeyCheck.RunAsync(AiService.Gemini, "", "k", "tr", minute.Client())).Status);

        var local = AiFake.Echoing(AiService.Local);
        Assert.Equal(KeyCheckStatus.Valid, (await AiKeyCheck.RunAsync(AiService.Local, "", "", "tr", local.Client(), Ollama)).Status);
        Assert.False(local.Requests[0].Headers.ContainsKey("Authorization"));
    }

    [Fact]
    public async Task ArapcaIstek()
    {
        var server = AiFake.Echoing(AiService.Gemini);
        var t = Create(AiService.Gemini, server, target: "ar");
        await t.TranslateAsync("Marco?");
        await t.TranslateAsync("Wait for me.");
        var r = server.Requests[1];
        var instruction = r.Json.GetProperty("systemInstruction").GetProperty("parts")[0].GetProperty("text").GetString()!;
        Assert.Contains("Modern Standard Arabic", instruction);
        var message = AiFake.Message(r, AiService.Gemini);
        Assert.Contains("into Arabic", message);
        Assert.DoesNotContain("Turkish", message + instruction);
        Assert.Contains("Arabic: [tr] Marco?", message);
    }

    [Fact]
    public async Task CeviriModeliYerel()
    {
        var gemma = LocalServer.Create(LocalServer.OllamaUrl, "translategemma:12b")!;
        var server = new FakeHandler(r => AiFake.Reply(AiService.Local, "Kapağı açıyorum.\nEğilin."));
        var t = Create(AiService.Local, server, local: gemma);
        Assert.Equal("Kapağı açıyorum. Eğilin.", (await t.TranslateAsync("Open the hatch. Keep low.")).Text);
        var j = server.Requests[0].Json;
        var messages = j.GetProperty("messages").EnumerateArray().ToList();
        Assert.Single(messages);
        Assert.EndsWith("into Turkish:\n\n\nOpen the hatch.\nKeep low.", messages[0].GetProperty("content").GetString());
        Assert.DoesNotContain("[", messages[0].GetProperty("content").GetString());
    }
}
