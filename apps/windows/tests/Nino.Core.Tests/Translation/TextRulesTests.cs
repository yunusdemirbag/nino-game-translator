// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Translation;

namespace Nino.Core.Tests.Translation;

public class SplitterTests
{
    /// <summary>Parçaları <c>[çevrilecek]</c> biçiminde yazar.</summary>
    static string Show(string text) =>
        string.Concat(SubtitleSplitter.Split(text).Select(p => p.Translatable ? "[" + p.Text + "]" : p.Text));

    [Theory]
    [InlineData("Duck!", "[Duck!]")]
    [InlineData("Lena! Hurry. The tide is still rising.", "[Lena!] [Hurry.] [The tide is still rising.]")]
    [InlineData("Did you hear that?! It came from the hold.", "[Did you hear that?!] [It came from the hold.]")]
    [InlineData("\"Duck!\" she shouted. Then silence.", "[\"Duck!\" she shouted.] [Then silence.]")]
    [InlineData("Maybe… but the storm is coming.", "[Maybe… but the storm is coming.]")]
    [InlineData("Hold on... is that smoke?", "[Hold on... is that smoke?]")]
    [InlineData("Capt. Reyes is aboard. Mrs. Hale too.", "[Capt. Reyes is aboard.] [Mrs. Hale too.]")]
    [InlineData("No. We sail now.", "[No.] [We sail now.]")]
    [InlineData("Orrin.", "[Orrin.]")]
    [InlineData("LENA: Captain, look at the reef!", "LENA: [Captain, look at the reef!]")]
    [InlineData("LENA: Look! ORRIN: Keep your head down.", "LENA: [Look!] ORRIN: [Keep your head down.]")]
    [InlineData("ORRIN SR.: Fair winds.", "ORRIN SR.: [Fair winds.]")]
    [InlineData("Hint: the reef hides a cave.", "[Hint: the reef hides a cave.]")]
    [InlineData("Orrin: Hold steady.", "Orrin: [Hold steady.]")]
    [InlineData("Harbor Master: Who sails there?", "Harbor Master: [Who sails there?]")]
    [InlineData("Objective: Reach the lighthouse.", "[Objective: Reach the lighthouse.]")]
    [InlineData("If we do not reach the harbor before the storm,\nwe will lose the cargo.",
        "[If we do not reach the harbor before the storm, we will lose the cargo.]")]
    [InlineData("LENA: Captain, look!\r\nORRIN: Keep your head down.", "LENA: [Captain, look!]\nORRIN: [Keep your head down.]")]
    [InlineData("- Is anyone aboard?\n- Only me.", "- [Is anyone aboard?]\n- [Only me.]")]
    [InlineData("...", "...")]
    [InlineData("?!", "?!")]
    [InlineData("", "")]
    [InlineData("   ", "")]
    public void Bolme(string input, string expected) => Assert.Equal(expected, Show(input));

    [Theory]
    [InlineData("THE ROPE WILL SNAP ANY SECOND.", "The rope will snap any second.")]
    [InlineData("I TRIED, BUT I WON'T.", "I tried, but I won't.")]
    [InlineData("DUCK!", "DUCK!")]
    [InlineData("ORRIN.", "ORRIN.")]
    [InlineData("Where to now?", "Where to now?")]
    [InlineData("ESA is calling.", "ESA is calling.")]
    public void BuyukHarfDuzeni(string input, string expected) => Assert.Equal(expected, CapsNormalizer.Normalize(input));

    [Fact]
    public void BuyukHarfBilinenAd() =>
        Assert.Equal("The rope will snap, Lena.",
            CapsNormalizer.Normalize("THE ROPE WILL SNAP, LENA.", new HashSet<string> { "lena" }));

    [Theory]
    [InlineData("Stop shooting, those are friendlies!", "Stop shooting, those are allies!")]
    [InlineData("Relax, I've got your six now.", "Relax, I've got your back now.")]
    [InlineData("Lena, check your six!", "Lena, watch behind you!")]
    [InlineData("Heads up, the mast is falling!", "Watch out, the mast is falling!")]
    [InlineData("Took you long enough, Lena.", "You're late, Lena.")]
    [InlineData("Get down, we've got company!", "Get down, enemies are coming!")]
    [InlineData("On this raft we're sitting ducks.", "On this raft we're easy targets.")]
    [InlineData("Roger. Moving in on the dock.", "Roger. Going in on the dock.")]
    [InlineData("The friendliest crew on the coast.", "The friendliest crew on the coast.")]
    [InlineData("Six ships, near the reef.", "Six ships, near the reef.")]
    [InlineData("Stand down!", "Stand down!")]
    public void OyunDeyimleri(string input, string expected) => Assert.Equal(expected, GameIdioms.Apply(input));
}

