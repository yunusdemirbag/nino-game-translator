// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using Nino.Core.Diagnostics;
using Nino.Core.Library;
using Nino.Core.Reading;
using Nino.Core.Telemetry;
using Nino.Core.Tests.Pool;

namespace Nino.Core.Tests.Library;

/// <summary>Asıl oyun kimliği: tablo, yedek okunur ad, gönderim noktaları, eski imleçler, listede tekilleşme.</summary>
public class GameIdsTests
{
    // ---- Tablo (sunucudakiyle aynı; beklenenler elle yazıldı) ----

    [Theory]
    [InlineData("grand-theft-auto-vi", "gta-6")]
    [InlineData("gta-vi", "gta-6")]
    [InlineData("gta6", "gta-6")]
    [InlineData("gtavi", "gta-6")]
    [InlineData("pool-gta-6", "gta-6")]
    [InlineData("grand-theft-auto-v", "gta-v")]
    [InlineData("gta-5", "gta-v")]
    [InlineData("gta5", "gta-v")]
    [InlineData("gtav", "gta-v")]
    [InlineData("pool-gta-5", "gta-v")]
    [InlineData("pool-gta-v", "gta-v")]
    [InlineData("assassin-s-creed-shadows", "assassins-creed-shadows")]
    [InlineData("marvel-s-spider-man-2", "marvels-spider-man-2")]
    [InlineData("death-stranding-director-s-cut", "death-stranding-directors-cut")]
    [InlineData("death-stranding-2-on-the-beach", "death-stranding-2")]
    [InlineData("farcry6", "far-cry-6")]
    [InlineData("ghost-of-y-tei", "ghost-of-yotei")]
    public void TakmaAd(string alias, string canonical) => Assert.Equal(canonical, GameIds.Canonical(alias));

    [Fact]
    public void TabloBoyu()
    {
        Assert.Equal(17, GameIds.Aliases.Count);
        Assert.Equal(27, GameIds.Names.Count);
    }

    [Theory]
    [InlineData("gta-6", "GTA 6")]
    [InlineData("gta-v", "GTA 5")]
    [InlineData("grand-theft-auto-iv", "GTA 4")]
    [InlineData("gta-iv", "GTA 4")]
    [InlineData("grand-theft-auto-online", "GTA Online")]
    [InlineData("red-dead-redemption-2", "Red Dead Redemption 2")]
    [InlineData("call-of-duty-modern-warfare-2019", "Call of Duty: Modern Warfare (2019)")]
    [InlineData("assassins-creed-shadows", "Assassin's Creed Shadows")]
    [InlineData("assassin-s-creed-mirage", "Assassin's Creed Mirage")]
    [InlineData("mafia-the-old-country", "Mafia: The Old Country")]
    [InlineData("death-stranding-2", "Death Stranding 2")]
    [InlineData("death-stranding-directors-cut", "Death Stranding Director's Cut")]
    [InlineData("elden-ring", "Elden Ring")]
    [InlineData("elden-ring-shadow-of-the-erdtree", "Elden Ring: Shadow of the Erdtree")]
    [InlineData("marvels-spider-man-2", "Marvel's Spider-Man 2")]
    [InlineData("kingdom-come-deliverance-ii", "Kingdom Come: Deliverance II")]
    [InlineData("the-last-of-us-part-ii", "The Last of Us Part II")]
    [InlineData("the-last-of-us-part-ii-remastered", "The Last of Us Part II Remastered")]
    [InlineData("wuchang-fallen-feathers", "Wuchang: Fallen Feathers")]
    [InlineData("far-cry-6", "Far Cry 6")]
    [InlineData("ghost-of-yotei", "Ghost of Yōtei")]
    [InlineData("astro-s-playroom", "Astro's Playroom")]
    [InlineData("final-fantasy.vii-remake", "Final Fantasy VII Remake")]
    [InlineData("ea-sports-fc-26", "EA Sports FC 26")]
    [InlineData("ea-sports-fc-27", "EA Sports FC 27")]
    [InlineData("nba-2k26", "NBA 2K26")]
    [InlineData("007-first-light", "007 First Light")]
    // takma adla da aynı ad
    [InlineData("grand-theft-auto-vi", "GTA 6")]
    [InlineData("farcry6", "Far Cry 6")]
    // tabloda yok: yedek ad (yalnız i–x büyük)
    [InlineData("god-of-war-ragnarok", "God Of War Ragnarok")]
    [InlineData("final-fantasy-xvi", "Final Fantasy Xvi")]
    [InlineData("dragon_quest.iii", "Dragon Quest III")]
    [InlineData("", "")]
    public void OkunurAd(string id, string name) => Assert.Equal(name, GameIds.DisplayName(id));

