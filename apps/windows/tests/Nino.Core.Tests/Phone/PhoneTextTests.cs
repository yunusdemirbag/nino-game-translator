// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Tests.Reading;

namespace Nino.Core.Tests.Phone;

public class PhoneTextTests
{
    [Fact]
    public void KeyRules()
    {
        Assert.Equal("señora", PhoneText.Key("Señora"));
        Assert.Equal("7 250 left", PhoneText.Key("$7,250 left"));
        Assert.Equal("body nutrition", PhoneText.Key("Body & Nutrition"));
    }

    [Fact]
    public void Similarity()
    {
        string[] shown = ["where did you park the boat", "ok"];
        Assert.True(PhoneText.SimilarToAny("Where did you park the boat?' U OK", shown));
        Assert.True(PhoneText.SameMessages(["Where did you park the boat??", "OK"], shown));
        Assert.False(PhoneText.SameMessages(["Bring the spare keys tomorrow."], shown));
        Assert.False(PhoneText.SameMessages([], shown));
        Assert.False(PhoneText.SimilarKeys("", ""));
    }

    [Theory]
    [InlineData("buckme", "BuckMe mi?", false)]
    [InlineData("Harbor Office", "Liman Ofisi", true)]
    [InlineData("Vice City Horn", "Vice City Horn", false)]
    [InlineData("Hello", "", false)]
    public void Worth(string source, string tr, bool worth) => Assert.Equal(worth, PhoneText.WorthShowing(source, tr));

    [Theory]
    [InlineData("Geliyorum 👍", "Geliyorum")]
    [InlineData("Rosa &amp; Marco", "Rosa & Marco")]
    [InlineData("ÇOK ÇOK ÇOK HIZLI", "ÇOK HIZLI")]
    [InlineData("Şu şu kapı $9 $9", "Şu kapı $9 $9")]
    public void Cleaning(string input, string output) => Assert.Equal(output, PhoneText.CleanTranslation(input));

    [Theory]
    [InlineData("Rent Boat ($40)", false)]
    [InlineData("Harbor Bait & Tackle", false)]
    [InlineData("1.74 mi", false)]
    [InlineData("Yo pal! U got the keys", true)]
    [InlineData("Are you high right now?", true)]
    [InlineData("Left the keys under yuh mat", true)]
    public void Sentence(string text, bool sentence) => Assert.Equal(sentence, PhoneText.IsSentence(text));

    [Fact]
    public void Names()
    {
        Assert.True(PhoneText.IsPersonName("Harbor Bait & Tackle"));
        Assert.True(PhoneText.IsPersonName("McKenzie"));
        Assert.False(PhoneText.IsPersonName("MESSAGES"));
        Assert.False(PhoneText.IsPersonName("Hey, you"));
        Assert.True(PhoneText.IsTitleLike("Marina, Coral Bay"));
        Assert.True(PhoneText.IsSenderName("Cal"));
        Assert.False(PhoneText.IsSenderName("Anyone got a lighter?"));
    }

    [Fact]
    public void Casing()
    {
        Assert.Equal("Open The North Gate", PhoneText.TitleCase("OPEN THE NORTH GATE"));
        Assert.Equal("TR: VİSİT THE FİSH MARKET", PhoneText.TurkishUpper("TR: Visit The Fish Market"));
        Assert.Equal("BUCKME'YE NAKİT YATIR", PhoneText.TurkishUpper("BuckMe'ye nakit yatır"));
    }

    [Theory]
    [InlineData("Savings Account", "Birikim Hesabı")]
    [InlineData("Recent Transactions", "Son Hareketler")]
    [InlineData("$1,250 to next goal", "Sonraki hedefe $1.250")]
    [InlineData("Are you high right now?", null)]
    [InlineData("Cancel Ryde ($15)", "Ryde'ı İptal Et ($15)")]
    [InlineData("Set A Goal", "Hedef Belirle")]
    [InlineData("Level 3/4", "Seviye 3/4")]
    [InlineData("Strength Workout", "Güç Antrenmanı")]
    [InlineData("Stamina - Medium", "Dayanıklılık - Orta")]
    [InlineData("Strength - Very Low", "Güç - Çok Düşük")]
    [InlineData("Ripped", "Kaslı")]
    [InlineData("Fat Medium", "Yağ - Orta")]
    [InlineData("Body & Nutrition", "Vücut ve Beslenme")]
    public void Glossary(string text, string? tr) => Assert.Equal(tr, PhoneGlossary.Lookup(text));

