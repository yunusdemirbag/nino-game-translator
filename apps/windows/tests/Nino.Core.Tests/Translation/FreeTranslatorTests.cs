// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Translation;

namespace Nino.Core.Tests.Translation;

/// <summary>Sahte model: verilen işlevle çevirir, çağrıları sayar, eşzamanlılığı ölçer.</summary>
internal sealed class FakeEngine(Func<string, string> translate) : ISentenceEngine
{
    int _active;
    public List<string>
        Calls { get; } = [];
    public int MaxConcurrent { get; private set; }
    public bool Disposed
        { get; private set; }
    public Func<string, Exception?>? Throw { get; set; }
    public TaskCompletionSource? Gate { get; set; }

    public string Translate(string sentence,
        CancellationToken cancellationToken)
    {
        var now = Interlocked.Increment(ref _active);
        lock (Calls)
        {
            Calls.Add(sentence);
            MaxConcurrent = Math.Max(MaxConcurrent, now);
        }
        try
        {
            Gate?.Task.Wait(cancellationToken);
            Thread.Sleep(1);
            if (Throw?.Invoke(sentence) is { } e) throw e;
            return translate(sentence);
        }
        finally
        {
            Interlocked.Decrement(ref _active);
        }
    }

    public void Dispose()
        => Disposed = true;
}

internal sealed class FakeSource(FakeEngine? engine, bool installed = true, Exception? openError = null)
    : ISentenceEngineSource
{
    public int Opens { get; private set; }
    public bool IsInstalled => installed;

    public ISentenceEngine Open(CancellationToken cancellationToken)
    {
        Opens++;
        if (openError is not null) throw openError;
        return engine!;
    }
}

public class FreeTranslatorTests
{
    static FreeTranslator Create(FakeEngine engine, string target = "tr", TranslationCache? cache = null,
        Glossary? glossary = null, TimeProvider? clock = null, FakeSource? source = null) =>
        new(source ?? new FakeSource(engine), target, cache ?? new TranslationCache(null),
            () => glossary ?? Glossary.Empty, clock);

    static FakeEngine Upper() => new(s => s.ToUpperInvariant());

    [Fact]
    public async Task OnbellekTamMetneBakar()
    {
        var engine = Upper();
        using var t = Create(engine);
        Assert.Equal("WAIT!", (await t.TranslateAsync("Wait!")).Text);
        Assert.Equal("WAIT!", (await t.TranslateAsync("Wait!")).Text);
        Assert.Single(engine.Calls);
        await t.TranslateAsync("wait!");
        Assert.Equal(2, engine.Calls.Count);
        Assert.Equal("opus-mt-ct2-p3", t.EngineName);
    }

    [Fact]
    public async Task IsitmaBaglamaKarismaz()
    {
        var engine = Upper();
        using var t = Create(engine);
        await t.WarmUpAsync();
        await t.TranslateAsync("Stay.");
        Assert.Equal(["Hello.", "Stay."], engine.Calls);
    }

    [Fact]
    public async Task CumleCumleCagrilar()
    {
        var engine = Upper();
        using var t = Create(engine);
        await t.TranslateAsync("We row to the island now. Stay low, little brother.");
        await t.TranslateAsync("We row to the island now. Keep the lantern lit.");
        Assert.Equal(["We row to the island now.",
            "Stay low, little brother.", "Keep the lantern lit."], engine.Calls);
    }

    [Fact]
    public async Task EtiketlerVeKisaCumle()
    {
        var engine = Upper();
        using var t = Create(engine);
        Assert.Equal("LENA: CAPTAIN, LOOK!\nORRIN: HIDE.", (await t.TranslateAsync("LENA: Captain, look!\nORRIN: Hide.")).Text);
        Assert.Equal("...", (await t.TranslateAsync("...")).Text);
        Assert.Equal(["Captain, look!",
            "Captain, look! *** Hide."], engine.Calls);
    }

