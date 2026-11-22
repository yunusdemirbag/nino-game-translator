// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Support;
using Nino.Core.Tests.Data;
using static Nino.Core.Tests.Compat.CompatFixtures;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// Veri klasöründeki küçük dosyalar (geçmiş, çeviri önbelleği, sorunlar, otomatik bildirim, sayaçlar, kimlik): eski
/// uygulamanın yazdığı örnek yeni kodla aynı değerlerle okunuyor ve yeni kod aynı içeriği aynı baytlarla yazıyor mu.
/// </summary>
public class SmallFilesCompatTests
{
    static readonly DateTimeOffset Day = new(2026, 11, 12, 10, 0, 0, TimeSpan.Zero);

    // ---- history.json

    static HistoryEntry[] HistoryLikeOld() =>
    [
        new(2, Day.AddSeconds(65), "Get down!", "Yere yat!", HistoryOrigin.Engine),
        new(1, Day.AddSeconds(7), "Say \"hi\" <b> & go\\now", "\"Selam\" de <b> & çık\\şimdi ğüşıİ 😀", HistoryOrigin.Engine),
        new(0, Day.AddMilliseconds(250), "Hold the gate", "Kapıyı tut", HistoryOrigin.Pack),
    ];

    [Fact]
    public void HistoryReadsAndWritesLikeOld()
    {
        var entries = SubtitleHistory.Parse(OldText("small", "history.json"));
        Assert.Equal(3, entries.Count);
        Assert.Equal(new HistoryEntry(2, Day.AddSeconds(65), "Get down!", "Yere yat!", HistoryOrigin.Engine), entries[0]);
        Assert.Equal("\"Selam\" de <b> & çık\\şimdi ğüşıİ 😀", entries[1].Translation);
        Assert.Equal(HistoryOrigin.Pack, entries[2].Origin);
        Assert.Equal(Day, entries[2].Date); // eski uygulama kesirli saniyeyi yazmaz

        SameText(OldText("small", "history.json"), SubtitleHistory.Serialize(entries), "history.json (okunup yazılan)");
        SameText(OldText("small", "history.json"), SubtitleHistory.Serialize(HistoryLikeOld()), "history.json (yeni yazılan)");

        using var temp = new TempFolder();
        var path = temp.File("history.json");
        File.WriteAllText(path, SubtitleHistory.Serialize(HistoryLikeOld()));
        Export(path, "history.json");
    }

    // ---- translations\*.jsonl

    [Fact]
    public void CacheFileNamesMatchOld()
    {
        using var names = JsonDocument.Parse(OldText("small", "translation-cache-names.json"));
        foreach (var p in names.RootElement.EnumerateObject())
        {
            var parts = p.Name.Split('|');
            Assert.Equal(p.Value.GetString(), TranslationCache.FileName(parts[0], parts[1], parts[2]));
        }
    }

    static void StoreLikeOld(TranslationCache cache)
    {
        cache.Store("Run!", "Koş!");
        cache.Store("Say \"hi\" <b>&", "\"Selam\" de <b>&");
        cache.Store("Line one\nLine two", "Satır bir\nSatır iki");
        cache.Store("Ghost of Yōtei 😀", "Yōtei'nin Hayaleti 😀 ğüşıöç");
        cache.Store("Run!", "Kaç!");
    }

    [Fact]
    public void CacheReadsAndWritesLikeOld()
    {
        using var temp = new TempFolder();
        var oldCopy = temp.File("old.jsonl");
        File.Copy(Old("small", "v1-opus_mt-en-tr.jsonl"), oldCopy);
        var read = new TranslationCache(oldCopy);
        Assert.Equal(4, read.Count);
        Assert.True(read.TryGet("Run!", out var run));
        Assert.Equal("Kaç!", run); // aynı anahtar iki kez: sonuncusu
        Assert.True(read.TryGet("Say \"hi\" <b>&", out var hi));
        Assert.Equal("\"Selam\" de <b>&", hi);
        Assert.True(read.TryGet("Line one\nLine two", out var lines));
        Assert.Equal("Satır bir\nSatır iki", lines);
        Assert.True(read.TryGet("Ghost of Yōtei 😀", out var ghost));
        Assert.Equal("Yōtei'nin Hayaleti 😀 ğüşıöç", ghost);

        var path = temp.File(TranslationCache.FileName("opus-mt", "en", "tr"));
        StoreLikeOld(new TranslationCache(path));
        SameBytes(OldBytes("small", "v1-opus_mt-en-tr.jsonl"), File.ReadAllBytes(path), "çeviri önbelleği");
        Export(path, "cache.jsonl");
    }