    [Theory]
    [InlineData("◇ CINEMATIC", "CINEMATIC")]
    [InlineData("ADD MARKER •", "ADD MARKER")]
    [InlineData("i Settings", "Settings")]
    [InlineData("ii Map", "Map")]
    [InlineData("Il Game", "Game")]
    [InlineData("SET DESTINATION X", "SET DESTINATION X")]
    [InlineData("2D VIEW", "VIEW")]
    public void MenuClean(string text, string clean) => Assert.Equal(clean, MapScreen.CleanMenu(text));

    [Fact]
    public void MapScreenDecision()
    {
        Assert.True(MapScreen.IsMapScreen(Fixtures.Load("gta6-harita-buckme").Lines.Select(l => l.Text)));
        Assert.True(MapScreen.IsMapScreen(Fixtures.Load("gta6-harita-balik").Lines.Select(l => l.Text)));
        Assert.False(MapScreen.IsMapScreen(Fixtures.Load("gta6-telefon-brian-parlama").Lines.Select(l => l.Text)));
        Assert.False(MapScreen.IsMapScreen(["You trying to kill me?"]));
        Assert.True(MapScreen.IsMapScreen(["◇ CINEMATIC", "MARKERS"]));
        Assert.False(MapScreen.IsMapScreen(["RECENTER", "RECENTER"]));
        Assert.False(MapScreen.IsMapButton("MARKERS"));
        Assert.True(MapScreen.IsMapButton("RECENTER"));
    }

    [Theory]
    [InlineData(new[] { "JASON & LUCIA", "MAP", "BRIEF", "PROGRESS" }, true)]
    [InlineData(new[] { "MAP", "BRIEF", "PROGRESS" }, true)]
    [InlineData(new[] { "Reminders", "WhatUp" }, true)]
    [InlineData(new[] { "Options", "Map", "Progress", "Quit Game" }, false)]
    [InlineData(new[] { "Jason, call me later!" }, false)]
    public void Gta6Signs(string[] lines, bool gta) => Assert.Equal(gta, MapScreen.ShowsGta6(lines));

    [Theory]
    [InlineData("gta6-harita-buckme", true)]
    [InlineData("gta6-altyazi-beyaz", false)]
    [InlineData("gta6-telefon-brian-parlama", false)]
    public void Gta6SignsInFixtures(string name, bool gta) =>
        Assert.Equal(gta, MapScreen.ShowsGta6(Fixtures.Load(name).Lines.Select(l => l.Text).ToArray()));

    [Theory]
    [InlineData("Strength High", true)]
    [InlineData("Strength Workout", true)]
    [InlineData("Lose Weight Plan", true)]
    [InlineData("You will gain weight", true)]
    [InlineData("Change Destinatoin", true)]
    [InlineData("New Destinatior", true)]
    [InlineData("Cancel Ryde ($15)", true)]
    [InlineData("Choose Ryde", true)]
    [InlineData("Trip Detail View", true)]
    [InlineData("TRIP DETAIL VIEW", true)]
    [InlineData("buckme", true)]
    [InlineData("Savings Account", true)]
    [InlineData("You can do it!", false)]
    [InlineData("Get to the boat", false)]
    [InlineData("Change of plans, see you at noon", false)]
    [InlineData("Rydeman's boat is over there", false)]
    [InlineData("I missed my workout again", false)]
    public void PhoneAppText(string text, bool app) => Assert.Equal(app, PhoneLineRules.IsPhoneAppText(text));

    [Fact]
    public void TurkishCultureDoesNotChangeRules()
    {
        var old = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = new System.Globalization.CultureInfo("tr-TR");
            Assert.True(PhoneLineRules.IsPhoneAppText("TRIP DETAIL VIEW"));
            Assert.True(MapScreen.IsMapScreen(["RECENTER", "SET DESTINATION"]));
        }
        finally { System.Globalization.CultureInfo.CurrentCulture = old; }
    }

    [Fact]
    public void Wrap()
    {
        Assert.Equal((1, 5), PhoneLayout.Wrap("hello", 0.2, 0.02));
        var (lines, longest) = PhoneLayout.Wrap("one two three four five six seven eight nine ten", 0.0675, 0.02);
        Assert.True(lines > 1);
        Assert.True(longest <= 12);
        Assert.Equal((1, 0), PhoneLayout.Wrap("", 0.1, 0.02));
    }
}
