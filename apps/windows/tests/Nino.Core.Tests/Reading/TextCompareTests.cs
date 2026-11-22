// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

public class TextCompareTests
{
    const string TwoLines = "Under the pale lanterns, Tvi waited,\nhoping a horse would carry her north.";

    [Theory]
    [InlineData("Under the pale lanterns, 7xqv Tvi waited, Hoping 4q horse would carry her north now.",
        "Under the pale lanterns, Tvi ka$7r waited, hoping a horse would carry her north.", true)]
    [InlineData("Under the pale lanterns O waited,", TwoLines, true)]
    [InlineData("Under the pale lanterns, Tvi waited,", TwoLines, true)]
    [InlineData("hoping a horse would carry her north.", TwoLines, true)]
    [InlineData(TwoLines, "Under the pale lanterns, Tvi waited,", false)]
    [InlineData("Who sent you here?", "Who sent you here, stranger?", false)]
    [InlineData("Who sent you here, stranger?", "Who sent you here?", false)]
    [InlineData("We must reach the harbor before the storm breaks, sister.",
        "We must reach the harbor before the storm breaks.", false)]
    [InlineData("Sister, we must reach the harbor before the storm breaks.",
        "We must reach the harbor before the storm breaks.", false)]
    [InlineData("we must climb the tower", "We must climb the tower before the guards return", false)]
    [InlineData("we must climb the tower", "We must climb the tower\nbefore the guards return", true)]
    [InlineData("we can not stay here", "the rope will snap soon", false)]
    [InlineData("we can not stay here tonight and you know why", "we can not stay here", false)]
    [InlineData("where is the key", "where is the map", false)]
    [InlineData("you should not go alone", "i asked you to wait by the gate", false)]
    [InlineData("we must climb the tower before the guards return", "the tower is too tall for us to climb tonight", false)]
    [InlineData("I can't open that gate for you yet.", "I can open that gate for you yet.", false)]
    [InlineData("She swore she would never trust them with this.", "She swore she would trust them with this.", false)]
    [InlineData("The guard is not leaving his post.", "The guard is leaving his post.", false)]
    [InlineData("Wait for me by the bridge at 9.", "Wait for me by the bridge at 8.", false)]
    [InlineData("I can’t open that gate for you yet.", "I can't open that gate for you yet.", true)]
    [InlineData("I dont trust what they say.", "I don't trust what they say.", true)]
    [InlineData("The guard is n0t leaving his post.", "The guard is not leaving his post.", true)]
    public void SameSubtitle(string reading, string sent, bool same)
    {
        var r = reading.StartsWith("Under the pale lanterns O") ? OcrJunk.Clean("Under the pale lanterns7xqv O waited,") : reading;
        Assert.Equal(same, TextCompare.SameSubtitle(TextKey.Of(r), TextKey.OfLines(sent)));
    }

    [Theory]
    [InlineData("We can not stay here tonight.", "We can not stay", true)]
    [InlineData("We can not stay", "We can not stay here tonight.", true)]
    [InlineData("stay here tonight, sister.", "We can not stay here tonight, sister.", true)]
    [InlineData("The rope will snap soon!", "The rope will snap spon", true)]
    [InlineData("Under the pale lanterns she waited, hoping a horse would carry her north.",
        "Under the pale lanterns O waited, Hoping a horsc would carry her north", true)]
    [InlineData("Row to the dock!", "We can not stay here tonight.", false)]
    [InlineData("Where is the lantern?", "Where is the key?", false)]
    [InlineData("No.", "Yes.", false)]
    [InlineData("I asked you to wait by the gate.", "You should not go alone.", false)]
    public void Correction(string newer, string older, bool correction) =>
        Assert.Equal(correction, TextCompare.IsCorrection(newer, older));

    const string Full = "Damn, I only stopped by to check if there's anythin' I can carry for you.";
    const string Bad = "Damn, I stopped by to check if there anythinl I can carry fo ya.";

    [Fact]
    public void WorseReread()
    {
        Assert.True(TextCompare.IsWorseReread(Bad, Full));
        Assert.False(TextCompare.IsWorseReread(Full, Bad));
    }

    [Theory]
    [InlineData("We can not stay here.", "We can not", true)]
    [InlineData("We can not", "We can not stay here.", false)]
    [InlineData("We can not stay here.", "We can not stay here.", false)]
    [InlineData("Then we sail north.", "Then", true)]
    [InlineData("Then we sail north.", "north", false)]
    [InlineData("Then we sail north.", "sail north", true)]
    public void Extension(string newer, string older, bool ext) => Assert.Equal(ext, TextCompare.IsExtension(newer, older));

