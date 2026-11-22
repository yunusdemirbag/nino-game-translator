// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;

namespace Nino.Core.Tests.Data;

public class SubtitleHistoryTests : IDisposable
{
    readonly TempFolder _tmp = new();
    readonly FakeClock _clock = new(new DateTimeOffset(2026, 11, 12, 10, 0, 0, 250, TimeSpan.Zero));

    public void Dispose() => _tmp.Dispose();

    [Fact]
    public void MacIleAyniBicim()
    {
        var h = new SubtitleHistory(clock: _clock);
        h.Add("Mind the gap!", "Boşluğa dikkat!", HistoryOrigin.Pack);
        Assert.Equal("{\"version\":1,\"entries\":[{\"id\":0,\"date\":\"2026-11-12T10:00:00Z\",\"source\":\"Mind the gap!\",\"translation\":\"Boşluğa dikkat!\",\"origin\":\"pack\"}]}",
            SubtitleHistory.Serialize(h.Entries));
        Assert.Contains("Kapıyı", SubtitleHistory.Serialize([new HistoryEntry(1, _clock.GetUtcNow(), "x", "Kapıyı", HistoryOrigin.Engine)]));
    }

    [Fact]
    public void BenzerSatirIlkKaydiGunceller()
    {
        var h = new SubtitleHistory(clock: _clock);
        h.Add("The rope will not last", "Halat dayanmayacak", HistoryOrigin.Engine);
        _clock.Advance(TimeSpan.FromSeconds(2));
        h.Add("The rcpe will not last!", "Halat dayanmaz", HistoryOrigin.Pack);
        Assert.Single(h.Entries);
        Assert.Equal(0, h.Entries[0].Id);
        Assert.Equal("Halat dayanmaz", h.Entries[0].Translation);
        Assert.Equal(HistoryOrigin.Pack, h.Entries[0].Origin);
        h.Add("Bring the lamp inside", "Feneri içeri getir", HistoryOrigin.Engine);
        Assert.Equal(2, h.Entries.Count);
        Assert.Equal(1, h.Entries[0].Id);
    }

    [Fact]
    public void BosCeviriEklenmezSinirlar()
    {
        var h = new SubtitleHistory((_, _) => false, _clock);
        Assert.False(h.Add("a", "   ", HistoryOrigin.Engine));
        for (var i = 0; i < 205; i++) h.Add("s" + i, "t" + i, HistoryOrigin.Engine);
        Assert.Equal(200, h.Entries.Count);
        Assert.Equal("t204", h.Entries[0].Translation);
        h.Add(new string('a', 600), new string('b', 700), HistoryOrigin.Engine);
        Assert.Equal(500, h.Entries[0].Source.Length);
        Assert.Equal(500, h.Entries[0].Translation.Length);
    }

    [Fact]
    public void KaydetYukleKimlikSurer()
    {
        var path = _tmp.File("sub", SubtitleHistory.FileName);
        var h = new SubtitleHistory((_, _) => false, _clock);
        h.Add("a", "1", HistoryOrigin.Engine);
        h.Add("b", "2", HistoryOrigin.Pack);
        h.Save(path);
        var again = new SubtitleHistory((_, _) => false, _clock);
        again.Load(path);
        Assert.Equal(2, again.Entries.Count);
        again.Add("c", "3", HistoryOrigin.Engine);
        Assert.Equal(2, again.Entries[0].Id);
    }

    [Theory]
    [InlineData("{bozuk")]
    [InlineData("{\"version\":1,\"entries\":[{\"id\":0,\"date\":\"yesterday\",\"source\":\"a\",\"translation\":\"b\",\"origin\":\"pack\"}]}")]
    [InlineData("{\"version\":1,\"entries\":[{\"id\":0,\"date\":\"2026-11-12T10:00:00Z\",\"source\":\"a\",\"translation\":\"b\",\"origin\":\"radio\"}]}")]
    public void BozukDosyaBosGecmis(string json) => Assert.Empty(SubtitleHistory.Parse(json));

    [Fact]
    public void EksikKayitAtlanirHerIsoTarihOkunur()
    {
        var list = SubtitleHistory.Parse("{\"version\":1,\"entries\":[" +
            "{\"id\":3,\"date\":\"2026-11-12T13:00:00.5+03:00\",\"source\":\"a\",\"translation\":\"b\",\"origin\":\"engine\"}," +
            "{\"id\":2,\"date\":\"2026-11-12T10:00:00Z\",\"translation\":\"b\",\"origin\":\"pack\"}]}");
        Assert.Single(list);
        Assert.Equal(new DateTimeOffset(2026, 11, 12, 10, 0, 0, 500, TimeSpan.Zero), list[0].Date);
        Assert.Equal(TimeSpan.Zero, list[0].Date.Offset);
    }

    [Fact]
    public void KopyalamaMetni()
    {
        var zone = TimeZoneInfo.CreateCustomTimeZone("utc3", TimeSpan.FromHours(3), "utc3", "utc3");
        var entries = new[]
        {
            new HistoryEntry(1, new DateTimeOffset(2026, 11, 12, 10, 1, 5, TimeSpan.Zero), "Mind the gap!", "Boşluğa dikkat!", HistoryOrigin.Pack),
            new HistoryEntry(0, new DateTimeOffset(2026, 11, 12, 10, 0, 0, TimeSpan.Zero), "Pull the anchor", "Çapayı çek", HistoryOrigin.Engine),
        };
        Assert.Equal("[13:01:05] Boşluğa dikkat!\nMind the gap!\n\n[13:00:00] Çapayı çek\nPull the anchor", SubtitleHistory.CopyText(entries, zone));
    }

    [Fact]
    public void Benzerlik()
    {
        Assert.True(TextSimilarity.Similar("the rope will not last", "the rcpe will not last", 0.85));
        Assert.False(TextSimilarity.Similar("bring the lamp inside", "the rope will not last", 0.85));
        Assert.False(TextSimilarity.Similar("", "abc", 0.85));
        Assert.Equal("nora the tide is rising fast", TextSimilarity.Simplify("Nora: The tide is RISING fast!"));
    }
}