    [Fact]
    public async Task OgrenilenAdlar()
    {
        var engine = Upper();
        using var t = Create(engine);
        await t.TranslateAsync("LENA: Captain, look!");
        await t.TranslateAsync("THE ROPE WILL SNAP, LENA.");
        Assert.Equal("The rope will snap, Lena.",
            engine.Calls[^1]);

        var engine2 = Upper();
        using var t2 = Create(engine2);
        await t2.TranslateAsync("DOCK MASTER: Ahoy.");
        await t2.TranslateAsync("HIDE, DOCK MASTER!");
        Assert.Equal("Ahoy. *** Hide, Dock Master!", engine2.Calls[^1]);
    }

    [Fact]
    public async Task KonusmaciAdlari()
    {
        async Task Check(string line, string expected, string? call = null)
        {
            var engine = Upper();
            using var t = Create(engine);
            Assert.Equal(expected, (await t.TranslateAsync(line)).Text);
            if (call is not null) Assert.Equal(call, engine.Calls[^1]);
        }
        await Check("LENA: Captain!", "LENA: CAPTAIN!", "Captain!");
        await Check("DOCK MASTER: Who rows there?", "DOCK MASTER: WHO ROWS THERE?", "Who rows there?");
        await Check("Harbor Master: Sister, wait.", "Harbor Master: SISTER, WAIT.");
        await Check("Hint: Press X.", "HINT: PRESS X.", "Hint: Press X.");
    }

