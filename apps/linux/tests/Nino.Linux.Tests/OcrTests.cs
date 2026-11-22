// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Linux.Imaging;
using Nino.Linux.Ocr;

namespace Nino.Linux.Tests;

public sealed class WordFilterTests
{
    private static readonly WordFilter Filter = new(strong: 75, edge: 60);

    private static OcrWord W(string text, float confidence) => new(text, confidence, 0, 0, 10, 10);

    [Fact]
    public void GuvenliSatirKalirUclariKirpilir()
    {
        var kept = Filter.Keep([W("|", 20), W("Where", 95), W("is", 30), W("he?", 93), W("eC,", 40)]);
        Assert.Equal(["Where", "is", "he?"], kept.Select(word => word.Text));
    }

    [Fact]
    public void UydurmaSatirAtilir()
    {
        Assert.Empty(Filter.Keep([W("~wuet", 50), W("ma", 70), W("dt", 74)]));
        Assert.Empty(Filter.Keep([W("a", 99)]));                  // tek harf
        Assert.Empty(Filter.Keep([W("Hello", 99), W("xxxxxxx", 10)])); // kesin pay yarıdan az
    }

    [Fact]
    public void KesinPayYariysaKalir() => Assert.Equal(2, Filter.Keep([W("abcd", 80), W("efgh", 65)]).Count);

    [Theory]
    [InlineData("|", "I")]
    [InlineData("|'m", "I'm")]
    [InlineData("|t's", "It's")]
    [InlineData("a|b", "aIb")]
    [InlineData("10|2", "10|2")]
    [InlineData("hello", "hello")]
    public void DikCizgiI(string word, string expected) => Assert.Equal(expected, WordFilter.RepairCapitalI(word));

    [Theory]
    [InlineData("en", "eng")]
    [InlineData("JA", "jpn")]
    [InlineData("zh", "chi_sim")]
    [InlineData("tr", "tr")]
    public void TesseractDilAdlari(string language, string name) => Assert.Equal(name, TesseractLanguage.For(language));
}

/// <summary>Çekirdeğin kurallarının basit bir taklidi.</summary>
internal sealed class SimpleRules : IOcrRules
{
    public Func<string, double> Likeness { get; set; } = text => text.Length;

    public BgraPicture KeepWhiteText(BgraPicture picture) => picture;

    public BgraPicture Enlarge(BgraPicture picture, int factor)
    {
        var pixels = new byte[picture.Width * factor * picture.Height * factor * 4];
        return BgraPicture.Packed(pixels, picture.Width * factor, picture.Height * factor);
    }

    public double WordLikeness(string text) => Likeness(text);

    public bool IsSeparateText(double gap, double lineHeight, double imageWidth) => gap > lineHeight * 3;
}

public sealed class LineBuilderTests
{
    [Fact]
    public void GenisBoslukSatiriBolerKutuPayliBuyur()
    {
        var words = new List<OcrWord>
        {
            new("Menu", 90, 0, 40, 40, 60),
            new("Hello", 90, 200, 40, 250, 60),
            new("there", 90, 260, 40, 300, 60),
        };
        var lines = LineBuilder.Build(words, 400, 100, new SimpleRules()).ToList();
        Assert.Equal(["Menu", "Hello there"], lines.Select(line => line.Text));
        var box = lines[1].Box!.Value;
        Assert.Equal(0.5, box.Left, 6);
        Assert.Equal(0.75, box.Right, 6);
        Assert.Equal(0.4 - 0.2 * 0.2, box.Top, 6);
        Assert.Equal(0.6 + 0.2 * 0.2, box.Bottom, 6);
    }

    [Fact]
    public void KutuSinirdaKalir()
    {
        var line = LineBuilder.Build([new OcrWord("Edge", 90, 0, 0, 50, 100)], 100, 100, new SimpleRules()).Single();
        Assert.Equal(0, line.Box!.Value.Top);
        Assert.Equal(1, line.Box!.Value.Bottom);
    }
}

public sealed class TesseractReaderTests
{
    /// <summary>
    /// Sahte motor: hangi görüntü okunuyor (beyaz süzgeçli mi, ters mi, şerit mi) sırayla kaydeder ve
    /// kuyruktaki yanıtı döner.
    /// </summary>
    private sealed class ScriptedEngine : IWordRecognizer
    {
        public Queue<List<List<OcrWord>>> Answers { get; } = new();
        public List<(int Width, int Height, byte First)> Calls { get; } = [];

        public List<List<OcrWord>> Recognize(byte[] gray, int width, int height)
        {
            Calls.Add((width, height, gray[0]));
            return Answers.Count > 0 ? Answers.Dequeue() : [];
        }

