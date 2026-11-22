// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

public class TextKeyTests
{
    [Fact]
    public void KeySimplifies()
    {
        Assert.Equal("lena we can not stay here sister", TextKey.Of("Lena: We can NOT stay here, sister."));
        Assert.Equal("señora", TextKey.Of("Señora"));
        Assert.Equal("12 350 left to raise", TextKey.Of("$12,350 left to raise"));
        Assert.Equal("a\nb c", TextKey.OfLines("A!\r\n\n  b, c "));
    }

    [Fact]
    public void KeyIsCultureInvariantUnderTurkish()
    {
        var old = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
            Assert.Equal("i will", TextKey.Of("I WILL"));
        }
        finally { CultureInfo.CurrentCulture = old; }
    }

    [Theory]
    [InlineData("the rope will snap soon", "the rope will snap spon", true)]
    [InlineData("we can not stay here", "the rope will snap soon", false)]
    [InlineData("", "abc", false)]
    [InlineData("abc", "abc", true)]
    public void Similarity(string a, string b, bool similar) => Assert.Equal(similar, TextKey.Similar(a, b));

    [Theory]
    [InlineData("Untie the rope.", true)]
    [InlineData("\"Hide.\"", true)]
    [InlineData("Maybe…", true)]
    [InlineData("Who is there?)", true)]
    [InlineData("Untie the rope", false)]
    [InlineData("  ", false)]
    public void SentenceEnd(string text, bool ends) => Assert.Equal(ends, TextKey.EndsSentence(text));
}

public class ButtonHintTests
{
    [Theory]
    [InlineData("CAMERA MODE L1 + R1", true)]
    [InlineData("CAMERA MODE [L1] + [R3]", true)]
    [InlineData("Pass me the L1 cable.", false)]
    [InlineData("B o EAT", true)]
    [InlineData("X : OPEN DOOR", true)]
    [InlineData("STAY LOW!", false)]
    [InlineData("I was FREEZING", false)]
    [InlineData("Hey, you found Mara's phone.", false)]
    [InlineData("Gently tilt ○ to steer the kite then press R2 when the wind drops", true)]
    [InlineData("Gently tilt t to steer the kite then press R2 when the wind drops", true)]
    [InlineData("Quickly pull to land the kite while it's low", true)]
    [InlineData("Tilt ○ to dive", true)]
    [InlineData("○ to dive", true)]
    [InlineData("Gently, we need to land.", false)]
    [InlineData("Quickly, run to the dock", false)]
    [InlineData("I need to rest now", false)]
    [InlineData("Follow the R2 sign, then right.", false)]
    [InlineData("R2 Swing", true)]
    [InlineData("L1 + R1 Storm Fury", true)]
    [InlineData("Press ✕ to jump", true)]
    [InlineData("△ Pick up", true)]
    public void Table(string line, bool hint) => Assert.Equal(hint, ButtonHints.IsHint(line));
}

public class DirectionTests
{
    [Theory]
    [InlineData("Turn Right 260 ft 318 ft", true)]
    [InlineData("Keep Right O ft 7 ft", true)]
    [InlineData("U-Turn Right 8 ft 31 ft", true)]
    [InlineData("Turn Right 190 ft—", true)]
    [InlineData("-turn Left 54 ft 76 ft", true)]
    [InlineData("Turn Left l 140 ft 152 ft", true)]
    [InlineData("Keep Left 1.4 km", true)]
    [InlineData("Turn left", true)]
    [InlineData("Turn Right", true)]
    [InlineData("Keep left", true)]
    [InlineData("Keep Right.", true)]
    [InlineData("Make a u-turn.", true)]
    [InlineData("U-Turn Left", true)]
    [InlineData("Turn right at the bridge, got it?", false)]
    [InlineData("Turn left after the gas station, yeah?", false)]
    [InlineData("Keep driving, it's not far now.", false)]
    [InlineData("Turn that radio off!", false)]
    [InlineData("Keep your voice low!", false)]
    [InlineData("Keep right and stay calm, 30 ft maybe", false)]
    [InlineData("I told you turn right, 80 ft ago, genius.", false)]
    public void Table(string line, bool direction) => Assert.Equal(direction, Directions.IsDirection(line));

