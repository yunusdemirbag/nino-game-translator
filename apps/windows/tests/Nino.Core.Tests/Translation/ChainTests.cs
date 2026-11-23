// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Translation;

namespace Nino.Core.Tests.Translation;

/// <summary>Sabit metin döndüren sahte çevirmen.</summary>
internal sealed class LabelTranslator(string label, bool batch = true) : ITranslator
{
    public List<string>
        Calls { get; } = [];
    public List<string> Pretranslated { get; } = [];
    public List<IReadOnlyList<string>> Batches { get; } = [];
    public string EngineName => label;
    public bool SupportsPretranslation => true;
    public bool SupportsBatch => batch;

    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        Calls.Add(text);
        return Task.FromResult(TranslationResult.FromEngine(label));
    }

    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        Pretranslated.Add(text);
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken
            cancellationToken = default)
    {
        Batches.Add(texts);
        return Task.FromResult<IReadOnlyList<string>>(texts.Select(_ => label).ToList());
    }
}

internal sealed class FakePool : IPoolFirstSource
{
    public Func<string?, bool> PoolFirst { get; set; } = _ => true;
    public Func<string, string?> Answer { get; set; } = _ => "havuz";
    public List<(string Line, IReadOnlyList<string> Context, string? Game)> Asked { get; } = [];

    public bool IsPoolFirst(string? game) => PoolFirst(game);

    public Task<string?> AskWithDeadlineAsync(string line, IReadOnlyList<string> context, string? game,
        CancellationToken cancellationToken)
    {
        Asked.Add((line, context, game));
        return Task.FromResult(Answer(line));
    }
}

public class ChainTests
{
    static (PoolFirstTranslator Chain, LabelTranslator Engine, LabelTranslator Free, FakePool Pool) Setup(string? game = "GTA VI")
    {
        var engine = new LabelTranslator("gemini");
        var free = new LabelTranslator("ücretsiz", batch: false);
        var pool = new FakePool();
        var currentGame = game;
        var chain = new PoolFirstTranslator(engine, free,
            new PoolFirstOptions(pool, true, () => currentGame, _ => ["önceki"]));
        return (chain, engine, free, pool);
    }

    [Fact]
    public async Task HavuzOncelikli()
    {
        var (chain, engine, free, pool) = Setup();
        var r = await chain.TranslateAsync("Climb into the boat!");
        Assert.Equal(("havuz", TranslationOrigin.Pool), (r.Text, r.Origin));
        await chain.PretranslateAsync("Climb into the boat!");
        Assert.Empty(engine.Pretranslated);
        Assert.False(chain.SupportsBatch);
        Assert.Equal(["havuz", "havuz"], await chain.TranslateBatchAsync(["one row", "a second row"]));
        Assert.Empty(engine.Calls);
        Assert.Empty(engine.Batches);
        Assert.Empty(free.Calls);
        Assert.Equal(3, pool.Asked.Count);
        Assert.Equal(["önceki"], pool.Asked[0].Context);
    }

    [Fact]
    public async Task HavuzVeUcretsizYoksaKendiMotoru()
    {
        // Ücretsiz model kurulu değilse (UnavailableTranslator) satır boş kalmaz: kullanıcının motoru denenir.
        var engine = new LabelTranslator("gemini");
        var pool = new FakePool { Answer = _ => null };
        var logs = new List<string>();
        var chain = new PoolFirstTranslator(engine, new UnavailableTranslator(UnavailableReason.DownloadRequired),
            new PoolFirstOptions(pool, true, () => "GTA VI", _ => [], logs.Add));
        var r = await chain.TranslateAsync("Follow me.");
        Assert.Equal(("gemini", TranslationOrigin.Engine), (r.Text, r.Origin));
        Assert.Equal(["Follow me."], engine.Calls);
        Assert.Equal(2, logs.Count);

        // Motorun kendisi ücretsizse ikinci deneme yapılmaz, hata satırı düşürür.
        var free = new UnavailableTranslator(UnavailableReason.DownloadRequired);
        var alone = new PoolFirstTranslator(free, free, new PoolFirstOptions(pool, true, () => "GTA VI", _ => []));
        await Assert.ThrowsAsync<TranslatorUnavailableException>(() => alone.TranslateAsync("Follow me."));
    }