public class GlossaryTests
{
    internal const string SaltCrown = """
        { "game": "Salt Crown",
          "terms": { "Ember Blade": "Kor Kılıcı", "Blade": "Kılıç",
              "Hollowmere": "Hollowmere", "Iron Choir": "Demir Koro" },
          "keep": ["Orrin", "Lena"], }
        """;

    [Fact]
    public void GenelSozlukIziVeIcerik()
    {
        var general = Glossary.General;
        // Boy, iz ve terim sayısı tools/gen-vectors.py'nin bağımsız hesabı (ceviri.md §5.5).
        Assert.Equal(3674, Glossary.GeneralBytes().Length);
        Assert.Equal("gcf7f6091", general.Fingerprint);
        Assert.Equal(27, general.TermCount);
        Assert.Equal("şifa iksiri", general.TurkishOf("Healing Potion"));
        Assert.Equal("kancalı halat", general.TurkishOf("grappling hook"));
        Assert.Equal("hızlı yolculuk", general.TurkishOf("FAST  TRAVEL"));
        Assert.Equal("Raven", general.TurkishOf("raven"));
        Assert.DoesNotContain("healing", general.KeepUpperWords);
        Assert.DoesNotContain("raven", general.KeepUpperWords);
    }

    [Fact]
    public void BosSozlukIzi() => Assert.Equal("g811c9dc5", Glossary.Empty.Fingerprint);

    [Fact]
    public void TerimEklemeKurali()
    {
        var g = Glossary.Parse("""{ "keep": [7], "terms": { "": "y", "Orrin": "Orrin", "--": "x" } }""");
        Assert.Equal(1, g.TermCount);
        Assert.Throws<GlossaryFormatException>(() => Glossary.Parse("[1]"));
        Assert.Throws<GlossaryFormatException>(() => Glossary.Parse("{ not json"));
    }

    [Fact]
    public void TerimBulma()
    {
        var g = Glossary.Parse(SaltCrown);
        Assert.Equal(6, g.TermCount);
        var found = g.FindTerms("DRAW THE EMBER BLADE, then the blade. Orrin's blades. Hollowmerean.");
        Assert.Equal(["Ember Blade", "Blade", "Orrin"], found.Select(m => m.Term.English));
        Assert.Equal(9, found[0].Index);
        Assert.Equal(["blade", "choir", "ember", "hollowmere", "iron", "lena", "orrin"],
            g.KeepUpperWords.Order(StringComparer.Ordinal));
        Assert.Equal("Kor Kılıcı", g.TurkishOf("ember  blade"));
        Assert.Equal("Orrin", g.TurkishOf("ORRIN"));

        var raven = Glossary.General.FindTerms("Raven, you fed the raven. RAVEN!");
        Assert.Single(raven);
        Assert.Equal(0, raven[0].Index);
    }

    [Fact]
    public void SatirlarVeArgo()
    {
        var g = Glossary.Parse("""{ "phrases": { "buff": "strengthen", "(": "x" }, "lines": { "GG!": "İyi oyundu" } }""");
        Assert.Equal("Strengthen the shield", g.FlattenSlang("Buff the shield"));
        Assert.Equal("( a", g.FlattenSlang("( a"));
        Assert.True(g.Rewrites("We buff it."));
        Assert.False(g.Rewrites("Buffed."));
        Assert.Equal("İyi oyundu", g.ReadyLine("gg"));
        Assert.Equal("İyi oyundu!", g.ReadyLine("GG!"));
        Assert.Equal("Seviye atladın!", Glossary.General.ReadyLine("Level up!"));
    }

