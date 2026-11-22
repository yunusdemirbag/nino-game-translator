// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.Json;
using Nino.Core.Library;

namespace Nino.Core.Tests.Pool;

public class TranslationPoolTests
{
    const double T0 = 1_763_300_000;
    static readonly Uri Server = new("http://localhost:8787/");

    sealed class Rig
    {
        public string Folder = PoolTemp.Folder();
        public PoolClock Clock = new(T0);
        public string Config = """{"ok":true}""";
        public Func<SeenRequest, Task<HttpResponseMessage>>? Translate;
        public Func<SeenRequest, HttpResponseMessage>? Other;
        public FakeServer Fake;

        public Rig()
        {
            Fake = new FakeServer(async r =>
            {
                var path = r.Uri.AbsolutePath;
                if (path == "/v1/config") return FakeServer.Json(Config);
                if (path == "/v1/translate" && Translate is not null) return await Translate(r);
                if (path == "/v1/translate")
                {
                    var lines = JsonDocument.Parse(r.Body).RootElement.GetProperty("lines").EnumerateArray()
                        .Select(l => "{\"text\":" + JsonSerializer.Serialize(l.GetString() == "Lower the sails." ? "Yelkenleri indir." : "TR " + l.GetString()) + "}");
                    return FakeServer.Json("{\"ok\":true,\"translations\":[" + string.Join(",", lines) + "]}");
                }
                return Other?.Invoke(r) ?? FakeServer.Status(HttpStatusCode.NotFound);
            });
        }

        public TranslationPool Open(string lang = "tr", bool share = true) =>
            new(new TranslationPoolOptions(Folder, Server, "4.0.0", Fake.Client(), Clock), lang, share);

        public List<SeenRequest> Of(string path) => Fake.Requests.Where(r => r.Uri.AbsolutePath == path).ToList();
    }

    static readonly string[] Context = ["a", "Who's on deck?", "Open up!", "Now!", "Says who?"];

    [Fact]
    public async Task TekSoruVeBellek()
    {
        var rig = new Rig();
        var pool = rig.Open();
        Assert.Equal("Yelkenleri indir.", await pool.AskAsync("Lower the sails.", Context, "Red Dead Redemption 2"));
        Assert.Equal("Yelkenleri indir.", await pool.AskAsync("Lower the sails.", Context, "Red Dead Redemption 2"));
        Assert.Single(rig.Of("/v1/translate"));
        Assert.Equal("Yelkenleri indir.", pool.Lookup("lower the SAILS"));
        var body = JsonDocument.Parse(rig.Of("/v1/translate")[0].Body).RootElement;
        Assert.Equal(1, body.GetProperty("v").GetInt32());
        Assert.Equal("windows",
            body.GetProperty("platform").GetString());
        Assert.Equal("tr", body.GetProperty("lang").GetString());
        Assert.Equal("red-dead-redemption-2", body.GetProperty("game").GetString());
        Assert.Equal(["Lower the sails."], body.GetProperty("lines").EnumerateArray().Select(e => e.GetString()));
        Assert.Equal(Context[1..], body.GetProperty("context").EnumerateArray().Select(e => e.GetString()));
        Assert.Equal(["v", "install", "app", "platform", "lang", "game", "lines", "context"],
            body.EnumerateObject().Select(p => p.Name));
    }

    [Fact]
    public async Task AyniSatirAyniAndaTekIstek()
    {
        var rig = new Rig();
        var gate = new TaskCompletionSource();
        rig.Translate = async _ =>
        {
            await gate.Task;
            return FakeServer.Json("""{"ok":true,"translations":[{"text":"Yelkenleri indir.","tier":"instant"}]}""");
        };
        var pool = rig.Open();
        var a = pool.AskAsync("Lower the sails.", [], null);
        var b = pool.AskAsync("Lower the sails.", [], null);
        await Task.Delay(50);
        gate.SetResult();
        Assert.All(await Task.WhenAll(a, b), t => Assert.Equal("Yelkenleri indir.", t));
        Assert.Single(rig.Of("/v1/translate"));
    }

