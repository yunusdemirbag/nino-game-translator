// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Translation;
using static Nino.Core.Tests.Reading.Script;

namespace Nino.Core.Tests.Reading;

/// <summary>Bırakma, havuz, ölçüm ve parlak zemin örnekleri.</summary>
public class PipelineReleaseTests
{
    const string Old = "Untie the rope.";
    const string New = "Run!";

    static (Harness H, SequenceReader R) Make(PendingTranslator t, ISubtitlePackLookup? pack = null, int partialWait = 300)
    {
        var reader = new SequenceReader();
        var h = new Harness(reader, t, new ManualMsClock(0), o => new SubtitlePipelineOptions
        {
            Pack = o.Pack,
            Log = o.Log,
            PartialWaitMs = partialWait,
        }, pack);
        return (h, reader);
    }

    static async Task At(Harness h, SequenceReader r, long time, string text)
    {
        h.Clock.NowMs = time;
        r.Push(text);
        await h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
    }

    // İptal çevirmen çağrıldıktan sonra kaydolur; pompa iş parçacığı geç başlayabilir.
    static async Task Eventually(Func<bool> condition)
    {
        for (var i = 0; i < 5000 && !condition(); i++) await Task.Delay(1);
        Assert.True(condition());
    }

    static async Task Settle(PendingTranslator t)
    {
        for (var i = 0; i < 200; i++) await Task.Delay(1);
    }

