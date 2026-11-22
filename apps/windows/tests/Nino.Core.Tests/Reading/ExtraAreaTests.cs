// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Translation;
using Nino.Core.Settings;

namespace Nino.Core.Tests.Reading;

public class ExtraAreaTests
{
    sealed class AreaReader : ITextReader
    {
        public (string Text, double Top, double Height)[] Lines = [];
        public int FailFirst;
        public int Reads;

        public string ReadText(BgraFrame image) => ReadLines(image, false).Text;

        public OcrReading ReadLines(BgraFrame image, bool deep)
        {
            Reads++;
            if (Reads <= FailFirst) throw new InvalidOperationException("okunamadı");
            return new OcrReading(Lines.Select(l => new OcrLine(l.Text, new Box(0.1, l.Top, 0.9, l.Top + l.Height))));
        }

        public void Set(params string[] texts) => Lines = texts.Select(t => (t, 0.2, 0.1)).ToArray();
    }

    sealed class AreaTranslator : FakeTranslator
    {
        public List<string> Calls { get; } = new();
        public int FailFirst;

        public override Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellation = default)
        {
            Calls.Add(text);
            if (Calls.Count <= FailFirst) throw new TimeoutException();
            return Task.FromResult(TranslationResult.FromEngine("TR: " + text));
        }
    }

    static BgraFrame Gray(byte tone) => BgraFrame.Filled(320, 180, tone);

    static readonly WatchedArea Quest = new("q", "Görev", Box.FromRegion(RegionPresets.ExtraQuest));
    static readonly WatchedArea Phone = new("p", "Telefon", Box.FromRegion(RegionPresets.ExtraPhone));

    readonly AreaReader _reader = new();
    readonly AreaTranslator _translator = new();
    readonly FakeOutput _tv = new();
    readonly ManualMsClock _clock = new(0);
    readonly ExtraAreaTracker _tracker;

    public ExtraAreaTests()
    {
        _tracker = new ExtraAreaTracker(_reader, _translator, _tv, _clock) { Areas = [Quest] };
    }

    List<string> Texts => _tv.Regions.Select(r => r.Text).ToList();

    Task Round(byte tone) => _tracker.RoundAsync(Gray(tone));

    [Fact]
    public async Task TranslatesWhenSettled()
    {
        _reader.Set("Locate the ferryman");
        await Round(10);
        Assert.Empty(_tv.Regions);
        await Round(10);
        Assert.Equal(["TR: Locate the ferryman"], Texts);
        var box = _tv.Regions[0].Box!.Value;
        var q = Quest.Region;
        Assert.True(box.Left >= q.Left && box.Right <= q.Right);
        await Round(10);
        await Round(10);
        Assert.Equal(1, _reader.Reads);
        Assert.Single(_translator.Calls);
        Assert.Single(_tv.Regions);
    }

    [Fact]
    public async Task MovedTextResentWithoutTranslation()
    {
        _reader.Set("Locate the ferryman");
        await Round(10);
        await Round(10);
        _reader.Lines = [("Locate the ferryman", 0.45, 0.2)];
        await Round(60);
        Assert.Equal(2, _tv.Regions.Count);
        Assert.Equal(_tv.Regions[0].Text, _tv.Regions[1].Text);
        Assert.NotEqual(_tv.Regions[0].Box!.Value.Top, _tv.Regions[1].Box!.Value.Top);
        Assert.NotEqual(_tv.Regions[0].Line, _tv.Regions[1].Line);
        Assert.Single(_translator.Calls);
    }

    [Fact]
    public async Task ChangesAndEmpties()
    {
        _reader.Set("Speak with Odile");
        await Round(10);
        await Round(10);
        _reader.Set("Meet Odile at the mill");
        await Round(90);
        await Round(90);
        _reader.Set();
        await Round(200);
        await Round(200);
        Assert.Equal(["TR: Speak with Odile", "TR: Meet Odile at the mill", ""], Texts);
    }

    [Fact]
    public async Task SameKeyTwiceIsEnough()
    {
        _reader.Set("Speak with Odile");
        foreach (var tone in new byte[] { 10, 60, 110, 160, 210 }) await Round(tone);
        Assert.Equal(5, _reader.Reads);
        Assert.Single(_translator.Calls);
        Assert.Single(_tv.Regions);
    }

    [Fact]
    public async Task HintsAndNumbersAreNotText()
    {
        _reader.Lines = [("R2 Swing", 0.2, 0.1), ("23m", 0.5, 0.1)];
        await Round(10);
        await Round(10);
        Assert.Empty(_tv.Regions);
    }

    [Fact]
    public async Task PackPartsAndTranslatedParts()
    {
        var tracker = new ExtraAreaTracker(_reader, _translator, _tv, _clock, new FakePack().Add("New message", "Yeni mesaj"))
        {
            Areas = [Quest],
        };
        _reader.Lines = [("New message", 0.1, 0.1), ("Ring me once you read this.", 0.25, 0.1)];
        await tracker.RoundAsync(Gray(10));
        await tracker.RoundAsync(Gray(10));
        Assert.Equal(["Yeni mesaj\nTR: Ring me once you read this."], Texts);
        Assert.Equal(["Ring me once you read this."], _translator.Calls);
    }

    [Fact]
    public async Task RemovedAreaClearedAndResetOnce()
    {
        _tracker.Areas = [Quest, Phone];
        _reader.Set("Who's out there?");
        await Round(10);
        await Round(10);
        Assert.Equal(["p", "q"], _tv.Regions.Select(r => r.Id).Order());
        _tracker.Areas = [Quest];
        await Round(10);
        Assert.Equal(("p", ""), (_tv.Regions[^1].Id, _tv.Regions[^1].Text));
        _tracker.Reset();
        Assert.Equal(1, _tv.RegionClears);
        _tracker.Reset();
        Assert.Equal(1, _tv.RegionClears);
    }

    [Fact]
    public async Task FailedTranslationRetried()
    {
        _reader.Set("Speak with Odile");
        await Round(10);
        await Round(10);
        _translator.FailFirst = 2;
        _reader.Set("Meet Odile at the mill");
        await Round(90);
        await Round(90);
        Assert.Equal(["TR: Speak with Odile"], Texts);
        await Round(90);
        Assert.Equal(["Speak with Odile", "Meet Odile at the mill", "Meet Odile at the mill"], _translator.Calls);
        Assert.Equal(["TR: Speak with Odile", "TR: Meet Odile at the mill"], Texts);
    }

    [Fact]
    public async Task ReadErrorIsNotEmpty()
    {
        _reader.FailFirst = 1;
        _reader.Set("Locate the ferryman");
        await Round(10);
        await Round(10);
        Assert.Empty(_tv.Regions);
        for (var i = 0; i < 4; i++) await Round(10);
        Assert.Equal(2, _reader.Reads);
        Assert.Single(_translator.Calls);
        Assert.Single(_tv.Regions);
    }

    [Fact]
    public async Task ReadErrorDropsCandidate()
    {
        _reader.Set("Speak with Odile");
        await Round(10);
        await Round(10);
        _reader.Set("Meet Odile at the mill");
        await Round(60);
        _reader.FailFirst = _reader.Reads + 1;
        await Round(100);
        _reader.Set("Locate the ferryman");
        await Round(100);
        Assert.Equal(["TR: Speak with Odile"], Texts);
        await Round(100);
        Assert.Equal(["Speak with Odile", "Locate the ferryman"], _translator.Calls);
        Assert.Equal(["TR: Speak with Odile", "TR: Locate the ferryman"], Texts);
    }

    [Fact]
    public async Task ErrorInOneAreaDoesNotBlockOther()
    {
        _tracker.Areas = [Quest, Phone];
        _reader.FailFirst = 1;
        _reader.Set("Who's out there?");
        await Round(10);
        await Round(10);
        Assert.Equal(["p"], _tv.Regions.Select(r => r.Id));
        await Round(10);
        Assert.Equal(["p", "q"], _tv.Regions.Select(r => r.Id));
        Assert.Equal(3, _reader.Reads);
    }

    [Fact]
    public async Task OfferedAtMostOncePerSecond()
    {
        _reader.Set("Locate the ferryman");
        for (var t = 0; t <= 900; t += 100)
        {
            _clock.NowMs = t;
            _tracker.Offer(Gray(10));
            await _tracker.WaitIdleAsync();
        }
        Assert.Equal(1, _tracker.Rounds);
        _clock.NowMs = 1000;
        _tracker.Offer(Gray(10));
        await _tracker.WaitIdleAsync();
        Assert.Equal(2, _tracker.Rounds);
        Assert.Equal(["TR: Locate the ferryman"], Texts);
    }

    [Fact]
    public async Task FailingReaderStillPaced()
    {
        _reader.FailFirst = 10;
        _reader.Set("Locate the ferryman");
        for (var t = 0; t <= 2000; t += 100)
        {
            _clock.NowMs = t;
            _tracker.Offer(Gray(10));
            await _tracker.WaitIdleAsync();
        }
        Assert.Equal(3, _tracker.Rounds);
        Assert.Equal(3, _reader.Reads);
        Assert.Empty(_tv.Regions);
    }

    [Fact]
    public void NoAreasNothingRuns()
    {
        _tracker.Areas = [];
        _tracker.Offer(Gray(10));
        Assert.False(_tracker.IsBusy);
        Assert.Equal(0, _reader.Reads);
    }

    [Fact]
    public void AreasFromSettings()
    {
        var s = new AppSettings { ExtraRegion1 = RegionPresets.ExtraQuest, ExtraLive1 = true, ExtraRegion2 = RegionPresets.ExtraPhone, ExtraLive3 = true };
        var areas = WatchedArea.FromSettings(s);
        Assert.Equal(["area1"], areas.Select(a => a.Id));
        Assert.Equal("Area 1", areas[0].Name);
    }
}

