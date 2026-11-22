// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Design;

namespace Nino.Core.Tests.Design;

public class DesignTokensTests
{
    private static readonly DesignTokens T = DesignTokens.Default;

    private static double Ratio(string fg, string bg, bool dark) =>
        ColorMath.ContrastRatio(T.Color(fg).Pick(dark), T.Color(bg).Pick(dark));

    [Fact]
    public void ContrastFormula_KnownPairs()
    {
        Assert.Equal(21.0, Math.Round(ColorMath.ContrastRatio("#000000", "#FFFFFF"), 2));
        Assert.Equal(4.48, Math.Round(ColorMath.ContrastRatio("#777777", "#FFFFFF"), 2));
        Assert.Equal(ColorMath.ContrastRatio("#FFFFFF", "#000000"), ColorMath.ContrastRatio("#000000", "#FFFFFF"));
    }

    [Theory]
    [InlineData("#FFFFFF", true)]
    [InlineData("#0a1430", true)]
    [InlineData("FFFFFF", false)]
    [InlineData("#FFF", false)]
    [InlineData("#FFFFFFF", false)]
    [InlineData("#GGGGGG", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void HexParsing(string? hex, bool valid) => Assert.Equal(valid, ColorMath.TryParseHex(hex, out _, out _, out _));

    [Fact]
    public void Header_AndEveryColorValid()
    {
        Assert.Equal("Nino", T.Name);
        Assert.Equal(4, T.Version);
        Assert.Equal("Segoe UI Variable", T.FontFamily["windows"]);
        Assert.Equal(21, T.Colors.Count);
        foreach (var (name, c) in T.Colors)
        {
            Assert.True(ColorMath.TryParseHex(c.Light, out _, out _, out _), name + " light");
            Assert.True(ColorMath.TryParseHex(c.Dark, out _, out _, out _), name + " dark");
        }
    }

    [Fact]
    public void RecipeValues()
    {
        Assert.Equal(new ThemeColor("#EEF3FB", "#050A1A"), T.Color("background"));
        Assert.Equal(new ThemeColor("#0070D1", "#2D8CFF"), T.Color("accent"));
        Assert.Equal(new ThemeColor("#FFFFFF", "#17181B"), T.Color("onDanger"));
        Assert.Equal(15, T.Fonts["body"].Size);
        Assert.Equal(24, T.Space["xl"]);
        Assert.Equal(22, T.Radius["card"]);
        Assert.Equal(1040, T.Size["windowWidth"]);
        Assert.Equal(720, T.Size["windowHeight"]);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ContrastInvariants(bool dark)
    {
        foreach (var bg in new[] { "background", "surface", "surface2" })
            Assert.True(Ratio("textPrimary", bg, dark) >= 7, $"textPrimary/{bg}");
        foreach (var fg in new[] { "textSecondary", "accentText", "success", "warning", "danger" })
            foreach (var bg in new[] { "background", "surface" })
                Assert.True(Ratio(fg, bg, dark) >= 4.5, $"{fg}/{bg}");
        Assert.True(Ratio("textSecondary", "surface2", dark) >= 4.5);
        Assert.True(Ratio("accentText", "accentSoft", dark) >= 4.5);
        foreach (var bg in new[] { "background", "surface", "proSoft" })
            Assert.True(Ratio("pro", bg, dark) >= 4.5, $"pro/{bg}");
        Assert.True(Ratio("danger", "dangerSoft", dark) >= 4.5);
        Assert.True(Ratio("success", "successSoft", dark) >= 4.5);
        Assert.True(Ratio("onAccent", "accent", dark) >= (dark ? 3 : 4.5));
        Assert.True(Ratio("onDanger", "danger", dark) >= 4.5);
    }

    [Fact]
    public void RadiusSet_FontSizes_Weights()
    {
        Assert.Equal(new SortedSet<double> { 6, 10, 14, 22, 999 }, new SortedSet<double>(T.Radius.Values));
        Assert.All(T.Fonts.Values, f => Assert.Contains(f.Size, new double[] { 13, 15, 17, 22, 28 }));
        Assert.All(T.Fonts.Values, f => Assert.Contains(f.Weight, new[] { "regular", "medium", "semibold" }));
        Assert.True(T.Fonts["body"].Size >= 15);
        Assert.True(T.Fonts["caption"].Size >= 12);
    }

    [Fact]
    public void EmbeddedFile_HasNoGlow()
    {
        using var s = typeof(DesignTokens).Assembly.GetManifestResourceStream(DesignTokens.ResourceName)!;
        var json = new StreamReader(s).ReadToEnd();
        Assert.DoesNotContain("glow", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Parse_CaseInsensitive_SkipsUnknown()
    {
        var t = DesignTokens.Parse("""
            { "NAME": "X", "Version": 2, "extra": [1, 2],
              "Color": { "accent": { "LIGHT": "#000000", "dark": "#FFFFFF", "note": "x" } },
              "radius": { "card": 22 } }
            """);
        Assert.Equal("X", t.Name);
        Assert.Equal(2, t.Version);
        Assert.Equal("#FFFFFF", t.Color("ACCENT").Dark);
        Assert.Equal(22, t.Radius["Card"]);
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("{ \"color\": {} }")]
    [InlineData("{ \"color\": { \"accent\": { \"light\": \"#000000\" } } }")]
    [InlineData("{ broken")]
    public void Parse_Broken_Throws(string json) =>
        Assert.ThrowsAny<Exception>(() => DesignTokens.Parse(json));
}