    [Fact]
    public async Task HavuzGelmezseUcretsiz()
    {
        var (chain, engine, free, pool) = Setup();
        var logs = new List<string>();
        var withLog = new PoolFirstTranslator(engine, free, new PoolFirstOptions(pool, true, () => "GTA VI", _ => [], logs.Add));
        pool.Answer = _ => null;
        Assert.Equal(TranslationOrigin.Free, (await withLog.TranslateAsync("Run!")).Origin);
        pool.Answer = _ => throw new HttpRequestException("ağ");
        var r = await withLog.TranslateAsync("Hide!");
        Assert.Equal(("ücretsiz", TranslationOrigin.Free), (r.Text, r.Origin));
        Assert.Equal(2, free.Calls.Count);
        Assert.Empty(engine.Calls);
        Assert.Equal(2, logs.Count);
        _ = chain;
    }

    [Fact]
    public async Task HavuzOncelikliDegil()
    {
        var (chain, engine, _, pool) = Setup();
        pool.PoolFirst = _ => false;
        var r = await chain.TranslateAsync("Run!");
        Assert.Equal(("gemini", TranslationOrigin.Engine), (r.Text, r.Origin));
        await chain.PretranslateAsync("Run!");
        Assert.Single(engine.Pretranslated);
        Assert.True(chain.SupportsBatch);
        await chain.TranslateBatchAsync(["a", "b"]);
        Assert.Single(engine.Batches);
        Assert.Empty(pool.Asked);
    }

    [Fact]
    public async Task OyunSatirArasindaDegisir()
    {
        var engine = new LabelTranslator("gemini");
        var free = new LabelTranslator("ücretsiz");
        var pool = new FakePool { PoolFirst = g => g == "GTA VI" };
        var game = "RDR 2";
        var chain = new PoolFirstTranslator(engine, free, new PoolFirstOptions(pool, true, () => game, _ => []));
        Assert.Equal("gemini", (await chain.TranslateAsync("one")).Text);
        game = "GTA VI";
        Assert.Equal("havuz", (await chain.TranslateAsync("two")).Text);
        Assert.Single(engine.Calls);
    }

    [Fact]
    public async Task KaynakIngilizceDegilse()
    {
        var engine = new LabelTranslator("gemini");
        var pool = new FakePool();
        var chain = new PoolFirstTranslator(engine, new LabelTranslator("x"), new PoolFirstOptions(pool, false, () => "GTA VI", _ => []));
        Assert.Equal("gemini", (await chain.TranslateAsync("Run!")).Text);
        Assert.Empty(pool.Asked);
    }

    [Fact]
    public async Task YaziDenetimi()
    {
        var inner = new LabelTranslator("iç");
        var ar = new ScriptGuardTranslator(inner, "ar");
        var same = await ar.TranslateAsync("الألعاب");
        Assert.Equal(("الألعاب", TranslationOrigin.AlreadyTarget), (same.Text, same.Origin));
        Assert.Equal("iç", (await ar.TranslateAsync("Stay close.")).Text);
        var tr = new ScriptGuardTranslator(inner, "tr");
        Assert.Equal("iç", (await tr.TranslateAsync("الألعاب")).Text);

        // Ekran çevirisi (translation.screen.translate): yazı denetimi toplu çeviriyi içe geçirir; hedef yazılı parçaları kendisi ayırır.
        Assert.True(ar.SupportsBatch);
        var batch = await ar.TranslateBatchAsync(["Light the beacon", "الإعدادات", "Untie the rope"]);
        Assert.Equal(["iç", "الإعدادات", "iç"], batch);
        Assert.Equal(["Light the beacon", "Untie the rope"], inner.Batches.Single());
        await ar.PretranslateAsync("الإعدادات");
        Assert.Empty(inner.Pretranslated);
    }

    [Fact]
    public void Butce()
    {
        var clock = new TestClock();
        var budget = new RequestBudget(3, clock);
        Assert.True(budget.TryAcquire());
        clock.Advance(TimeSpan.FromSeconds(20));
        Assert.True(budget.TryAcquire());
        Assert.True(budget.TryAcquire());
        Assert.False(budget.TryAcquire());
        clock.Advance(TimeSpan.FromSeconds(39));
        Assert.False(budget.TryAcquire());
        clock.Advance(TimeSpan.FromSeconds(1));
        Assert.True(budget.TryAcquire());
        Assert.False(budget.TryAcquire());
        budget.Lower(1);
        Assert.Equal(1, budget.Limit);
        budget.Lower(50);
        Assert.Equal(1, budget.Limit);
        budget.Lower(0);
        Assert.Equal(1, budget.Limit);
    }

