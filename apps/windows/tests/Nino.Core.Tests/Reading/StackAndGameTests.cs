// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

public class SubtitleStackTests
{
    static string[] Texts(SubtitleStack s, double now) => s.Lines(now).Select(l => l.Text).ToArray();

    [Fact]
    public void WithoutStacking()
    {
        var s = new SubtitleStack { StackPrevious = false };
        s.Show("Yere yat!", 4000, false, 0);
        s.Show("Kapıyı tut!", 4000, false, 0.5);
        Assert.Equal(["Kapıyı tut!"], Texts(s, 0.6));
    }

    [Fact]
    public void Durations()
    {
        var s = new SubtitleStack();
        s.Show("Kapıyı aç.", 4000, false, 0);
        Assert.Single(Texts(s, 3.9));
        Assert.Empty(Texts(s, 4));
        s.Show("Evet.", 100, false, 10);
        Assert.Single(Texts(s, 11.1));
        Assert.Empty(Texts(s, 11.2));
        s.Show("Evet.", 0, false, 20);
        Assert.Single(Texts(s, 22.29));
        Assert.Empty(Texts(s, 22.31));
    }

    [Fact]
    public void ThreeLines()
    {
        var s = new SubtitleStack();
        s.Show("Birinci", 8000, false, 0);
        s.Show("İkinci", 8000, false, 0.5);
        s.Show("Üçüncü", 8000, false, 1);
        Assert.Equal(["Birinci", "İkinci", "Üçüncü"], Texts(s, 1));
        Assert.Equal([StackRole.SecondPrevious, StackRole.Previous, StackRole.Current], s.Lines(1).Select(l => l.Role));
        s.Show("Dördüncü", 8000, false, 1.5);
        Assert.Equal(["İkinci", "Üçüncü", "Dördüncü"], Texts(s, 1.5));
    }

    [Fact]
    public void LateLineReplaces()
    {
        var s = new SubtitleStack();
        s.Show("Birinci", 8000, false, 0);
        s.Show("İkinci", 8000, false, 2);
        Assert.Equal(["İkinci"], Texts(s, 2));
    }

    [Fact]
    public void FadeTimes()
    {
        var s = new SubtitleStack();
        s.Show("Birinci", 8000, false, 0);
        s.Show("İkinci", 8000, false, 1);
        Assert.False(s.Lines(2.4)[0].Fading);
        Assert.True(s.Lines(2.6)[0].Fading);
        Assert.Equal(["İkinci"], Texts(s, 2.9));
        Assert.Equal(2.5, s.NextChange(1));
        Assert.Equal(2.9, s.NextChange(2.5));
        Assert.Equal(9, s.NextChange(2.9));
    }

    [Fact]
    public void SameLineNotStacked()
    {
        var s = new SubtitleStack();
        s.Show("Kapak", 8000, false, 0);
        s.Show("Kapak bir türlü açılmıyor.", 8000, false, 0.5);
        Assert.Equal(["Kapak bir türlü açılmıyor."], Texts(s, 0.5));
    }

    [Fact]
    public void ReplaceKeepsUpper()
    {
        var s = new SubtitleStack();
        s.Show("Birinci", 8000, false, 0);
        s.Show("Zaman kalmadı", 8000, false, 0.5);
        s.Show("Bunun için zaman kalmadı, kaptan.", 8000, false, 0.8, replace: true);
        Assert.Equal(["Birinci", "Bunun için zaman kalmadı, kaptan."], Texts(s, 0.8));
    }

    [Fact]
    public void ParagraphsAlone()
    {
        var s = new SubtitleStack();
        s.Show("Birinci", 8000, false, 0);
        s.Show("GÖREV\n• Feneri yak", 8000, true, 0.5);
        var lines = s.Lines(0.5);
        Assert.True(Assert.Single(lines).Paragraphs);
    }

    [Fact]
    public void ClearWaitsForReading()
    {
        var s = new SubtitleStack();
        s.Show("Kapıyı aç.", 15000, false, 0);
        s.Clear(1);
        Assert.Single(Texts(s, 2.5));
        Assert.Empty(Texts(s, 2.61));

        var t = new SubtitleStack();
        t.Show("Birinci", 8000, false, 0);
        t.Show("İkinci", 15000, false, 1);
        t.Clear(4);
        Assert.Empty(Texts(t, 4));
        Assert.Null(t.NextChange(4));

        t.Show("a b c", 8000, false, 10);
        t.Show("d e f", 8000, false, 10.5);
        t.Hide();
        Assert.Empty(Texts(t, 10.6));
    }

    [Theory]
    [InlineData("No!", "Not now!")]
    [InlineData("Go!", "Going home.")]
    [InlineData("No!", "I know!")]
    public void DifferentShortLinesStack(string a, string b)
    {
        var s = new SubtitleStack();
        s.Show(a, 8000, false, 0);
        s.Show(b, 8000, false, 0.5);
        Assert.Equal([a, b], Texts(s, 0.5));
    }