public class RegionAndScreenTests
{
    static OcrLine L(string text, double left, double top, double right, double height = 0.03) =>
        new(text, new Box(left, top, right, top + height));

    [Fact]
    public void Blocks()
    {
        Assert.Equal(["Locate the ferryman by the old stone bridge"],
            RegionTranslation.Blocks(OcrReading.FromText("Locate the ferryman by\nthe old stone bridge"), 400, 200).Select(b => b.Text));
        Assert.Equal(2, RegionTranslation.Blocks(OcrReading.FromText("Locate the ferryman.\nPay him two silver coins."), 400, 200).Count);
        var boxed = new OcrReading([new OcrLine("Active task", new Box(0, 0, 1, 0.10)),
            new OcrLine("Locate the ferryman", new Box(0, 0.30, 1, 0.40)), new OcrLine("by the bridge", new Box(0, 0.42, 1, 0.52))]);
        Assert.Equal(["Active task", "Locate the ferryman by the bridge"], RegionTranslation.Blocks(boxed, 400, 200).Select(b => b.Text));
        var bullets = RegionTranslation.Blocks(OcrReading.FromText("QUEST\n• Find the key\n◇ Open the door\no Leave"), 400, 200);
        Assert.Equal([false, true, true, true], bullets.Select(b => b.Bullet));
        Assert.Equal("Leave", bullets[3].Text);
        Assert.Equal(("Find", true), RegionTranslation.StripBullet("<> Find"));
    }