    [Fact]
    public void IzFarklari()
    {
        Assert.NotEqual(Glossary.Parse("""{"keep":["Raven"]}""").Fingerprint,
            Glossary.Parse("""{"keepExact":["Raven"]}""").Fingerprint);
        var user = Glossary.Parse("""{"terms":{"grappling hook":"kanca ipi"}}""");
        var merged = Glossary.Merge([Glossary.General, user]);
        Assert.NotEqual(Glossary.General.Fingerprint, merged.Fingerprint);
        Assert.Equal(merged.Fingerprint, Glossary.Merge([Glossary.General, user]).Fingerprint);
        Assert.Equal("kanca ipi", merged.TurkishOf("grappling hook"));
    }

    [Fact]
    public void KlasorVeIzleme()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-glossary-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "salt.json"), SaltCrown);
        File.WriteAllText(Path.Combine(dir, "broken.json"), "{ not json");
        File.WriteAllText(Path.Combine(dir, "notes.txt"), """{"keep":["Ignored"]}""");
        var g = new GlossaryFolder(dir).Current;
        Assert.Equal("Kor Kılıcı", g.TurkishOf("Ember Blade"));
        Assert.Equal("şifa iksiri", g.TurkishOf("healing potion"));
        Assert.Null(g.TurkishOf("Ignored"));
        Assert.Equal(Glossary.General.TermCount, new GlossaryFolder(Path.Combine(dir, "yok")).Current.TermCount);
        // Klasör yoksa önbellek anahtarına giren iz genel sözlüğünkiyle aynı kalır (var olan önbellekler geçerli).
        Assert.Equal(Glossary.General.Fingerprint, new GlossaryFolder(Path.Combine(dir, "yok")).Current.Fingerprint);

        var empty = Path.Combine(dir, "watch");
        Directory.CreateDirectory(empty);
        var clock = new TestClock();
        var folder = new GlossaryFolder(empty, clock: clock);
        Assert.Null(folder.Current.TurkishOf("Orrin"));
        File.WriteAllText(Path.Combine(empty, "k.json"), """{"keep":["Orrin"]}""");
        Assert.Null(folder.Current.TurkishOf("Orrin"));
        clock.Advance(TimeSpan.FromSeconds(6));
        Assert.Equal("Orrin", folder.Current.TurkishOf("Orrin"));
    }
}

/// <summary>Elle ilerletilen saat.</summary>
internal sealed class TestClock : TimeProvider
{
    DateTimeOffset _now = new(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);

    public override DateTimeOffset GetUtcNow() => _now;

    public void Advance(TimeSpan by) => _now += by;
}

