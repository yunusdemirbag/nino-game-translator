// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Json;
using Nino.Core.Settings;
using Nino.Core.Text;

namespace Nino.Core.Tests.Text;

public class TextCatalogTests
{
    private static Dictionary<string, string> Raw(string language)
    {
        using var s = typeof(TextCatalog).Assembly.GetManifestResourceStream($"text/{language}.json")
            ?? throw new InvalidOperationException("katalog yok: " + language);
        return JsonSerializer.Deserialize<Dictionary<string, string>>(s)!;
    }

    public static TheoryData<string> Languages()
    {
        var data = new TheoryData<string>();
        foreach (var l in UiLanguage.Translated) data.Add(l);
        return data;
    }

    [Fact]
    public void TwelveLanguages() =>
        Assert.Equal(["en", "tr", "ar", "hi", "id", "th", "vi", "ur", "bn", "ms", "fil", "nl"], UiLanguage.All);

    [Theory]
    [MemberData(nameof(Languages))]
    public void EveryKeyInEveryLanguage(string language)
    {
        var en = Raw("en");
        var other = Raw(language);
        Assert.Empty(en.Keys.Except(other.Keys));
        Assert.Empty(other.Keys.Except(en.Keys));
    }

    [Theory]
    [MemberData(nameof(Languages))]
    public void PlaceholdersMatchEnglish(string language)
    {
        var en = Raw("en");
        var other = Raw(language);
        var bad = en.Keys
            .Where(k => !PrintfFormat.Placeholders(en[k]).Order().SequenceEqual(PrintfFormat.Placeholders(other[k]).Order()))
            .ToList();
        Assert.Empty(bad);
    }

    [Theory]
    [MemberData(nameof(Languages))]
    [InlineData("en")]
    public void NoEmptyValues(string language) =>
        Assert.Empty(Raw(language).Where(p => string.IsNullOrWhiteSpace(p.Value)).Select(p => p.Key));

    [Theory]
    [InlineData("ar")]
    [InlineData("bn")]
    [InlineData("hi")]
    [InlineData("th")]
    [InlineData("ur")]
    public void NonLatinLanguages_AreActuallyTranslated(string language)
    {
        var en = Raw("en");
        var other = Raw(language);
        // Yalnız harf içeren ve marka adı olmayan uzun metinler: İngilizceyle aynı kalmamalı.
        var same = en.Keys
            .Where(k => en[k].Length > 24 && en[k] == other[k] && k != "about.basedOn")
            .ToList();
        Assert.Empty(same);
    }

    [Fact]
    public void PositionalPlaceholders_WhenMoreThanOne()
    {
        var en = Raw("en");
        var bad = en.Where(p =>
        {
            var list = PrintfFormat.Placeholders(p.Value);
            return list.Count > 1 && list.Any(x => !x.Contains('$'));
        }).Select(p => p.Key).ToList();
        Assert.Empty(bad);
    }

    [Fact]
    public void Lookup_FallsBackToEnglishThenKey()
    {
        var c = TextCatalog.FromValues("tr",
            new Dictionary<string, string> { ["a"] = "bir" },
            new Dictionary<string, string> { ["a"] = "one", ["b"] = "two" });
        Assert.Equal("bir", c.Get("a"));
        Assert.Equal("two", c.Get("b"));
        Assert.Equal("missing.key", c.Get("missing.key"));
    }

    [Fact]
    public void EmbeddedCatalog_Works()
    {
        var tr = TextCatalog.For("tr");
        Assert.Equal("Ayarlar", tr.Get("common.settings"));
        Assert.Equal("Settings", TextCatalog.For("de").Get("common.settings"));
        Assert.Equal("en", TextCatalog.For("de").Language);
        Assert.Equal("الإعدادات", TextCatalog.For("ar").Get("common.settings"));
        Assert.True(TextCatalog.For("ar").IsRightToLeft);
        Assert.False(tr.IsRightToLeft);
    }

    [Fact]
    public void Upper_UsesLanguageCulture()
    {
        var c = TextCatalog.FromValues("tr", new Dictionary<string, string> { ["k"] = "Kayıtlı İçerik sayısı" });
        Assert.Equal("KAYITLI İÇERİK SAYISI", c.Upper("k"));
    }

    [Fact]
    public void AiModelLabels_AreCatalogKeys()
    {
        using var s = typeof(TextCatalog).Assembly.GetManifestResourceStream("ai-models.json")!;
        using var doc = JsonDocument.Parse(s);
        var en = Raw("en");
        var labels = doc.RootElement.EnumerateObject()
            .Where(p => p.Value.ValueKind == JsonValueKind.Array)
            .SelectMany(p => p.Value.EnumerateArray())
            .Select(m => m.GetProperty("text").GetString()!)
            .Distinct()
            .ToList();
        Assert.NotEmpty(labels);
        Assert.All(labels, l => Assert.True(en.ContainsKey(l), l));
        Assert.Equal(["ai.model.fast", "ai.model.better"], labels);
        Assert.Equal("Çabuk ve düşük maliyetli (tavsiye edilir)", TextCatalog.For("tr").Get("ai.model.fast"));
    }

