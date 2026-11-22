// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Library;
using Nino.Core.Tests.Data;
using static Nino.Core.Tests.Compat.CompatFixtures;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// Ortak havuz kuyruğu (<c>pool\</c>: <c>state.json</c>, <c>pending.jsonl</c>, <c>outbox\*.json</c>). Eski
/// uygulamanın bıraktığı kuyruk yeni kodla kaybolmadan sürüyor mu; yeni kodun bıraktığını eski kod okuyabiliyor mu.
/// Kimlikler (kuruluş, oturum, parça) rastgele olduğu için bayt değil değer karşılaştırılır.
/// </summary>
public class PoolCompatTests
{
    sealed class NoNetwork : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new HttpRequestException("ağ yok (test)");
    }

    static void CopyFolder(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var f in Directory.GetFiles(from)) File.Copy(f, Path.Combine(to, Path.GetFileName(f)));
        foreach (var d in Directory.GetDirectories(from)) CopyFolder(d, Path.Combine(to, Path.GetFileName(d)));
    }

    [Fact]
    public void OldQueueContinuesInNewCode()
    {
        using var temp = new TempFolder();
        var folder = temp.File("pool");
        CopyFolder(Old("pool"), folder);
        using var oldState = JsonDocument.Parse(File.ReadAllText(Old("pool", "state.json")));
        var install = oldState.RootElement.GetProperty("install").GetString();

        using var http = new HttpClient(new NoNetwork());
        var q = new LineQueue(new LineQueueOptions(folder, null, "3.5.0", http));
        var st = q.Status;
        Assert.Equal(install, st.InstallId);
        Assert.Equal(1, st.Pending);   // dondurulmamış tek satır
        Assert.Equal(1, st.Outbox);    // gönderilemeyen parça
        Assert.Equal(0, st.Parked);
        Assert.Equal(0, st.Dropped);
        // Sıra numarası eski dondurma sınırından sürer: yeni satır 5 olur.
        Assert.True(q.Add("A brand new line from the new app", "gta6", "sess"));
        var last = File.ReadAllLines(Path.Combine(folder, "pending.jsonl")).Last();
        using var line = JsonDocument.Parse(last);
        Assert.Equal(5, line.RootElement.GetProperty("s").GetInt64());
        q.Close();
        // Parça olduğu gibi duruyor.
        var chunk = Directory.GetFiles(Path.Combine(folder, "outbox")).Single();
        Assert.Equal(File.ReadAllText(Directory.GetFiles(Old("pool", "outbox")).Single()), File.ReadAllText(chunk));
    }

    [Fact]
    public async Task NewQueueIsReadableByOldCode()
    {
        using var temp = new TempFolder();
        var folder = temp.File("pool");
        var clock = new FakeClock(new DateTimeOffset(2026, 11, 22, 10, 0, 0, TimeSpan.Zero));
        var ids = 0;
        using var http = new HttpClient(new NoNetwork());
        var q = new LineQueue(new LineQueueOptions(folder, new Uri("http://127.0.0.1:9/"), "3.5.0", http, Clock: clock,
            Random: () => 0.5, NewId: () => $"00000000-0000-4000-8000-{++ids:000000000000}"));
        Assert.True(q.Add("Get to the boat before they see us", "gta6", "sess-1"));
        Assert.True(q.Add("Say \"hi\" to Lucía 😀 now", null, "sess-1"));
        Assert.True(q.Add("Get to the boat before they see us", "gta6", "sess-1"));
        await q.SendAsync(force: true);
        Assert.True(q.Add("This line stays pending in the queue", "gta6", "sess-1"));
        q.Close();
        Export(folder, "pool");

        // Eski parçayla aynı alanlar ve değerler (kimlikler dışında).
        using var oldChunk = JsonDocument.Parse(File.ReadAllText(Directory.GetFiles(Old("pool", "outbox")).Single()));
        using var newChunk = JsonDocument.Parse(File.ReadAllText(Directory.GetFiles(Path.Combine(folder, "outbox")).Single()));
        static string Shape(JsonElement e) => string.Join(",", e.EnumerateObject().Select(p => p.Name));
        Assert.Equal(Shape(oldChunk.RootElement), Shape(newChunk.RootElement));
        Assert.Equal(Shape(oldChunk.RootElement.GetProperty("lines")[0]), Shape(newChunk.RootElement.GetProperty("lines")[0]));
        foreach (var name in new[] { "v", "app", "platform", "upTo" })
            Assert.Equal(oldChunk.RootElement.GetProperty(name).GetRawText(), newChunk.RootElement.GetProperty(name).GetRawText());
        for (var i = 0; i < 2; i++)
            foreach (var name in new[] { "text", "game", "count", "first", "last" })
                Assert.Equal(Canon(oldChunk.RootElement.GetProperty("lines")[i].GetProperty(name).GetRawText()),
                    newChunk.RootElement.GetProperty("lines")[i].GetProperty(name).GetRawText());
        using var oldState = JsonDocument.Parse(File.ReadAllText(Old("pool", "state.json")));
        using var newState = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder, "state.json")));
        Assert.Equal(Shape(oldState.RootElement), Shape(newState.RootElement));
        var oldPending = JsonDocument.Parse(File.ReadAllLines(Old("pool", "pending.jsonl")).Single()).RootElement;
        var newPending = JsonDocument.Parse(File.ReadAllLines(Path.Combine(folder, "pending.jsonl")).Last()).RootElement;
        Assert.Equal(Shape(oldPending), Shape(newPending));

        // Eski koda okutulan klasör bugünkü yazıcının çıktısı (kimlik, saat, rastgele sabit).
        foreach (var rel in new[] { "state.json", "pending.jsonl" })
            SameBytes(CanonBytes(File.ReadAllBytes(New("pool", rel))), File.ReadAllBytes(Path.Combine(folder, rel)), rel);
        var exported = Directory.GetFiles(New("pool", "outbox")).Single();
        var written = Directory.GetFiles(Path.Combine(folder, "outbox")).Single();
        Assert.Equal(Path.GetFileName(exported), Path.GetFileName(written));
        SameBytes(CanonBytes(File.ReadAllBytes(exported)), File.ReadAllBytes(written), "outbox parçası");

        // Eski kod (deneme programı) bu klasörü açınca gördükleri.
        using var read = JsonDocument.Parse(File.ReadAllText(New("oldread.json")));
        var pool = read.RootElement.GetProperty("pool");
        Assert.Equal("00000000-0000-4000-8000-000000000001", pool.GetProperty("InstallId").GetString());
        Assert.Equal(1, pool.GetProperty("PendingLines").GetInt32());
        Assert.Equal(1, pool.GetProperty("OutboxBatches").GetInt32());
        Assert.Equal(0, pool.GetProperty("ParkedBatches").GetInt32());
    }
}
