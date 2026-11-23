// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using Nino.Core.Library;

namespace Nino.Core.Tests.Library;

/// <summary>Testte paket klasörü: verilen dosyalar geçici bir klasöre yazılır.</summary>
internal static class PackFolder
{
    public static string Create(params (string Name, byte[] Bytes)[] files)
    {
        var dir = LibraryTestFiles.TempFolder();
        foreach (var (name, bytes) in files) File.WriteAllBytes(Path.Combine(dir, name), bytes);
        return dir;
    }

    public static PackLibrary Library(params (string Name, byte[] Bytes)[] files) => new(Create(files));

    /// <summary>Biçim 1 paket (sunucunun <c>/v1/packs/&lt;id&gt;</c> biçimi ya da içe aktarılan dosya).</summary>
    public static byte[] Format1(string id, string title, params (string En, string Tr)[] rows) =>
        Encoding.UTF8.GetBytes("{\"format\":1,\"id\":\"" + id + "\",\"title\":\"" + title + "\",\"lang\":\"tr\",\"entries\":{" +
            string.Join(",", rows.Select(r => $"\"{LineKey.Compute(r.En)}\":\"{r.Tr}\"")) + "}}");

    /// <summary>Üreticinin (tools/gen-vectors.py) biçim 2 deneme paketi tek başına.</summary>
    public static PackLibrary Sample() => Library(("lantern-coast.json.gz", LibraryTestFiles.Bytes("pack-sample.json.gz")));
}

public class PackTests
{
    static byte[] Utf8(string s) => Encoding.UTF8.GetBytes(s);

    static string Key(string text) => LineKey.Compute(text)!;

    [Fact]
    public void SariliVeDuzPaketOkunur()
    {
        var wrapped = GamePackReader.Read(LibraryTestFiles.Bytes("pack-wrapped.json.gz"), "pack-wrapped.json.gz");
        Assert.Equal("test-game", wrapped.Id);
        Assert.Equal("Test Game", wrapped.Title);
        Assert.Equal(5, wrapped.Entries.Count);
        // "<b><c>DARK LANTERN</c></b> UNLOCKED" satırının anahtarı (tools/gen-vectors.py).
        LineKey.TryParse("489f15a9c3746361", out var lantern);
        Assert.Equal("KARANLIK FENER AÇILDI", wrapped.Entries[lantern]);

        var bare = GamePackReader.Read(LibraryTestFiles.Bytes("pack-bare.json.gz"), "pack-bare.json.gz");
        Assert.Equal("pack-bare", bare.Id);
        Assert.Equal("pack-bare", bare.Title);
        Assert.Equal(2, bare.Entries.Count);
        LineKey.TryParse("def865077d435943", out var beacon);
        Assert.Equal("İşaret ateşini yak!", bare.Entries[beacon]);
    }

    [Fact]
    public void BozukPaketlerReddedilir()
    {
        var gzip = new byte[] { 0x1f, 0x8b, 0x08, 0x00 }.Concat(Enumerable.Repeat((byte)7, 30)).ToArray();
        foreach (var bytes in new[]
                 {
                     Utf8("not json"), gzip, Utf8("{\"format\":3,\"entries\":{\"0123456789abcdef\":\"x\"}}"),
                     Utf8("{\"bad\":\"x\"}"),
                 })
            Assert.Throws<PackFormatException>(() => GamePackReader.Read(bytes, "x.json"));
    }

    [Fact]
    public void DosyaAdindanAd()
    {
        Assert.Equal("lantern-coast", GamePackReader.NameFromFile("lantern-coast.json.gz"));
        Assert.Equal("x", GamePackReader.NameFromFile("x.json"));
    }

    [Fact]
    public void KutuphaneBirlesimiVeSonrakiDosya()
    {
        var dir = PackFolder.Create(("a.json.gz", LibraryTestFiles.Bytes("pack-bare.json.gz")),
            ("b.json.gz", LibraryTestFiles.Bytes("pack-wrapped.json.gz")), ("c.json.gz", Utf8("bozuk")));
        var lib = new PackLibrary(dir);
        Assert.Equal(["a", "Test Game"], lib.Infos.Select(i => i.Title));
        Assert.Equal([2, 5], lib.Infos.Select(i => i.EntryCount));
        Assert.Equal("Köprüyü kaldır!", lib.FindExact("Raise the drawbridge!"));
        Assert.Equal("İşaret ateşini yak!", lib.FindExact("Light the beacon!"));

        File.WriteAllText(Path.Combine(dir, "test.json"),
            "{\"format\":1,\"id\":\"test-game\",\"title\":\"Test Game 2\",\"entries\":{\"" + Key("Raise the drawbridge!") +
            "\":\"Köprüyü indirme!\"}}");
        File.WriteAllText(Path.Combine(dir, "ignored.JSON"), "{\"" + Key("Raise the drawbridge!") + "\":\"Hayır\"}");
        lib.Reload();
        Assert.Equal(["a", "Test Game 2"], lib.Infos.Select(i => i.Title));
        Assert.Equal("Köprüyü indirme!", lib.FindExact("Raise the drawbridge!"));
        Assert.Null(lib.FindExact("Who left the door open?"));
    }