        public void Dispose() { }
    }

    private static List<List<OcrWord>> Line(string text, int top = 40, int bottom = 60) =>
        [[.. text.Split(' ').Select((word, i) => new OcrWord(word, 95, i * 60, top, i * 60 + 50, bottom))]];

    private static (TesseractReader Reader, ScriptedEngine Engine, SimpleRules Rules) Make()
    {
        var engine = new ScriptedEngine();
        var rules = new SimpleRules();
        return (new TesseractReader(engine, rules, new WordFilter(75, 60), "eng", dump: null), engine, rules);
    }

    private static BgraPicture Dark(int w = 400, int h = 100) => BgraPictureTests.Solid(w, h, 0, 0, 0);

    [Fact]
    public void KucukGoruntuOkunmaz()
    {
        var (reader, engine, _) = Make();
        Assert.True(reader.Read(Dark(39, 100), deep: true).IsEmpty);
        Assert.Empty(engine.Calls);
    }

    [Fact]
    public void BeyazYaziVarsaCevresiDeOkunurDahaIyisiSecilir()
    {
        var (reader, engine, rules) = Make();
        engine.Answers.Enqueue(Line("Hello there"));
        engine.Answers.Enqueue(Line("ARTHUR: Hello there", top: 10, bottom: 30));
        var reading = reader.Read(Dark(), deep: false);
        Assert.Equal("ARTHUR: Hello there", reading.Text);
        Assert.Equal(2, engine.Calls.Count);
        Assert.Equal(0, engine.Calls[0].First);   // beyaz süzgeç: ters çevrilmez (siyah 0)
        Assert.Equal(255, engine.Calls[1].First); // çevre olduğu gibi: ters çevrilir
        Assert.False(reader.InColorMode);

        // Eşitlikte beyaz yazı seçilir.
        rules.Likeness = _ => 1;
        engine.Answers.Enqueue(Line("Hi you"));
        engine.Answers.Enqueue(Line("Hl yoo"));
        Assert.Equal("Hi you", reader.Read(Dark(), deep: false).Text);
    }

    [Fact]
    public void OlaganOkumadaBeyazYoksaBos()
    {
        var (reader, engine, _) = Make();
        Assert.True(reader.Read(Dark(), deep: false).IsEmpty);
        Assert.Single(engine.Calls);
    }

    [Fact]
    public void DerinOkumadaRenkliAltyaziBulunursaRenkliKipSurer()
    {
        var (reader, engine, _) = Make();
        engine.Answers.Enqueue([]);                 // beyaz yok
        engine.Answers.Enqueue(Line("Yellow words")); // olduğu gibi var
        Assert.Equal("Yellow words", reader.Read(Dark(), deep: true).Text);
        Assert.True(reader.InColorMode);

        // Renkli kipte olağan karede de olduğu gibi okunur.
        engine.Answers.Enqueue([]);
        engine.Answers.Enqueue(Line("Still yellow"));
        Assert.Equal("Still yellow", reader.Read(Dark(), deep: false).Text);

        // Kaybolunca kip kapanır.
        Assert.True(reader.Read(Dark(), deep: false).IsEmpty);
        Assert.False(reader.InColorMode);
    }

    [Fact]
    public void DerinOkumadaHicYoksaOrtaSeritBuyutulerekOkunur()
    {
        var (reader, engine, _) = Make();
        engine.Answers.Enqueue([]);
        engine.Answers.Enqueue([]);
        engine.Answers.Enqueue([[new OcrWord("Go!", 95, 0, 0, 320, 200)]]);
        var reading = reader.Read(Dark(), deep: true);
        Assert.Equal((320, 200), (engine.Calls[2].Width, engine.Calls[2].Height)); // %40 genişlik × 2
        var box = reading.Lines.Single().Box!.Value;
        Assert.Equal(0.3, box.Left, 6);
        Assert.Equal(0.7, box.Right, 6);
    }
}

public sealed class ReadTimingTests
{
    [Fact]
    public void YalnizMetinDegisinceYazar()
    {
        var journal = new Hosting.Journal();
        var timing = new ReadTiming(journal);
        var hello = new OcrReading([new OcrLine("Hello", null)]);
        timing.Measure(() => hello, deep: true);
        timing.Measure(() => hello, deep: false);
        timing.Measure(() => OcrReading.Nothing, deep: false);
        var lines = journal.Recent();
        Assert.Equal(2, lines.Length);
        Assert.Contains(", derin → Hello", lines[0]);
        Assert.EndsWith("→ —", lines[1]);
    }
}
