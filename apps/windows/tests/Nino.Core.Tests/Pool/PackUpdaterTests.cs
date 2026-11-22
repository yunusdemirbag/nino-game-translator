// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Nino.Core.Library;

namespace Nino.Core.Tests.Pool;

public class PackUpdaterTests
{
    static string Sha(string content) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(content)));

    sealed class Rig
    {
        public string Root = PoolTemp.Folder();
        public string Packs => Path.Combine(Root, "packs");
        public string State => Path.Combine(Root, "packs-remote.json");
        public PoolClock Clock = new(1_793_000_000);
        public Dictionary<string, (long Version, string Content, string Declared)> Remote = new();
        public HashSet<string> Missing = [];
        public string? ListOverride;
        public HttpStatusCode ListStatus = HttpStatusCode.OK;
        public FakeServer Fake;

        public Rig()
        {
            Fake = new FakeServer(r =>
            {
                var path = r.Uri.AbsolutePath;
                if (path == "/v1/packs")
                {
                    if (ListStatus != HttpStatusCode.OK) return FakeServer.Status(ListStatus);
                    return FakeServer.Json(ListOverride ?? "{\"packs\":[" + string.Join(",", Remote.Select(p =>
                        $"{{\"id\":\"{p.Key}\",\"title\":\"{p.Key}\",\"version\":{p.Value.Version},\"sha256\":\"{p.Value.Declared}\"}}")) + "]}");
                }
                var id = path["/v1/packs/".Length..];
                if (Missing.Contains(id) || !Remote.TryGetValue(id, out var pack)) return FakeServer.Status(HttpStatusCode.NotFound);
                return FakeServer.Bytes(Encoding.UTF8.GetBytes(pack.Content));
            });
        }

        public void Serve(string id, long version, string content, string? declared = null) =>
            Remote[id] = (version, content, declared ?? Sha(content));

        public PackUpdater Updater() =>
            new(Packs, State, new Uri("https://packs.example.test/"), Fake.Client(), Clock);

        public string File(string id) => System.IO.File.ReadAllText(Path.Combine(Packs, id + ".json.gz"));

        public int Downloads(string id) => Fake.Requests.Count(r => r.Uri.AbsolutePath == "/v1/packs/" + id);
    }

    [Fact]
    public async Task IndirmeVeSureli()
    {
        var rig = new Rig();
        rig.Serve("gta-6", 1, "one");
        var r = await rig.Updater().RefreshAsync(force: true);
        Assert.Equal(["gta-6"], r.Downloaded);
        Assert.Equal("one", rig.File("gta-6"));
        rig.Serve("gta-6", 2, "two");
        Assert.True((await rig.Updater().RefreshAsync(false)).Skipped);
        rig.Clock.Advance(24 * 3600 + 1);
        Assert.Equal(["gta-6"], (await rig.Updater().RefreshAsync(false)).Downloaded);
        Assert.Equal("two", rig.File("gta-6"));
        var before = rig.Downloads("gta-6");
        await rig.Updater().RefreshAsync(true);
        Assert.Equal(before, rig.Downloads("gta-6"));
        var state = JsonDocument.Parse(System.IO.File.ReadAllText(rig.State)).RootElement;
        Assert.Equal(["checked", "packs"], state.EnumerateObject().Select(p => p.Name));
    }

    [Fact]
    public async Task TasimaBasarisiz()
    {
        var rig = new Rig();
        rig.Serve("gta-6", 1, "one");
        await rig.Updater().RefreshAsync(true);
        rig.Serve("gta-6", 2, "two");
        var locked = rig.Updater();
        locked.MoveFile = (_, _) => throw new IOException("başka süreçte açık");
        var r = await locked.RefreshAsync(true);
        Assert.Empty(r.Downloaded);
        Assert.Equal("one", rig.File("gta-6"));
        Assert.Contains("\"version\":-1", System.IO.File.ReadAllText(rig.State));
        Assert.False(System.IO.File.Exists(Path.Combine(rig.Packs, ".gta-6.download")));
        Assert.Equal(["gta-6"], (await rig.Updater().RefreshAsync(false)).Downloaded);
        Assert.Contains("\"version\":2", System.IO.File.ReadAllText(rig.State));
    }

    [Fact]
    public async Task OzetTutmazsaKurulmaz()
    {
        var rig = new Rig();
        rig.Remote["gta-6"] = (1, "tampered", Sha("good"));
        var r = await rig.Updater().RefreshAsync(true);
        Assert.Empty(r.Downloaded);
        Assert.False(System.IO.File.Exists(Path.Combine(rig.Packs, "gta-6.json.gz")));
        Assert.DoesNotContain("gta-6", System.IO.File.ReadAllText(rig.State));
    }

    [Fact]
    public async Task EksikPaketSonBakisiIlerletmez()
    {
        var rig = new Rig();
        rig.Serve("gta-6", 1, "one");
        await rig.Updater().RefreshAsync(true);
        rig.Clock.Advance(24 * 3600);
        rig.Serve("rdr-2", 1, "red");
        rig.Missing.Add("rdr-2");
        var first = await rig.Updater().RefreshAsync(false);
        Assert.Empty(first.Downloaded);
        var checkedAt = JsonDocument.Parse(System.IO.File.ReadAllText(rig.State)).RootElement.GetProperty("checked").GetDouble();
        Assert.Equal(1_793_000_000, checkedAt);
        rig.Missing.Clear();
        rig.Clock.Advance(60);
        var second = await rig.Updater().RefreshAsync(false, PackUpdater.NewGameMaxAge);
        Assert.False(second.Skipped);
        Assert.Equal(["rdr-2"], second.Downloaded);
        Assert.Equal("one", rig.File("gta-6"));
    }

    [Fact]
    public async Task ListeAlinamadiVeBosListe()
    {
        var rig = new Rig();
        rig.Serve("gta-6", 1, "one");
        await rig.Updater().RefreshAsync(true);
        rig.ListStatus = HttpStatusCode.ServiceUnavailable;
        Assert.True((await rig.Updater().RefreshAsync(true)).ListFailed);
        Assert.Equal("one", rig.File("gta-6"));
        rig.ListStatus = HttpStatusCode.OK;
        foreach (var bad in new[] { "{}", "{\"packs\":null}" })
        {
            rig.ListOverride = bad;
            var r = await rig.Updater().RefreshAsync(true);
            Assert.True(r.ListFailed);
            Assert.Empty(r.Removed);
            Assert.Contains("gta-6", System.IO.File.ReadAllText(rig.State));
        }
        rig.ListOverride = "{\"packs\":[]}";
        var empty = await rig.Updater().RefreshAsync(true);
        Assert.Equal(["gta-6"], empty.Removed);
        Assert.False(System.IO.File.Exists(Path.Combine(rig.Packs, "gta-6.json.gz")));
    }

    [Fact]
    public async Task KullanicininDosyasiVeGecersizKimlik()
    {
        var rig = new Rig();
        Directory.CreateDirectory(rig.Packs);
        System.IO.File.WriteAllText(Path.Combine(rig.Packs, "gta-6.json.gz"), "mine");
        rig.Serve("gta-6", 1, "one");
        rig.Serve("../evil", 1, "evil");
        var r = await rig.Updater().RefreshAsync(true);
        Assert.Empty(r.Downloaded);
        Assert.Equal("mine", rig.File("gta-6"));
        Assert.DoesNotContain(rig.Fake.Requests, q => q.Uri.AbsolutePath.Contains("evil"));
        rig.Updater().DeleteDownloaded();
        Assert.Equal("mine", rig.File("gta-6"));
    }

    [Fact]
    public void AdresVeKimlik()
    {
        Assert.Null(PackUpdater.ResolveAddress(null, ""));
        Assert.Null(PackUpdater.ResolveAddress("ftp://x", null));
        var uri = PackUpdater.ResolveAddress(null, "https://packs.example.test");
        Assert.Equal("packs.example.test", uri!.Host);
        Assert.EndsWith("/", uri.ToString());
        Assert.True(PackUpdater.IsValidId(
            "gta-6"));
        foreach (var bad in new[] { "-gta", "../evil", "GTA" }) Assert.False(PackUpdater.IsValidId(bad));
    }
}