public class TurkishRulesTests
{
    [Theory]
    [InlineData("Varos", "u", "Varos'u")]
    [InlineData("Varos", "un", "Varos'un")]
    [InlineData("Varos", "a", "Varos'a")]
    [InlineData("Varos", "da", "Varos'ta")]
    [InlineData("Varos", "dan", "Varos'tan")]
    [InlineData("Varos", "la", "Varos'la")]
    [InlineData("Varos", "dur", "Varos'tur")]
    [InlineData("Kaelus", "un", "Kaelus'un")]
    [InlineData("Kaelus", "a", "Kaelus'a")]
    [InlineData("Ostgard", "a", "Ostgard'a")]
    [InlineData("Ostgard", "da", "Ostgard'da")]
    [InlineData("Ostgard", "u", "Ostgard'ı")]
    [InlineData("Ostgard", "un", "Ostgard'ın")]
    [InlineData("Ostgard", "daki", "Ostgard'daki")]
    [InlineData("Sela", "u", "Sela'yı")]
    [InlineData("Sela", "a", "Sela'ya")]
    [InlineData("Sela", "un", "Sela'nın")]
    [InlineData("Sela", "la", "Sela'yla")]
    [InlineData("Sela", "da", "Sela'da")]
    [InlineData("Sela", "nın", "Sela'nın")]
    [InlineData("Edrin", "a", "Edrin'e")]
    [InlineData("Edrin", "u", "Edrin'i")]
    [InlineData("Edrin", "un", "Edrin'in")]
    [InlineData("Edrin", "dan", "Edrin'den")]
    [InlineData("Tork", "da", "Tork'ta")]
    [InlineData("Tork", "u", "Tork'u")]
    [InlineData("Nordemir", "a", "Nordemir'e")]
    [InlineData("Nordemir", "da", "Nordemir'de")]
    [InlineData("Bor", "un", "Bor'un")]
    [InlineData("Mardur", "u", "Mardur'u")]
    [InlineData("Teri", "un", "Teri'nin")]
    [InlineData("Teri", "u", "Teri'yi")]
    [InlineData("Elvin", "a", "Elvin'e")]
    [InlineData("Elvin", "ya", "Elvin'e")]
    [InlineData("Varos", "nın", "Varos'un")]
    [InlineData("Varos", "", "Varos")]
    [InlineData("Kor Kılıcı", "u", "Kor Kılıcı'nı")]
    [InlineData("Kor Kılıcı", "a", "Kor Kılıcı'na")]
    [InlineData("Kor Kılıcı", "da", "Kor Kılıcı'nda")]
    [InlineData("Kor Kılıcı", "dan", "Kor Kılıcı'ndan")]
    [InlineData("Kor Kılıcı", "un", "Kor Kılıcı'nın")]
    [InlineData("Kor Kılıcı", "la", "Kor Kılıcı'yla")]
    [InlineData("Demir Kapısı", "a", "Demir Kapısı'na")]
    [InlineData("Gölge Okları", "u", "Gölge Okları'nı")]
    [InlineData("mana iksiri", "u", "mana iksirini")]
    [InlineData("dinlenme noktası", "a", "dinlenme noktasına")]
    [InlineData("dolum süresi", "da", "dolum süresinde")]
    [InlineData("defter", "a", "deftere")]
    [InlineData("defter", "da", "defterde")]
    [InlineData("kırbaç", "u", "kırbacı")]
    [InlineData("dolap", "u", "dolabı")]
    [InlineData("tüfek", "u", "tüfeği")]
    [InlineData("çelenk", "u", "çelengi")]
    [InlineData("kep", "u", "kepi")]
    [InlineData("kama", "u", "kamayı")]
    [InlineData("kama", "lar", "kamalar")]
    [InlineData("miğfer", "lar", "miğferler")]
    [InlineData("miğfer", "dan", "miğferden")]
    [InlineData("miğfer", "la", "miğferle")]
    [InlineData("HP", "u", "HP'yi")]
    [InlineData("Ostgard", "A", "Ostgard'a")]
    public void EkKurma(string term, string suffix, string expected) =>
        Assert.Equal(expected,
            TurkishSuffix.Attach(term, suffix));

    [Fact]
    public void EgikKesme() => Assert.Equal("Varos’un", TurkishSuffix.Attach("Varos", "un", '’'));

    static Glossary Salt() => Glossary.Parse("""
        { "terms": { "Ember Blade": "Kor Kılıcı",
            "Ostgard": "Ostgard", "mana potion": "mana iksiri" },
          "keep": ["Varos", "Kaelus"] }
        """);

    [Fact]
    public void KorumaVeGeriKoyma()
    {
        const string line = "Varos, carry the Ember Blade into Ostgard. Hurry, Varos!";
        var shield = new TermShield(Salt(), line);
        var p = shield.Protect(line);
        Assert.Equal("Zarmon, carry the Velkor into Dorvan. Hurry, Zarmon!", p.Text);
        Assert.Equal(["Zarmon", "Velkor", "Dorvan"], p.Names);
        Assert.Equal("Varos, Kor Kılıcı'nı Ostgard'a taşı. Acele et, Varos!",
            shield.Restore("Zarmon, Velkor'u Dorvan'a taşı. Acele et, Zarmon!", p.Names, shield.AllNames));
        Assert.Equal("Varos, Kor Kılıcı'nı Ostgard'a TAŞI. ACELE ET, Varos!",
            shield.Restore("ZARMON, VELKOR'U DORVAN'A TAŞI. ACELE ET, ZARMON!", p.Names, shield.AllNames));
        Assert.Equal("Varos, Kor Kılıcı'nı Ostgard'a taşı. Acele et, Varos!",
            shield.Restore("Zarmon, Velkor ’u Dorvana taşı. Acele et, Zarmon!", p.Names, shield.AllNames));

        var taken = new TermShield(Salt(), "Zarmon greeted Varos.");
        Assert.Equal("Zarmon greeted Velkor.", taken.Protect("Zarmon greeted Varos.").Text);

        var plain = new TermShield(Salt(), "The tide is turning.");
        var none = plain.Protect("The tide is turning.");
        Assert.Equal("The tide is turning.", none.Text);
        Assert.Empty(none.Names);
        Assert.Equal("Gelgit dönüyor.", plain.Restore("Gelgit dönüyor.", none.Names, plain.AllNames));
    }

