// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

public class DeepReadTests
{
    static readonly BgraFrame Image = BgraFrame.Blank(64, 64);

    [Fact]
    public void StripGeometry()
    {
        Assert.Equal((19, 26), DeepRead.StripOf(64));
        var widths = new List<int>();
        var r = DeepRead.Read(Image, img =>
        {
            lock (widths) widths.Add(img.Width);
            return img.Width == 52 ? new OcrReading([new OcrLine("Go!", new Box(0, 0.5, 1, 1))]) : OcrReading.Empty;
        });
        Assert.Contains(52, widths);
        var b = r.Lines.Single().Box!.Value;
        Assert.Equal(19 / 64.0, b.Left, 9);
        Assert.Equal(45 / 64.0, b.Right, 9);
        Assert.Equal(0.5, b.Top, 9);
    }

    [Fact]
    public void PrefersStrip()
    {
        Assert.Equal("Go!", DeepRead.Read(Image, img => img.Width == 52 ? OcrReading.FromText("Go!") : OcrReading.Empty).Text);
        Assert.Equal("Go!", DeepRead.Read(Image, img => img.Width switch
        {
            52 => OcrReading.FromText("Go!"),
            128 => OcrReading.FromText("G0!"),
            _ => OcrReading.Empty,
        }).Text);
        Assert.Equal("G0!", DeepRead.Read(Image, img => img.Width == 128 ? OcrReading.FromText("G0!") : OcrReading.Empty).Text);
        Assert.True(DeepRead.Read(Image, _ => OcrReading.Empty).IsEmpty);
    }

    [Fact]
    public void FullReadOnlyOnce()
    {
        var calls = 0;
        Assert.Equal("Untie the rope", DeepRead.Read(Image, _ =>
        {
            Interlocked.Increment(ref calls);
            return OcrReading.FromText("Untie the rope");
        }).Text);
        Assert.Equal(1, calls);
    }

    [Fact]
    public void FallbacksRunTogether()
    {
        ThreadPool.SetMinThreads(32, 32);
        using var barrier = new Barrier(2);
        var met = 0;
        DeepRead.Read(Image, _ => OcrReading.Empty, _ =>
        {
            if (barrier.SignalAndWait(TimeSpan.FromSeconds(10))) Interlocked.Increment(ref met);
            return OcrReading.Empty;
        });
        Assert.Equal(2, met);
    }
}

public class WordLineSplitterTests
{
    [Theory]
    [InlineData(900, 30, 1920, true)]
    [InlineData(150, 30, 1920, false)]
    [InlineData(200, 30, 1920, false)]
    [InlineData(120, 20, 1920, false)]
    public void GapRule(double gap, double height, double width, bool separate) =>
        Assert.Equal(separate, WordLineSplitter.IsSeparateText(gap, height, width));

    [Fact]
    public void SplitsFarWords()
    {
        var words = new[]
        {
            new OcrWord("MAP", 10, 100, 80, 130), new OcrWord("HELP", 90, 100, 170, 130),
            new OcrWord("$500", 1100, 100, 1180, 130),
        };
        var lines = WordLineSplitter.Split("MAP HELP $500", words, 1920, 1080);
        Assert.Equal(["MAP HELP", "$500"], lines.Select(l => l.Text));
        Assert.Equal(10 / 1920.0, lines[0].Box!.Value.Left, 9);
        Assert.Null(lines[0].Confidence);
        var joined = WordLineSplitter.Split("日本語", [new OcrWord("日本", 0, 0, 40, 30), new OcrWord("語", 45, 0, 60, 30)], 1920, 1080);
        Assert.Equal("日本語", joined.Single().Text);
        var sorted = WordLineSplitter.SortByTop([new OcrLine("b", new Box(0, 0.5, 1, 0.6)), new OcrLine("a"), new OcrLine("c", new Box(0, 0.1, 1, 0.2))]);
        Assert.Equal(["a", "c", "b"], sorted.Select(l => l.Text));
    }
}

public class PreparedReaderTests
{
    static readonly BgraFrame Image = BgraFrame.Filled(100, 60, 120);

    sealed class ScriptedOcr(params string[] texts)
    {
        readonly Queue<string> _texts = new(texts);
        public int Calls;

        public OcrReading Read(BgraFrame _)
        {
            Calls++;
            return OcrReading.FromText(_texts.Count > 0 ? _texts.Dequeue() : "");
        }
    }

    [Fact]
    public void SmallImageReadOnce()
    {
        var ocr = new ScriptedOcr("x");
        var reader = new PreparedReader(ocr.Read, _ => false);
        reader.Read(BgraFrame.Blank(30, 30), false);
        Assert.Equal(1, ocr.Calls);
    }