    static async Task<RegionTranslationResult?> Region(string[] lines, Box region, ITranslator? t = null, Box? lineBox = null) =>
        await RegionTranslation.TranslateAsync(BgraFrame.Blank(100, 100), region,
            new FuncReader(_ => lineBox is { } b ? new OcrReading(lines.Select(l => new OcrLine(l, b))) : OcrReading.FromText(string.Join("\n", lines))),
            t ?? new FakeTranslator());

    [Fact]
    public async Task RegionResults()
    {
        var whole = new Box(0, 0, 1, 1);
        Assert.Null(await Region([], whole));
        var hint = await Region(["R2 Swing", "Locate the ferryman."], whole);
        Assert.Equal("Locate the ferryman.", hint!.Source);
        Assert.Equal("TR: Locate the ferryman.", hint.Translation);
        var two = await Region(["Locate the ferryman.", "Pay him two silver coins."], whole);
        Assert.Equal("TR: Locate the ferryman.\nTR: Pay him two silver coins.", two!.Translation);
        Assert.True(two.Structured);
        var region = Box.FromRegion(new Region(0.1, 0.5, 0.5, 0.9));
        var placed = await Region(["Find it."], region, lineBox: new Box(0, 0, 1, 0.5));
        var pb = placed!.Box;
        Assert.Equal([0.5, 0.1, 0.9, 0.3], new[] { pb.Left, pb.Top, pb.Right, pb.Bottom }.Select(v => Math.Round(v, 9)));
        Assert.Equal(region, (await Region(["Find it."], region))!.Box);
        await Assert.ThrowsAsync<TranslatorUnavailableException>(() =>
            Region(["Find it."], whole, new FakeTranslator { FailReason = UnavailableReason.DownloadRequired }));
        Assert.Equal([6000, 11000, 25000], new[] { 5, 100, 5000 }.Select(RegionTranslation.DurationMs));
    }

