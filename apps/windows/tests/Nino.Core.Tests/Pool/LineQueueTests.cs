// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.Json;
using Nino.Core.Library;

namespace Nino.Core.Tests.Pool;

public class LineQueueTests
{
    const double T0 = 1_763_300_000;
    static readonly Uri Server = new("http://localhost:8787/");

    sealed class Rig
    {
        public string Folder = PoolTemp.Folder();
        public PoolClock Clock = new(T0);
        public bool Online = true;
        public Func<SeenRequest, HttpResponseMessage?>? Override;
        public FakeServer Fake;
        public List<JsonElement> Received = [];

        public Rig()
        {
            Fake = new FakeServer(r =>
            {
                if (!Online) throw new HttpRequestException("çevrimdışı");
                if (Override?.Invoke(r) is { } custom) return custom;
                return Accept(r);
            });
        }

        public HttpResponseMessage Accept(SeenRequest r)
        {
            var doc = JsonDocument.Parse(r.Body).RootElement.Clone();
            lock (Received) Received.Add(doc);
            return FakeServer.Json($$"""{"ok":true,"batch":"{{doc.GetProperty("batch").GetString()!.ToUpperInvariant()}}"}""");
        }

        public LineQueue Open(Uri? endpoint = null, bool enabled = true, string version = "4.0.0", int chunk = 200,
            string? legacy = null, bool noEndpoint = false) =>
            new(new LineQueueOptions(Folder, noEndpoint ? null : endpoint ?? Server, version, Fake.Client(), enabled,
                legacy, Clock, () => 0.5, null, chunk));

        public IEnumerable<JsonElement> Lines => Received.SelectMany(b => b.GetProperty("lines").EnumerateArray());
    }

    [Fact]
    public async Task SatirDiskteVeZorlaGider()
    {
        var rig = new Rig();
        var q = rig.Open();
        Assert.True(q.Add("Where is Marco heading?", "GTA V", "s1"));
        Assert.True(File.Exists(Path.Combine(rig.Folder, "pending.jsonl")));
        var line = File.ReadAllLines(Path.Combine(rig.Folder, "pending.jsonl"))[0];
        Assert.StartsWith("{\"s\":1,\"t\":\"Where is Marco heading?\",\"g\":\"gta-v\",\"e\":\"s1\",\"a\":", line);
        var q2 = rig.Open();
        Assert.Equal(1, q2.Status.Pending);
        await q2.SendAsync(force: true);
        var sent = rig.Lines.Single();
        Assert.Equal("Where is Marco heading?", sent.GetProperty("text").GetString());
        Assert.Equal("gta-v", sent.GetProperty("game").GetString());
        Assert.Equal("/v1/batches", rig.Fake.Requests[0].Uri.AbsolutePath);
        Assert.Equal("nino-pool/1 (windows; 4.0.0)", rig.Fake.Requests[0].Message.Headers.UserAgent.ToString());
    }

    [Fact]
    public async Task AdresYokkenBekler()
    {
        var rig = new Rig();
        var q = rig.Open(noEndpoint: true);
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        Assert.Empty(rig.Fake.Requests);
        Assert.Equal(1, q.Status.Pending);
        Assert.False(q.Status.HasEndpoint);
        q.SetEndpoint(Server);
        await q.SendAsync(true);
        Assert.Single(rig.Lines);
    }

    [Fact]
    public async Task YarimSatirKesilir()
    {
        var rig = new Rig();
        var q = rig.Open();
        q.Add("First line is here.");
        q.Add("Second line is here.");
        File.AppendAllText(Path.Combine(rig.Folder, "pending.jsonl"), "{\"s\":3,\"t\":\"Half writ");
        var q2 = rig.Open();
        q2.Add("Third line is here.");
        await q2.SendAsync(true);
        Assert.Equal(3, rig.Lines.Count());
    }

    [Fact]
    public async Task CevrimdisiParcaKalir()
    {
        var rig = new Rig { Online = false };
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        Assert.Equal(1, q.Status.Outbox);
        Assert.Equal(0, q.Status.Pending);
        rig.Online = true;
        var q2 = rig.Open();
        await q2.SendAsync();
        Assert.Single(rig.Lines);
        Assert.Equal(0, q2.Status.Outbox);
    }

