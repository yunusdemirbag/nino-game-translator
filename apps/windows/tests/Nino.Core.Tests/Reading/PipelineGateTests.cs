// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Translation;
using static Nino.Core.Tests.Reading.Script;

namespace Nino.Core.Tests.Reading;

/// <summary>Paket, bekletme, paket parçası ve sıra düzeltme örnekleri.</summary>
public class PipelineGateTests
{
    static FakePack LowerSails() => new FakePack().Add("Lower the sails", "Yelkenleri indir!");

    static Harness Make(string[] script, ITranslator translator, ISubtitlePackLookup? pack = null,
        bool holdWithoutPack = false, Func<string, bool>? misread = null, Func<string, int>? score = null,
        int? misreadWait = null, int? partialWait = null, long start = 0) =>
        new(new SequenceReader(script), translator, new ManualMsClock(start), o => new SubtitlePipelineOptions
        {
            Pack = o.Pack,
            HoldWithoutPack = o.HoldWithoutPack,
            Log = o.Log,
            ExtraMisread = misread,
            ReadingScore = score,
            MisreadWaitMs = misreadWait ?? 800,
            PartialWaitMs = partialWait ?? 300,
        }, pack, holdWithoutPack);

    [Fact]
    public async Task PackLineShownWithoutTranslator()
    {
        var t = new FakeTranslator();
        var h = Make(Repeat("Lower the sails!", 3), t, LowerSails());
        await h.Frames(3, 100);
        Assert.Equal(["Yelkenleri indir!"], h.Output.Texts);
        Assert.Empty(t.Requests);
        Assert.Equal(("Lower the sails!", "Yelkenleri indir!"), (h.Pairs.Single().Source, h.Pairs.Single().Translation));
        Assert.Empty(h.NotInPack);
        Assert.Equal(ShownOrigin.Pack, h.Pipeline.LastOrigin);
        Assert.Equal(1, h.Pipeline.PackHits);
    }

    [Fact]
    public async Task PartialLineHeld()
    {
        var t = new FakeTranslator();
        var h = Make(Repeat("Untie the rope", 4), t, LowerSails());
        await h.Frame(100);
        await h.Frame(100);
        Assert.Empty(h.Output.Texts);
        Assert.Contains(h.Log, l => l.StartsWith("bekletiliyor"));
        await h.Frame(200);
        await h.Frame(200);
        Assert.Equal(["TR: Untie the rope"], h.Output.Texts);
        Assert.Equal(["Untie the rope"], h.NotInPack);
        Assert.Equal(ShownOrigin.Engine, h.Pipeline.LastOrigin);
    }

    [Fact]
    public async Task MisreadWaitsForPackLine()
    {
        var t = new FakeTranslator();
        var h = Make(["Lowér the saiils!", "Lower the saiils!", "Lower the sails!", "Lower the sails!"], t, LowerSails(),
            misread: s => s.Contains("ii") || s.Contains('é'));
        await h.Frames(4, 100);
        Assert.Equal(["Yelkenleri indir!"], h.Output.Texts);
        Assert.Empty(t.Requests);
    }

    [Fact]
    public async Task MisreadWaitIsLonger()
    {
        var t = new FakeTranslator();
        var h = Make(Repeat("Untie the ropee", 12), t, LowerSails(), misread: s => s.Contains("ee"));
        await h.Frames(7, 100);
        Assert.Empty(h.Output.Texts);
        await h.Frames(3, 100);
        Assert.Equal(["TR: Untie the ropee"], h.Output.Texts);
    }