    [Fact]
    public async Task GurultuGonderilmez()
    {
        var rig = new Rig();
        var pool = rig.Open();
        foreach (var noise in new[] { "%%% ### !!!", "1234", "" }) Assert.Null(await pool.AskAsync(noise, [], null));
        Assert.Empty(rig.Of("/v1/translate"));
    }

    [Fact]
    public async Task OrtakHavuzKapali()
    {
        var rig = new Rig();
        var first = rig.Open();
        await first.AskAsync("Lower the sails.", [], null);
        first.Save();
        var pool = rig.Open(share: false);
        Assert.Equal(0, pool.Count);
        Assert.False(pool.Enabled);
        rig.Fake.Requests.Clear();
        Assert.Null(await pool.AskAsync("Shut the hatch now.", [], "Red Dead Redemption 2"));
        Assert.Equal(0, await pool.SyncAsync(null, true));
        await pool.PingAsync(null);
        Assert.DoesNotContain(rig.Fake.Requests, r => r.Uri.AbsolutePath != "/v1/config");
        pool.SetSharePool(true);
        Assert.Equal(1, pool.Count);
        pool.SetSharePool(false);
        Assert.Equal(0, pool.Count);
        Assert.Equal("TR Shut the hatch now.", await pool.AskAsync("Shut the hatch now.", [], "Grand Theft Auto VI"));
        Assert.Equal("gta-6",
            JsonDocument.Parse(rig.Of("/v1/translate").Single().Body).RootElement.GetProperty("game").GetString());
    }

    [Fact]
    public async Task SunucuCeviriyiKapatti()
    {
        var rig = new Rig { Config = """{"ok":true,"translate":{"enabled":false}}""" };
        var pool = rig.Open();
        Assert.Null(await pool.AskAsync("Lower the sails.", [], "Grand Theft Auto VI"));
        Assert.Equal(0, await pool.SyncAsync(null, true));
        Assert.False(pool.Enabled);
        Assert.False(pool.IsPoolFirst(
                "Grand Theft Auto VI"));
        Assert.Single(rig.Of("/v1/config"));
        Assert.Empty(rig.Of("/v1/translate"));
    }

    [Fact]
    public async Task HavuzOnceligi()
    {
        var rig = new Rig();
        var pool = rig.Open();
        foreach (var g in new[] { "Grand Theft Auto VI", "GTA VI", "gta6" }) Assert.True(pool.IsPoolFirst(g), g);
        foreach (var g in new[] { "Grand Theft Auto V", "Red Dead Redemption 2", null }) Assert.False(pool.IsPoolFirst(g), g);

        rig.Config = """{"translate":{"enabled":true},"poolFirst":{"games":["mafia-the-old-country"],"deadlineMs":700}}""";
        await pool.RefreshConfigAsync(true);
        Assert.True(pool.IsPoolFirst(
                "Mafia: The Old Country"));
        Assert.False(pool.IsPoolFirst(
                "Grand Theft Auto VI"));
        Assert.Equal(700, pool.PoolFirst.DeadlineMs);

        var ar = new Rig().Open("ar-SA");
        Assert.False(ar.IsPoolFirst("Grand Theft Auto VI"));
    }

    [Fact]
    public async Task SunucununTanidigiOyun()
    {
        var rig = new Rig();
        var game = "grand-theft-auto-vi";
        rig.Translate = _ => Task.FromResult(FakeServer.Json(
            "{\"ok\":true,\"translations\":[{\"text\":\"x\"}],\"game\":\"" + game + "\"}"));
        var pool = rig.Open();
        await pool.AskAsync("First line is here.", [], "Call of Duty: Modern Warfare");
        Assert.True(pool.IsPoolFirst(null));
        Assert.True(pool.IsPoolFirst(
                "Call of Duty: Modern Warfare"));
        game = "red-dead-redemption-2";
        await pool.AskAsync("Second line is here.", [], null);
        Assert.False(pool.IsPoolFirst(null));
        game = "grand-theft-auto-vi";
        await pool.AskAsync("Third line is here.", [], null);
        Assert.True(pool.IsPoolFirst(null));
        rig.Clock.Advance(601);
        Assert.False(pool.IsPoolFirst(null));
    }

