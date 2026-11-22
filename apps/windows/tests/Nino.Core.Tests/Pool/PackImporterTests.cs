// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Json;
using Nino.Core.Library;

namespace Nino.Core.Tests.Pool;

public class PackImporterTests
{
    static readonly byte[] Bom = [0xEF, 0xBB, 0xBF];

    static PackImportPreview Json(string json, bool bom = false) =>
        PackImporter.Parse((bom ? Bom : []).Concat(Encoding.UTF8.GetBytes(json)).ToArray(), ".json");

    static Dictionary<string, string> Map(PackImportPreview p) => p.Entries.ToDictionary(e => e.Key, e => e.Value);

    [Fact]
    public void DuzJson()
    {
        var p = PackImporter.Parse(Bom.Concat(Encoding.UTF8.GetBytes(
            """{"You sank the whole fleet, boy!":"  Bu kez bütün filoyu batırdın!  ","...":"x","":"x","Blank":"  ","Number":7}""")).ToArray(),
            ".JSON");
        Assert.Null(p.SuggestedTitle);
        Assert.Equal(new Dictionary<string, string> { ["8d2f9a77e69742ab"] = "Bu kez bütün filoyu batırdın!" }, Map(p));
        Assert.Equal((4, 0, 0), (p.Invalid, p.Duplicates, p.Conflicts));
    }

    [Fact]
    public void AltyaziNesnesi()
    {
        var p = Json("""{"game":"Old","game":"  Test Game  ","title":"Alternate","subtitles":{"Stay Low!":"Alçakta kal!"},"other":"ignored"}""");
        Assert.Equal("Test Game", p.SuggestedTitle);
        Assert.Equal("Alçakta kal!", Map(p)["8632a5b669820abe"]);
        Assert.Equal(0, p.Invalid);
        Assert.Equal("Alternate", Json("""{"game":"  ","title":"Alternate","subtitles":{"Stay Low!":"Alçakta kal!"}}""").SuggestedTitle);
    }

    [Fact]
    public void Bicim1()
    {
        var p = Json("""{"format":2,"format":1.0,"id":"ignored","title":" Harbor Lights ","game":"Alternate","entries":{"0123456789ABCDEF":"Türkçe","0123456789abcdef":"Türkçe","+123456789abcdef":"bad","g123456789abcdef":"bad","fedcba9876543210":null,"9999999999999999":"  ","123":"bad"}}""");
        Assert.Equal("Harbor Lights", p.SuggestedTitle);
        Assert.Equal(new Dictionary<string, string> { ["0123456789abcdef"] = "Türkçe" }, Map(p));
        Assert.Equal((5, 1, 0), (p.Invalid, p.Duplicates, p.Conflicts));
    }

    [Fact]
    public void YinelenenVeCelisen()
    {
        var flat = Json("""{"Stay Low!":"Alçakta kal!","Stay Low!":"Saklan!","Stay Low!":"Saklan!","Who's at the door?":"Kapıdaki kim?","Who's at the door?":"Kapıdaki kim?"}""");
        Assert.Equal(new Dictionary<string, string> { ["1f38ae8099ce80c7"] = "Kapıdaki kim?" }, Map(flat));
        Assert.Equal((0, 2, 1), (flat.Invalid, flat.Duplicates, flat.Conflicts));
        var subs = Json("""{"subtitles":{"Stay Low!":"Alçakta kal!","Stay Low!":"Saklan!","Stay Low!":"Saklan!","Who's at the door?":"Kapıdaki kim?","Who's at the door?":"Kapıdaki kim?"}}""");
        Assert.Equal((0, 2, 1), (subs.Invalid, subs.Duplicates, subs.Conflicts));
        var f1 = Json("""{"format":1,"entries":{"8632a5b669820abe":"Alçakta kal!","8632a5b669820abe":"Saklan!","8632a5b669820abe":"Saklan!","ffffffffffffffff":"Kapıdaki kim?","ffffffffffffffff":"Kapıdaki kim?"}}""");
        Assert.Equal(new Dictionary<string, string> { ["ffffffffffffffff"] = "Kapıdaki kim?" }, Map(f1));
        Assert.Equal((0, 2, 1), (f1.Invalid, f1.Duplicates, f1.Conflicts));
    }

