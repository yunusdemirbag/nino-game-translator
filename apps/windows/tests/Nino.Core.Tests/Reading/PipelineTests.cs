// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Translation;
using static Nino.Core.Tests.Reading.Script;

namespace Nino.Core.Tests.Reading;

public class PipelineTests
{
    const string Hold = "Untie the rope";
    const string HoldP = "Untie the rope.";

    [Fact]
    public async Task StableLineShownOnce()
    {
        var h = new Harness(new SequenceReader(Repeat(Hold, 3)), new FakeTranslator());
        await h.Frames(3);
        Assert.Equal(["TR: Untie the rope"], h.Output.Texts);
        Assert.Equal(Hold, h.Pipeline.LastPair!.Value.Source);
    }

    [Fact]
    public async Task ReadsOffCallerThread()
    {
        var reader = new SequenceReader(Hold);
        var h = new Harness(reader, new FakeTranslator());
        var callerThread = Environment.CurrentManagedThreadId;
        await h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        Assert.NotEqual(callerThread, reader.Threads.Single());
    }

    [Fact]
    public async Task TranslatorStatusIsLastError()
    {
        var h = new Harness(new SequenceReader(Repeat(Hold, 2)), new FakeTranslator { FailReason = UnavailableReason.DownloadRequired });
        await h.Frames(2);
        Assert.Empty(h.Output.Texts);
        Assert.Equal(UnavailableReason.DownloadRequired, h.Pipeline.LastError);
        Assert.Equal((false, (UnavailableReason?)UnavailableReason.DownloadRequired), h.Results.Last());
    }

    [Fact]
    public async Task RetriedWhileOnScreen()
    {
        var h = new Harness(new SequenceReader(Repeat(Hold, 25)), new FakeTranslator { TimeoutsFirst = 1 });
        await h.Frames(25);
        Assert.Equal(["TR: Untie the rope"], h.Output.Texts);
        Assert.Null(h.Pipeline.LastError);
    }

    [Fact]
    public async Task FailingTranslatorAtMostOncePerSecond()
    {
        var t = new FakeTranslator { FailReason = UnavailableReason.DownloadRequired };
        var h = new Harness(new SequenceReader(Repeat(Hold, 40)), t);
        await h.Frames(40);
        Assert.InRange(t.Requests.Count, 2, 3);
    }

    [Fact]
    public async Task ShortGapsDoNotClear()
    {
        var t = new FakeTranslator();
        var h = new Harness(new SequenceReader(Of(Repeat(Hold, 2), Repeat("", 2), Hold)), t);
        await h.Frames(5);
        Assert.Equal(0, h.Output.Clears);
        Assert.Single(h.Output.Texts);

        var t2 = new FakeTranslator();
        var h2 = new Harness(new SequenceReader(Of(Repeat(Hold, 3), Repeat("", 15), Repeat(Hold, 3), Repeat("", 10), Repeat(Hold, 3))), t2);
        await h2.Frames(34);
        Assert.Equal(0, h2.Output.Clears);
        Assert.Single(h2.Output.Texts);
        Assert.Single(t2.Requests);
    }

    [Fact]
    public async Task ClearsAfterEighteenFrames()
    {
        var h = new Harness(new SequenceReader(Of(Repeat(Hold, 2), Repeat("", 17))), new FakeTranslator());
        await h.Frames(18);
        Assert.Equal(0, h.Output.Clears);
        await h.Frames(1);
        Assert.Equal(1, h.Output.Clears);
    }

    [Fact]
    public async Task RestoredLineReshownWithoutNewRequest()
    {
        var t = new FakeTranslator();
        var h = new Harness(new SequenceReader(Of(Repeat(HoldP, 2), Repeat("", 20), Repeat(HoldP, 2))), t);
        await h.Frames(24);
        Assert.Equal(1, h.Output.Clears);
        Assert.Equal(["TR: Untie the rope.", "TR: Untie the rope."], h.Output.Texts);
        Assert.All(h.Output.Shows, s => Assert.Equal(15_000, s.DurationMs));
        Assert.Single(t.Requests);
        Assert.Single(h.Pairs);
    }

    [Fact]
    public async Task LongGapRetranslates()
    {
        var t = new FakeTranslator();
        var h = new Harness(new SequenceReader(Of(Repeat(HoldP, 2), Repeat("", 50), Repeat(HoldP, 2))), t);
        await h.Frames(54);
        Assert.Equal(2, t.Requests.Count);
    }

    [Fact]
    public async Task LongerAndShorterBothShown()
    {
        var h = new Harness(new SequenceReader(Of(Repeat("Who sent you here, stranger?", 3), Repeat("Who sent you here?", 3))),
            new FakeTranslator());
        await h.Frames(6);
        Assert.Equal(["TR: Who sent you here, stranger?", "TR: Who sent you here?"], h.Output.Texts);
    }