    [Fact]
    public void TurkishCulture()
    {
        var old = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
            Assert.True(Directions.IsDirection("TURN LEFT 275 ft"));
            Assert.True(Directions.IsDirection("turn left 275 ft"));
            Assert.True(Directions.IsDirection("U-TURN RIGHT 9 ft"));
        }
        finally { CultureInfo.CurrentCulture = old; }
    }

    [Fact]
    public void RemovedFromReading()
    {
        var r = Directions.Remove(new OcrReading([new("Turn Left 275 ft"), new("Why are we taking the long way?")]));
        Assert.Equal("Why are we taking the long way?", r.Text);
    }
}

public class OcrJunkTests
{
    [Theory]
    [InlineData("Over the cold hills, Tvi ka$7r rode, hoping the fort would still stand.", "Over the cold hills, Tvi rode, hoping the fort would still stand.")]
    [InlineData("Over the cold hills7xqv O rode, Hoping the fort.", "Over the cold hills O rode, Hoping the fort.")]
    [InlineData("She waited 4q, by the well.", "She waited, by the well.")]
    [InlineData("?! Who told you to open that door?", "Who told you to open that door?")]
    [InlineData("Who told you to open that door ?!", "Who told you to open that door?!")]
    [InlineData("Close the hatch, Mara. ?!", "Close the hatch, Mara.")]
    [InlineData("Listen, ?! Baron Holt wants you.", "Listen, Baron Holt wants you.")]
    [InlineData(". Close the hatch.", "Close the hatch.")]
    [InlineData("| Close the hatch, Mara.", "Close the hatch, Mara.")]
    [InlineData("Close the hatch, Mara. |", "Close the hatch, Mara.")]
    [InlineData("Drop it. l", "Drop it.")]
    [InlineData("l never asked, Baron Holt.", "I never asked, Baron Holt.")]
    [InlineData("| never asked.", "I never asked.")]
    [InlineData("l'm sure of it, l heard her.", "I'm sure of it, I heard her.")]
    [InlineData("|'ll find the key.", "I'll find the key.")]
    [InlineData("She and l've met once.", "She and I've met once.")]
    [InlineData("Where am l?", "Where am I?")]
    [InlineData("Can you see, |?", "Can you see, I?")]
    [InlineData("I never asked, l!", "I never asked, I!")]
    [InlineData("Drop it. l.", "Drop it.")]
    [InlineData("7? They'll find our trail.", "They'll find our trail.")]
    [InlineData("250. Ivy and Rook...", "Ivy and Rook...")]
    [InlineData("41m HOLT: They're here! Run!", "HOLT: They're here! Run!")]
    [InlineData("300 riders came", "300 riders came")]
    public void Cleans(string input, string output) => Assert.Equal(output, OcrJunk.Clean(input));

    [Theory]
    [InlineData("Switch on the PS5 first.")]
    [InlineData("Hold C3-K9 steady.")]
    [InlineData("That's $750 total.")]
    [InlineData("Be there by 9:45am.")]
    [InlineData("The 3rd tower is 200m north.")]
    [InlineData("Locked at 30fps, 8K.")]
    [InlineData("Combo x3!")]
    [InlineData("Since 1987.")]
    [InlineData("I won't — not yet…")]
    [InlineData("\"Mara!\" he called.")]
    [InlineData("Mk4 scope, 2.5kg.")]
    [InlineData("L1 + R1 Storm Fury")]
    [InlineData("Huh?! The lamp turned off by itself!")]
    [InlineData("- Who? - Nobody.")]
    [InlineData("Hold on... why?")]
    [InlineData("I... I never said that.")]
    [InlineData("\"Hide!\" she said.")]
    [InlineData("So, you're Mara?")]
    [InlineData("... and then she vanished.")]
    [InlineData("Hold on ... why?")]
    [InlineData("I told you no!")]
    [InlineData("Drop it, I told you.")]
    [InlineData("Press R to reload.")]
    public void LeavesUntouched(string line) => Assert.Equal(line, OcrJunk.Clean(line));

    [Fact]
    public void JunkOnlyLineLeavesReading()
    {
        var r = OcrJunk.Clean(new OcrReading([new("The tide turned."), new("ka$7r 9xqvz")]));
        Assert.Equal("The tide turned.", r.Text);
        Assert.Single(r.Lines);
    }

