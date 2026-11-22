// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Nino.Core.Library;
using Nino.Core.Tests.Data;
using static Nino.Core.Tests.Compat.CompatFixtures;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// Çeviri havuzundan inenler (<c>pool-translations\translations-&lt;dil&gt;.json</c>, <c>install</c>) ve eski satır
/// havuzu kuyruğunun (<c>pool.json</c>) yeni kuyruğa bir kezlik aktarımı. Fikstürler: eski kodun aynı sahte sunucu
/// cevabıyla yazdığı dosyalar.
/// </summary>
public class PoolTranslationsCompatTests
{
    static readonly string[] Lines = ["Get down!", "Hold the gate, Lucía", "Say \"hi\" to the <crew> & go 😀"];
    static readonly string[] Turkish = ["Yere yat!", "Kapıyı tut, Lucía", "Ekibe \"selam\" de <x> & çık 😀 ğüşıöç"];

    /// <summary>Eski kahinin kullandığı sahte sunucunun aynısı (anahtarlar eski kodun hesapladığı).</summary>
    sealed class FakeServer(string[] keys) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var path = request.RequestUri!.AbsolutePath;
            string body;
            if (path.EndsWith("/v1/config", StringComparison.Ordinal))
                body = "{\"ok\":true,\"translate\":{\"enabled\":true,\"deadlineMs\":900,\"syncSeconds\":180},\"downloads\":3439}";
            else if (path.EndsWith("/v1/translations", StringComparison.Ordinal))
                body = new JsonObject
                {
                    ["items"] = new JsonArray([.. keys.Select((k, i) => (JsonNode)new JsonArray(k, Turkish[i], 1795341600000 + i, "approved"))]),
                }.ToJsonString();
            else return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        }
    }

    static string[] OldKeys()
    {
        using var probe = JsonDocument.Parse(OldText("pool-translations.oldprobe.json"));
        return [.. probe.RootElement.GetProperty("keys").EnumerateArray().Select(k => k.GetString()!)];
    }

    [Fact]
    public void KeysMatchOldKeys()
    {
        var keys = OldKeys();
        for (var i = 0; i < Lines.Length; i++)
            Assert.Equal(keys[i], LineKey.Compute(PoolFilter.Clean(Lines[i])));
    }

    [Fact]
    public void OldDownloadsReadInNewPool()
    {
        using var temp = new TempFolder();
        var folder = temp.File("pool-translations");
        Directory.CreateDirectory(folder);
        foreach (var f in Directory.GetFiles(Old("pool-translations"))) File.Copy(f, Path.Combine(folder, Path.GetFileName(f)));
        using var http = new HttpClient(new FakeServer(OldKeys()));
        var pool = new TranslationPool(new TranslationPoolOptions(folder, null, "3.5.0", http), "tr-TR", sharePool: true);
        Assert.Equal(3, pool.Count);
        for (var i = 0; i < Lines.Length; i++) Assert.Equal(Turkish[i], pool.Lookup(Lines[i]));
        Assert.Equal("5e1f0000-0000-4000-8000-00000000abcd", pool.InstallId);
    }

    [Fact]
    public async Task NewDownloadWritesOldBytes()
    {
        using var temp = new TempFolder();
        var folder = temp.File("pool-translations");
        var clock = new FakeClock(new DateTimeOffset(2026, 11, 22, 10, 0, 0, TimeSpan.Zero));
        using var http = new HttpClient(new FakeServer(OldKeys()));
        var pool = new TranslationPool(new TranslationPoolOptions(folder, new Uri("http://127.0.0.1:9/"), "3.5.0", http, clock), "tr",
            sharePool: true);
        Assert.Equal(3, await pool.SyncAsync("gta6", force: true));
        pool.Save();
        SameBytes(CanonBytes(OldBytes("pool-translations", "translations-tr.json")), File.ReadAllBytes(Path.Combine(folder, "translations-tr.json")),
            "translations-tr.json");
        File.WriteAllText(Path.Combine(folder, "install"), "5e1f0000-0000-4000-8000-00000000abcd");
        Export(folder, "pool-translations");

        // Eski kod yeni dosyayı okuyunca (deneme programı) aynı çevirileri buluyor.
        using var read = JsonDocument.Parse(File.ReadAllText(New("oldread.json")));
        var seen = read.RootElement.GetProperty("pool-translations");
        Assert.Equal(3, seen.GetProperty("Count").GetInt32());
        Assert.Equal("5e1f0000-0000-4000-8000-00000000abcd", seen.GetProperty("Install").GetString());
        for (var i = 0; i < Lines.Length; i++) Assert.Equal(Turkish[i], seen.GetProperty(Lines[i]).GetString());
    }

    [Fact]
    public void LegacyLineQueueImportsLikeOld()
    {
        using var temp = new TempFolder();
        var legacy = temp.File("pool.json");
        File.Copy(Old("pool.json"), legacy);
        using var http = new HttpClient(new FakeServer([]));
        var q = new LineQueue(new LineQueueOptions(temp.File("pool"), null, "3.5.0", http, LegacyQueueFile: legacy,
            Clock: new FakeClock(new DateTimeOffset(2026, 11, 22, 10, 0, 0, TimeSpan.Zero))));
        using var expected = JsonDocument.Parse(OldText("pool-json-import.oldread.json"));
        Assert.Equal(expected.RootElement.GetProperty("PendingLines").GetInt32(), q.Status.Pending);
        var texts = File.ReadAllLines(temp.File("pool", "pending.jsonl")).Select(l => JsonDocument.Parse(l).RootElement.GetProperty("t").GetString());
        Assert.Equal(expected.RootElement.GetProperty("Texts").EnumerateArray().Select(t => t.GetString()), texts);
        Assert.Equal(expected.RootElement.GetProperty("ImportedRenamed").GetBoolean(), File.Exists(legacy + ".imported"));
        Assert.Equal(expected.RootElement.GetProperty("OriginalGone").GetBoolean(), !File.Exists(legacy));
        q.Close();
    }
}