    // ---- sorunlar.json

    static ProblemRecord[] ProblemsLikeOld() =>
    [
        new()
        {
            Id = Guid.Parse("11111111-2222-3333-4444-555555555555"), Date = new DateTimeOffset(2026, 11, 22, 18, 4, 5, 123, TimeSpan.Zero),
            Kind = ProblemKind.Ps5Dropped, Reason = "NotFound", StreamedMinutes = 31.5, LossPerMinute = 12, StallsPerMinute = 0.4,
            Network = "wifi", Game = "GTA 6 \"Vice\" ğ",
        },
        new()
        {
            Id = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), Date = new DateTimeOffset(2026, 11, 22, 18, 10, 0, TimeSpan.Zero),
            Kind = ProblemKind.NetworkLost, Network = "wired",
        },
        new()
        {
            Id = Guid.Parse("00000000-0000-0000-0000-000000000003"), Date = new DateTimeOffset(2026, 11, 22, 18, 11, 0, TimeSpan.Zero),
            Kind = ProblemKind.TvDropped, Network = "unknown", StreamedMinutes = 0,
        },
        new()
        {
            Id = Guid.Parse("00000000-0000-0000-0000-000000000004"), Date = new DateTimeOffset(2026, 11, 22, 18, 12, 0, TimeSpan.Zero),
            Kind = ProblemKind.Ps5Unreachable, Reason = "ConsoleAsleep", Network = "wifi",
        },
    ];

    [Fact]
    public void ProblemLogReadsAndWritesLikeOld()
    {
        using var temp = new TempFolder();
        var oldCopy = temp.File("old", ProblemLog.FileName);
        Directory.CreateDirectory(Path.GetDirectoryName(oldCopy)!);
        File.Copy(Old("small", "sorunlar.json"), oldCopy);
        var read = new ProblemLog(oldCopy).All;
        Assert.Equal(ProblemsLikeOld(), read);
        Assert.All(read, r => Assert.Equal(TimeSpan.Zero, r.Date.Offset));

        var path = temp.File(ProblemLog.FileName);
        var log = new ProblemLog(path);
        foreach (var r in ProblemsLikeOld()) log.Add(r);
        SameBytes(OldBytes("small", "sorunlar.json"), File.ReadAllBytes(path), "sorunlar.json");
        Export(path, "sorunlar.json");
    }

    // ---- otomatik-bildirim.json

    static ReportBody AutoBody() => new()
    {
        Install = "0123456789abcdef0123456789abcdef", App = "3.5.0", Language = "tr",
        Text = "[Otomatik] PS5 bağlantısı koptu \"x\" <y> & ğ", Device = "app: 3.5.0 | device: Windows PC | system: Windows 11 (26100)",
    };

    [Fact]
    public async Task AutoReportReadsAndWritesLikeOld()
    {
        var clock = new FakeClock(new DateTimeOffset(2026, 11, 22, 12, 0, 0, TimeSpan.Zero));
        using var temp = new TempFolder();
        var oldCopy = temp.File("old", AutoReporter.FileName);
        Directory.CreateDirectory(Path.GetDirectoryName(oldCopy)!);
        File.Copy(Old("small", "otomatik-bildirim.json"), oldCopy);
        ReportBody? sent = null;
        var read = new AutoReporter(oldCopy, (b, _) => { sent = b; return Task.FromResult(ReportResult.Failed); }, clock);
        Assert.True(read.HasPending);
        Assert.True(read.CanSendToday);
        Assert.False(await read.SendPendingAsync());
        Assert.NotNull(sent);
        Assert.Equal("[Otomatik] PS5 bağlantısı koptu \"x\" <y> & ğ", sent!.Text);
        Assert.Equal("auto", sent.Kind);
        Assert.Equal("0123456789abcdef0123456789abcdef", sent.Install);
        // Bekleyen gövde, sunucuya eski uygulamanınkiyle aynı baytlarla gider.
        using var oldPending = JsonDocument.Parse(OldText("small", "otomatik-bildirim.json"));
        Assert.True(JsonElement.DeepEquals(oldPending.RootElement.GetProperty("Pending"), JsonDocument.Parse(sent.ToJson()).RootElement));

        var path = temp.File(AutoReporter.FileName);
        var day = new FakeClock(new DateTimeOffset(2026, 11, 22, 9, 0, 0, TimeSpan.Zero));
        var writer = new AutoReporter(path, (_, _) => Task.FromResult(ReportResult.Failed), day);
        Assert.False(await writer.SendAsync(AutoBody()));
        SameBytes(OldBytes("small", "otomatik-bildirim.json"), File.ReadAllBytes(path), "otomatik-bildirim.json");
        Export(path, "otomatik-bildirim.json");
    }

    // ---- downloads.txt, auto-update-tried.txt, report-install.txt

    [Fact]
    public void CountersAndIdsMatchOld()
    {
        using var temp = new TempFolder();
        Assert.Equal(3502, new DownloadCounter(Old("small", "downloads.txt")).Value);
        var downloads = temp.File("downloads.txt");
        Assert.True(new DownloadCounter(downloads).Update("{\"ok\":true,\"downloads\":3502}"));
        SameBytes(OldBytes("small", "downloads.txt"), File.ReadAllBytes(downloads), "downloads.txt");
        Export(downloads, "downloads.txt");

        Assert.Equal(2, new AutoUpdateAttempts(Old("small", "auto-update-tried.txt")).Count("3.5.1"));
        Assert.True(new AutoUpdateAttempts(Old("small", "auto-update-tried.txt")).Exhausted("3.5.1"));
        var tries = temp.File("auto-update-tried.txt");
        var attempts = new AutoUpdateAttempts(tries);
        attempts.Record("3.5.1");
        attempts.Record("3.5.1");
        SameBytes(OldBytes("small", "auto-update-tried.txt"), File.ReadAllBytes(tries), "auto-update-tried.txt");
        Export(tries, "auto-update-tried.txt");

        Assert.Equal("0123456789abcdef0123456789abcdef", InstallIdFile.ReadOrCreateReportId(Old("small", "report-install.txt"), null));
    }

    [Fact]
    public void OldReaderSeesNewSmallFiles()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(New("oldread.json")));
        var root = doc.RootElement;

        var history = root.GetProperty("history");
        Assert.Equal(3, history.GetArrayLength());
        Assert.Equal("2026-11-12T10:01:05.0000000Z", history[0].GetProperty("Date").GetString());
        Assert.Equal("Utc", history[0].GetProperty("Kind").GetString());
        Assert.Equal("\"Selam\" de <b> & çık\\şimdi ğüşıİ 😀", history[1].GetProperty("Translation").GetString());
        Assert.Equal("Pack", history[2].GetProperty("Origin").GetString());

        var cache = root.GetProperty("cache");
        Assert.Equal(4, cache.GetProperty("Count").GetInt32());
        Assert.Equal("Kaç!", cache.GetProperty("Run!").GetString());
        Assert.Equal("Satır bir\nSatır iki", cache.GetProperty("Line one\nLine two").GetString());
        Assert.Equal("Yōtei'nin Hayaleti 😀 ğüşıöç", cache.GetProperty("Ghost of Yōtei 😀").GetString());

        var problems = root.GetProperty("sorunlar");
        Assert.Equal(4, problems.GetArrayLength());
        Assert.Equal("2026-11-22T18:04:05.1230000Z", problems[0].GetProperty("Date").GetString());
        Assert.Equal("Utc", problems[0].GetProperty("DateKind").GetString());
        Assert.Equal("Ps5Dropped", problems[0].GetProperty("Kind").GetString());
        Assert.Equal(31.5, problems[0].GetProperty("StreamedMinutes").GetDouble());
        Assert.Equal("GTA 6 \"Vice\" ğ", problems[0].GetProperty("Game").GetString());
        Assert.Equal("Ps5Unreachable", problems[3].GetProperty("Kind").GetString());

        var auto = root.GetProperty("otomatik-bildirim");
        Assert.True(auto.GetProperty("HasPending").GetBoolean());
        Assert.True(auto.GetProperty("CanSendToday").GetBoolean());
        Assert.Equal(AutoBody() with { Kind = ReportBody.AutoKind } is var b ? b.ToJsonText() : null,
            auto.GetProperty("PendingJson").GetString());

        Assert.Equal(3502, root.GetProperty("downloads").GetInt32());
        Assert.Equal(2, root.GetProperty("auto-update-tried").GetInt32());

        // Eski koda okutulan dosyalar, bugünkü yazıcının (yukarıdaki testlerde eskisiyle bayt bayt aynı) çıktısıdır.
        foreach (var (name, oldName) in new[]
                 {
                     ("history.json", "history.json"), ("cache.jsonl", "v1-opus_mt-en-tr.jsonl"), ("sorunlar.json", "sorunlar.json"),
                     ("otomatik-bildirim.json", "otomatik-bildirim.json"), ("downloads.txt", "downloads.txt"),
                     ("auto-update-tried.txt", "auto-update-tried.txt"),
                 })
            SameBytes(OldBytes("small", oldName), File.ReadAllBytes(New(name)), name);
    }
}