    [Fact]
    public void ScreenGroups()
    {
        var g = ScreenTranslation.Group(new OcrReading([L("Locate the ferryman by", 0.05, 0.10, 0.30), L("the old stone bridge", 0.05, 0.135, 0.25),
            L("Pull the chain to raise the bridge.", 0.40, 0.85, 0.60), L("Reward collected", 0.75, 0.60, 0.95)]));
        Assert.Equal(3, g.Count);
        Assert.Equal(["Locate the ferryman by the old stone bridge"], g[0].Parts);
        Assert.Equal(0.05, g[0].Box.Left, 9);
        Assert.Equal(0.165, g[0].Box.Bottom, 9);
        Assert.Equal(0.03, g[0].LineHeight, 9);
        Assert.Equal(["Reward collected"], g[1].Parts);
        Assert.Equal(["Pull the chain to raise the bridge."], g[2].Parts);

        Assert.Equal(2, ScreenTranslation.Group(new OcrReading([L("Settings", 0.05, 0.05, 0.15), L("Return to title", 0.80, 0.05, 0.95)])).Count);
        var menu = ScreenTranslation.Group(new OcrReading([L("Map", 0.05, 0.30, 0.15), L("Inventory", 0.05, 0.34, 0.15),
            L("Settings", 0.05, 0.38, 0.15)]));
        Assert.Equal(["Map", "Inventory", "Settings"], Assert.Single(menu).Parts);
        var chapter = ScreenTranslation.Group(new OcrReading([L("Chapter One", 0.30, 0.20, 0.70, 0.08),
            L("The voyage starts at dawn.", 0.30, 0.29, 0.70)]));
        Assert.Equal(2, chapter.Count);
        Assert.Equal(0.08, chapter[0].LineHeight, 9);
    }

    static OcrLine[] Columns() =>
    [
        L("Locate the ferryman by", 0.05, 0.14, 0.43), L("the old stone bridge.", 0.05, 0.18, 0.40),
        L("Carry the lantern to", 0.57, 0.14, 0.95), L("the eastern tower.", 0.57, 0.18, 0.92),
    ];

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void ColumnsStaySeparate(bool reversed)
    {
        var lines = new List<OcrLine> { L("Open contracts", 0.05, 0.10, 0.95) };
        lines.AddRange(Columns());
        if (reversed) lines.Reverse();
        var g = ScreenTranslation.Group(new OcrReading(lines));
        Assert.Equal(3, g.Count);
        var header = g.Single(x => x.Parts[0] == "Open contracts");
        Assert.Equal(0.13, header.Box.Bottom, 9);
        var left = g.Single(x => x.Parts[0].StartsWith("Locate"));
        Assert.Equal(["Locate the ferryman by the old stone bridge."], left.Parts);
        Assert.True(left.Box.Right < 0.5);
        var right = g.Single(x => x.Parts[0].StartsWith("Carry"));
        Assert.Equal(["Carry the lantern to the eastern tower."], right.Parts);
        Assert.True(right.Box.Left > 0.5);

        var withFooter = Columns().ToList();
        withFooter.Add(L("Pick a route", 0.05, 0.22, 0.95));
        if (reversed) withFooter.Reverse();
        var f = ScreenTranslation.Group(new OcrReading(withFooter));
        Assert.Equal(3, f.Count);
        var footer = f.Single(x => x.Parts[0] == "Pick a route");
        Assert.Equal(0.22, footer.Box.Top, 9);
    }

    [Theory]
    [InlineData(0.05, 0.4)]
    [InlineData(0.30, 0.70)]
    [InlineData(0.60, 0.95)]
    public void ContinuationJoins(double left, double right)
    {
        var g = ScreenTranslation.Group(new OcrReading([L("Locate the ferryman by", 0.05, 0.10, 0.95), L("the old stone bridge.", left, 0.14, right)]));
        Assert.Equal(["Locate the ferryman by the old stone bridge."], Assert.Single(g).Parts);
    }

    [Fact]
    public void ObjectiveJoinsLeftColumn()
    {
        var lines = new List<OcrLine> { L("Active goal", 0.05, 0.10, 0.43) };
        lines.AddRange(Columns());
        var g = ScreenTranslation.Group(new OcrReading(lines));
        Assert.Equal(2, g.Count);
        Assert.Contains(g, x => x.Parts.SequenceEqual(["Active goal", "Locate the ferryman by the old stone bridge."]));
    }