    [Fact]
    public void ButceZamanCizelgesi()
    {
        var clock = new TestClock();
        var start = clock.GetUtcNow();
        var budget = new RequestBudget(15, clock);
        long[] times = [21734, 30010, 35159, 36602, 37585, 38121, 40015, 43233, 45500, 49720, 51248, 54432, 56567, 60607,
            63772, 68160, 76612, 77354, 80223, 81879, 82560, 87568, 88425, 88661, 93364, 98714];
        var cloud = 0;
        var local = 0;
        foreach (var ms in times)
        {
            clock.Advance(start.AddMilliseconds(ms) - clock.GetUtcNow());
            if (budget.TryAcquire()) cloud++;
            else local++;
        }
        Assert.Equal(18, cloud);
        Assert.Equal(8, local);
    }

    [Fact]
    public void OrtakHak()
    {
        var a = RequestBudget.Shared("gemini:test-" + Guid.NewGuid(), 15);
        Assert.NotNull(a);
        Assert.Null(RequestBudget.Shared("openai:gpt-6-luna", null));
        var name = "gemini:same-" + Guid.NewGuid();
        Assert.Same(RequestBudget.Shared(name, 15), RequestBudget.Shared(name, 15));
    }

    [Fact]
    public void ModelListesi()
    {
        var c = AiModelCatalog.Default;
        Assert.Equal(["gemini", "openai", "claude"], c.Services);
        Assert.Equal("gemini-3.5-flash-lite", c.Resolve(AiService.Gemini, "")!.Id);
        Assert.Equal(15, c.Resolve(AiService.Gemini, null)!.RequestsPerMinute);
        Assert.Equal("LOW", c.Resolve(AiService.Gemini, "gemini-3.6-flash")!.Thinking);
        Assert.Equal("gpt-6-luna", c.Resolve(AiService.OpenAi, "gpt-4o")!.Id);
        Assert.Equal("none", c.Resolve(AiService.OpenAi, "gpt-6.1-terra")!.Effort);
        Assert.Equal("between_tools", c.Resolve(AiService.Claude, "claude-sonnet-5-5")!.Thinking);
        Assert.Equal("claude-haiku-5-5", c.Resolve(AiService.Claude, null)!.Id);
        Assert.True(c.HasFreeTier(AiService.Gemini));
        Assert.False(c.HasFreeTier(AiService.Claude));
        Assert.Null(c.Resolve(AiService.Local, "x"));
        Assert.Equal("gemini:gemini-3.5-flash-lite", EngineNames.Cloud(AiService.Gemini, "gemini-3.5-flash-lite"));
        Assert.Equal("openai:gpt-6-luna", EngineNames.Cloud(AiService.OpenAi, "gpt-6-luna"));
    }

    [Fact]
    public void ModelMetinleri_KatalogAnahtari()
    {
        var c = AiModelCatalog.Default;
        foreach (var service in new[] { AiService.Gemini, AiService.OpenAi, AiService.Claude })
        {
            var models = c.Models(service);
            Assert.Equal(["ai.model.fast", "ai.model.better"], models.Select(m => m.TextKey));
            foreach (var language in new[] { "en", "tr", "ar" })
            {
                var text = Nino.Core.Text.TextCatalog.For(language);
                foreach (var m in models) Assert.NotEqual(m.TextKey, text.Get(m.TextKey));
            }
        }
        var noText = AiModelCatalog.Parse("""{"gemini":[{"id":"m1"}]}"""u8.ToArray());
        Assert.Equal("m1", noText.Models(AiService.Gemini)[0].TextKey);
    }

    [Theory]
    [InlineData("http://localhost:11434/v1", "http://localhost:11434/v1")]
    [InlineData("  http://localhost:11434/v1/  ", "http://localhost:11434/v1")]
    [InlineData("localhost:11434", "http://localhost:11434/v1")]
    [InlineData("http://127.0.0.1:1234", "http://127.0.0.1:1234/v1")]
    [InlineData("http://localhost:1234/v1/chat/completions", "http://localhost:1234/v1")]
    [InlineData("https://ai.example.com/openai/v1", "https://ai.example.com/openai/v1")]
    [InlineData("", null)]
    [InlineData("ftp://localhost:11434", null)]
    [InlineData("http://", null)]
    [InlineData("local host", null)]
    public void YerelAdres(string input, string? expected) => Assert.Equal(expected, LocalServer.NormalizeAddress(input));