    // ---- Sadeleştirme ----

    [Theory]
    [InlineData("GTA6", "gta-6")]
    [InlineData("Gta--Vi", "gta-6")]
    [InlineData("grand---theft-auto-vi", "gta-6")]
    [InlineData("POOL-GTA-V", "gta-v")]
    [InlineData("red-dead-redemption-2", "red-dead-redemption-2")]
    [InlineData("Some--New-Game", "some-new-game")]
    public void BuyukHarfVeCiftTire(string id, string canonical) => Assert.Equal(canonical, GameIds.Canonical(id));

    [Fact]
    public void BosKalir()
    {
        Assert.Null(GameIds.Canonical(null));
        Assert.Equal("", GameIds.Canonical(""));
        Assert.Null(GameIds.FromName(null));
        Assert.Null(GameIds.FromName("  ™ "));
    }

    [Theory]
    [InlineData("Grand Theft Auto VI", "gta-6")]
    [InlineData("Grand Theft Auto VI™", "gta-6")]
    [InlineData("GTA VI", "gta-6")]
    [InlineData("GTA 6", "gta-6")]
    [InlineData("gta6", "gta-6")]
    [InlineData("GTA 5", "gta-v")]
    [InlineData("GTA V", "gta-v")]
    [InlineData("Grand Theft Auto V", "gta-v")]
    [InlineData("Ghost of Yōtei", "ghost-of-yotei")]
    [InlineData("Marvel's Spider-Man 2", "marvels-spider-man-2")]
    [InlineData("Death Stranding 2: On the Beach", "death-stranding-2")]
    [InlineData("Red Dead Redemption 2", "red-dead-redemption-2")]
    public void AddanKimlik(string name, string id) => Assert.Equal(id, GameIds.FromName(name));

    [Theory]
    [InlineData("Grand Theft Auto VI", "GTA 6", true)]
    [InlineData("gtavi", "GTA 6", true)]
    [InlineData("pool-gta-6", "Grand Theft Auto VI", true)]
    [InlineData("The Last of Us Part 2", "The Last of Us Part II", true)]
    [InlineData("GTA 5", "GTA 6", false)]
    [InlineData("", "", false)]
    public void AyniOyun(string a, string b, bool same) => Assert.Equal(same, GameIds.Same(a, b));

    [Theory]
    [InlineData("Grand Theft Auto VI", "GTA 6")]
    [InlineData("grand-theft-auto-vi", "GTA 6")]
    [InlineData("some-new-game", "Some New Game")]
    [InlineData("Some New Game", "Some New Game")]
    public void GosterilenAd(string name, string shown) => Assert.Equal(shown, GameIds.ReadableName(name));

    // ---- GTA 6'ya özgü kararlar takma adlarla da ----

    [Theory]
    [InlineData("gtavi")]
    [InlineData("grand-theft-auto-vi")]
    [InlineData("GTA VI")]
    public void Gta6TakmaAdlaTanınır(string name)
    {
        var sense = new GameSense();
        sense.SetScreen(name);
        Assert.False(Nino.Core.Phone.PhoneGame.NoteGta6(sense, running: true));
    }

    [Fact]
    public void Ps5AyniOyunuBildirinceSecimKalir()
    {
        var sense = new GameSense();
        sense.SetUser("gtavi");
        sense.SetPs5(RunningGame.WithName("Grand Theft Auto VI"));
        Assert.Equal("gtavi", sense.User?.Name);
    }

    // ---- Gönderim noktaları: yalnız asıl kimlik ----

    static readonly Uri Server = new("http://localhost:8787/");
    static readonly string[] Aliases = ["grand-theft-auto-vi", "gta-vi", "gtavi", "gta6", "pool-gta-6"];

    static void OnlyCanonical(string text)
    {
        foreach (var a in Aliases) Assert.DoesNotContain("\"" + a + "\"", text);
        foreach (var a in Aliases) Assert.DoesNotContain("game=" + a, text);
    }

