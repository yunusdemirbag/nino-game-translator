// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Design;
using Nino.Core.Settings;

namespace Nino.Core.Tests.Design;

public sealed class GameRoomSignTests
{
    [Theory]
    [InlineData("TR", "en", true)]
    [InlineData("tr", "tr", true)]
    [InlineData("US", "ar", true)]
    [InlineData("SA", "en", true)]
    [InlineData("EG", "en", true)]
    [InlineData("US", "en", false)]
    [InlineData("DE", "tr", false)]
    [InlineData(null, null, false)]
    public void AsksOnlyInTurkeyOrArabic(string? region, string? language, bool expected) =>
        Assert.Equal(expected, GameRoomSign.AsksName(region, language));

    [Theory]
    [InlineData("Yunus", "YUNUS'S GAMING ROOM")]
    [InlineData("Ahmets", "AHMETS'S GAMING ROOM")]
    [InlineData("  ali   veli ", "ALİ VELİ'S GAMING ROOM")]
    public void LatinNamesAreUpperCasedWithEnglishTail(string name, string expected)
    {
        var sign = GameRoomSign.Text(name, "tr");
        Assert.NotNull(sign);
        Assert.Equal(expected, sign.Value.Text);
        Assert.Equal(GameRoomScript.Latin, sign.Value.Script);
    }

    [Fact]
    public void NonTurkishInterfaceUsesPlainUpperCaseUnlessNameIsTurkish()
    {
        Assert.Equal("MIKE'S GAMING ROOM", GameRoomSign.Text("Mike", "en")!.Value.Text);
        Assert.Equal("IŞIL'S GAMING ROOM", GameRoomSign.Text("ışıl", "en")!.Value.Text);
    }

    [Fact]
    public void ArabicNamesUseArabicPattern()
    {
        var sign = GameRoomSign.Text("أحمد", "en")!.Value;
        Assert.Equal("غرفة ألعاب أحمد", sign.Text);
        Assert.Equal(GameRoomScript.Arabic, sign.Script);
        Assert.Equal(GameRoomScript.Latin, GameRoomSign.Text("Ahmed", "ar")!.Value.Script);
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData("   ", null)]
    [InlineData("A\tB", "A B")]
    [InlineData("abcdefghijklmnopqrstu", "abcdefghijklmnop")]
    public void CleanNameTrimsCollapsesAndCaps(string? input, string? expected) =>
        Assert.Equal(expected, GameRoomSign.CleanName(input));

    [Theory]
    [InlineData("yunus", "Yunus")]
    [InlineData("Yunus Demirbağ", "Yunus")]
    [InlineData(@"DOMAIN\ahmet.k", "Ahmet")]
    [InlineData("john_doe", "John")]
    [InlineData("123", null)]
    [InlineData("", null)]
    public void SuggestsFirstWordOfAccount(string? account, string? expected) =>
        Assert.Equal(expected, GameRoomSign.SuggestedName(account));

    [Fact]
    public void NewFieldsAreNotWrittenWhileDefaultAndRoundTrip()
    {
        var plain = SettingsJson.Serialize(new AppSettings());
        Assert.DoesNotContain("GameRoom", plain, StringComparison.Ordinal);
        var s = new AppSettings { GameRoomSign = true, GameRoomName = "Yunus", GameRoomAsked = true };
        var back = SettingsJson.Deserialize(SettingsJson.Serialize(s));
        Assert.True(back.GameRoomSign);
        Assert.Equal("Yunus", back.GameRoomName);
        Assert.True(back.GameRoomAsked);
    }

    [Fact]
    public void WriteRulesCleanTheName()
    {
        var next = new AppSettings { GameRoomName = "  Yunus  " };
        SettingsRules.ApplyWriteRules(new AppSettings(), next, 8);
        Assert.Equal("Yunus", next.GameRoomName);
    }
}