    [Fact]
    public void GecersizGeriKoyma()
    {
        var one = new TermShield(Salt(), "Bring the Ember Blade back to Ostgard.");
        var p = one.Protect("Bring the Ember Blade back to Ostgard.");
        Assert.Null(one.Restore("Kılıcı Dorvan'a geri getir.", p.Names, one.AllNames));

        var two = new TermShield(Salt(), "Varos!", "Sail to Ostgard.");
        two.Protect("Varos!");
        var q = two.Protect("Sail to Ostgard.");
        Assert.Null(two.Restore("Zarmon Velkor'a yelken aç.", q.Names, two.AllNames));
        Assert.Equal("Ostgard'a yelken aç.", two.Restore("Velkor'a yelken aç.", q.Names, two.AllNames));

        var potion = new TermShield(Salt(), "Save the mana potion. Mana potion later!");
        var r = potion.Protect("Save the mana potion. Mana potion later!");
        Assert.Equal("Mana iksirini sakla. Sonra mana iksiri!",
            potion.Restore("Zarmon'u sakla. Sonra Zarmon!", r.Names, potion.AllNames));

        var quote = new TermShield(Salt(), "She whispered 'Ostgard' twice.");
        var s = quote.Protect("She whispered 'Ostgard' twice.");
        Assert.Equal("İki kez 'Ostgard' diye fısıldadı.",
            quote.Restore("İki kez 'Zarmon' diye fısıldadı.", s.Names, quote.AllNames));
    }

    [Theory]
    [InlineData("Jump!", "Atla.", "Atla!")]
    [InlineData("Jump!", "Atla", "Atla!")]
    [InlineData("Who?!", "Kim?", "Kim?!")]
    [InlineData("Listen…", "Dinle.", "Dinle…")]
    [InlineData("Listen...", "Dinle.", "Dinle...")]
    [InlineData("Is the boat ready?", "Tekne hazır mı.", "Tekne hazır mı?")]
    [InlineData("She yelled \"Duck!\"", "\"Eğil.\" diye bağırdı.", "\"Eğil.\" diye bağırdı.")]
    [InlineData("She yelled \"Duck!\"", "\"Eğil\" diye bağırdı", "\"Eğil\" diye bağırdı")]
    [InlineData("\"Duck!\"", "\"Eğil.\"", "\"Eğil!\"")]
    [InlineData("We rest.", "Dinleniyoruz!", "Dinleniyoruz!")]
    [InlineData("We rest.", "Dinleniyoruz", "Dinleniyoruz")]
    [InlineData("Captain!", "Kaptan!", "Kaptan!")]
    [InlineData("Fine. Move.", "Tamam , yürü !", "Tamam, yürü!")]
    [InlineData("Fine. Move.", "Kim  geldi ?", "Kim geldi?")]
    [InlineData("Fine. Move.", "Pekâlâ ... yürüyelim .", "Pekâlâ... yürüyelim.")]
    [InlineData("She said \"hide\", Varos's sister.", "“Saklan” dedi, Varos’un kız kardeşi.", "\"Saklan\" dedi, Varos'un kız kardeşi.")]
    [InlineData("She said “hide”, Varos’s sister.", "\"Saklan\" dedi, Varos'un kız kardeşi.", "“Saklan” dedi, Varos’un kız kardeşi.")]
    public void TurkceDuzeltme(string source, string translation, string expected) =>
        Assert.Equal(expected, TurkishPolish.Polish(source, translation));