    [Theory]
    [InlineData("""{"format":1,"title":"Harbor Lights","entries":[]}""")]
    [InlineData("""{"format":1,"title":"Harbor Lights","entries":"text"}""")]
    [InlineData("""{"format":1,"title":"Harbor Lights","entries":[true,"Stay Low!","Alçakta kal!"]}""")]
    [InlineData("""{"format":1,"title":"Harbor Lights","subtitles":{"Stay Low!":"Alçakta kal!"}}""")]
    [InlineData("""{"format":2,"title":"Harbor Lights","entries":null}""")]
    [InlineData("""{"format":2,"entries":{"0123456789abcdef":"Türkçe"}}""")]
    [InlineData("""{"format":true,"entries":{"0123456789abcdef":"Türkçe"}}""")]
    [InlineData("""{"oops",1}""")]
    [InlineData("""{"Stay Low!":"\uD800"}""")]
    [InlineData("[1,2]")]
    public void HataliJson(string json) => Assert.Throws<PackImportException>(() => Json(json));

    [Fact]
    public void HataliDosyalar()
    {
        Assert.Equal(PackImportError.UnsupportedFileType,
            Assert.Throws<PackImportException>(() => PackImporter.Parse("a = b"u8.ToArray(), ".csv")).Error);
        Assert.Equal(PackImportError.NotUtf8,
            Assert.Throws<PackImportException>(() => PackImporter.Parse([0xFF], ".json")).Error);
    }

    [Fact]
    public void Txt()
    {
        var text = "  # ignored\r\n\r\nStay Low! = Alçakta kal! = hemen\r\nWho's at the door?\tKapıdaki kim? = bilmem\r\n" +
                   "You sank the whole fleet, boy!\tBu kez bütün filoyu batırdın!\r\nSpare = wrong\tthree\tparts\r\nbroken\r\nEmpty = \r\n\tMissing\r\n";
        var p = PackImporter.Parse(Bom.Concat(Encoding.UTF8.GetBytes(text)).ToArray(), ".txt");
        Assert.Equal(new Dictionary<string, string>
        {
            ["8632a5b669820abe"] = "Alçakta kal! = hemen", ["1f38ae8099ce80c7"] = "Kapıdaki kim? = bilmem",
            ["8d2f9a77e69742ab"] = "Bu kez bütün filoyu batırdın!",
        }, Map(p));
        Assert.Equal(4, p.Invalid);

        var conflict = PackImporter.Parse(Encoding.UTF8.GetBytes(
            "Stay Low! = Alçakta kal!\nstay low = Alçakta kal!\n<b>STAY LOW</b> = Saklan!\nStay low? = Alçakta kal!\nStay low = Eğil!\nWho's at the door? = Kapıdaki kim?\n"), ".txt");
        Assert.Equal(new Dictionary<string, string> { ["1f38ae8099ce80c7"] = "Kapıdaki kim?" }, Map(conflict));
        Assert.Equal((0, 2, 1), (conflict.Invalid, conflict.Duplicates, conflict.Conflicts));
    }