    [Fact]
    public void InenVeIceAktarilanPaketler()
    {
        // Sunucudan inen (<id>.json.gz, havuz kimliği, fuzzy yok) ve içe aktarılan (community-*.json) aynı klasörde.
        var dir = PackFolder.Create(
            ("pool-lantern-coast.json.gz", PackFolder.Format1("pool-lantern-coast", "Lantern Coast",
                ("Hold the line!", "Hattı tutun!"), ("Who left the lantern on?", "Feneri kim açık bıraktı?"))),
            ("community-lantern-coast.json", PackFolder.Format1("community-lantern-coast", "Lantern Coast",
                ("Hold the line!", "Hattı bırakmayın!"), ("Bring me the map.", "Haritayı getir."))));
        var lib = new PackLibrary(dir);
        Assert.Equal(["community-lantern-coast", "pool-lantern-coast"], lib.Infos.Select(i => i.Id));
        Assert.Equal("Hattı tutun!", lib.Lookup("Hold the line!"));
        Assert.Equal("Haritayı getir.", lib.Lookup("Bring me the map."));

        // Bulanık dizini olmayan pakette tek düzeltme çalışır, Bloom benzerliği çalışmaz.
        Assert.Null(lib.Lookup("Who 1eft the lantern on?"));
        Assert.Equal("Feneri kim açık bıraktı?", lib.Lookup("Who left the lantern on?"));
        Assert.Equal("pool-lantern-coast", lib.ScopeId);
        Assert.Equal("Feneri kim açık bıraktı?", lib.Lookup("Who 1eft the lantern on?"));
        Assert.Null(lib.Lookup("Wh0 1eft the 1antem 0n?"));

        // Elle seçimde aynı oyunun paketlerinden listede sonraki (sunucudan inen) kullanılır.
        lib.SelectGame("LANTERN COAST");
        Assert.Equal("pool-lantern-coast", lib.SelectedPack?.Id);
        Assert.Null(lib.Lookup("Bring me the map."));
        lib.SelectGame(null);

        // Aynı kimlikli kullanıcı dosyası (ad sırasıyla sonra gelir) inen paketi tamamen ezer.
        File.WriteAllBytes(Path.Combine(dir, "zz-mine.json"), PackFolder.Format1("pool-lantern-coast", "Lantern Coast (mine)",
            ("Hold the line!", "Saflarınızı koruyun!")));
        lib.Reload();
        Assert.Equal(["community-lantern-coast", "pool-lantern-coast"], lib.Infos.Select(i => i.Id));
        Assert.Equal("Lantern Coast (mine)", lib.Infos[1].Title);
        Assert.Equal("Saflarınızı koruyun!", lib.Lookup("Hold the line!"));
        Assert.Null(lib.Lookup("Who left the lantern on?"));
    }