    [Fact]
    public void Hitap()
    {
        Assert.Equal(["Seni uyardım.",
            "Dur!", "Sakin ol, kaptan."],
            TurkishPolish.UnifyAddress(["Seni uyardım.", "Durun!", "Sakin olun, kaptan."]));
        Assert.Equal(["Sana güveniyorum. Hemen koş!"], TurkishPolish.UnifyAddress(["Sana güveniyorum. Hemen koşun!"]));
        Assert.Equal(["Saklanın!"], TurkishPolish.UnifyAddress(["Saklanın!"]));
        Assert.Equal(["Siz durun, seni sonra ararım!"],
            TurkishPolish.UnifyAddress(["Siz durun, seni sonra ararım!"]));
        Assert.Equal(["Sen o koşun sonunu gördün mü?"], TurkishPolish.UnifyAddress(["Sen o koşun sonunu gördün mü?"]));
        Assert.Equal(["", "Seni bekledim.", "", "Git!"], TurkishPolish.UnifyAddress(["", "Seni bekledim.", "", "Gidin!"]));
    }

    [Fact]
    public void KisaSatirVeAyrac()
    {
        Assert.True(ShortLineContext.IsShort("Captain!"));
        Assert.True(ShortLineContext.IsShort("Not now, captain."));
        Assert.False(ShortLineContext.IsShort("We sail to the island."));
        Assert.False(ShortLineContext.IsShort("..."));

        const string src = "Not now.";
        Assert.Equal("Şimdi değil.", ShortLineContext.AfterSeparator("Gemi nerede? *** Şimdi değil.", src));
        Assert.Equal("Şimdi değil.", ShortLineContext.AfterSeparator("Gemi nerede?***Şimdi değil.", src));
        Assert.Equal("ŞİMDİ DEĞİL.", ShortLineContext.AfterSeparator("GEMİ NEREDE? *** ŞİMDİ DEĞİL.", src));
        foreach (var bad in new[]
                 {
                     "Gemi nerede? Şimdi değil.", "Gemi *** nerede? *** Şimdi değil.", "Gemi nerede? **** Şimdi değil.",
                     "*** Şimdi değil.", "Gemi nerede? ***",
                     "Gemi nerede? *** Şimdi değil, şimdi değil, şimdi değil, şimdi değil, şimdi değil, şimdi değil, şimdi değil.",
                 })
            Assert.Null(ShortLineContext.AfterSeparator(bad, src));

        var clock = new TestClock();
        var ctx = new ShortLineContext(clock);
        Assert.Null(ctx.ContextFor("Which way is north?"));
        Assert.Equal("Which way is north?", ctx.ContextFor("Not now."));
        clock.Advance(TimeSpan.FromMinutes(5));
        Assert.Equal("Which way is north?", ctx.ContextFor("Not now."));
        Assert.Equal("Not now.", ctx.ContextFor("Go."));
        clock.Advance(TimeSpan.FromSeconds(25));
        Assert.Null(ctx.ContextFor("Later."));
    }

    [Fact]
    public void HedefDiller()
    {
        Assert.Equal(11, TargetLanguages.All.Count);
        Assert.Equal("tr", TargetLanguages.All[0].Code);
        Assert.Equal("Turkish", TargetLanguages.EnglishName("xx"));
        Assert.Equal("Arabic", TargetLanguages.EnglishName("ar-SA"));
        Assert.True(TargetLanguages.IsWrittenInTargetScript("الإعدادات", "ar"));
        Assert.False(TargetLanguages.IsWrittenInTargetScript("Settings", "ar"));
        Assert.False(TargetLanguages.IsWrittenInTargetScript("الإعدادات", "tr"));
        Assert.True(TargetLanguages.IsWrittenInTargetScript("ตั้งค่า", "th"));
        Assert.True(TargetLanguages.IsWrittenInTargetScript("सेटिंग्स", "hi"));
        Assert.True(TargetLanguages.IsWrittenInTargetScript("সেটিংস", "bn"));
        Assert.True(TargetLanguages.IsWrittenInTargetScript("ترتیبات", "ur"));
        Assert.False(TargetLanguages.IsWrittenInTargetScript("Where is the harbor?", "th"));
        var marked = TargetLanguages.ApplyRtlMarks("LENA: أين السفينة؟\nانتظر قليلاً");
        Assert.All(marked.Split('\n'), p => Assert.StartsWith("‏", p));
        Assert.Equal(marked, TargetLanguages.ApplyRtlMarks(marked));
        Assert.Equal("Fırtına geçti.", TargetLanguages.ApplyRtlMarks("Fırtına geçti."));
    }
}