    [Fact]
    public async Task DondurulmusSiraTekrarGitmez()
    {
        var rig = new Rig { Online = false };
        var q = rig.Open(chunk: 3);
        for (var i = 0; i < 7; i++) q.Add($"Distinct line number {i} here.");
        var pendingCopy = File.ReadAllText(Path.Combine(rig.Folder, "pending.jsonl"));
        await q.SendAsync(true);
        var outbox = Directory.GetFiles(Path.Combine(rig.Folder, "outbox")).Order(StringComparer.Ordinal).ToArray();
        Assert.Equal(3, outbox.Length);
        File.Delete(outbox[1]);
        File.Delete(outbox[2]);
        File.WriteAllText(Path.Combine(rig.Folder, "pending.jsonl"), pendingCopy);
        var statePath = Path.Combine(rig.Folder, "state.json");
        File.WriteAllText(statePath, File.ReadAllText(statePath).Replace("\"frozenThrough\":7", "\"frozenThrough\":0"));
        rig.Online = true;
        var q2 = rig.Open(chunk: 3);
        await q2.SendAsync(true);
        var lines = rig.Lines.ToList();
        Assert.Equal(7, lines.Count);
        Assert.Equal(7, lines.Select(l => l.GetProperty("text").GetString()).Distinct().Count());
        Assert.All(lines, l => Assert.Equal(1, l.GetProperty("count").GetInt32()));
    }

    [Fact]
    public async Task EtkisizKip()
    {
        var rig = new Rig { Online = false };
        var q = rig.Open();
        q.Add("First line is here.");
        await q.SendAsync(true);
        q.Add("Second line is here.");
        var off = rig.Open(enabled: false);
        Assert.False(off.Add("Third line is here."));
        Assert.Equal(1, off.Status.Outbox);
        Assert.Equal(1, off.Status.Pending);
    }

    [Fact]
    public async Task BirlestirmeVeParcaSiniri()
    {
        var rig = new Rig();
        var q = rig.Open(chunk: 3);
        for (var i = 0; i < 4; i++) q.Add("Same line again here.", "GTA V", "one");
        rig.Clock.Advance(10);
        q.Add("Same line again here.", "GTA V", "one");
        for (var i = 0; i < 4; i++) q.Add($"Other line {i} is here.", "GTA V", "one");
        await q.SendAsync(true);
        Assert.Equal([3, 2], rig.Received.Select(b => b.GetProperty("lines").GetArrayLength()));
        var same = rig.Lines.First(l => l.GetProperty("text").GetString() == "Same line again here.");
        Assert.Equal(5, same.GetProperty("count").GetInt32());
        Assert.Equal("gta-v", same.GetProperty("game").GetString());
        Assert.Equal(10, same.GetProperty("last").GetInt64() - same.GetProperty("first").GetInt64());
        Assert.Single(rig.Lines.Select(l => l.GetProperty("session").GetString()).Distinct());
        var batch = rig.Received[0];
        Assert.Equal(["v", "batch", "install", "app", "platform", "lines", "upTo"], batch.EnumerateObject().Select(p => p.Name));
        Assert.Equal("windows", batch.GetProperty("platform").GetString());
    }

    [Fact]
    public async Task TekSatir120SnSonra()
    {
        var rig = new Rig();
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync();
        Assert.Empty(rig.Fake.Requests);
        rig.Clock.Advance(120);
        await q.SendAsync();
        Assert.Single(rig.Lines);
    }

    [Fact]
    public async Task ArtanBekleme()
    {
        var rig = new Rig();
        var fail = true;
        rig.Override = _ => fail ? FakeServer.Status(HttpStatusCode.InternalServerError) : null;
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        Assert.Single(rig.Fake.Requests);
        rig.Clock.Advance(10);
        await q.SendAsync();
        Assert.Single(rig.Fake.Requests);
        rig.Clock.Advance(40);
        await q.SendAsync();
        Assert.Equal(2, rig.Fake.Requests.Count);
        rig.Clock.Advance(40);
        await q.SendAsync();
        Assert.Equal(2, rig.Fake.Requests.Count);
        fail = false;
        rig.Clock.Advance(40);
        await q.SendAsync();
        Assert.Equal(3, rig.Fake.Requests.Count);
        Assert.Equal(0, q.Status.Outbox);
    }

    [Fact]
    public async Task YanitKaybolursaAyniKimlik()
    {
        var rig = new Rig();
        var drop = true;
        rig.Override = r =>
        {
            if (!drop) return null;
            rig.Accept(r);
            throw new HttpRequestException("ağ yok");
        };
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        drop = false;
        await q.NetworkAvailableAsync();
        Assert.Equal(2, rig.Received.Count);
        Assert.Equal(rig.Received[0].GetProperty("batch").GetString(), rig.Received[1].GetProperty("batch").GetString());
    }

    [Fact]
    public async Task KapaliAgPortali()
    {
        var rig = new Rig();
        var portal = true;
        rig.Override = _ => portal ? FakeServer.Json("<html>otel ağı giriş sayfası</html>") : null;
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        Assert.Equal(1, q.Status.Outbox);
        portal = false;
        await q.NetworkAvailableAsync();
        Assert.Single(rig.Lines);
    }