    [Fact]
    public void DroppedHintsMakeNoColumn()
    {
        var g = ScreenTranslation.Group(new OcrReading([L("Locate the ferryman by", 0.05, 0.10, 0.95),
            L("the old stone bridge.", 0.05, 0.14, 0.43), L("R2 Swing", 0.57, 0.14, 0.95)]));
        Assert.Single(g);
        var hud = ScreenTranslation.Group(new OcrReading([L("23m", 0.1, 0.1, 0.2), L("9", 0.3, 0.1, 0.35),
            L("R2 Swing", 0.5, 0.5, 0.7), L("HP 120/300", 0.8, 0.8, 0.95)]));
        Assert.Equal(["HP 120/300"], Assert.Single(hud).Parts);
        Assert.Empty(ScreenTranslation.Group(OcrReading.FromText("Locate the ferryman.")));
    }

    sealed class NumberedTranslator : FakeTranslator
    {
        int _n;
        public override Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellation = default)
        {
            Requests.Enqueue(text);
            return Task.FromResult(TranslationResult.FromEngine("Çeviri sonucu " + Interlocked.Increment(ref _n)));
        }
    }

    [Fact]
    public async Task ScreenTranslatesInOrder()
    {
        var lines = new List<OcrLine> { L("Open contracts", 0.05, 0.10, 0.95) };
        lines.AddRange(Columns());
        var t = new NumberedTranslator();
        var items = await ScreenTranslation.TranslateAsync(ScreenTranslation.Group(new OcrReading(lines)), t);
        Assert.Equal(["Open contracts", "Locate the ferryman by the old stone bridge.", "Carry the lantern to the eastern tower."],
            items.Select(i => i.Source));
        Assert.Equal(items.Select(i => i.Source), t.Requests);
        Assert.Equal(["Çeviri sonucu 1", "Çeviri sonucu 2", "Çeviri sonucu 3"], items.Select(i => i.Text));
    }

    [Fact]
    public async Task ScreenProgressAndParagraphs()
    {
        var groups = ScreenTranslation.Group(new OcrReading([L("Locate the ferryman.", 0.05, 0.10, 0.30),
            L("Pay him two silver coins.", 0.05, 0.135, 0.30), L("Exit the cave", 0.60, 0.80, 0.90)]));
        var progress = new List<int>();
        var items = await ScreenTranslation.TranslateAsync(groups, new FakeTranslator(), p => progress.Add(p.Count));
        Assert.Equal(2, items.Count);
        Assert.Equal("TR: Locate the ferryman.\nTR: Pay him two silver coins.", items[0].Text);
        Assert.True(items[0].Paragraphs);
        Assert.False(items[1].Paragraphs);
        Assert.Equal([1, 2], progress);
    }

    [Fact]
    public async Task UntranslatedGroupsSkipped()
    {
        var groups = ScreenTranslation.Group(new OcrReading([L("VAROS", 0.05, 0.10, 0.20), L("Ring the bell.", 0.40, 0.80, 0.60)]));
        var t = new FakeTranslator { Map = s => s == "Ring the bell." ? "Zili çal." : s };
        var items = await ScreenTranslation.TranslateAsync(groups, t);
        Assert.Equal(["Zili çal."], items.Select(i => i.Text));
        await Assert.ThrowsAsync<TranslatorUnavailableException>(() =>
            ScreenTranslation.TranslateAsync(groups, new FakeTranslator { FailReason = UnavailableReason.DownloadRequired }));
        Assert.Equal([12000, 18000, 60000], new[] { 0, 200, 5000 }.Select(ScreenTranslation.DurationMs));
    }

    sealed class BatchTranslator : FakeTranslator
    {
        public int Batches;
        public override bool SupportsBatch => true;

        public override Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellation = default)
        {
            Batches++;
            return Task.FromResult<IReadOnlyList<string>>(texts.Take(texts.Count - 1).Select(s => "TR: " + s).ToArray());
        }
    }

    [Fact]
    public async Task BatchInOneRequest()
    {
        var groups = ScreenTranslation.Group(new OcrReading([L("Locate the ferryman.", 0.05, 0.10, 0.30),
            L("Exit the cave now", 0.60, 0.80, 0.90)]));
        var t = new BatchTranslator();
        var progress = 0;
        var items = await ScreenTranslation.TranslateAsync(groups, t, _ => progress++);
        Assert.Equal(1, t.Batches);
        Assert.Single(items);
        Assert.Equal(1, progress);
    }
}