    [Fact]
    public async Task ExpiredRunningReleasedWhenNewLineWaits()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, 2601, New);
        await Eventually(() => t.CancelRequested == 1);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["TR: Run!"], h.Output.Texts);
        Assert.Null(h.Pipeline.LastError);
    }

    [Theory]
    [InlineData(2100)]
    [InlineData(2600)]
    public async Task NotYetExpired(long second)
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, second, New);
        Assert.Equal(0, t.CancelRequested);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["TR: Untie the rope.", "TR: Run!"], h.Output.Texts);
    }

    [Fact]
    public async Task OnScreenLineNeverReleased()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 10_000, Old);
        Assert.Equal(0, t.CancelRequested);
    }

    [Fact]
    public async Task ReturningOldLineKept()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, 1000, Old);
        Assert.Equal(0, t.CancelRequested);
        t.Open();
        await h.WaitAll();
        Assert.Contains("TR: Untie the rope.", h.Output.Texts);
    }

    [Fact]
    public async Task NoWaitingLineNoRelease()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        for (var time = 100; time <= 2000; time += 100) await At(h, r, time, "");
        await At(h, r, 10_000, "");
        Assert.Equal(0, t.CancelRequested);

        var t2 = new PendingTranslator();
        var (h2, r2) = Make(t2);
        await At(h2, r2, 0, Old);
        await At(h2, r2, 100, New);
        for (var time = 200; time <= 2000; time += 100) await At(h2, r2, time, "");
        await At(h2, r2, 10_000, "");
        Assert.Equal(0, t2.CancelRequested);
    }

    [Fact]
    public async Task DeafTranslatorStillOneCallAtATime()
    {
        var t = new PendingTranslator(honorsCancel: false);
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, 3000, New);
        await Eventually(() => t.CancelRequested == 1);
        await Settle(t);
        Assert.Equal([Old], t.Requests);
        t.Open();
        await h.WaitAll();
        Assert.Equal([Old, New], t.Requests);
        Assert.Equal(["TR: Run!"], h.Output.Texts);
    }

    [Fact]
    public async Task PackLinePassesRunning()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t, new FakePack().Add(New, "Koş!"), partialWait: 0);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await Eventually(() => t.CancelRequested == 1);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["Koş!"], h.Output.Texts);
        Assert.Null(h.Pipeline.LastError);
    }

    [Fact]
    public async Task OldLineReturnsAfterRelease()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, 2700, New);
        await At(h, r, 2800, Old);
        t.Open();
        await h.WaitAll();
        Assert.Equal([Old, New, Old], t.Requests);
        Assert.Equal(["TR: Run!", "TR: Untie the rope."], h.Output.Texts);
    }

    [Fact]
    public async Task OldLineReturnsAfterPackLine()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t, new FakePack().Add(New, "Koş!"));
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, 200, Old);
        t.Open();
        await h.WaitAll();
        Assert.Equal([Old, Old], t.Requests);
        Assert.Equal(["Koş!", "TR: Untie the rope."], h.Output.Texts);
    }

    [Fact]
    public async Task SameLanguagePackLineDoesNotRelease()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t, new FakePack().Add("İpi çöz!", "İpi çöz!"));
        await At(h, r, 0, Old);
        await At(h, r, 100, "İpi çöz!");
        Assert.Empty(h.Output.Texts);
        Assert.Equal(0, t.CancelRequested);
        t.Open();
        await h.WaitAll();
        Assert.Equal(["TR: Untie the rope."], h.Output.Texts);
    }

    [Fact]
    public async Task PackSameAsSourceWithoutTurkishShown()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t, new FakePack().Add(New, New));
        await At(h, r, 0, New);
        Assert.Equal(["Run!"], h.Output.Texts);
    }

    sealed class LatePack : ISubtitlePackLookup
    {
        public volatile bool Ready;
        public PackMatch? Find(string text) => Ready && TextKey.Of(text) == "lower the sails" ? new PackMatch("Yelkenleri indir!") : null;
    }

    [Fact]
    public async Task PackReadyWhileHeld()
    {
        var t = new PendingTranslator();
        var pack = new LatePack();
        var (h, r) = Make(t, pack);
        await At(h, r, 0, Old);
        await At(h, r, 100, "Lower the sails");
        await At(h, r, 150, "Lower the sails");
        pack.Ready = true;
        await At(h, r, 200, "Lower the sails");
        Assert.Equal(["Yelkenleri indir!"], h.Output.Texts);
        await Eventually(() => t.CancelRequested == 1);
        await At(h, r, 250, Old);
        t.Open();
        await h.WaitAll();
        Assert.Equal([Old, Old], t.Requests);
        Assert.Equal(["Yelkenleri indir!", "TR: Untie the rope."], h.Output.Texts);
    }

    [Fact]
    public async Task CancelCallbackRunsOutsideLock()
    {
        var translator = new LockProbeTranslator(null);
        var reader = new SequenceReader();
        var harness = new Harness(reader, translator, new ManualMsClock(0), o => new SubtitlePipelineOptions { Log = o.Log });
        translator.Harness = harness;
        harness.Clock.NowMs = 0;
        reader.Push(Old);
        await harness.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        harness.Clock.NowMs = 100;
        reader.Push(New);
        await harness.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        for (var i = 0; i < 5000 && translator.Calls == 0; i++) await Task.Delay(1);
        harness.Clock.NowMs = 2601;
        reader.Push(New);
        await harness.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        for (var i = 0; i < 5000 && translator.LockHeldInCallback is null; i++) await Task.Delay(1);
        Assert.False(translator.LockHeldInCallback);
        Assert.NotNull(translator.WaitFromCallback);
        translator.Open();
        await harness.WaitAll();
        Assert.Equal(["TR: Run!"], harness.Output.Texts);
    }

    sealed class LockProbeTranslator(Harness? harness) : ITranslator
    {
        readonly PendingTranslator _inner = new();
        public Harness? Harness { get; set; } = harness;
        public bool? LockHeldInCallback;
        public Task? WaitFromCallback;
        public volatile int Calls;

        public string EngineName => "probe";
        public bool SupportsPretranslation => false;
        public bool SupportsBatch => false;
        public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
            this.TranslateOneByOneAsync(texts, cancellationToken);

        public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellation = default)
        {
            Calls++;
            cancellation.Register(() =>
            {
                LockHeldInCallback = Harness!.Pipeline.LockHeldByCurrentThread;
                WaitFromCallback = Harness.Pipeline.WaitForTranslationsAsync();
            });
            return _inner.TranslateAsync(text, cancellation);
        }

        public void Open() => _inner.Open();
    }

    [Fact]
    public async Task ReleasedFailureIsSilent()
    {
        var t = new PendingTranslator(honorsCancel: false) { FailWith = s => s == Old ? new TimeoutException() : null };
        var (h, r) = Make(t);
        await At(h, r, 0, Old);
        await At(h, r, 100, New);
        await At(h, r, 3000, New);
        t.Open();
        await h.WaitAll();
        Assert.Null(h.Pipeline.LastError);
        Assert.Equal(["TR: Run!"], h.Output.Texts);
        Assert.Equal([(true, (UnavailableReason?)null)], h.Results);
    }

    [Fact]
    public async Task ShowingOldNotReleasedByNew()
    {
        var t = new PendingTranslator();
        var (h, r) = Make(t);
        var gate = new ManualResetEventSlim();
        var entered = new ManualResetEventSlim();
        h.Pipeline.PairShown += p =>
        {
            if (p.Source != Old) return;
            entered.Set();
            gate.Wait(TimeSpan.FromSeconds(10));
        };
        await At(h, r, 0, Old);
        t.Open();
        Assert.True(entered.Wait(TimeSpan.FromSeconds(10)));
        await At(h, r, 2700, New);
        gate.Set();
        await h.WaitAll();
        Assert.Equal(["TR: Untie the rope.", "TR: Run!"], h.Output.Texts);
    }

    [Fact]
    public async Task PoolUpgradeReplacesShownLine()
    {
        var h = new Harness(new SequenceReader(Repeat("Untie the rope", 8)), new FakeTranslator(), pack: new FakePack());
        await h.Frames(4, 150);
        Assert.Equal(["TR: Untie the rope"], h.Output.Texts);
        h.Pipeline.OnBetterTranslation("Untie the rope", "İpi çöz");
        Assert.Equal(["TR: Untie the rope", "İpi çöz"], h.Output.Texts);
        Assert.True(h.Output.Shows.Last().Replace);
        Assert.Equal(ShownOrigin.Pool, h.Pipeline.LastOrigin);
        Assert.Equal(("Untie the rope", "İpi çöz"), h.Pipeline.LastPair);
        Assert.Equal(("Untie the rope", "İpi çöz"), (h.Pairs.Last().Source, h.Pairs.Last().Translation));
        h.Pipeline.OnBetterTranslation("Untie the rope", "İpi çöz");
        Assert.Equal(2, h.Output.Texts.Count);
    }

    [Fact]
    public async Task PoolUpgradeOnlyRememberedWhenGone()
    {
        var h = new Harness(new SequenceReader(Of(Repeat("Untie the rope", 4), Repeat("", 20))), new FakeTranslator(), pack: new FakePack());
        await h.Frames(24, 150);
        h.Pipeline.OnBetterTranslation("Untie the rope", "İpi çöz");
        Assert.Equal(["TR: Untie the rope"], h.Output.Texts);
        Assert.Equal(ShownOrigin.Engine, h.Pipeline.LastOrigin);

        var h2 = new Harness(new SequenceReader(Of(Repeat("Untie the rope", 4), Repeat("Climb the north wall", 4))), new FakeTranslator(),
            pack: new FakePack());
        await h2.Frames(8, 150);
        var before = h2.Output.Texts.Count;
        h2.Pipeline.OnBetterTranslation("Untie the rope", "İpi çöz");
        Assert.Equal(before, h2.Output.Texts.Count);

        var h3 = new Harness(new SequenceReader(Repeat("Lower the sails!", 3)), new FakeTranslator(), pack: new FakePack().Add("Lower the sails", "Yelkenleri indir!"));
        await h3.Frames(3, 150);
        h3.Pipeline.OnBetterTranslation("Lower the sails!", "Eğil!");
        Assert.Equal(["Yelkenleri indir!"], h3.Output.Texts);
        Assert.Equal(ShownOrigin.Pack, h3.Pipeline.LastOrigin);
    }

    sealed class TimedReader(ManualMsClock clock, long ms, Func<OcrReading> read) : ITextReader
    {
        public string ReadText(BgraFrame image) => ReadLines(image, false).Text;

        public OcrReading ReadLines(BgraFrame image, bool deep)
        {
            clock.Advance(ms);
            return read();
        }
    }

    [Fact]
    public async Task MeasuresRealTimes()
    {
        var clock = new ManualMsClock(1000);
        var t = new FakeTranslator(clock, 300);
        var h = new Harness(new TimedReader(clock, 40, () => OcrReading.FromText("Untie the rope")), t, clock);
        for (var i = 0; i < 3; i++)
        {
            clock.Advance(50);
            await h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea, clock.NowMs);
            await h.WaitAll();
        }
        var m = Assert.Single(h.Metrics);
        Assert.Equal(ShownOrigin.Engine, m.Origin);
        Assert.Equal(40, m.OcrMs);
        Assert.Equal(300, m.TranslationMs);
        Assert.Equal(340, m.TotalMs);
        Assert.Null(m.ConfidencePercent);
        Assert.Equal(m, h.Pipeline.LastMetrics);
    }

    [Fact]
    public async Task QueueDelayCountsInTotal()
    {
        // Karenin gelişiyle hatta verilişi arasında 180 ms (kuyruk); okuma 40, çeviri 300 → toplam 520.
        var clock = new ManualMsClock(1000);
        var h = new Harness(new TimedReader(clock, 40, () => OcrReading.FromText("Untie the rope")), new FakeTranslator(clock, 300), clock);
        for (var i = 0; i < 3; i++)
        {
            clock.Advance(50);
            var arrived = clock.NowMs;
            clock.Advance(180);
            await h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea, arrived);
            await h.WaitAll();
        }
        var m = Assert.Single(h.Metrics);
        Assert.Equal((40L, 300L, 520L), (m.OcrMs!.Value, m.TranslationMs!.Value, m.TotalMs!.Value));
    }

    [Fact]
    public async Task MeasuresPackLine()
    {
        var clock = new ManualMsClock(1000);
        var h = new Harness(new TimedReader(clock, 25, () => OcrReading.FromText("Lower the sails!")), new FakeTranslator(), clock,
            pack: new FakePack().Add("Lower the sails", "Yelkenleri indir!"));
        var order = new List<string>();
        h.Pipeline.MetricsReady += _ => order.Add("ölçüm");
        h.Pipeline.PairShown += _ => order.Add("çift");
        for (var i = 0; i < 3; i++)
        {
            clock.Advance(50);
            await h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea, clock.NowMs);
        }
        var m = Assert.Single(h.Metrics);
        Assert.Equal(new SubtitleMetrics(25, null, 25, null, ShownOrigin.Pack), m);
        Assert.Equal([MetricPartKind.Ocr, MetricPartKind.FromPack, MetricPartKind.Latency], m.Parts().Select(p => p.Kind));
        Assert.Equal(["ölçüm", "çift"], order);
    }

    [Fact]
    public async Task ConfidenceFromBoxlessLine()
    {
        var h = new Harness(new FuncReader(_ => new OcrReading([new OcrLine("Untie the rope.", null, 0.91)])), new FakeTranslator());
        await h.Frames(1);
        Assert.Equal(91, h.Metrics.Single().ConfidencePercent);
    }

    [Fact]
    public async Task TotalWithoutArrivalUsesProcessingStart()
    {
        var clock = new ManualMsClock(1000);
        var h = new Harness(new TimedReader(clock, 40, () => OcrReading.FromText("Untie the rope.")), new FakeTranslator(clock, 300), clock);
        await h.Pipeline.ProcessFrameAsync(Harness.Blank, Harness.DefaultArea);
        await h.WaitAll();
        Assert.Equal(340, h.Metrics.Single().TotalMs);
    }

    // Parlak zemin: 640 × 360, her yeri 230; altyazı varken alanın (0,3, 0,6, 0,7, 0,8) kısmı 2 piksel 255 / 2 piksel 0 çizgili.
    static BgraFrame Bright(bool subtitle, byte topBrightness = 230)
    {
        var f = BgraFrame.Filled(640, 360, 230);
        var area = Harness.DefaultArea;
        for (var y = 0; y < (int)(360 * 0.4); y++)
            for (var x = 0; x < 640; x++) f.SetPixel(x, y, topBrightness, topBrightness, topBrightness);
        if (!subtitle) return f;
        var spot = new Box(0.3, 0.6, 0.7, 0.8).PlaceIn(area);
        for (var y = (int)(spot.Top * 360); y < (int)(spot.Bottom * 360); y++)
            for (var x = (int)(spot.Left * 640); x < (int)(spot.Right * 640); x++)
            {
                var v = (byte)(x / 2 % 2 == 0 ? 255 : 0);
                f.SetPixel(x, y, v, v, v);
            }
        return f;
    }

    static Harness BrightHarness(FakeTranslator t, Func<bool> miss) =>
        new(new FuncReader(img => !miss() && img.Pixels.Contains((byte)0)
            ? new OcrReading([new OcrLine("Untie the rope.", new Box(0.3, 0.6, 0.7, 0.8))])
            : OcrReading.Empty), t, null, o => new SubtitlePipelineOptions { Log = o.Log, Plan = ReadPlan.ForApp(false) });

    [Fact]
    public async Task BrightBackgroundKeepsUnmovedLine()
    {
        var t = new FakeTranslator();
        var miss = false;
        var h = BrightHarness(t, () => miss);
        for (var i = 0; i < 3; i++) await h.Frame(frame: Bright(true));
        Assert.Equal(["TR: Untie the rope."], h.Output.Texts);
        miss = true;
        for (var i = 0; i < 40; i++) await h.Frame(frame: Bright(true, 120));
        Assert.Equal(0, h.Output.Clears);
        miss = false;
        for (var i = 0; i < 3; i++) await h.Frame(frame: Bright(true, 200));
        Assert.Equal(0, h.Output.Clears);
        Assert.Single(h.Output.Texts);
        Assert.Single(t.Requests);
    }

    [Fact]
    public async Task BrightBackgroundClearsWhenGone()
    {
        var t = new FakeTranslator();
        var h = BrightHarness(t, () => false);
        for (var i = 0; i < 3; i++) await h.Frame(frame: Bright(true));
        for (var i = 0; i < 16; i++) await h.Frame(frame: Bright(false));
        Assert.Equal(0, h.Output.Clears);
        await h.Frame(frame: Bright(false));
        Assert.Equal(1, h.Output.Clears);
    }
}