    [Fact]
    public void KnownLineStopsChain()
    {
        var ocr = new ScriptedOcr("Gtt down", "Get down!", "never");
        var reader = new PreparedReader(ocr.Read, s => s == "Get down!");
        Assert.Equal("Get down!", reader.Read(Image, false).Text);
        Assert.Equal(2, ocr.Calls);
        Assert.Equal(0, reader.Misses);
    }

    [Fact]
    public void EmptyRegionStopsAfterWhite()
    {
        var ocr = new ScriptedOcr("", "", "", "", "x", "x");
        var reader = new PreparedReader(ocr.Read, _ => false);
        var r = reader.Read(Image, false);
        Assert.True(r.IsEmpty);
        Assert.Equal(4, ocr.Calls); // G1, G2, B, sonra eski seçimde ham okuma
    }

    [Fact]
    public void OldChoicePrefersCleanerWhite()
    {
        var ocr = new ScriptedOcr("a", "b", "Get to the boat now.", "c", "d", "Gtt t0 th3 b0@t");
        var reader = new PreparedReader(ocr.Read, _ => false);
        Assert.Equal("Get to the boat now.", reader.Read(Image, false).Text);
        Assert.Equal(1, reader.Misses);
    }

    [Fact]
    public void DictionaryPicksBestAndExtendsPackMatch()
    {
        var ocr = new ScriptedOcr("Go to", "Go to Copper Ridge.", "Go to Coppr", "xx", "yy", "zz");
        var reader = new PreparedReader(ocr.Read, s => s == "Go to", s => s.Length);
        Assert.Equal("Go to Copper Ridge.", reader.Read(Image, false).Text);
        Assert.Equal(6, ocr.Calls);

        var ocr2 = new ScriptedOcr("Untie th rope", "Untie the rope", "Unt", "", "", "");
        var reader2 = new PreparedReader(ocr2.Read, null, s => s.Length);
        Assert.Equal("Untie the rope", reader2.Read(Image, false).Text);
    }

    [Fact]
    public void SparseAfterManyMisses()
    {
        var ocr = new ScriptedOcr();
        var reader = new PreparedReader(img => { ocr.Calls++; return OcrReading.FromText("Some text here"); }, _ => false);
        for (var i = 0; i < 30; i++) reader.Read(Image, false);
        Assert.Equal(30, reader.Misses);
        var before = ocr.Calls;
        reader.Read(Image, false);
        Assert.Equal(2, ocr.Calls - before); // seyrek: yalnız ham + beyaz
    }

    [Fact]
    public void ChainHasSixPreparations()
    {
        Assert.Equal(["G1", "G2", "B", "G3", "GR", "H"], PreparedReader.StandardChain().Select(p => p.Name));
        Assert.Equal(5, PreparedReader.StandardChain(coloredWords: false).Count);
    }
}

public class SpellScoringTests
{
    sealed class Dict(params string[] words) : ISpellDictionary
    {
        readonly HashSet<string> _words = new(words, StringComparer.Ordinal);
        public bool Contains(string word) => _words.Contains(word);
    }

    static readonly SpellScoring Spell = new(new Dict("hello", "man", "go", "to", "something", "staring", "the", "rope", "untie",
        "we", "need", "sure", "fine", "copper", "ridge"));

    [Theory]
    [InlineData("Arfgfit man", true)]
    [InlineData("Untie the rope", false)]
    [InlineData("Ravenmoor man", true)]
    [InlineData("go to Ravenmoor", false)]
    [InlineData("DORIAN go", true)]
    [InlineData("go DORIAN", false)]
    [InlineData("gonna go", false)]
    [InlineData("go somethin' staring", false)]
    [InlineData("go starin'", false)]
    [InlineData("go gatte", true)]
    public void Misread(string text, bool misread) => Assert.Equal(misread, Spell.IsMisread(text));

    [Fact]
    public void Scores()
    {
        Assert.Equal(12, Spell.Score("Untie the rope"));
        Assert.Equal(0, Spell.Score("24"));
        Assert.Equal(-2, Spell.Score("•"));
        Assert.True(Spell.Score("Sure? Qrrvx.") < Spell.Score("Sure? Fine."));
        Assert.Equal(4, Spell.Score("Sure? Qrrvx."));
        Assert.True(Spell.Score("Go to Copper Ridge.") > Spell.Score("Go to"));
        Assert.Equal(-8, Spell.Score("g@te"));
    }
}