    [Theory]
    [InlineData("Kapıyı aç!", "kapıyı aç.", true)]
    [InlineData("Kapak", "Kapak bir türlü açılmıyor.", true)]
    [InlineData("Evet", "Hayır", false)]
    [InlineData("Kapıyı aç!", "Kapıyıaç", true)]
    [InlineData("Kapıyı a", "Kapıyı aç!", true)]
    [InlineData("No!", "Not now!", false)]
    public void SameLine(string a, string b, bool same) => Assert.Equal(same, SubtitleStack.SameLine(a, b));
}

public class LineWrapTests
{
    [Fact]
    public void Wraps()
    {
        Assert.Equal(("Hemen çıkmalıyız.", 1.0), LineWrap.Wrap("Hemen çıkmalıyız."));
        const string two = "Fırtına dinmeden önce hepimiz limana dönüp gemiyi sağlama almalıyız";
        var (t, scale) = LineWrap.Wrap(two);
        var lines = t.Split('\n');
        Assert.Equal(2, lines.Length);
        Assert.Equal(1, scale);
        Assert.InRange(lines[0].Length - lines[1].Length, -12, 12);
        Assert.Equal(two, string.Join(" ", lines));

        var (many, s2) = LineWrap.Wrap(string.Join(" ", Enumerable.Repeat("kelime", 30)));
        Assert.Equal(3, many.Split('\n').Length);
        Assert.InRange(s2, 0.75, 0.999);

        var (named, _) = LineWrap.Wrap("HOLT: We have to slip out before the guards notice us in the dead of the night, got it?");
        var first = named.Split('\n')[0];
        Assert.StartsWith("HOLT: ", first);
        Assert.True(first.Length > "HOLT: ".Length);

        const string manual = "Kervan sabah erkenden yola çıktı\nRehber de en arkada yavaş yavaş yürüdü";
        Assert.Equal((manual, 1.0), LineWrap.Wrap(manual));

        var p = string.Join(" ", Enumerable.Repeat("kelime", 20));
        Assert.Equal((p, 1.0), SubtitleStack.Visible(p, paragraphs: true));
    }
}

public class GameTests
{
    [Theory]
    [InlineData("Grand Theft Auto VI", "gta 6")]
    [InlineData("GTA 6", "gta 6")]
    [InlineData("gta vi", "gta 6")]
    [InlineData("GTA6", "gta 6")]
    [InlineData("Grand Theft Auto VI™", "gta 6")]
    [InlineData("Marvel's Spider-Man 2", "marvels spider man 2")]
    [InlineData("The Witcher 3: Wild Hunt", "witcher 3 wild hunt")]
    [InlineData("Call of Duty: Black Ops 7", "cod black ops 7")]
    [InlineData("Ghost of Yōtei", "ghost of yotei")]
    [InlineData("EA Sports FC 26", "fc 26")]
    [InlineData("Red Dead Redemption 2", "rdr 2")]
    [InlineData("Tom & Jerry", "tom and jerry")]
    [InlineData("", "")]
    public void Keys(string name, string key) => Assert.Equal(key, GameNames.Key(name));

    [Fact]
    public void Ids()
    {
        Assert.Equal("PPSA01234", RunningGame.ParseId(" ppsa01234 "));
        Assert.Equal("CUSA00419_00", RunningGame.ParseId("CUSA00419_00"));
        Assert.Null(RunningGame.ParseId("PPSA1234"));
        Assert.Null(RunningGame.WithId("bad"));
        Assert.Equal(new RunningGame(null, "A B"), RunningGame.WithName(" A\u0001  B "));
        Assert.Null(RunningGame.WithName("  "));
        Assert.Equal("CUSA00419_00", GameSense.IdFromPack("pool-cusa00419-00"));
        Assert.Null(GameSense.IdFromPack("pool-gta-6"));
    }

    [Fact]
    public void PackVotes()
    {
        var g = new GameSense();
        for (var i = 0; i < 4; i++) Assert.False(g.NotePackLine("gta-v", "Grand Theft Auto V"));
        Assert.Null(g.Current);
        Assert.True(g.NotePackLine("gta-v", "Grand Theft Auto V"));
        Assert.Equal(new RunningGame(null, "Grand Theft Auto V"), g.Current);
        Assert.Equal(GameSource.Pack, g.Source);
        Assert.False(g.NotePackLine("gta-v", "Grand Theft Auto V"));
        for (var i = 0; i < 10; i++) Assert.False(g.NotePackLine(null));

        var h = new GameSense();
        for (var i = 0; i < 5; i++) h.NotePackLine("gta-v", "Grand Theft Auto V");
        h.NotePackLine("rdr-2", "Red Dead Redemption 2");
        Assert.Equal("Grand Theft Auto V", h.Current!.Name);
        for (var i = 0; i < 3; i++) Assert.False(h.NotePackLine("rdr-2"));
        Assert.True(h.NotePackLine("rdr-2"));
        Assert.Equal("Red Dead Redemption 2", h.Current!.Name);
    }