    [Fact]
    public async Task BetterReadReplacesHeld()
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat("the rope", 2), Repeat("Untie the rope!", 4)), t, holdWithoutPack: true, score: s => s.Length);
        await h.Frames(6, 100);
        Assert.Equal(["TR: Untie the rope!"], h.Output.Texts);
        Assert.Equal(["Untie the rope!"], t.Requests);
    }

    [Fact]
    public async Task ShorterRereadIgnored()
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat("Follow the cart.", 6), Repeat("Follow the", 6)), t, holdWithoutPack: true, score: s => s.Length);
        await h.Frames(12, 100);
        Assert.Equal(["Follow the cart."], t.Requests);
    }

    [Fact]
    public async Task SeparateShortLineTranslated()
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat("I swear, you crack me up!", 4), Repeat("You crack me up!", 4)), t, holdWithoutPack: true,
            score: s => s.Length);
        await h.Frames(8, 100);
        Assert.Equal(["I swear, you crack me up!", "You crack me up!"], t.Requests);
    }

    [Theory]
    [InlineData(800, 300)]
    [InlineData(0, 0)]
    public async Task MisreadVariantIgnored(int misreadWait, int partialWait)
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat("Sure? Fine.", 4), Repeat("Sure? Qrrvx.", 4)), t, holdWithoutPack: true,
            misread: s => s.Contains("qrrvx", StringComparison.OrdinalIgnoreCase),
            score: s => s.Contains("qrrvx", StringComparison.OrdinalIgnoreCase) ? 4 : 8,
            misreadWait: misreadWait, partialWait: partialWait);
        await h.Frames(8, 100);
        Assert.Equal(["Sure? Fine."], t.Requests);
    }

    [Fact]
    public async Task HeadlessRereadIgnored()
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat("But we can always find another horse.", 4), Repeat("can always find another horse.", 4)), t, LowerSails());
        await h.Frames(8, 100);
        Assert.Equal(["But we can always find another horse."], t.Requests);
    }

    [Theory]
    [InlineData("Wait for me by the bridge at 8.", "Wait for me by the bridge at 9.")]
    [InlineData("I can open that gate for you yet.", "I can't open that gate for you yet.")]
    [InlineData("She swore she would trust them with this.", "She swore she would never trust them with this.")]
    public async Task MeaningCorrectionSentAgain(string wrong, string right)
    {
        var t = new FakeTranslator();
        var h = Make(Of(wrong, Repeat(right, 6)), t, holdWithoutPack: true, score: _ => 10);
        await h.Frames(7, 100);
        Assert.Equal([wrong, right], t.Requests);
    }

    [Fact]
    public async Task DroppedNegationNotSent()
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat("I can't open that gate for you yet.", 3), Repeat("I can open that gate for you yet.", 3)), t,
            holdWithoutPack: true, score: _ => 10);
        await h.Frames(6, 100);
        Assert.Equal(["I can't open that gate for you yet."], t.Requests);
    }

    [Theory]
    [InlineData("I can open that gate for you yet", "I can't open that gate for you yet", 2)]
    [InlineData("I can open that gate for you yet", "I can't open that gate for you yet", 4)]
    [InlineData("Wait for me by the bridge at 8", "Wait for me by the bridge at 9", 2)]
    [InlineData("Wait for me by the bridge at 8", "Wait for me by the bridge at 9", 4)]
    public async Task HeldCorrectionKeepsDeadline(string wrong, string right, int wrongFrames)
    {
        var t = new FakeTranslator();
        var h = Make(Of(Repeat(wrong, wrongFrames), Repeat(right, 8)), t, holdWithoutPack: true, score: _ => 10);
        await h.Frames(4, 100);
        Assert.Empty(t.Requests);
        await h.Frames(1, 100);
        Assert.Equal([right], t.Requests);
        await h.Frames(wrongFrames + 8 - 5, 100);
        Assert.Equal([right], t.Requests);
    }

    [Fact]
    public async Task CompleteLineNotHeld()
    {
        var t = new FakeTranslator();
        var h = Make(Repeat("Untie the rope!", 2), t, holdWithoutPack: true);
        await h.Frame(10);
        Assert.Equal(["TR: Untie the rope!"], h.Output.Texts);
    }

    [Fact]
    public async Task NoPackLookupStillReportsNotInPack()
    {
        var h = Make(Repeat("Lower the sails!", 2), new FakeTranslator());
        await h.Frames(2, 100);
        Assert.Equal(["TR: Lower the sails!"], h.Output.Texts);
        Assert.Equal(["Lower the sails!"], h.NotInPack);
    }

    [Fact]
    public async Task PackLineBeatsHeldLine()
    {
        var t = new PendingTranslator();
        var h = Make(Of(Repeat("Untie the rope", 2), Repeat("Lower the sails!", 2)), t, LowerSails());
        await h.Frames(4, 100, waitTranslations: false);
        Assert.Equal(["Yelkenleri indir!"], h.Output.Texts);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["Yelkenleri indir!"], h.Output.Texts);
    }

    [Theory]
    [InlineData("We made it to port.", "port.")]
    [InlineData("Then the guard fainted.", "fainted")]
    [InlineData("Come on, hurry up, hurry up!", "hurry up!")]
    public async Task PackFragmentDoesNotWin(string full, string fragment)
    {
        var t = new PendingTranslator();
        var pack = new FakePack().Add(fragment, "Parça çevirisi");
        var h = Make(Of(Repeat(full, 4), Repeat(fragment, 4)), t, pack, score: s => s.Length, misreadWait: 0, partialWait: 0);
        await h.Frames(8, 100, waitTranslations: false);
        Assert.Empty(h.Output.Texts);
        h.Clock.Advance(3000);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["TR: " + full], h.Output.Texts);
        Assert.Equal([full], t.Requests);
        Assert.Equal(0, h.Pipeline.PackHits);
    }

    [Fact]
    public async Task FragmentDoesNotExtendWait()
    {
        var t = new FakeTranslator();
        const string port = "We made it to port.";
        var pack = new FakePack().Add("port.", "Liman");
        var h = Make(Of(Repeat(port, 4), Repeat("port.", 8)), t, pack, misread: s => s == port, score: s => s.Length);
        h.Clock.NowMs = 100;
        for (var i = 0; i < 9; i++) await h.Frame(100);
        Assert.Equal([port], t.Requests);
        await h.Frames(3, 100);
        Assert.Equal([port], t.Requests);
        Assert.Equal(["TR: " + port], h.Output.Texts);
    }

    [Theory]
    [InlineData("I swear, you crack me up!", "You crack me up!", 0)]
    [InlineData("We made it to port.", "port.", 12)]
    [InlineData("Then the guard fainted.", "Lower the sails!", 0)]
    [InlineData("We got three ropes.", "We got one rope.", 0)]
    public async Task NextLineFromPack(string full, string next, int gap)
    {
        var t = new FakeTranslator();
        var pack = new FakePack().Add(next, "Yeni replik");
        var h = Make(Of(Repeat(full, 4), Repeat("", gap), Repeat(next, 4)), t, pack, score: s => s.Length, misreadWait: 0,
            partialWait: 0);
        await h.Frames(4 + gap + 2, 100);
        Assert.Equal("Yeni replik", h.Output.Texts.Last());
        await h.Frames(2, 100);
        Assert.DoesNotContain(next, t.Requests);
    }

    const string Full = "Wait, sailing across the sea, chasing old maps? Honestly, that is madness.";
    const string Short = "Wait, sailing across the sea, chasing old maps?";

    static Harness Queueing(string[] script, PendingTranslator t) =>
        Make(script, t, holdWithoutPack: true, misreadWait: 0, partialWait: 0);

    [Fact]
    public async Task FullReadNeverLost()
    {
        // "TR: " + uzun cümle kaynağa 0,90'dan çok benzer ("zaten hedef dilde"); bu yüzden farklı bir çeviri.
        var t = new PendingTranslator { Map = s => "Çeviri " + s.Length };
        var h = Queueing(["Untie the rope.", Full, Short], t);
        await h.Frames(3, 100, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Contains(Full, t.Requests);
        Assert.Contains("Çeviri " + Full.Length, h.Output.Texts);

        var t2 = new PendingTranslator();
        var h2 = Queueing(["Untie the rope.", Full, Short, Full], t2);
        await h2.Frames(4, 100, waitTranslations: false);
        t2.Open();
        await h2.WaitAll();
        Assert.Equal(["Untie the rope.", Full], t2.Requests);
    }

    [Theory]
    [InlineData("Hide! Stay here.", "Hide!")]
    [InlineData("I swear, you crack me up!", "You crack me up!")]
    [InlineData("Keep the fire lit until I return.", "Lower the sails!")]
    public async Task SeparateShortLinesBothQueued(string first, string second)
    {
        var t = new PendingTranslator();
        var h = Queueing(["Untie the rope.", first, second], t);
        await h.Frames(3, 100, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["Untie the rope.", first, second], t.Requests);
    }

    [Theory]
    [InlineData("We got 3 hours left.", "We got 1 hour left.")]
    [InlineData("Be at the gate at 07:15.", "Be at the gate at 07:25.")]
    [InlineData("I can open that gate for you yet.", "I can't open that gate for you yet.")]
    [InlineData("We got room to spare.", "We got no room to spare.")]
    [InlineData("We can not stay...", "We can not stay here.")]
    public async Task CorrectionReplacesQueued(string first, string fix)
    {
        var t = new PendingTranslator();
        var h = Queueing(["Untie the rope.", first, fix], t);
        await h.Frames(3, 100, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["Untie the rope.", fix], t.Requests);
    }

    [Fact]
    public async Task FullReturnsAfterManyShortReads()
    {
        var t = new PendingTranslator();
        var h = Queueing(Of("Untie the rope.", Full, Repeat(Short, 18), Full), t);
        await h.Frames(21, 100, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["Untie the rope.", Full], t.Requests);
    }

    [Fact]
    public async Task RealGapKeepsShortRead()
    {
        var t = new PendingTranslator();
        var h = Queueing(Of("Untie the rope.", Full, Short, Repeat("", 12), Full), t);
        await h.Frames(16, 100, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["Untie the rope.", Full, Short], t.Requests);
    }
}