    [Fact]
    public async Task PendingTranslatorQueuesInOrder()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(Hold, Hold, "Run", "Run"), t);
        await h.Frames(4, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Equal([Hold, "Run"], t.Requests);
    }

    [Fact]
    public async Task ReleasedOneByOne()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(HoldP, "Run!", "Lower the sails!"), t);
        await h.Frames(3, waitTranslations: false);
        for (var i = 0; i < 3; i++)
        {
            await WaitPending(t);
            t.ReleaseNext();
        }
        await h.WaitAll();
        Assert.Equal([HoldP, "Run!", "Lower the sails!"], t.Requests);
        Assert.Equal(["TR: Untie the rope.", "TR: Run!", "TR: Lower the sails!"], h.Output.Texts);
    }

    static async Task WaitPending(PendingTranslator t)
    {
        for (var i = 0; i < 3000 && t.PendingCount == 0; i++) await Task.Delay(1);
    }

    [Fact]
    public async Task QueueKeepsTwo()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(HoldP, "Run!", "Lower the sails!", "Now!"), t);
        await h.Frames(4, waitTranslations: false);
        t.Open();
        await h.WaitAll();
        Assert.Equal([HoldP, "Lower the sails!", "Now!"], t.Requests);
    }

    [Fact]
    public async Task RemovedLinesShortDuration()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(HoldP, "Run!", "Lower the sails!"), t);
        await h.Frames(3, waitTranslations: false);
        h.Clock.Advance(2000);
        for (var i = 0; i < 3; i++)
        {
            await WaitPending(t);
            t.ReleaseNext();
        }
        await h.WaitAll();
        Assert.Equal([SubtitlePipeline.RemovedDurationMs("TR: Untie the rope."), SubtitlePipeline.RemovedDurationMs("TR: Run!"), 15_000],
            h.Output.Shows.Select(s => s.DurationMs));
    }

    [Fact]
    public async Task ExtensionReplacesRunning()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader("Row to", "Row to", "Row to the dock!", "Row to the dock!"), t);
        await h.Frames(4, waitTranslations: false);
        await WaitPending(t);
        t.ReleaseNext();
        await h.WaitAll();
        Assert.Equal(["Row to", "Row to the dock!"], t.Requests);
        Assert.Equal(["TR: Row to the dock!"], h.Output.Texts);
    }

    [Fact]
    public async Task ReplaceFlags()
    {
        var h = new Harness(new SequenceReader("Row to", "Row to", "Row to the dock!", "Row to the dock!", "Lower the sails now!", "Lower the sails now!"),
            new FakeTranslator());
        await h.Frames(6);
        Assert.Equal(3, h.Output.Texts.Count);
        Assert.Equal([false, true, false], h.Output.Shows.Select(s => s.Replace));
    }

    [Fact]
    public async Task LateResultDropped()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(HoldP, "Run!"), t);
        await h.Frames(2, waitTranslations: false);
        h.Clock.Advance(2600);
        for (var i = 0; i < 2; i++)
        {
            await WaitPending(t);
            t.ReleaseNext();
        }
        await h.WaitAll();
        Assert.Equal(["TR: Run!"], h.Output.Texts);
    }

    [Fact]
    public async Task ClearedLineShownBriefly()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(Of(HoldP, Repeat("", 17))), t);
        await h.Frames(18, waitTranslations: false);
        Assert.Equal(1, h.Output.Clears);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["TR: Untie the rope."], h.Output.Texts);
        Assert.Equal(2000 + 19 * 60, h.Output.Shows[0].DurationMs);

        var t2 = new PendingTranslator();
        var h2 = new Harness(new SequenceReader(Of(HoldP, Repeat("", 17))), t2);
        await h2.Frames(18, waitTranslations: false);
        h2.Clock.Advance(2600);
        t2.Open();
        await h2.WaitAll();
        Assert.Empty(h2.Output.Texts);
    }

    [Fact]
    public async Task ResetDropsPending()
    {
        var t = new PendingTranslator();
        var h = new Harness(new SequenceReader(Hold, Hold), t);
        await h.Frames(2, waitTranslations: false);
        h.Pipeline.Reset();
        t.Open();
        await h.WaitAll();
        Assert.Empty(h.Output.Texts);
    }

    [Fact]
    public async Task ResetDuringReadDiscardsIt()
    {
        var reader = new BlockingReader(HoldP);
        var t = new FakeTranslator();
        var h = new Harness(reader, t);
        var frame = h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        Assert.True(reader.Entered.Wait(TimeSpan.FromSeconds(10)));
        h.Pipeline.Reset();
        reader.Release.Set();
        await frame;
        await h.WaitAll();
        Assert.Empty(t.Requests);
        Assert.Empty(h.Output.Texts);

        var reader2 = new BlockingReader(HoldP);
        var t2 = new FakeTranslator();
        var h2 = new Harness(reader2, t2);
        var frame2 = h2.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        Assert.True(reader2.Entered.Wait(TimeSpan.FromSeconds(10)));
        reader2.Release.Set();
        await frame2;
        await h2.WaitAll();
        Assert.Equal([HoldP], t2.Requests);
    }

    [Fact]
    public async Task BoxPlacedAndCentered()
    {
        var reader = new FuncReader(_ => new OcrReading([new OcrLine(HoldP, new Box(0.25, 0.5, 0.75, 0.6))]));
        var h = new Harness(reader, new FakeTranslator());
        await h.Frame(area: new Box(0.1, 0.6, 0.9, 1.0));
        var b = h.Output.Shows.Single().Box!.Value;
        Assert.Equal(0.3, b.Left, 6);
        Assert.Equal(0.8, b.Top, 6);
        Assert.Equal(0.7, b.Right, 6);
        Assert.Equal(0.84, b.Bottom, 6);
    }

    [Fact]
    public async Task LogEntries()
    {
        var pack = new FakePack("mafia").Add("Run!", "Koş!");
        var h = new Harness(new SequenceReader(HoldP, HoldP, "Run!", "Run!"), new FakeTranslator(), pack: pack);
        await h.Frames(4);
        h.Pipeline.Reset();
        Assert.Equal(["TR: Untie the rope.", "Koş!"], h.Output.Texts);
        Assert.Equal(6, h.Log.Count);
        Assert.StartsWith("ilk kare", h.Log[0]);
        Assert.StartsWith("ilk yazı", h.Log[1]);
        Assert.EndsWith("\"Untie the rope.\"", h.Log[1]);
        Assert.Contains("#1", h.Log[2]);
        Assert.Contains("\"Untie the rope.\"", h.Log[2]);
        Assert.Contains("çeviriye", h.Log[2]);
        Assert.Contains("#1 çeviri:fake", h.Log[3]);
        Assert.Contains("gösterildi", h.Log[3]);
        Assert.Contains("#2 \"Run!\" paket mafia", h.Log[4]);
        Assert.Contains("sıfırlandı", h.Log[5]);
        Assert.Contains("1 satır", h.Log[5]);
    }

    [Fact]
    public async Task OriginFromTranslator()
    {
        var cached = new Harness(new SequenceReader(HoldP), new FakeTranslator { FromCache = true });
        await cached.Frames(1);
        Assert.Contains(cached.Log, l => l.Contains("#1 önbellek"));
        var fresh = new Harness(new SequenceReader(HoldP), new FakeTranslator());
        await fresh.Frames(1);
        Assert.Contains(fresh.Log, l => l.Contains("#1 çeviri:fake"));
    }

    [Fact]
    public async Task HintsAndDirectionsNeverSent()
    {
        var t = new FakeTranslator();
        var h = new Harness(new SequenceReader("R2 Swing", "R2 Swing", "Untie the rope\nR2 Swing", "Untie the rope\nR2 Swing"), t);
        await h.Frames(4);
        Assert.Equal(["TR: Untie the rope"], h.Output.Texts);

        var t2 = new FakeTranslator();
        var h2 = new Harness(new SequenceReader("Turn Right 260 ft 318 ft", "Turn Right 260 ft 318 ft",
            "Why are we stopping?\nKeep Right O ft 7 ft", "Why are we stopping?\nKeep Right O ft 7 ft"), t2);
        await h2.Frames(4);
        Assert.Equal(["TR: Why are we stopping?"], h2.Output.Texts);
        Assert.DoesNotContain(t2.Requests, r => r.Contains("ft"));
    }

    [Fact]
    public async Task GiantSignSkippedAndLoggedOnce()
    {
        var reader = new FuncReader(_ => new OcrReading([new OcrLine("Welcome to Leonida", new Box(0.1, 0.05, 0.9, 0.45)),
            new OcrLine(HoldP, new Box(0.1, 0.8, 0.9, 0.9))]));
        var t = new FakeTranslator();
        var h = new Harness(reader, t);
        await h.Frames(3, waitTranslations: true);
        Assert.DoesNotContain(t.Requests, r => r.Contains("Leonida"));
        Assert.Single(h.Log, l => l.StartsWith("dev yazı") && l.Contains("\"Welcome to Leonida\""));
    }

    [Fact]
    public async Task PretranslatesBeforeStable()
    {
        var t = new FakeTranslator { Pretranslates = true };
        var h = new Harness(new SequenceReader("ARTHUR: We need to", "ARTHUR: We need to"), t);
        await h.Frames(1);
        Assert.Equal(["We need to"], t.Pretranslated);
    }
}