    [Fact]
    public void Priorities()
    {
        var g = new GameSense();
        g.SetUser("Marvel's Wolverine");
        for (var i = 0; i < 5; i++) g.NotePackLine("rdr-2", "Red Dead Redemption 2");
        Assert.Equal(("Marvel's Wolverine", GameSource.User), (g.Current!.Name, g.Source));
        Assert.Equal("Marvel's Wolverine", g.PackSearchLimit);
        g.SetPs5(RunningGame.WithName("Mafia: The Old Country"));
        Assert.Equal(GameSource.Ps5, g.Source);
        Assert.Null(g.PackSearchLimit);
        g.SetPs5(null);
        Assert.Equal("Red Dead Redemption 2", g.Current!.Name);
        Assert.Null(g.PackSearchLimit);

        var h = new GameSense();
        h.SetUser("GTA 5");
        h.SetPs5(RunningGame.WithName("Grand Theft Auto V"));
        h.SetPs5(null);
        Assert.Equal("GTA 5", h.Current!.Name);
        Assert.Equal("GTA 5", h.PackSearchLimit);

        var k = new GameSense();
        for (var i = 0; i < 4; i++) k.NotePackLine("rdr-2");
        Assert.Null(k.Current);
        k.SetUser("Grand Theft Auto V");
        Assert.Equal("Grand Theft Auto V", k.Current!.Name);
        k.SetPs5(RunningGame.WithName("Mafia: The Old Country"));
        Assert.Equal("Mafia: The Old Country", k.Current!.Name);

        var p = new GameSense();
        for (var i = 0; i < 10; i++) Assert.False(p.NotePackLine(GameSense.GeneralPoolPack));
        for (var i = 0; i < 5; i++) p.NotePackLine("pool-ppsa01234", "Grand Theft Auto VI");
        Assert.Equal(new RunningGame("PPSA01234", "Grand Theft Auto VI"), p.Current);
    }

    [Fact]
    public void Asking()
    {
        var g = new GameSense();
        Assert.False(g.ShouldAsk(true, TimeSpan.FromMinutes(1)));
        Assert.False(g.ShouldAsk(false, TimeSpan.FromMinutes(2)));
        Assert.True(g.ShouldAsk(true, TimeSpan.FromMinutes(2)));
        g.MarkAsked();
        Assert.False(g.ShouldAsk(true, TimeSpan.FromMinutes(2)));
        g.SetUser("GTA 6");
        g.NewSession();
        Assert.Equal(new RunningGame(null, "GTA 6"), g.Current);
        Assert.False(g.ShouldAsk(true, TimeSpan.FromMinutes(3)));
        g.SetPs5(RunningGame.WithId("PPSA01234", "Grand Theft Auto VI"));
        Assert.Equal("PPSA01234", g.Current!.Id);
    }

    [Fact]
    public void ScreenSourceLowest()
    {
        var g = new GameSense();
        g.SetScreen("Grand Theft Auto VI");
        Assert.Equal(GameSource.Screen, g.Source);
        for (var i = 0; i < 5; i++) g.NotePackLine("gta-v", "Grand Theft Auto V");
        Assert.Equal(GameSource.Pack, g.Source);
        g.SetUser("Elden Ring");
        Assert.Equal(GameSource.User, g.Source);
        g.SetPs5(RunningGame.WithName("Astro Bot"));
        Assert.Equal(GameSource.Ps5, g.Source);
        g.SetPs5(null);
        g.NewSession();
        Assert.Equal(("Grand Theft Auto VI", GameSource.Screen), (g.Current!.Name, g.Source));
        g.SetScreen(null);
        Assert.Null(g.Current);
        Assert.Null(g.Source);
    }

    [Fact]
    public void UnknownGameSchedule()
    {
        var s = new ScreenCheckSchedule();
        var t = new DateTimeOffset(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);
        s.Restart(t);
        Assert.False(s.ShouldCheck(t, null));
        Assert.False(s.ShouldCheck(t.AddSeconds(8), null));
        t = t.AddSeconds(9);
        Assert.True(s.ShouldCheck(t, null));
        s.Begin(t);
        t = t.AddSeconds(120);
        Assert.False(s.ShouldCheck(t, null));
        s.Finish();
        Assert.True(s.ShouldCheck(t, null));
        s.Begin(t);
        s.Finish();
        var attempts = 2;
        while (attempts < 6)
        {
            t = t.AddSeconds(59);
            Assert.False(s.ShouldCheck(t, null));
            t = t.AddSeconds(2);
            Assert.True(s.ShouldCheck(t, null));
            s.Begin(t);
            s.Finish();
            attempts++;
        }
        Assert.False(s.ShouldCheck(t.AddHours(1), null));
    }