    [Fact]
    public async Task HavuzSorusuIndirmeVePing()
    {
        var folder = PoolTemp.Folder();
        var fake = new FakeServer(r => r.Uri.AbsolutePath switch
        {
            "/v1/config" => FakeServer.Json("""{"translate":{"enabled":true},"poolFirst":{"games":["gta-vi"],"langs":["tr"]}}"""),
            "/v1/translate" => FakeServer.Json("""{"ok":true,"game":"grand-theft-auto-vi","translations":[{"text":"Merhaba"}]}"""),
            "/v1/translations" => FakeServer.Json("""{"items":[]}"""),
            _ => FakeServer.Json("{}"),
        });
        var pool = new TranslationPool(new TranslationPoolOptions(folder, Server, "4.0.0", fake.Client(), new PoolClock(1_763_300_000)),
            "tr", sharePool: true);
        Assert.Equal("Merhaba", await pool.AskAsync("Hello there, partner.", [], "Grand Theft Auto VI"));
        await pool.SyncAsync("gtavi", force: true);
        await pool.PingAsync("GTA VI");

        var translate = JsonDocument.Parse(fake.Requests.Single(r => r.Uri.AbsolutePath == "/v1/translate").Body).RootElement;
        Assert.Equal("gta-6", translate.GetProperty("game").GetString());
        Assert.Contains("game=gta-6", fake.Requests.Single(r => r.Uri.AbsolutePath == "/v1/translations").Uri.Query);
        Assert.Contains("game=gta-6", fake.Requests.Single(r => r.Uri.AbsolutePath == "/v1/ping").Uri.Query);
        foreach (var r in fake.Requests) OnlyCanonical(r.Body + " " + r.Uri.Query);

        // Sunucu listesinde yalnız takma ad olsa da (gta-vi) oyun havuz öncelikli sayılır.
        Assert.True(pool.IsPoolFirst("GTA 6"));
        Assert.True(pool.IsPoolFirst("gtavi"));
        // Sunucunun son cevaptaki oyunu (grand-theft-auto-vi → gta-6) da listeyle eşleşir: 10 dk her soru havuz öncelikli.
        Assert.True(pool.IsPoolFirst("Red Dead Redemption 2"));
    }