    [Theory]
    [InlineData("STAY LOW!!", "Alçakta kal!")]
    [InlineData("  Who's   at the\ndoor?  ", "Kapıdaki kim?")]
    [InlineData("Go away!", null)]
    [InlineData("", null)]
    [InlineData("NORA: The captain is waiting.", "NORA: Kaptan bekliyor.")]
    [InlineData("Tomas: Stay low!", "Tomas: Alçakta kal!")]
    [InlineData("NORA: Go away!", null)]
    [InlineData("NORA: Stay low!\nTOMAS: Who's at the door?", "NORA: Alçakta kal!\nTOMAS: Kapıdaki kim?")]
    [InlineData("- Stay low!\n- Who's at the door?", "- Alçakta kal!\n- Kapıdaki kim?")]
    [InlineData("Stay low!\nWho are they?", null)]
    [InlineData("Saltmarsh Bay\nWho's at the door?", "Kapıdaki kim?")]
    [InlineData("Stay low!\nPhoto Mode • tilt", "Alçakta kal!")]
    [InlineData("Stay low!\nSaltmarsh Bay\nWho's at the door?", "Alçakta kal!\nKapıdaki kim?")]
    [InlineData("Saltmarsh Bay\nCoral Point", null)]
    [InlineData("Stay low!\nwho are they", null)]
    [InlineData("I have to deliver this crate to the harbor tonight• Not that it matters to you\nWho's at the door?", null)]
    [InlineData("NORA: Stay low! Who's at the door?", "NORA: Alçakta kal! Kapıdaki kim?")]
    [InlineData("Stay low! Move away!", "Alçakta kal! Uzaklaş!")]
    [InlineData("Stay low! Who are they?", null)]
    [InlineData("-MARISOL: The captain is waiting.", "- MARISOL: Kaptan bekliyor.")]
    [InlineData("- MARISOL: The captain is waiting.", "- MARISOL: Kaptan bekliyor.")]
    [InlineData("M]: Stay low!", "M]: Alçakta kal!")]
    [InlineData("li NORA: Who's at the door?", "li NORA: Kapıdaki kim?")]
    [InlineData("MARISOL Who's at the door?", "MARISOL Kapıdaki kim?")]
    [InlineData("I warned you: go away!", null)]
    public void ParcaliArama(string screen, string? expected)
    {
        var table = new Dictionary<string, string>
        {
            [Key("Stay Low!")] = "Alçakta kal!", [Key("Who's at the door?")] = "Kapıdaki kim?",
            [Key("The captain is waiting.")] = "Kaptan bekliyor.", [Key("Move away!")] = "Uzaklaş!",
        };
        string? Exact(string t) => LineKey.Compute(t) is { } k && table.TryGetValue(k, out var v) ? v : null;
        Assert.Equal(expected, PackLookup.Lookup(screen, Exact, _ => null));
    }

    [Fact]
    public void TamSatirParcalardanOnceVeBulanikYalnizEksikte()
    {
        var table = new Dictionary<string, string>
        {
            [Key("Stay Low!")] = "Alçakta kal!", [Key("Stay low! Move away!")] = "Alçakta kal ve uzaklaş!",
        };
        string? Exact(string t) => LineKey.Compute(t) is { } k && table.TryGetValue(k, out var v) ? v : null;
        Assert.Equal("Alçakta kal ve uzaklaş!", PackLookup.Lookup("Stay low! Move away!", Exact, _ => null));

        var asked = new List<string>();
        string? Near(string t)
        {
            asked.Add(t);
            return t == "Who'z at the door?" ? "Kapıdaki kim?" : null;
        }
        Assert.Equal("NORA: Alçakta kal! Kapıdaki kim?", PackLookup.Lookup("NORA: Stay low! Who'z at the door?", Exact, Near));
        Assert.DoesNotContain("Stay low!",
            asked);
        Assert.Equal("Alçakta kal!", PackLookup.Lookup("STAY LOW!!", Exact, _ => "x"));
    }

    [Fact]
    public void ElleSecilenOyun()
    {
        var lib = PackFolder.Library(
            ("1.json", PackFolder.Format1("lantern-coast", "Lantern Coast", ("Let's go.", "Gidelim."),
                ("Raise the sails!", "Yelkenleri kaldır!"))),
            ("2.json", PackFolder.Format1("harbor-lights-2", "Harbor Lights II", ("Let's go.", "Haydi yürü."),
                ("Steady, boy.", "Sakin ol evlat."))));
        Assert.Equal("Haydi yürü.", lib.Lookup("Let's go."));

        lib.SelectGame("Deep Sea Story");
        Assert.Null(lib.Lookup("Let's go."));
        Assert.Null(lib.Lookup("Raise the sails!"));
        Assert.Null(lib.Lookup("Raise the sai1s!"));
        Assert.Null(lib.ScopeId);
        Assert.Null(lib.TakeDistinctiveHit());

        lib.SelectGame("LANTERN COAST");
        Assert.Equal("Gidelim.", lib.Lookup("Let's go."));
        Assert.Equal("Yelkenleri kaldır!", lib.Lookup("Raise the sails!"));
        Assert.Equal("Yelkenleri kaldır!", lib.Lookup("Raise the sai1s!"));
        Assert.Null(lib.Lookup("Steady, boy."));
        Assert.Equal("lantern-coast", lib.ScopeId);
        Assert.Equal("lantern-coast", lib.TakeDistinctiveHit()?.Id);

        lib.SelectGame("Harbor Lights 2");
        Assert.Equal("harbor-lights-2", lib.SelectedPack?.Id);
        Assert.Equal("Haydi yürü.", lib.Lookup("Let's go."));

        lib.SelectGame(null);
        Assert.Equal("Sakin ol evlat.", lib.Lookup("Steady, boy."));
    }