    [Fact]
    public void YerelSunucu()
    {
        var lm = LocalServer.Create(LocalServer.LmStudioUrl, " qwen2.5-7b-instruct ")!;
        Assert.Equal("http://localhost:1234/v1/chat/completions", lm.ChatUrl);
        Assert.Equal("local:localhost:1234/qwen2.5-7b-instruct", lm.EngineName);
        Assert.Equal(LocalServerKind.LmStudio, lm.Kind);
        Assert.Equal("http://localhost:11434", LocalServer.Create("http://LOCALHOST:11434/v1/", "m")!.ShortAddress);
        Assert.Equal("local:localhost:11434/qwen2.5:7b", LocalServer.Create("http://LOCALHOST:11434/v1/", "qwen2.5:7b")!.EngineName);
        Assert.Equal(LocalServerKind.Ollama, LocalServer.Create("localhost:11434", "m")!.Kind);
        Assert.Equal(LocalServerKind.Other, LocalServer.Create("https://ai.example.com/v1", "m")!.Kind);
        Assert.Equal("local:ai.example.com/m", LocalServer.Create("https://ai.example.com/v1", "m")!.EngineName);
        Assert.Null(LocalServer.Create("ftp://nowhere", "m"));
        Assert.Null(LocalServer.Create(LocalServer.OllamaUrl, "  "));
        Assert.True(LocalServer.Create(LocalServer.OllamaUrl, "TranslateGemma:12b")!.IsTranslationModel);
    }

    sealed class FakeFactory(ITranslator free) : ITranslatorFactory
    {
        public List<string> Made { get; } = [];
        public ITranslator? Fallback { get; private set; }

        public ITranslator CreateFree(string target)
        {
            Made.Add("free:" + target);
            return free;
        }

        public ITranslator CreateDeepL(string apiKey, string target, ITranslator? fallback)
        {
            Made.Add($"deepl:{apiKey}:{target}");
            Fallback = fallback;
            return new LabelTranslator("deepl");
        }

        public ITranslator CreateAi(AiService service, string model, string apiKey, string target, LocalServer? local,
            ITranslator? fallback, Func<string?> gameName)
        {
            Made.Add($"ai:{service}:{model}:{apiKey}:{local?.EngineName}");
            Fallback = fallback;
            return new LabelTranslator("ai");
        }
    }

    [Fact]
    public void ZincirKurulumu()
    {
        var secrets = new Dictionary<string, string> { [SecretKeys.DeepLKey] = " key:fx " };
        string? Read(string name) => secrets.TryGetValue(name, out var v) ? v : null;
        var unavailable = new UnavailableTranslator(UnavailableReason.DownloadRequired);

        var settings = new AppSettings { OnlineTranslation = true, OnlineEngine = OnlineEngine.DeepL };
        var factory = new FakeFactory(unavailable);
        var chain = TranslationChain.Build(settings, Read, factory, () => null, null);
        Assert.True(chain.OnlineEnabled);
        Assert.Equal(["free:tr", "deepl:key:fx:tr"], factory.Made);
        Assert.Null(factory.Fallback);
        Assert.IsType<ScriptGuardTranslator>(chain.Translator);

        settings.TargetLanguage = "hi";
        Assert.False(TranslationChain.OnlineEnabled(settings, Read));
        settings.TargetLanguage = "tr";
        settings.SourceLanguage = "de";
        Assert.False(TranslationChain.OnlineEnabled(settings, Read));
        settings.SourceLanguage = "en";

        settings.OnlineEngine = OnlineEngine.Claude;
        Assert.False(TranslationChain.OnlineEnabled(settings, Read));
        secrets[SecretKeys.ClaudeKey] = "ck";
        settings.ClaudeModel = "claude-sonnet-5-5";
        var usable = new LabelTranslator("ücretsiz");
        var f2 = new FakeFactory(usable);
        TranslationChain.Build(settings, Read, f2, () => "GTA", null);
        Assert.Equal("ai:Claude:claude-sonnet-5-5:ck:", f2.Made[1]);
        Assert.Same(usable, f2.Fallback);

        settings.OnlineEngine = OnlineEngine.Local;
        settings.LocalAiBaseUrl = LocalServer.LmStudioUrl;
        settings.LocalAiModel = " qwen2.5-7b-instruct ";
        var f3 = new FakeFactory(usable);
        var local = TranslationChain.Build(settings, Read, f3, () => null, new PoolFirstOptions(new FakePool(), true, () => null, _ => []));
        Assert.Equal("ai:Local:qwen2.5-7b-instruct::local:localhost:1234/qwen2.5-7b-instruct", f3.Made[1]);
        Assert.IsType<PoolFirstTranslator>(((ScriptGuardTranslator)local.Translator).Inner);
        settings.LocalAiBaseUrl = "ftp://nowhere";
        Assert.False(TranslationChain.OnlineEnabled(settings, Read));

        settings.OnlineTranslation = false;
        var f4 = new FakeFactory(usable);
        var off = TranslationChain.Build(settings, Read, f4, () => null, null);
        Assert.False(off.OnlineEnabled);
        Assert.Same(usable, off.Base);
        Assert.Null(off.OnlineStatus);
    }
}
