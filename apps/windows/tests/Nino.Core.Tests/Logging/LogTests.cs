// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Logging;
using Nino.Core.Tests.Data;

namespace Nino.Core.Tests.Logging;

public class LogTests : IDisposable
{
    readonly TempFolder _tmp = new();
    readonly FakeClock _clock = new(new DateTimeOffset(2026, 11, 22, 10, 5, 7, 42, TimeSpan.Zero));

    public void Dispose() => _tmp.Dispose();

    static string NL => Environment.NewLine;

    [Fact]
    public void HataGunlugu()
    {
        var log = new ErrorLog(_tmp.File("x", LogNames.Error), _clock);
        log.Write("Ayarlar kaydedilemedi");
        Assert.Equal($"[2026-11-22 10:05:07] Ayarlar kaydedilemedi{NL}{NL}{NL}", File.ReadAllText(log.FilePath));
        log.Write("Tarayıcı açılamadı", new InvalidOperationException("x"));
        Assert.Contains("System.InvalidOperationException: x", File.ReadAllText(log.FilePath));
    }

    [Fact]
    public void AltyaziGunluguDondurulur()
    {
        var path = _tmp.File(LogNames.Subtitle);
        File.WriteAllText(path, new string('x', 1_048_570));
        using var log = new SubtitleLog(path, _clock);
        log.Write("kapalıyken atılır");
        Assert.True(log.Flush());
        Assert.False(File.Exists(path + ".1"));
        log.Enabled = true;
        log.Write("MIRA: Hide the map!");
        Assert.True(log.Flush());
        Assert.True(File.Exists(_tmp.File(LogNames.SubtitleRotated)));
        Assert.Equal($"[2026-11-22 10:05:07.042] MIRA: Hide the map!{NL}", File.ReadAllText(path));
    }

    [Fact]
    public void TvKurulumGunluguSatirBasindanKalir()
    {
        var path = _tmp.File(LogNames.TvInstall);
        var lines = string.Concat(Enumerable.Range(0, 50_000).Select(i => $"satır {i:D10} ...........\n"));
        File.WriteAllText(path, lines);
        var log = new TvInstallLog(path, _clock);
        log.Write("kuruldu   ");
        var text = File.ReadAllText(path);
        Assert.StartsWith("satır ", text);
        Assert.EndsWith($"[2026-11-22 10:05:07] kuruldu{NL}", text);
        Assert.True(text.Length < lines.Length);
    }

    [Fact]
    public void Alinti()
    {
        Assert.Equal("\"MIRA: Hide the map! / Now!\"", LogQuote.Of("MIRA: Hide the map!\nNow!"));
        var longText = new string('a', 118) + "😀😀😀";
        var q = LogQuote.Of(longText);
        Assert.Equal("\"" + new string('a', 118) + "😀…\"", q);
    }

    [Fact]
    public void GoruntuDuraklamasi()
    {
        var t = new VideoStallTracker(_clock);
        Assert.Null(t.OnNativeLine("başka satır"));
        Assert.Equal("görüntü durdu (FEC hatası); IDR karesi bekleniyor", t.OnNativeLine("Video FEC failure"));
        Assert.Null(t.OnNativeLine("FEC failed again"));
        _clock.Advance(TimeSpan.FromMilliseconds(1500));
        Assert.Equal("görüntü yeniden akıyor: IDR karesi geldi, boşluk 1500 ms", t.OnNativeLine("Received IDR frame"));
        Assert.Null(t.OnNativeLine("Received IDR frame"));
        t.OnNativeLine("FEC failed");
        _clock.Advance(TimeSpan.FromMilliseconds(200));
        Assert.Equal("görüntü hiç gelmedi; IDR beklenmeyecek, PS5 oturumu yeniden kuruluyor, boşluk 200 ms", t.OnSessionRestartForNoVideo());
        Assert.False(t.Stalled);
    }

    [Fact]
    public async Task CeviriYoklamasi()
    {
        using (var scope = TranslationProbe.Begin())
        {
            await Task.Run(() => TranslationProbe.NoteFresh("deepl"));
            Assert.Equal("çeviri:deepl", scope.Probe.Label());
        }
        using (var scope = TranslationProbe.Begin())
        {
            TranslationProbe.NoteCached();
            Assert.Equal("önbellek", scope.Probe.Label());
        }
        using (var scope = TranslationProbe.Begin())
            Assert.Equal("çeviri:opus", scope.Probe.Label("opus"));
        using (var scope = TranslationProbe.Begin())
            Assert.Equal("çeviri:motor", scope.Probe.Label());
        Assert.Null(TranslationProbe.Current);
    }
}