    [Fact]
    public void PaketsizCalisir()
    {
        // Uygulamayla gelen paket yok; gömülü kaynaklarda yalnız sözlük ve model listesi kalır.
        var names = typeof(PackLibrary).Assembly.GetManifestResourceNames();
        Assert.DoesNotContain(names, n => n.StartsWith("packs/", StringComparison.Ordinal));
        Assert.Contains("glossary-en-tr.json", names);
        Assert.Contains("ai-models.json", names);

        var empty = LibraryTestFiles.TempFolder();
        foreach (var lib in new[] { new PackLibrary(null), new PackLibrary(empty), new PackLibrary(Path.Combine(empty, "yok")) })
        {
            lib.WarmUp();
            Assert.Empty(lib.Infos);
            Assert.Empty(lib.Packs);
            Assert.Null(lib.FindExact("Raise the drawbridge!"));
            Assert.Null(lib.FindAnyPack("Raise the drawbridge!"));
            Assert.Null(lib.FindNearest("Raise the drawbridge!"));
            Assert.Null(lib.Lookup("Raise the drawbridge!"));
            Assert.Null(lib.Lookup("MARISOL: Raise the drawbridge!\nWho left the door open?"));
            Assert.Null(lib.ScopeId);
            Assert.Null(lib.ScopeTitle);
            Assert.Null(lib.TakeDistinctiveHit());
            Assert.Null(lib.PackForGame("Lantern Coast"));
            lib.SelectGame("Lantern Coast");
            Assert.Null(lib.SelectedPack);
            Assert.Null(lib.Lookup("Raise the drawbridge!"));
            lib.SelectGame(null);
            lib.Reload();
            Assert.Empty(lib.Infos);

            var lookup = new SubtitleLookup(lib, null);
            var on = new LookupState("en", "tr", GamePacks: true, SharePool: true, PoolFirst: false);
            Assert.Null(lookup.Find("Raise the drawbridge!", on));
            Assert.True(lookup.ShouldSuggest("Raise the drawbridge!", on));
            Assert.True(lookup.ShouldSuggest("Raise the drawbridge!", on with { GamePacks = false }));
        }

        // Paket sonradan inince (yeniden yükleme) kullanılır.
        var later = new PackLibrary(empty);
        Assert.Null(later.Lookup("Raise the drawbridge!"));
        File.WriteAllBytes(Path.Combine(empty, "pool-test-game.json.gz"), LibraryTestFiles.Bytes("pack-wrapped.json.gz"));
        later.Reload();
        Assert.Equal("Köprüyü kaldır!", later.Lookup("Raise the drawbridge!"));
        Assert.Equal("test-game", later.TakeDistinctiveHit()?.Id);
    }

    [Fact]
    public void OrnekPaketTamVeBulanik()
    {
        var lib = PackFolder.Sample();
        var pack = lib.Packs.Single();
        Assert.Equal("lantern-coast", pack.Id);
        Assert.Equal(55, pack.Entries.Count);
        Assert.Equal(4, pack.Segments.Count);
        Assert.Equal(59, pack.SortedKeys.Count);
        Assert.Equal(53, pack.Fuzzy!.Count);
        Assert.True(pack.ContainsKey(LineKey.ComputeValue("Untranslated sailor chatter in the background.")!.Value));

        var damaged = "The lighthouse keeper sald the st0rm wouId pass beföre the mornlng tide.";
        Assert.Null(lib.Lookup(damaged));
        Assert.Null(lib.ScopeId);
        Assert.Null(lib.ScopeTitle);
        Assert.Null(lib.Lookup("Untranslated sailor chatter in the background."));
        Assert.Equal("Buon viaggio.", lib.Lookup("Buon viaggio."));
        Assert.Equal("Feneri yak, çabuk.", lib.Lookup("Light the lantern, quickly."));
        Assert.Equal("lantern-coast", lib.ScopeId);
        Assert.Equal("Lantern Coast", lib.ScopeTitle);
        Assert.Equal("lantern-coast", lib.TakeDistinctiveHit()?.Id);
        Assert.Null(lib.TakeDistinctiveHit());
        // Aynı anahtar hem entries'te hem segments'te: tam satır kazanır.
        Assert.Equal("Hattı tutun!", lib.Lookup("Hold the line!"));
        Assert.Equal("MARISOL: Hattı tutun!", lib.Lookup("MARISOL: Hold the line!"));
        Assert.Equal("Hattı tutun!\nHaritayı bana getir.", lib.Lookup("Hold the line!\nBring me the map."));
        var clean = lib.Lookup("The lighthouse keeper said the storm would pass before the morning tide.");
        Assert.Equal("Fener bekçisi fırtınanın sabah gelgitinden önce geçeceğini söyledi.", clean);
        Assert.Equal(clean, lib.Lookup(damaged));
    }

