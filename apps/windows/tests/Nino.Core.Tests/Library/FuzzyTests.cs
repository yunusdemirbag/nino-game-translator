// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Library;

namespace Nino.Core.Tests.Library;

public class FuzzyTests
{
    [Fact]
    public void ImzaVektorleri()
    {
        using var doc = LibraryTestFiles.Json("fuzzy-vectors.json");
        var n = 0;
        foreach (var v in doc.RootElement.GetProperty("signatures").EnumerateArray())
        {
            var input = v.GetProperty("input").GetString()!;
            var folded = FuzzySignature.Fold(input);
            Assert.Equal(v.GetProperty("folded").GetString(), FuzzySignature.ToText(folded));
            Assert.Equal(v.GetProperty("damaged").GetBoolean(), FuzzySignature.LooksDamaged(input));
            var sig = FuzzySignature.Signature(input);
            if (v.GetProperty("length").ValueKind == JsonValueKind.Null)
            {
                Assert.Null(sig);
            }
            else
            {
                Assert.NotNull(sig);
                Assert.Equal(v.GetProperty("length").GetInt32(), sig!.Value.Length);
                Assert.Equal(v.GetProperty("bits").GetInt32(), sig.Value.Bits);
                Assert.Equal(v.GetProperty("bloom").GetString(),
                    Convert.ToHexStringLower(FuzzySignature.ToBytes(sig.Value.Words)));
            }
            n++;
        }
        Assert.True(n >= 14);
    }

    [Fact]
    public void BenzerlikVektorleri()
    {
        using var doc = LibraryTestFiles.Json("fuzzy-vectors.json");
        foreach (var v in doc.RootElement.GetProperty("similarities").EnumerateArray())
        {
            var bits = v.GetProperty("bits").GetInt32();
            var q = FuzzySignature.Bloom(FuzzySignature.Trigrams(FuzzySignature.Fold(v.GetProperty("query").GetString()!)), bits);
            var e = FuzzySignature.Bloom(FuzzySignature.Trigrams(FuzzySignature.Fold(v.GetProperty("entry").GetString()!)), bits);
            Assert.Equal(v.GetProperty("similarity").GetDouble(), FuzzySignature.Similarity(q, e), 9);
        }
    }

    [Fact]
    public void BozukEtiketVektorleri()
    {
        using var doc = LibraryTestFiles.Json("fuzzy-vectors.json");
        foreach (var v in doc.RootElement.GetProperty("looseLabels").EnumerateArray())
        {
            var result = PackLookup.LooseLabel(v.GetProperty("input").GetString()!);
            var label = v.GetProperty("label");
            if (label.ValueKind == JsonValueKind.Null) Assert.Null(result);
            else
            {
                Assert.NotNull(result);
                Assert.Equal(label.GetString(), result!.Value.Label);
                Assert.Equal(v.GetProperty("body").GetString(), result.Value.Body);
            }
        }
    }

    [Fact]
    public void EsikVektorleri()
    {
        using var doc = LibraryTestFiles.Json("fuzzy-vectors.json");
        var t = doc.RootElement.GetProperty("thresholds");
        foreach (var (name, damaged) in new[] { ("clean", false), ("damaged", true) })
        {
            var previous = 0;
            foreach (var row in t.GetProperty(name).EnumerateArray())
            {
                var below = row[0].GetInt32();
                var value = row[1].GetDouble();
                Assert.Equal(value, FuzzySignature.Threshold(below - 1, damaged));
                Assert.Equal(value, FuzzySignature.Threshold(previous, damaged));
                previous = below;
            }
        }
        Assert.Equal(FuzzySignature.Margin, t.GetProperty("margin").GetDouble());
        Assert.Equal(FuzzySignature.MinLength, t.GetProperty("minLength").GetInt32());
    }

    [Fact]
    public void YanCumleBolme()
    {
        Assert.Equal(["Harbor Gate Hmm.", "Boat's late.",
            "Call me later,", "fine? Bye, Kid."],
            FuzzyClauses.Split("Harbor Gate Hmm. Boat's late. Call me later, fine? Bye, Kid."));
        Assert.Equal(["to sail...", "if the tide allows.",
            "You heard right. bt right."],
            FuzzyClauses.Split("to sail... if the tide allows. You heard right. bt right."));
    }

    [Theory]
    [InlineData("San Andreas", true)]
    [InlineData("Photo Mode • tilt", true)]
    [InlineData("Coral Point", true)]
    [InlineData("LOSNN", true)]
    [InlineData("Hold still,", false)]
    [InlineData("Hey, Marco!", false)]
    [InlineData("I have to deliver this crate to the harbor tonight• Not that it matters to you", false)]
    public void KoseYazisi(string line, bool expected) => Assert.Equal(expected, PackLookup.IsCornerText(line));

    [Theory]
    [InlineData("Grand Theft Auto VI", "gta 6")]
    [InlineData("GTA6", "gta 6")]
    [InlineData("ELDEN RING", "elden ring")]
    [InlineData("The Witcher 3", "witcher 3")]
    [InlineData("Ghost of Tsushima™ Director's Cut", "ghost of tsushima directors cut")]
    [InlineData("Call of Duty: Modern Warfare", "cod modern warfare")]
    [InlineData("EA SPORTS FC 25", "fc 25")]
    [InlineData("", "")]
    public void OyunAdiAnahtari(string name, string key) => Assert.Equal(key, GameNames.Key(name));

    [Theory]
    [InlineData("GTA V", "gta-v")]
    [InlineData("Mafia: The Old Country", "mafia-the-old-country")]
    [InlineData("mafia--the-old-country", "mafia-the-old-country")]
    [InlineData("Marvel's   Spider-Man 2", "marvel-s-spider-man-2")]
    [InlineData("  Death Stranding 2: On the Beach?! ", "death-stranding-2-on-the-beach")]
    [InlineData("Ghost of Yōtei", "ghost-of-y-tei")]
    [InlineData("  ", null)]
    public void OyunKimligi(string name, string? slug) => Assert.Equal(slug, GameNames.Slug(name));
}