    [Fact]
    public async Task SureliSoru()
    {
        var rig = new Rig { Config = """{"ok":true,"poolFirst":{"deadlineMs":150}}""" };
        var gate = new TaskCompletionSource();
        rig.Translate = async _ =>
        {
            await gate.Task;
            return FakeServer.Json("""{"ok":true,"translations":[{"text":"Yelkenleri indir."}]}""");
        };
        var pool = rig.Open();
        var watch =
            System.Diagnostics.Stopwatch.StartNew();
        Assert.Null(await pool.AskWithDeadlineAsync("Lower the sails.", [], "GTA 6", CancellationToken.None));
        Assert.InRange(watch.ElapsedMilliseconds, 100, 3000);
        var again = pool.AskAsync("Lower the sails.", [], "GTA 6");
        gate.SetResult();
        Assert.Equal("Yelkenleri indir.", await again);
        Assert.Single(rig.Of("/v1/translate"));
        Assert.Equal("Yelkenleri indir.", pool.Lookup("Lower the sails."));
    }

    [Fact]
    public async Task SinirDoluVeHata()
    {
        var rig = new Rig();
        rig.Translate = _ => Task.FromResult(FakeServer.Json("""{"ok":true,"translations":[{"text":null,"limited":"daily_cap"}]}"""));
        var pool = rig.Open();
        Assert.Null(await pool.AskWithDeadlineAsync("Lower the sails.", [], "GTA 6", CancellationToken.None));
        rig.Translate = _ => Task.FromResult(FakeServer.Status(HttpStatusCode.InternalServerError));
        Assert.Null(await pool.AskWithDeadlineAsync("Shut the hatch now.", [], "GTA 6", CancellationToken.None));
    }

    [Fact]
    public async Task CokSatirliSoru()
    {
        var rig = new Rig();
        var pool = rig.Open();
        rig.Translate = _ => Task.FromResult(FakeServer.Json("""{"ok":true,"translations":[{"text":"Bunu zaten gördük"}]}"""));
        await pool.AskAsync("Seen this one before", [], null);
        rig.Translate = null;
        rig.Fake.Requests.Clear();
        var result = await pool.AskManyAsync(
            ["Seen this one before", "Take it to the pier at dawn", "Dont miss the boat", "Take it to the pier at dawn"],
            ["Yo"], "gta-vi", TranslationPool.MultiLineDeadline);
        Assert.Equal<string?>(["Bunu zaten gördük", "TR Take it to the pier at dawn", "TR Dont miss the boat", "TR Take it to the pier at dawn"], result);
        var body = JsonDocument.Parse(rig.Of("/v1/translate").Single().Body).RootElement;
        Assert.Equal(["Take it to the pier at dawn", "Dont miss the boat"], body.GetProperty("lines").EnumerateArray().Select(e => e.GetString()));
        Assert.Equal(["Yo"], body.GetProperty("context").EnumerateArray().Select(e => e.GetString()));
        Assert.Equal("TR Dont miss the boat", await pool.AskAsync("Dont miss the boat", [], null));
        Assert.Single(rig.Of("/v1/translate"));

        var small = new Rig { Config = """{"ok":true,"translate":{"maxLines":2}}""" };
        var p2 = small.Open();
        await p2.AskManyAsync(["First line here now", "Second line here now", "Third line here now"], [], "gta-vi", null);
        Assert.Equal(2, small.Of("/v1/translate").Count);
    }