    [Fact]
    public void OrtakEslesmeVakalari()
    {
        // pack-matches.json ve pack-sample.json.gz tools/gen-vectors.py ile üretildi: beklenen sonuçları C# kodundan
        // bağımsız bir Python başvuru uygulaması hesapladı.
        using var doc = LibraryTestFiles.Json("pack-matches.json");
        var root = doc.RootElement;
        var lib = PackFolder.Library(("sample.json.gz", LibraryTestFiles.Bytes(root.GetProperty("pack").GetString()!)));
        Assert.NotNull(lib.Lookup(root.GetProperty("warmUp").GetString()!));
        var failures = new List<string>();
        var count = 0;
        foreach (var c in root.GetProperty("cases").EnumerateArray())
        {
            var screen = c.GetProperty("screen").GetString()!;
            var expected = c.GetProperty("turkish").ValueKind == System.Text.Json.JsonValueKind.Null
                ? null
                : c.GetProperty("turkish").GetString();
            var actual = lib.Lookup(screen);
            if (actual != expected) failures.Add($"{screen} → {actual ?? "null"} (beklenen {expected ?? "null"})");
            count++;
        }
        Assert.True(count >= 50);
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void YanYanaIkiAltyaziYarimCevrilmez()
    {
        var lib = PackFolder.Sample();
        Assert.NotNull(lib.Lookup("Light the lantern, quickly."));
        foreach (var (first, second) in new[]
                 {
                     ("Somebody cut the ropes on purpose.", " Tell the crew we leave at sunrise."),
                     ("Watch your step, the planks are rotten.", " I've never seen the sea this calm."),
                     ("The storm took three boats last winter.", " Your brother owes me ten silver coins."),
                 })
        {
            var alone = lib.Lookup(first);
            Assert.NotNull(alone);
            var both = lib.Lookup(first + second);
            if (both is not null)
            {
                Assert.NotEqual(alone, both);
                Assert.StartsWith(alone!, both);
            }
        }
    }
}

public class SubtitleLookupTests
{
    [Fact]
    public void PaketVeHavuzBakisi()
    {
        var lib = PackFolder.Library(("b.json.gz", LibraryTestFiles.Bytes("pack-wrapped.json.gz")));
        var lookup = new SubtitleLookup(lib, null);
        var on = new LookupState("en", "tr", GamePacks: true, SharePool: true, PoolFirst: false);
        Assert.Equal(("Köprüyü kaldır!", true), lookup.Find("Raise the drawbridge!", on));
        Assert.Null(lookup.Find("Raise the drawbridge!", on with { Target = "fr" }));
        // Kütüphane hedef dilin klasörünü okur; Arapça da paketli dildir.
        Assert.Equal(("Köprüyü kaldır!", true), lookup.Find("Raise the drawbridge!", on with { Target = "ar" }));
        // Havuz öncelikli oyunda havuz yoksa paket yerelde yine bulunur.
        Assert.Equal(("Köprüyü kaldır!", true), lookup.Find("Raise the drawbridge!", on with { PoolFirst = true }));
        Assert.Null(lookup.Find("Raise the drawbridge!", on with { Source = "de" }));
        Assert.Null(lookup.Find("Raise the drawbridge!", on with { GamePacks = false }));

        var off = on with { GamePacks = false };
        Assert.False(lookup.ShouldSuggest("Raise the drawbridge!", off));
        Assert.True(lookup.ShouldSuggest("Mind the cannon.", off));
        Assert.True(lookup.ShouldSuggest("Raise the drawbridge!", on));
        Assert.False(lookup.ShouldSuggest("Mind the cannon.", on with { Source = "de" }));
    }
}