    [Fact]
    public async Task KaliciOnbellek()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-free-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(dir, TranslationCache.FileName(FreeTranslator.Name, "en", "tr"));
        Assert.EndsWith("v1-opus_mt_ct2_p3-en-tr.jsonl", path);
        var first = Upper();
        using (var t = Create(first, cache: new TranslationCache(path))) await t.TranslateAsync("ORRIN: We sail now. Stay low.");
        var second = Upper();
        using var t2 = Create(second, cache: new TranslationCache(path));
        Assert.Equal("ORRIN: WE SAIL NOW. STAY LOW.", (await t2.TranslateAsync("ORRIN: We sail now. Stay low.")).Text);
        Assert.Empty(second.Calls);
        await t2.TranslateAsync("We sail now. Row to the dock, sister!");
        Assert.Equal(["Stay low. *** We sail now.", "Row to the dock, sister!"], second.Calls);
    }

    [Fact]
    public async Task ModelKuruluDegil()
    {
        var engine = Upper();
        var source = new FakeSource(engine, installed: false);
        using var t = Create(engine, source: source);
        Assert.Equal(FreeTranslatorState.DownloadRequired, t.State);
        var e = await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Run!"));
        Assert.Equal(UnavailableReason.DownloadRequired, e.Reason);
        Assert.Equal(0, source.Opens);
    }

    [Fact]
    public async Task MotorAcilamiyor()
    {
        var cache = new TranslationCache(null);
        cache.Store("This line is already known here.", "Bilinen.");
        var source = new FakeSource(null, openError: new FileNotFoundException("python.exe"));
        using var t = Create(Upper(), cache: cache, source: source);
        var events = 0;
        t.EngineFailed += _ => Interlocked.Increment(ref events);
        await t.WarmUpAsync();
        var e = await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Run!"));
        Assert.Equal(UnavailableReason.EngineFailed, e.Reason);
        Assert.IsType<FileNotFoundException>(e.InnerException);
        await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Hide!"));
        Assert.Equal(1, source.Opens);
        Assert.Equal(1, events);
        Assert.Equal(FreeTranslatorState.EngineFailed, t.State);
        Assert.Equal("Bilinen.", (await t.TranslateAsync("This line is already known here.")).Text);
    }

    [Fact]
    public async Task IsciKapanmasiKaliciHata()
    {
        var engine = Upper();
        engine.Throw = _ => new IOException("çeviri sırasında kapandı");
        using var t = Create(engine);
        var events = 0;
        t.EngineFailed += _ => events++;
        Assert.Equal(UnavailableReason.EngineFailed,
            (await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Run!"))).Reason);
        Assert.Equal(UnavailableReason.EngineFailed,
            (await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Hide!"))).Reason);
        Assert.Equal(1, events);
        Assert.Single(engine.Calls);
    }

    [Fact]
    public async Task TekSatirHatasiYalnizOnuDusurur()
    {
        var engine = Upper();
        engine.Throw = s => s == "Bad." ? new InvalidOperationException("satır") : null;
        using var t = Create(engine);
        await Assert.ThrowsAsync<InvalidOperationException>(() => t.TranslateAsync("Bad."));
        Assert.Equal("GOOD.", (await t.TranslateAsync("Good.")).Text);
    }

    [Fact]
    public async Task EsZamanliSatirlarSiraylaCevrilir()
    {
        var engine = Upper();
        using var t = Create(engine);
        var tasks = Enumerable.Range(0, 40).Select(i => t.TranslateAsync($"Subtitle row {i % 10} is here.")).ToArray();
        var results = await Task.WhenAll(tasks);
        for (var i = 0; i < 40; i++) Assert.Equal($"SUBTITLE ROW {i % 10} IS HERE.", results[i].Text);
        Assert.Equal(1, engine.MaxConcurrent);
        Assert.Equal(10, engine.Calls.Count);
    }

    [Fact]
    public async Task BekleyenIptalEdilir()
    {
        var engine = Upper();
        engine.Gate = new TaskCompletionSource();
        using var t = Create(engine);
        var first = t.TranslateAsync("First line here.");
        while (engine.Calls.Count == 0) await Task.Delay(5);
        using var cts = new CancellationTokenSource();
        var second = t.TranslateAsync("Second line here.", cts.Token);
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(()
            => second);
        engine.Gate.SetResult();
        Assert.Equal("FIRST LINE HERE.", (await first).Text);
    }

    [Fact]
    public async Task Kapatinca()
    {
        var engine = Upper();
        var t = Create(engine);
        await t.TranslateAsync("We run to the boat now.");
        t.Dispose();
        Assert.True(engine.Disposed);
        Assert.Equal(UnavailableReason.Closed,
            (await Assert.ThrowsAsync<TranslatorUnavailableException>(() => t.TranslateAsync("Hide!"))).Reason);
        Assert.Equal("WE RUN TO THE BOAT NOW.", (await t.TranslateAsync("We run to the boat now.")).Text);
    }

    [Fact]
    public async Task KisaSatirBaglami()
    {
        var engine = new FakeEngine(s => s switch
        {
            "Who lit the fire?"
                => "Ateşi kim yaktı?",
            "Who lit the fire? *** Not me."
                => "Ateşi kim yaktı? *** Ben değil.",
            "Not me." => "Ben değil.",
            _ => s,
        });
        var clock = new TestClock();
        using var t = Create(engine, clock: clock);
        Assert.Equal("Ateşi kim yaktı?", (await t.TranslateAsync("Who lit the fire?")).Text);
        Assert.Equal("Ben değil.", (await t.TranslateAsync("Not me.")).Text);
        Assert.Equal("Ben değil.", (await t.TranslateAsync("Not me.")).Text);
        Assert.Equal(2, engine.Calls.Count);
        clock.Advance(TimeSpan.FromMinutes(1));
        await t.TranslateAsync("Something else entirely here.");
        clock.Advance(TimeSpan.FromMinutes(1));
        await t.TranslateAsync("Not me.");
        Assert.Equal("Not me.", engine.Calls[^1]);

        var vague = new FakeEngine(s => s.Contains("***") ? "Ateşi kim yaktı, ben değil." : s == "Not me." ? "Ben değil." : "Ateşi kim yaktı?");
        using var t2 = Create(vague);
        await t2.TranslateAsync("Who lit the fire?");
        Assert.Equal("Ben değil.", (await t2.TranslateAsync("Not me.")).Text);
        Assert.Equal("Not me.", vague.Calls[^1]);
    }

    [Fact]
    public async Task SozlukluCeviri()
    {
        var salt = Glossary.Parse("""{ "terms": { "Ember Blade": "Kor Kılıcı" }, "keep": ["Varos", "Kaelus"] }""");
        var engine = new FakeEngine(s => s switch
        {
            "Zarmon, raise the Velkor!" => "Zarmon, Velkor'u kaldır.",
            "Raise the Zarmon!" => "Kılıcı kaldır!",
            "Raise the Ember Blade!" => "Kor Kılıcını kaldır!",
            _ => "?" + s,
        });
        using var t = Create(engine, glossary: salt);
        Assert.Equal("Varos, Kor Kılıcı'nı kaldır!", (await t.TranslateAsync("Varos, raise the Ember Blade!")).Text);
        Assert.Equal("Zarmon, raise the Velkor!", engine.Calls[^1]);
        Assert.Equal("Kor Kılıcını kaldır!", (await t.TranslateAsync("Raise the Ember Blade!")).Text);
        Assert.Equal(["Raise the Zarmon!", "Raise the Ember Blade!"], engine.Calls.Skip(1));

        var context = new FakeEngine(s => s switch
        {
            "Zarmon is aboard. *** Run, Velkor!" => "Gemide. *** Koş, Zarmon Velkor!",
            "Run, Zarmon!" => "Koş, Zarmon!",
            _ => "Zarmon gemide.",
        });
        using var t2 = Create(context, glossary: salt);
        await t2.TranslateAsync("Varos is aboard.");
        Assert.Equal("Koş, Kaelus!", (await t2.TranslateAsync("Run, Kaelus!")).Text);
        Assert.Equal(["Zarmon is aboard.", "Zarmon is aboard. *** Run, Velkor!", "Run, Zarmon!"], context.Calls);

        var ok = new FakeEngine(s => s == "Zarmon is aboard. *** Run, Velkor!" ? "Zarmon gemide. *** Koş, Velkor!" : "Zarmon gemide.");
        using var t3 = Create(ok, glossary: salt);
        await t3.TranslateAsync("Varos is aboard.");
        Assert.Equal("Koş, Kaelus!", (await t3.TranslateAsync("Run, Kaelus!")).Text);
    }

    [Fact]
    public async Task HazirlamaSirasi()
    {
        var engine = new FakeEngine(s => s);
        using var t = Create(engine, glossary: Glossary.Parse("""{ "keep": ["Varos"] }"""));
        await t.TranslateAsync("CHECK YOUR SIX, VAROS!");
        Assert.Equal("Watch behind you, Zarmon!", engine.Calls[0]);

        var salt = Glossary.Parse("""{ "terms": { "Ember Blade": "Kor Kılıcı" }, "keep": ["Varos"] }""");
        var blade = new FakeEngine(s => s == "Zarmon, raise the Velkor!" ? "Zarmon, Velkor'u kaldır!" : "??");
        using var t2 = Create(blade, glossary: salt);
        Assert.Equal("Varos, Kor Kılıcı'nı kaldır!", (await t2.TranslateAsync("VAROS, RAISE THE EMBER BLADE!")).Text);
    }

    [Fact]
    public async Task GenelSozlukModelsiz()
    {
        var engine = new FakeEngine(s => "MODEL:" + s);
        using var t = Create(engine, glossary: Glossary.General);
        Assert.Equal("Seviye atladın!", (await t.TranslateAsync("Level up!")).Text);
        Assert.Equal("Seviye atladın!", (await t.TranslateAsync("LEVEL UP!")).Text);
        Assert.Equal("Oyun kaydedildi.", (await t.TranslateAsync("Game saved.")).Text);
        Assert.Equal("İksirim kalmadı!", (await t.TranslateAsync("I’m out of potions!")).Text);
        Assert.Equal("Arkanda!", (await t.TranslateAsync("Behind you!")).Text);
        Assert.Equal("Dikkat et!", (await t.TranslateAsync("Watch out!")).Text);
        Assert.Equal("Hadi ilerleyelim.", (await t.TranslateAsync("Let's move.")).Text);
        Assert.Equal("Kalkan düştü!", (await t.TranslateAsync("Shield’s down!")).Text);
        Assert.Equal("- Pusu!", (await t.TranslateAsync("- Ambush!")).Text);
        Assert.Empty(engine.Calls);
    }

    [Theory]
    [InlineData("Chug a pot and keep going.", "Drink a Zarmon and keep going.", "Bir Zarmon iç ve devam et.", "Bir şifa iksiri iç ve devam et.")]
    [InlineData("USE A POT IN HERE!", "Drink a Zarmon in here!", "Burada bir Zarmon iç!", "Burada bir şifa iksiri iç!")]
    [InlineData("Pop some pots, we're leaving.", "Drink a Zarmon, we're leaving.", "Bir Zarmon iç, gidiyoruz.", "Bir şifa iksiri iç, gidiyoruz.")]
    [InlineData("Mobs on the bridge.", "Monsters on the bridge.", "Köprüde canavarlar.", "Köprüde canavarlar.")]
    [InlineData("Take the mana potion with you.", "Take the Zarmon with you.", "Zarmon'u yanına al.", "Mana iksirini yanına al.")]
    public async Task GenelSozlukleModele(string line, string sent, string output, string expected)
    {
        var engine = new FakeEngine(s => s == sent ? output : "??");
        using var t = Create(engine, glossary: Glossary.General);
        Assert.Equal(expected, (await t.TranslateAsync(line)).Text);
        Assert.Equal(sent, engine.Calls[0]);
    }

    [Theory]
    [InlineData("Drink a pot of tea.")]
    [InlineData("The pottery shop is closed.")]
    [InlineData("Where is the mob boss?")]
    [InlineData("Cover the left flank.")]
    public async Task DegismedenModele(string line)
    {
        var engine = new FakeEngine(s => s);
        using var t = Create(engine, glossary: Glossary.General);
        await t.TranslateAsync(line);
        Assert.Equal(line, engine.Calls[0]);
    }

    [Fact]
    public async Task HitapSatirda()
    {
        var engine = new FakeEngine(s => s switch
        {
            "I asked you to guard the boat." =>
                "Senden tekneyi korumanı istedim.",
            "I asked you to guard the boat. *** Stay put!" =>
                "Senden tekneyi korumanı istedim. *** Orada bekleyin!",
            _ => s,
        });
        using var t = Create(engine, glossary: Glossary.General);
        Assert.Equal("Senden tekneyi korumanı istedim. Orada bekle!",
            (await t.TranslateAsync("I asked you to guard the boat. Stay put!")).Text);
    }

    [Fact]
    public void OnbellekAnahtari()
    {
        var salt = Glossary.Parse("""{ "terms": { "Ember Blade": "Kor Kılıcı" }, "keep": ["Varos", "Kaelus"] }""");
        var p = new FreeTextPipeline("tr");
        Assert.Equal("We row.", p.CacheKey("We row.", null, salt));
        Assert.Equal("Why?\u001FWe row.", p.CacheKey("We row.", "Why?", salt));
        Assert.Equal(salt.Fingerprint + "\u001FVaros, go.", p.CacheKey("Varos, go.", null, salt));
        Assert.StartsWith(salt.Fingerprint, p.CacheKey("Go.", "Varos!", salt));
        Assert.StartsWith("gcf7f6091\u001F", p.CacheKey("Level up!", null, Glossary.General));
        Assert.StartsWith("gcf7f6091\u001F", p.CacheKey("Chug a pot and go.", null, Glossary.General));
        Assert.Equal("I smell it.", p.CacheKey("I smell it.", null, Glossary.General));
    }

    [Fact]
    public async Task TurkceDisiHedef()
    {
        var engine = new FakeEngine(_ => "ترجمة");
        using var t = Create(engine, target: "ar", glossary: Glossary.General);
        Assert.Equal("ORRIN: ترجمة", (await t.TranslateAsync("ORRIN: RAISE THE EMBER BLADE, SISTER!")).Text);
        Assert.Equal("raise the ember blade, sister!", engine.Calls[0].ToLowerInvariant());
    }
}