    [Fact]
    public async Task EskiImlecAnahtarlariBirlesir()
    {
        var folder = PoolTemp.Folder();
        File.WriteAllText(Path.Combine(folder, "translations-tr.json"), """
            {"language":"tr","texts":{},"cursors":{
              "gta6":{"since":500,"after":"","checked":10},
              "grand-theft-auto-vi":{"since":200,"after":"k1","checked":20},
              "red-dead-redemption-2":{"since":7,"after":"","checked":3},
              "":{"since":9,"after":"","checked":4}}}
            """);
        var fake = new FakeServer(r => r.Uri.AbsolutePath == "/v1/config"
            ? FakeServer.Json("""{"translate":{"enabled":true}}""")
            : FakeServer.Json("""{"items":[]}"""));
        var pool = new TranslationPool(new TranslationPoolOptions(folder, Server, "4.0.0", fake.Client(), new PoolClock(1_763_300_000)),
            "tr", sharePool: true);
        await pool.SyncAsync("Grand Theft Auto VI", force: true);

        // Daha geride olan imleç (since 200, after k1) asıl kimlikte sürer.
        var query = fake.Requests.Single(r => r.Uri.AbsolutePath == "/v1/translations").Uri.Query;
        Assert.Equal("?lang=tr&since=200&game=gta-6&after=k1", query);
        var cursors = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder, "translations-tr.json")))
            .RootElement.GetProperty("cursors");
        Assert.Equal(["gta-6", "red-dead-redemption-2", ""], cursors.EnumerateObject().Select(p => p.Name));
    }

    [Fact]
    public async Task SatirKuyruguEskiVeYeniSatirlar()
    {
        var folder = PoolTemp.Folder();
        Directory.CreateDirectory(Path.Combine(folder, "outbox"));
        // Eski sürümün bıraktığı bekleyen satır ve dondurulmuş parça (takma adla).
        File.WriteAllText(Path.Combine(folder, "pending.jsonl"),
            """{"s":1,"t":"Get to the boat before they see us","g":"gtavi","e":"s1","a":1763300000}""" + "\n");
        File.WriteAllText(Path.Combine(folder, "outbox", "001763299000000-0000-aaaaaaaa-0000-4000-8000-000000000001.json"),
            """{"v":1,"batch":"aaaaaaaa-0000-4000-8000-000000000001","install":"5e1f0000-0000-4000-8000-00000000abcd","app":"3.5.0","platform":"windows","lines":[{"text":"Hold the line right there","game":"grand-theft-auto-vi","session":"s0","count":1,"first":1763299000,"last":1763299000},{"text":"No game on this one","game":null,"session":"s0","count":1,"first":1763299000,"last":1763299000}],"upTo":0}""");
        var received = new List<JsonElement>();
        var fake = new FakeServer(r =>
        {
            var doc = JsonDocument.Parse(r.Body).RootElement.Clone();
            lock (received) received.Add(doc);
            return FakeServer.Json($$"""{"ok":true,"batch":"{{doc.GetProperty("batch").GetString()}}"}""");
        });
        var ids = 0;
        var q = new LineQueue(new LineQueueOptions(folder, Server, "4.0.0", fake.Client(), Clock: new PoolClock(1_763_300_100),
            Random: () => 0.5, NewId: () => $"00000000-0000-4000-8000-{++ids:000000000000}"));
        Assert.True(q.Add("Where is Marco heading now?", "Grand Theft Auto VI", "s1"));
        Assert.True(q.Add("Meet me at the docks tonight", "community-grand-theft-auto-vi", "s1"));
        await q.SendAsync(force: true);
        q.Close();

        Assert.Equal(2, received.Count);
        var games = received.SelectMany(b => b.GetProperty("lines").EnumerateArray())
            .Select(l => l.GetProperty("game").ValueKind == JsonValueKind.Null ? null : l.GetProperty("game").GetString()).ToList();
        Assert.Equal(["gta-6", null, "gta-6", "gta-6", "community-grand-theft-auto-vi"], games);
        foreach (var r in fake.Requests) OnlyCanonical(r.Body);
        // Eski parçanın öbür alanları olduğu gibi gider.
        Assert.Equal("3.5.0", received[0].GetProperty("app").GetString());
        Assert.Equal("5e1f0000-0000-4000-8000-00000000abcd", received[0].GetProperty("install").GetString());
    }

    [Fact]
    public void DegismeyenParcaAyniBaytlar()
    {
        var body = System.Text.Encoding.UTF8.GetBytes(
            """{"v":1,"batch":"b","lines":[{"text":"x","game":"gta-6"},{"text":"y","game":null}],"upTo":1}""");
        Assert.Same(body, LineQueue.CanonicalGames(body));
    }

    [Fact]
    public void OlcumVeTeshis()
    {
        Assert.Equal("gta-6", TelemetryText.Game("gta-vi"));
        Assert.Equal("gta-v", TelemetryText.Game("GTA5"));
        Assert.Equal("", TelemetryText.Game("GTA 6"));
        var e = TelemetryEvent.Session(DateTimeOffset.FromUnixTimeSeconds(1_763_300_000), 60, "grand-theft-auto-vi",
            SessionSource.RemotePlay, 3, null);
        Assert.Equal("gta-6", (string)e.Body["game"]!);

        var diag = DiagPayload.Build(DateTimeOffset.FromUnixTimeSeconds(1_763_300_000), "tr.errors", "quota", DiagSeverity.Warn,
            [], new JsonArray(), null, "gtavi", [])!;
        Assert.Equal("gta-6", (string)diag["game"]!);
    }

    // ---- Paketler: aynı oyun tek satır ----

    [Fact]
    public void PaketKimligi()
    {
        Assert.Equal("gta-6", GameIds.ForPack("gta-6", "GTA 6"));
        Assert.Equal("gta-6", GameIds.ForPack("pool-gta-6", "Pool"));
        Assert.Equal("gta-6", GameIds.ForPack("community-grand-theft-auto-vi", "Grand Theft Auto VI"));
        Assert.Equal("gta-6", GameIds.ForPack("community-my-gta", "Grand Theft Auto VI"));
        Assert.Equal("some-game", GameIds.ForPack("community-some-game", "Some Game"));
        Assert.Equal("some-game", GameIds.ForPack("some-game", "Some Game"));
    }

    [Fact]
    public void ListedeTekillesme()
    {
        var rows = GameIds.DistinctPacks([
            new PackInfo("community-grand-theft-auto-vi", "Grand Theft Auto VI", 120),
            new PackInfo("pool-genel", "Genel", 50),
            new PackInfo("gta-6", "Grand Theft Auto VI", 900),
            new PackInfo("red-dead-redemption-2", "Red Dead Redemption 2", 10),
            new PackInfo("pool-gta-6", "GTA 6 havuzu", 300),
            new PackInfo("community-some-game", "Some Game", 4),
            new PackInfo("some-game", "Some Game", 8),
        ]);
        Assert.Equal(["GTA 6", "Genel", "Red Dead Redemption 2", "Some Game"], rows.Select(r => r.Title));
        Assert.Equal([900, 50, 10, 8], rows.Select(r => r.EntryCount));
        Assert.Equal("community-grand-theft-auto-vi", rows[0].Id); // kimlik ve dosya adı değişmez
    }

    [Fact]
    public void OyunSecicideTekSatir()
    {
        var list = GamePicker.Suggestions(null, [("gta-6", "gtavi"), ("x", "Grand Theft Auto VI")], "GTA VI");
        Assert.Single(list, n => GameIds.FromName(n) == "gta-6");
        Assert.Equal("GTA VI", list[0]);
    }
}