    [Theory]
    [InlineData("I can't swim there.", "I can swim there.", true)]
    [InlineData("I can swim there.", "I can't swim there.", false)]
    [InlineData("Back by 7.", "Back by 4.", true)]
    [InlineData("Back by", "Back by 4.", false)]
    [InlineData("She is n0t ready.", "She is ready.", true)]
    [InlineData("I dont care.", "I don't care.", false)]
    [InlineData("Grab a t shirt.", "Grab a shirt.", false)]
    [InlineData("Grab a wool t shirt.", "Grab a wool shirt.", false)]
    [InlineData("I won t stay.", "I will stay.", true)]
    [InlineData("They haven t eaten.", "They have eaten.", true)]
    [InlineData("Pack 3 and 3.", "Pack 3.", true)]
    [InlineData("Pack 3.", "Pack 3 and 3.", false)]
    [InlineData("That's $750 total now.", "That's $750 total.", false)]
    [InlineData("1 can swim there.", "I can swim there.", false)]
    public void MeaningMarker(string reading, string sent, bool adds) =>
        Assert.Equal(adds, TextCompare.AddsMeaningMarker(reading, sent));

    [Theory]
    [InlineData("I got 1 arrow left.", "I got 3 arrows left.")]
    [InlineData("I got 1 arrow left.", "I got 3 arrow left.")]
    [InlineData("1 got 1 arrow left.", "I got 3 arrows left.")]
    [InlineData("I need 1 more rope.", "I need more ropes.")]
    [InlineData("I got 1 and 1 left.", "I got 1 left.")]
    [InlineData("I got 1 and 1 left.", "I got 1 and 3 left.")]
    [InlineData("O, we got 0 ropes left.", "O, we got 3 ropes left.")]
    [InlineData("I got 12 ropes left.", "I got 3 ropes left.")]
    [InlineData("I got 1 rope left.", "I got\n3 ropes left.")]
    public void NumberChanges(string reading, string sent)
    {
        Assert.True(TextCompare.AddsMeaningMarker(reading, sent));
        Assert.False(TextCompare.SameSubtitle(reading, sent));
        Assert.False(TextCompare.IsWorseReread(reading, sent));
    }

    [Theory]
    [InlineData("1 can swim there.", "I can swim there.")]
    [InlineData("0, we should rest here.", "O, we should rest here.")]
    [InlineData("Now 1 can swim there.", "Now I can swim there.")]
    [InlineData("Ycs 1 can swim thcre.", "Yes I can swim there.")]
    [InlineData("Yes 1 can swim there.", "Well I can swim there.")]
    [InlineData("1 can swim there now.", "I can swim there.")]
    [InlineData("Now 1 can swim there.", "I can swim there.")]
    [InlineData("1 got 1 rope left.", "I got 1 rope left.")]
    [InlineData("1 said 1 can swim there.", "I said I can swim there.")]
    [InlineData("1 got 3 ropes left.", "I got 3 ropes left.")]
    public void GlyphNoise(string reading, string sent) => Assert.False(TextCompare.AddsMeaningMarker(reading, sent));

    static bool Misread(string s) => s.Contains("qrrvx", StringComparison.OrdinalIgnoreCase);

    [Fact]
    public void Helpers()
    {
        Assert.True(TextCompare.LooksComplete("Untie the rope."));
        Assert.False(TextCompare.LooksComplete("untie the rope."));
        Assert.False(TextCompare.LooksComplete("Untie the rope"));
        Assert.False(TextCompare.LooksComplete("24 / 120"));
        Assert.True(TextCompare.IsPackFragment("harbor.", "We finally made it to the harbor."));
        Assert.False(TextCompare.IsPackFragment("Hurry up!", "Come on Mara, hurry up, hurry up!"));
        Assert.True(TextCompare.IsPackFragment("hurry up!", "Come on Mara, hurry up, hurry up!"));
        Assert.True(TextCompare.Related("Untie the rope", "the rope"));
        Assert.False(TextCompare.Related("Row", "Untie the rope"));
        Assert.True(TextCompare.IsRereadOf("Sure? Qrrvx.", "Sure? Fine.", Misread));
        Assert.True(TextCompare.IsRereadOf("Go to Ridge.", "Go to Copper Ridge.", Misread));
        Assert.True(TextCompare.IsRereadOf("can always find another horse.", "But we can always find another horse.", Misread));
        Assert.False(TextCompare.IsRereadOf("You crack me up!", "I swear, you crack me up!", Misread));
        Assert.False(TextCompare.AllLinesCovered("She's a liar!\nI knew it!", "She's a liar!", Misread));
        Assert.True(TextCompare.AllLinesCovered("She's a liar!", "She's a liar!\nI knew it!", Misread));
    }
}