    [Fact]
    public async Task RetryAfter()
    {
        var rig = new Rig();
        var busy = true;
        rig.Override = _ =>
        {
            if (!busy) return null;
            var r = FakeServer.Status(HttpStatusCode.TooManyRequests);
            r.Headers.Add("Retry-After", "600");
            return r;
        };
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        busy = false;
        rig.Clock.Advance(599);
        await q.SendAsync();
        Assert.Single(rig.Fake.Requests);
        rig.Clock.Advance(2);
        await q.SendAsync();
        Assert.Single(rig.Lines);
    }

    [Fact]
    public async Task KabulEdilmeyenKenara()
    {
        var rig = new Rig();
        var reject = true;
        rig.Override = _ => reject ? FakeServer.Status(HttpStatusCode.BadRequest) : null;
        var q = rig.Open();
        q.Add("First line is here.");
        q.Add("Second line is here.");
        await q.SendAsync(true);
        Assert.Equal(0, q.Status.Outbox);
        Assert.Equal(1, q.Status.Parked);
        reject = false;
        var same = rig.Open();
        await same.SendAsync(true);
        Assert.Single(rig.Fake.Requests);
        var updated = rig.Open(version: "0.1.7");
        await updated.SendAsync(true);
        Assert.Equal(2, rig.Lines.Count());
    }

    [Fact]
    public async Task CokBuyukBolunur()
    {
        var rig = new Rig();
        rig.Override = r => JsonDocument.Parse(r.Body).RootElement.GetProperty("lines").GetArrayLength() == 5
            ? FakeServer.Status(HttpStatusCode.RequestEntityTooLarge)
            : null;
        var q = rig.Open();
        for (var i = 0; i < 5; i++) q.Add($"Distinct line number {i} here.");
        await q.SendAsync(true);
        Assert.Equal([2, 3], rig.Received.Select(b => b.GetProperty("lines").GetArrayLength()));
        Assert.Equal(5, rig.Lines.Select(l => l.GetProperty("text").GetString()).Distinct().Count());
    }

    [Fact]
    public async Task BulunamadiKalir()
    {
        var rig = new Rig();
        rig.Override = _ => FakeServer.Status(HttpStatusCode.NotFound);
        var q = rig.Open();
        q.Add("Where is Marco heading?");
        await q.SendAsync(true);
        Assert.Equal(1, q.Status.Outbox);
        Assert.Equal(0, q.Status.Parked);
    }

    [Fact]
    public async Task KapatincaSilinir()
    {
        var rig = new Rig { Online = false };
        var q = rig.Open();
        q.Add("First line is here.");
        await q.SendAsync(true);
        q.Add("Second line is here.");
        q.SetEnabled(false);
        Assert.Equal(0, q.Status.Pending + q.Status.Outbox + q.Status.Parked);
        Assert.False(q.Add("Third line is here."));
    }

    [Fact]
    public void EskiKuyrukIceAktarilir()
    {
        var rig = new Rig();
        var legacy = Path.Combine(rig.Folder, "pool.json");
        File.WriteAllText(legacy,
            """{"install":"x","queue":[{"text":"Earlier line still waiting.","key":"k","firstSeen":"2026-11-11T03:17:00Z"},{"text":"Oturum Açtı","key":"k2","firstSeen":"2026-11-11T03:17:00Z"}],"sent":[]}""");
        var q = rig.Open(legacy: legacy);
        Assert.Equal(1, q.Status.Pending);
        var line = File.ReadAllLines(Path.Combine(rig.Folder, "pending.jsonl")).Single();
        Assert.Contains("\"t\":\"Earlier line still waiting.\"", line);
        Assert.Contains("\"a\":1794367020", line);
        Assert.Contains("\"g\":null", line);
        Assert.False(File.Exists(legacy));
        Assert.True(File.Exists(legacy + ".imported"));
        Assert.Equal(1, rig.Open(legacy: legacy).Status.Pending);
    }

    [Fact]
    public void BozukDurumKenaraAlinir()
    {
        var rig = new Rig();
        File.WriteAllText(Path.Combine(rig.Folder, "state.json"), "{bozuk");
        var q = rig.Open();
        Assert.True(Guid.TryParse(q.InstallId, out _));
        Assert.Single(Directory.GetFiles(rig.Folder, "state.broken-*.json"));
        Assert.Equal(q.InstallId, rig.Open().InstallId);
    }

    [Fact]
    public void Zamanlama()
    {
        Assert.Equal(TimeSpan.FromSeconds(5), LineQueue.DelayBeforeAttempt(0));
        Assert.Equal(TimeSpan.FromMinutes(1), LineQueue.DelayBeforeAttempt(3));
    }
}