    [Fact]
    public void KnownGameSchedule()
    {
        var s = new ScreenCheckSchedule();
        var t = new DateTimeOffset(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);
        s.Restart(t);
        foreach (var src in new[] { GameSource.Pack, GameSource.Ps5, GameSource.User })
            Assert.False(s.ShouldCheck(t.AddHours(1), src));
        s.Restart(t);
        t = t.AddMinutes(4);
        Assert.False(s.ShouldCheck(t, GameSource.Screen));
        t = t.AddMinutes(2);
        Assert.True(s.ShouldCheck(t, GameSource.Screen));
        s.Begin(t);
        s.Finish();
        t = t.AddMinutes(19);
        Assert.False(s.ShouldCheck(t, GameSource.Screen));
        t = t.AddMinutes(2);
        Assert.True(s.ShouldCheck(t, GameSource.Screen));
        s.Begin(t);
        s.Finish();
        for (var i = 2; i < 12; i++)
        {
            t = t.AddMinutes(21);
            Assert.True(s.ShouldCheck(t, GameSource.Screen));
            s.Begin(t);
            s.Finish();
        }
        Assert.False(s.ShouldCheck(t.AddMinutes(21), GameSource.Screen));
    }

    [Theory]
    [InlineData(new[] { "JASON & LUCIA", "MAP", "BRIEF", "PROGRESS" }, true)]
    [InlineData(new[] { "MAP", "BRIEF", "PROGRESS" }, true)]
    [InlineData(new[] { "Reminders", "WhatUp" }, true)]
    [InlineData(new[] { "Options", "Map", "Progress", "Quit Game" }, false)]
    [InlineData(new[] { "Jason, open the trunk!" }, false)]
    public void Gta6Signs(string[] lines, bool gta) => Assert.Equal(gta, Gta6Markers.Detect(lines));

    [Fact]
    public void Suggestions()
    {
        var s = GamePicker.Suggestions("", [("mafia", "Mafia: The Old Country")], "Elden Ring");
        Assert.Equal("Elden Ring", s[0]);
        Assert.Equal("Mafia: The Old Country", s[1]);
        Assert.True(s.Count <= 8);
        Assert.Equal("GTA 6", GamePicker.Suggestions("gta 6", [], null)[0]);
        Assert.Empty(GamePicker.Suggestions("zzzz", [], null));
        Assert.Contains("GTA 6", GamePicker.Suggestions("grand theft", [], null));
        Assert.Equal("GTA 6", GamePicker.Suggestions("", [(GameSense.GeneralPoolPack, "Genel")], null)[0]);
        Assert.Equal("Grand Theft Auto VI", GamePicker.LongName("GTA 6"));
    }
}

public class MetricsTests
{
    [Fact]
    public void Builds()
    {
        var m = SubtitleMetrics.Build(1000, 40, 1100, 1400, 1520, null, ShownOrigin.Engine);
        Assert.Equal((40L, 300L, 520L), (m.OcrMs!.Value, m.TranslationMs!.Value, m.TotalMs!.Value));
        Assert.Equal([new MetricPart(MetricPartKind.Ocr, 40), new MetricPart(MetricPartKind.Translation, 300),
            new MetricPart(MetricPartKind.Latency, 520)], m.Parts());
        var z = SubtitleMetrics.Build(2000, -5, 1500, 1400, 1000, null, ShownOrigin.Engine);
        Assert.Equal((0L, 0L, 0L), (z.OcrMs!.Value, z.TranslationMs!.Value, z.TotalMs!.Value));
        var p = SubtitleMetrics.Build(1000, 35, null, null, 1060, null, ShownOrigin.Pack);
        Assert.Equal([MetricPartKind.Ocr, MetricPartKind.FromPack, MetricPartKind.Latency], p.Parts().Select(x => x.Kind));
        Assert.Equal(new MetricPart(MetricPartKind.Confidence, 93),
            SubtitleMetrics.Build(1000, 35, null, null, 1060, 0.93, ShownOrigin.Pack).Parts()[3]);
        Assert.Equal([new MetricPart(MetricPartKind.Latency, 250)],
            new SubtitleMetrics(null, null, 250, null, ShownOrigin.Engine).Parts());
    }

    [Theory]
    [InlineData(0.934, 93)]
    [InlineData(0.936, 94)]
    [InlineData(1.2, 100)]
    [InlineData(-0.1, 0)]
    public void Percent(double c, int p) => Assert.Equal(p, SubtitleMetrics.Percent(c));
}