    [Theory]
    [InlineData("HOLT: Back me up!", "- HOLTrWQäkk'z!")]
    [InlineData("This should stay closed now.", "T his sh[oul Should stay closed now.")]
    [InlineData("Get to the boat now.", "Gxt to the boat now.")]
    public void ScoreOrders(string better, string worse) => Assert.True(OcrJunk.Score(better) > OcrJunk.Score(worse));

    [Theory]
    [InlineData("We eat at McKinley's tonight.")]
    [InlineData("Hmm!")]
    [InlineData("Shh!")]
    [InlineData("Brr!")]
    [InlineData("Psst!")]
    [InlineData("Mmm!")]
    public void ScorePositive(string text) => Assert.True(OcrJunk.Score(text) > 0);

    [Theory]
    [InlineData("Gxt brrvwlk.", true)]
    [InlineData("- HOLTrWQäkk'z!", true)]
    [InlineData("Brrk thnk.", true)]
    [InlineData("Lock the door.", false)]
    [InlineData("The CIA and the NSA agents.", false)]
    [InlineData("Hmm, I doubt that, sister.", false)]
    [InlineData("Go to school.", false)]
    public void Garbage(string text, bool garbage) => Assert.Equal(garbage, OcrJunk.LooksLikeGarbage(text));

    [Theory]
    [InlineData("Lock the door.", false)]
    [InlineData("Stäy back!", true)]
    [InlineData("I won’t — not yet…", false)]
    [InlineData("Lock th3 door", true)]
    [InlineData("Run q now", true)]
    [InlineData("I need a map, O captain", false)]
    [InlineData("Misunderstandings", true)]
    [InlineData("Sail to Ber#muda now", true)]
    [InlineData("Ant-Man can't hide", false)]
    public void MisreadTrace(string text, bool misread) => Assert.Equal(misread, OcrJunk.IsMisread(text));
}

public class SpeakerNameTests
{
    [Theory]
    [InlineData("HOLT: We have to move.", "HOLT", "We have to move.")]
    [InlineData("Mara: I know a way.", "Mara", "I know a way.")]
    [InlineData("Mr. Grey：Stay back.", "Mr. Grey", "Stay back.")]
    [InlineData("TALL GUARD : Hm.", "TALL GUARD", "Hm.")]
    [InlineData("HOLT:We run.", "HOLT", "We run.")]
    [InlineData("Holt:\nWe have to move.", "Holt", "We have to move.")]
    public void Splits(string text, string name, string sentence)
    {
        var s = SpeakerName.Split(text);
        Assert.Equal(name, s.Name);
        Assert.Equal(sentence, s.Sentence);
    }

    [Theory]
    [InlineData("09:15 at the harbor.")]
    [InlineData("Be at the pier by 11:40.")]
    [InlineData("HTTPS://example.com")]
    [InlineData("Ratio 16:9")]
    [InlineData("Tip: the bridge is out.")]
    [InlineData("I warned you: run!")]
    [InlineData("Some Very Long Title: words")]
    [InlineData("Maximiliano Fairweatherby: Hi.")]
    [InlineData("HOLT:")]
    public void NoName(string text) => Assert.Null(SpeakerName.Split(text).Name);

    [Theory]
    [InlineData("Hareket etmeliyiz.", "HOLT: We have to move.", true, "HOLT: Hareket etmeliyiz.")]
    [InlineData("Hareket etmeliyiz.", "HOLT: We have to move.", false, "Hareket etmeliyiz.")]
    [InlineData("HOLT: Hareket etmeliyiz.", "HOLT: We have to move.", true, "HOLT: Hareket etmeliyiz.")]
    [InlineData("HOLT: Tamam.\nMARA: Olmaz.", "HOLT: Fine.\nMARA: Never.", false, "Tamam.\nOlmaz.")]
    [InlineData("Hedef: Limana git.", "Objective: Reach the harbor.", false, "Hedef: Limana git.")]
    public void Presents(string translation, string source, bool show, string expected) =>
        Assert.Equal(expected, SpeakerName.Present(translation, source, show));
}