    [Fact]
    public async Task TopluIndirme()
    {
        var rig = new Rig();
        rig.Other = r =>
        {
            if (r.Uri.AbsolutePath != "/v1/translations") return FakeServer.Status(HttpStatusCode.NotFound);
            return r.Uri.Query.Contains("after=k2")
                ? FakeServer.Json("""{"ok":true,"now":30,"items":[["00000000000000a3","Üç",30,"review"],["bad"],[1,2,3]],"next":null}""")
                : FakeServer.Json("""{"ok":true,"now":30,"items":[["00000000000000a1","Bir",10,"instant"],["00000000000000a2","İki",20,"instant"]],"next":{"since":20,"after":"k2"}}""");
        };
        var pool = rig.Open();
        Assert.Equal(3, await pool.SyncAsync("Ghost of Yōtei", false));
        var pages = rig.Of("/v1/translations");
        Assert.Equal("?lang=tr&since=0&game=ghost-of-yotei", pages[0].Uri.Query);
        Assert.Contains("since=20", pages[1].Uri.Query);
        Assert.Contains("after=k2", pages[1].Uri.Query);
        var file = Path.Combine(rig.Folder, "translations-tr.json");
        Assert.True(File.Exists(file));
        Assert.Contains("\"Üç\"", File.ReadAllText(file));
        Assert.Equal(0, await pool.SyncAsync("Ghost of Yōtei", false));
        Assert.Equal(2, pages.Count);
        rig.Clock.Advance(181);
        await pool.SyncAsync("Ghost of Yōtei", false);
        var third = rig.Of("/v1/translations")[2].Uri.Query;
        Assert.Contains("since=30", third);
        Assert.DoesNotContain("after", third);

        var reopened = rig.Open();
        Assert.Equal(3, reopened.Count);
        var cursorFile = File.ReadAllText(file);
        Assert.Contains("\"since\":", cursorFile);
        var before = rig.Of("/v1/translations").Count;
        rig.Clock.Advance(181);
        await reopened.SyncAsync("Ghost of Yōtei", false);
        Assert.Contains("since=30", rig.Of("/v1/translations")[before].Uri.Query);
    }

    [Fact]
    public async Task DilDegisimi()
    {
        var rig = new Rig();
        rig.Other = r => r.Uri.Query.Contains("lang=ar")
            ? FakeServer.Json("""{"ok":true,"items":[["00000000000000b1","واحد",5]]}""")
            : FakeServer.Json("""{"ok":true,"items":[["00000000000000a1","Bir",10],["00000000000000a2","İki",20]]}""");
        var pool = rig.Open();
        await pool.SyncAsync(null, true);
        Assert.Equal(2, pool.Count);
        pool.SetLanguage("ar-SA");
        Assert.Equal(0, pool.Count);
        Assert.Equal(1, await pool.SyncAsync(null, true));
        Assert.Contains("lang=ar", rig.Of("/v1/translations").Last().Uri.Query);
        await pool.AskAsync("Lower the sails.", [], null);
        Assert.Equal("ar", JsonDocument.Parse(rig.Of("/v1/translate").Last().Body).RootElement.GetProperty("lang").GetString());
        pool.SetLanguage("tr");
        Assert.Equal(2, pool.Count);
        Assert.Null(pool.Lookup("Lower the sails."));
        pool.SetLanguage("ar");
        Assert.Equal(2, pool.Count);
    }

    [Fact]
    public async Task Ping()
    {
        var rig = new Rig();
        rig.Other = _ => FakeServer.Status(HttpStatusCode.OK);
        var pool = rig.Open();
        await
            pool.PingAsync("Red Dead Redemption 2");
        await
            pool.PingAsync("Red Dead Redemption 2");
        var pings = rig.Of("/v1/ping");
        Assert.Single(pings);
        var q = pings[0].Uri.Query;
        Assert.Contains("install=" + pool.InstallId, q);
        Assert.Contains("platform=windows", q);
        Assert.Contains("app=4.0.0", q);
        Assert.Contains("game=red-dead-redemption-2", q);
        Assert.Contains("lang=tr", q);
        rig.Clock.Advance(60);
        await pool.PingAsync(null);
        Assert.Contains("game=&", rig.Of("/v1/ping")[1].Uri.Query);
    }