    [Fact]
    public void Srt()
    {
        var blocks = new[]
        {
            "1\r\n00:00:01,250 --> 00:00:03,999\r\n Stay Low! \r\n Alçakta kal! ",
            "2\r\n00:00:04,000 --> 00:00:05,000\r\nOnly one line",
            "3\r\n00:00:04,000 --> 00:00:05,000\r\nOne\r\nTwo\r\nThree",
            "４\r\n00:00:04,000 --> 00:00:05,000\r\nWho's at the door?\r\nKapıdaki kim?",
            "5\r\n00:60:00,000 --> 01:00:00,000\r\nWho's at the door?\r\nKapıdaki kim?",
            "6\r\n00:00:04.000 --> 00:00:05.000\r\nWho's at the door?\r\nKapıdaki kim?",
            "7\r\n00:00:05,000 --> 00:00:04,000\r\nWho's at the door?\r\nKapıdaki kim?",
            "8\r\n00:00:05,000 --> 00:00:05,000\r\nWho's at the door?\r\nKapıdaki kim?",
            "9\r\n00:00:06,000 --> 00:00:07,000\r\nWho's at the door?\r\nKapıdaki kim?",
        };
        var text = string.Join("\r\n \t\r\n", blocks) + "\r\n";
        var p = PackImporter.Parse(Bom.Concat(Encoding.UTF8.GetBytes(text)).ToArray(), ".srt");
        Assert.Equal(new Dictionary<string, string> { ["8632a5b669820abe"] = "Alçakta kal!", ["1f38ae8099ce80c7"] = "Kapıdaki kim?" }, Map(p));
        Assert.Equal(7, p.Invalid);
    }

    [Fact]
    public void Kimlik()
    {
        Assert.Equal("community-my-game-a-a", PackImporter.IdFor(" ../My GAME\\a:a... "));
        Assert.Equal("community-game", PackImporter.IdFor("../遊戲"));
        Assert.Equal("community-" + new string('a', 80), PackImporter.IdFor(new string('a', 300)));
        Assert.Equal("community-" + new string('a', 79), PackImporter.IdFor(new string('a', 79) + " b"));
    }

    [Fact]
    public void YazmaVeDegistirme()
    {
        var folder = PoolTemp.Folder();
        var p = PackImporter.Parse("Stay Low! = Alçakta kal!"u8.ToArray(), ".txt");
        var target = PackImporter.Write(p, " Test Game ", folder, null, replace: false);
        Assert.Equal(Path.Combine(folder, "community-test-game.json"), target);
        var doc = JsonDocument.Parse(File.ReadAllText(target)).RootElement;
        Assert.Equal(["format", "id", "title", "entries"], doc.EnumerateObject().Select(x => x.Name));
        Assert.Equal(1, doc.GetProperty("format").GetInt32());
        Assert.Equal("community-test-game", doc.GetProperty("id").GetString());
        Assert.Equal("Test Game", doc.GetProperty("title").GetString());
        Assert.Equal("Alçakta kal!", doc.GetProperty("entries").GetProperty("8632a5b669820abe").GetString());

        var lib = new PackLibrary(folder);
        Assert.Equal("Test Game", lib.Infos.Single().Title);
        Assert.Equal(1, lib.Infos.Single().EntryCount);
        Assert.Equal("Alçakta kal!", lib.FindExact("Stay Low!"));

        var bytes = File.ReadAllBytes(target);
        var p2 = PackImporter.Parse("Stay Low! = Saklan!"u8.ToArray(), ".txt");
        Assert.Equal(PackImportError.AlreadyExists,
            Assert.Throws<PackImportException>(() => PackImporter.Write(p2, "Test Game", folder, null, false)).Error);
        Assert.Equal(bytes, File.ReadAllBytes(target));
        Assert.Single(Directory.GetFiles(folder));
        PackImporter.Write(p2, "Test Game", folder, null, replace: true);
        lib.Reload();
        Assert.Equal("Saklan!", lib.FindExact("Stay Low!"));
        Assert.Single(Directory.GetFiles(folder));

        Assert.Equal(PackImportError.SourceIsTarget,
            Assert.Throws<PackImportException>(() => PackImporter.Write(p2, "Test Game", folder, target, true)).Error);
        Assert.Equal(PackImportError.MissingTitle,
            Assert.Throws<PackImportException>(() => PackImporter.Write(p2, "  ", folder, null, true)).Error);
        var empty = PackImporter.Parse("broken"u8.ToArray(), ".txt");
        Assert.Equal(PackImportError.NoEntries,
            Assert.Throws<PackImportException>(() => PackImporter.Write(empty, "Other", folder, null, true)).Error);
    }
}