    [Theory]
    [InlineData("de", "en")]
    [InlineData("tr-TR", "tr")]
    [InlineData("TR", "tr")]
    [InlineData("fil-PH", "fil")]
    [InlineData("tl", "fil")]
    [InlineData("fi-FI", "en")]
    [InlineData("ar-SA", "ar")]
    [InlineData("ur-PK", "ur")]
    [InlineData("nl-BE", "nl")]
    [InlineData("", "en")]
    [InlineData(null, "en")]
    public void UiLanguage_FromCulture(string? culture, string expected) =>
        Assert.Equal(expected, UiLanguage.FromCultureName(culture));

    [Theory]
    [InlineData("ar", true)]
    [InlineData("ur", true)]
    [InlineData("tr", false)]
    [InlineData("en", false)]
    public void RightToLeft(string language, bool rtl) => Assert.Equal(rtl, UiLanguage.IsRightToLeft(language));

    [Fact]
    public void ShortcutText_Rules()
    {
        var en = TextCatalog.For("en");
        Assert.Null(ShortcutText.Keys(en, []));
        Assert.Equal("Num 0", ShortcutText.Keys(en, ["Num 0"]));
        Assert.Equal("Num 0 or Ctrl+Shift+0", ShortcutText.Keys(en, ["Num 0", "Ctrl+Shift+0", "X"]));
        Assert.Equal("Num 0 ya da Ctrl+Shift+0", ShortcutText.Keys(TextCatalog.For("tr"), ["Num 0", "Ctrl+Shift+0"]));
    }

    [Fact]
    public void ShortcutText_NoKeys_TitleAndSentence()
    {
        var en = TextCatalog.For("en");
        var off = Hotkeys.Table.Select(t => new HotkeyBinding { Action = t.Action, Slot = t.Slot, Key = null }).ToList();
        Assert.Equal(en.Get("shortcut.none"), ShortcutText.ForTitle(en, off, HotkeyAction.Screen));
        Assert.Equal(en.Get("shortcut.noneSentence"),
            ShortcutText.ForSentence(en, "shortcut.keysTwo", off, HotkeyAction.Screen));
    }

    [Fact]
    public void ShortcutText_EveryActionHasName()
    {
        var en = Raw("en");
        Assert.Equal(Enum.GetValues<HotkeyAction>().Length, ShortcutText.DisplayOrder.Count);
        Assert.All(ShortcutText.DisplayOrder, a => Assert.True(en.ContainsKey(ShortcutText.ActionKey(a))));
    }
}

public class PrintfFormatTests
{
    private static readonly CultureInfo Tr = CultureInfo.GetCultureInfo("tr");

    [Fact]
    public void RecipeExample_Mixed()
    {
        Assert.Equal("A x B % A B %q", PrintfFormat.Apply("%1$@ x %2$@ %% %lld %@ %q", Tr, "A", "B"));
    }

    [Fact]
    public void Sequential_Integers() =>
        Assert.Equal("Adım 2 / 6", PrintfFormat.Apply("Adım %lld / %lld", Tr, 2, 6));

    [Fact]
    public void Positional_Reordered() =>
        Assert.Equal("6 içinde 2", PrintfFormat.Apply("%2$lld içinde %1$lld", Tr, 2, 6));

    [Fact]
    public void MissingValue_IsEmpty() =>
        Assert.Equal("a  b", PrintfFormat.Apply("a %@ b", Tr));

    [Fact]
    public void CultureFormatting() =>
        Assert.Equal("1,5", PrintfFormat.Apply("%@", Tr, 1.5));

    [Fact]
    public void NoPercent_ReturnsSameString()
    {
        const string s = "Ayarlar";
        Assert.Same(s, PrintfFormat.Apply(s, Tr));
    }

    [Theory]
    [InlineData("%", "%")]
    [InlineData("100%", "100%")]
    [InlineData("%y", "%y")]
    [InlineData("%1x", "%1x")]
    [InlineData("%0$@", "%0$@")]
    public void Unrecognized_StaysAsIs(string pattern, string expected) =>
        Assert.Equal(expected, PrintfFormat.Apply(pattern, Tr, "A"));

    [Fact]
    public void Placeholders_List() =>
        Assert.Equal(["%1$@", "%2$lld", "%@"], PrintfFormat.Placeholders("%1$@ %% %2$lld %@ %q"));
}