    [Fact]
    public async Task EkrandanTanima()
    {
        var rig = new Rig();
        var reply = """{"ok":true,"game":"Grand Theft Auto VI","id":"grand-theft-auto-vi","confidence":0.92}""";
        rig.Other = _ => reply == "500" ? FakeServer.Status(HttpStatusCode.InternalServerError) : FakeServer.Json(reply);
        var pool = rig.Open();
        var jpeg = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0xFF, 0xD9 };
        Assert.Equal("GTA 6", // tablodaki oyun okunur adıyla döner
            await pool.IdentifyAsync(jpeg));
        var body = JsonDocument.Parse(rig.Of("/v1/identify")[0].Body).RootElement;
        Assert.Equal(["app", "image", "install", "platform", "v"], body.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal));
        Assert.Equal(Convert.ToBase64String(jpeg), body.GetProperty("image").GetString());
        reply = """{"ok":true,"game":null}""";
        Assert.Null(await
            pool.IdentifyAsync(jpeg));
        reply = "500";
        Assert.Null(await
            pool.IdentifyAsync(jpeg));
        Assert.Null(await pool.IdentifyAsync(new byte[TranslationPool.MaxImageBytes + 1]));
        Assert.Equal(3, rig.Of("/v1/identify").Count);
        var off = rig.Open(share: false);
        Assert.Null(await off.IdentifyAsync(jpeg));
        Assert.Equal(3, rig.Of("/v1/identify").Count);
    }

    [Fact]
    public void KurulumKimligi()
    {
        var rig = new Rig();
        var id = rig.Open().InstallId;
        Assert.True(Guid.TryParse(id, out _));
        Assert.Equal(id, rig.Open().InstallId);
        File.WriteAllText(Path.Combine(rig.Folder, "install"), "bozuk");
        Assert.NotEqual(id, rig.Open().InstallId);
    }

    [Fact]
    public void BaglamListesi()
    {
        var clock = new PoolClock(T0);
        var lines = new PoolContextLines(clock);
        Assert.Empty(lines.Add("One."));
        Assert.Equal(["One."], lines.Add("Two."));
        clock.Advance(31);
        Assert.Empty(lines.Add("Three."));
        Assert.Equal(["Three."], lines.Before("Four."));
        Assert.Equal(["Three."], lines.Add("Four."));
    }

    [Fact]
    public void TanimaZamanlamasi()
    {
        var start = DateTimeOffset.FromUnixTimeSeconds((long)T0);
        var s = new GameIdentifySchedule();
        s.StartSession(start);
        Assert.False(s.Due(start.AddSeconds(7), KnownGameSource.None, true));
        Assert.True(s.Due(start.AddSeconds(8), KnownGameSource.None, true));
        s.Begin(start.AddSeconds(8));
        Assert.False(s.Due(start.AddSeconds(30), KnownGameSource.None, true));
        s.End();
        Assert.False(s.Due(start.AddSeconds(67), KnownGameSource.None, true));
        var at = start.AddSeconds(68);
        for (var i = 1; i < 6; i++, at = at.AddSeconds(60))
        {
            Assert.True(s.Due(at, KnownGameSource.None, true));
            s.Begin(at);
            s.End();
        }
        Assert.False(s.Due(at.AddHours(1), KnownGameSource.None, true));
        Assert.False(s.Due(at, KnownGameSource.Other, true));
        Assert.False(s.Due(at, KnownGameSource.Screen, true));
        Assert.True(s.Due(at.AddMinutes(5), KnownGameSource.Screen, true));
        Assert.False(s.Due(at.AddMinutes(5), KnownGameSource.Screen, false));
    }
}
