// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;

namespace Nino.Core.Tests.Library;

public class LineKeyTests
{
    [Fact]
    public void OrtakVektorlerBirebirTutar()
    {
        using var doc = LibraryTestFiles.Json("golden-vectors.json");
        var count = 0;
        foreach (var v in doc.RootElement.EnumerateArray())
        {
            var input = v.GetProperty("input").GetString();
            var canon = v.GetProperty("canon").GetString() ?? "";
            var key = v.TryGetProperty("key", out var k) && k.ValueKind == System.Text.Json.JsonValueKind.String
                ? k.GetString()
                : null;
            if (key == "") key = null;
            Assert.Equal(canon, LineKey.Canon(input));
            Assert.Equal(key, LineKey.Compute(input));
            count++;
        }
        Assert.Equal(18, count);
    }

    [Theory]
    [InlineData("a <b> c", "a   c")]
    [InlineData("a < b <i> c", "a < b   c")]
    [InlineData("<<b>>", "< >")]
    public void EtiketSilme(string input, string expected) => Assert.Equal(expected, LineKey.StripTags(input, " "));

    [Fact]
    public void EtiketUzunlukSiniri()
    {
        Assert.Equal(" ", LineKey.StripTags("<" + new string('x', 40) + ">", " "));
        var longer = "<" + new string('x', 41) + ">";
        Assert.Equal(longer, LineKey.StripTags(longer, " "));
    }

    [Fact]
    public void SikAnahtarlarVeSayiCevirme()
    {
        // Beklenenler tools/gen-vectors.py'nin çıktısı (deneme paketlerinin anahtarları).
        Assert.Equal("def865077d435943", LineKey.Compute("Light the beacon!"));
        Assert.Equal("b3849f092374fe09", LineKey.Compute("Who left the door open?"));
        Assert.True(LineKey.TryParse("A2BD858B12CAB17C", out var v));
        Assert.Equal("a2bd858b12cab17c", LineKey.Format(v));
        Assert.Equal(v, LineKey.ComputeValue("RAISE THE DRAWBRIDGE"));
        Assert.False(LineKey.TryParse("a2bd858b12cab17", out _));
        Assert.False(LineKey.TryParse("+2bd858b12cab17c", out _));
    }

    [Fact]
    public void BozukVekilHataVermez()
    {
        Assert.Equal("a b", LineKey.Canon("a\uD800b"));
        Assert.NotNull(LineKey.Compute("x\uDC00"));
    }
}
