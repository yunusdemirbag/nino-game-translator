// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics;

/// <summary>Bildirimin önemi (<c>sev</c>).</summary>
public enum DiagSeverity { Info, Warn, Error }

/// <summary>
/// Otomatik teşhis kuralları (otomatik-teshis.md): kodlar, öncelik, önem, sebep kodları. Cümle burada yoktur;
/// uygulama yalnız kod gönderir.
/// </summary>
public static class DiagRules
{
    /// <summary>PS5 koptu, geri gelmedi.</summary>
    public const string Ps5NoReturn = "ps5.no_return";

    /// <summary>TV bağlantısı tekrar tekrar kopuyor.</summary>
    public const string TvFlapping = "tv.flapping";

    /// <summary>Görüntü geliyor ama yazı okunmuyor.</summary>
    public const string OcrSilent = "ocr.silent";

    /// <summary>Yazı tanıma ya da görüntü akışı takıldı.</summary>
    public const string OcrStalled = "ocr.stalled";

    /// <summary>Çeviri gecikmesi yüksek.</summary>
    public const string TrSlow = "tr.slow";

    /// <summary>Çeviri hizmeti sık hata veriyor.</summary>
    public const string TrErrors = "tr.errors";

    /// <summary>Uygulama askıda kaldı.</summary>
    public const string AppHang = "app.hang";

    /// <summary>Bellek ya da işlemci aşırı.</summary>
    public const string AppResources = "app.resources";

    /// <summary>Oyun paketi indirilemedi.</summary>
    public const string PackDownload = "pack.download";

    /// <summary>Sebep belirlenemedi.</summary>
    public const string Unknown = "unknown";

    /// <summary>Öncelik sırası (ilk en yüksek): aynı 5 dakikada yalnız en yükseği gider.</summary>
    public static IReadOnlyList<string> ByPriority { get; } =
    [
        AppHang, Ps5NoReturn, TvFlapping, OcrStalled, TrErrors, TrSlow, OcrSilent, AppResources, PackDownload,
    ];

    static readonly Dictionary<string, (DiagSeverity Sev, string[] Causes, bool Network)> Table = new(StringComparer.Ordinal)
    {
        [Ps5NoReturn] = (DiagSeverity.Error, ["network_lost", "ps5_standby", "ps5_closed", "kicked", "stalled", "timeout"], true),
        [TvFlapping] = (DiagSeverity.Warn, ["write_error", "timeout", "closed", "resume", "network_change", "replaced", "mixed"], true),
        [OcrSilent] = (DiagSeverity.Info, ["video_black", "region_wrong", "no_text"], false),
        [OcrStalled] = (DiagSeverity.Error, ["ocr_hang", "frames_stopped", "decoder"], false),
        [TrSlow] = (DiagSeverity.Warn, ["provider_slow", "pool_slow", "device_busy", "network_slow"], true),
        [TrErrors] = (DiagSeverity.Warn, ["quota", "auth", "offline", "server", "timeout"], true),
        [AppHang] = (DiagSeverity.Error, ["main_thread"], false),
        [AppResources] = (DiagSeverity.Warn, ["memory_high", "cpu_high", "thermal"], false),
        [PackDownload] = (DiagSeverity.Warn, ["offline", "http_4xx", "http_5xx", "corrupt", "storage_full"], true),
    };

    /// <summary>Bilinen bütün kurallar.</summary>
    public static IEnumerable<string> All => Table.Keys;

    /// <summary>Kuralın önceliği (küçük daha önemli; bilinmeyen en sonda).</summary>
    public static int Priority(string rule)
    {
        for (var i = 0; i < ByPriority.Count; i++)
            if (ByPriority[i] == rule) return i;
        return ByPriority.Count;
    }

    /// <summary>Kuralın önemi (bilinmeyen kural: <c>warn</c>).</summary>
    public static DiagSeverity Severity(string rule) => Table.TryGetValue(rule, out var r) ? r.Sev : DiagSeverity.Warn;

    /// <summary>Kuralın sebep kodları (<c>unknown</c> her kuralda geçerlidir).</summary>
    public static IReadOnlyList<string> Causes(string rule) => Table.TryGetValue(rule, out var r) ? r.Causes : [];

    /// <summary>Sebep bu kuralın kodlarından değilse <c>unknown</c>.</summary>
    public static string CauseOrUnknown(string rule, string? cause) =>
        cause is not null && Table.TryGetValue(rule, out var r) && r.Causes.Contains(cause) ? cause : Unknown;

    /// <summary>
    /// Ağ kuralı mı: ağ tamamen gittiğinde yalnız bunlar çalışmaya devam eder (bildirim kuyrukta ağı bekler); öbürleri
    /// susar.
    /// </summary>
    public static bool IsNetworkRule(string rule) => Table.TryGetValue(rule, out var r) && r.Network;

    /// <summary>Önemin JSON yazımı.</summary>
    public static string Code(DiagSeverity sev) => sev switch
    {
        DiagSeverity.Info => "info",
        DiagSeverity.Error => "error",
        _ => "warn",
    };
}

/// <summary>Varsayılan eşikler ve uzak ayardaki anahtar adları (iki yazım da kabul edilir).</summary>
public static class DiagLimitKeys
{
    /// <summary>PS5 kopmasından sonra beklenecek süre (sn).</summary>
    public static readonly DiagLimit Ps5NoReturnSec = new("ps5.no_return.sec", "ps5NoReturnSec", 180);

    /// <summary>TV kopma penceresi (dk).</summary>
    public static readonly DiagLimit TvFlapWindowMin = new("tv.flapping.windowMin", "tvFlapWindowMin", 10);

    /// <summary>Pencerede kaç kopma.</summary>
    public static readonly DiagLimit TvFlapCount = new("tv.flapping.count", "tvFlapCount", 3);

    /// <summary>Yazı okunmadan geçen süre (dk).</summary>
    public static readonly DiagLimit OcrSilentMin = new("ocr.silent.min", "ocrSilentMin", 15);

    /// <summary>Yazı tanıma isteğinin takılmış sayılma süresi (sn).</summary>
    public static readonly DiagLimit OcrStallSec = new("ocr.stalled.sec", "ocrStallSec", 10);

    /// <summary>PS5 bağlıyken kare gelmeyen süre (sn).</summary>
    public static readonly DiagLimit FrameStallSec = new("ocr.stalled.frameSec", "frameStallSec", 30);

    /// <summary>Çeviri gecikmesi p90 eşiği (ms).</summary>
    public static readonly DiagLimit TrSlowP90Ms = new("tr.slow.p90Ms", "trSlowP90Ms", 3000);

    /// <summary>Çeviri hata oranı eşiği (0–1; 1'den büyük verilirse yüzde sayılır).</summary>
    public static readonly DiagLimit TrErrorRate = new("tr.errors.rate", "trErrorRate", 0.30);

    /// <summary>Ana iş parçacığı yanıtsız süre (sn).</summary>
    public static readonly DiagLimit HangSec = new("app.hang.sec", "hangSec", 5);

    /// <summary>Bellek eşiği (MB; masaüstü varsayılanı).</summary>
    public static readonly DiagLimit MemHighMB = new("app.resources.memMB", "memHighMB", 1500);

    /// <summary>İşlemci eşiği (%).</summary>
    public static readonly DiagLimit CpuHighPct = new("app.resources.cpu", "cpuHighPct", 90);

    /// <summary>Kaynak sınırının sürmesi gereken süre (sn).</summary>
    public static readonly DiagLimit ResourceSec = new("app.resources.sec", "resourceSec", 120);

    /// <summary>Aynı paket art arda kaç kez inmezse.</summary>
    public static readonly DiagLimit PackAttempts = new("pack.download.attempts", "packAttempts", 3);

    /// <summary>Aynı paket kaç saattir inmiyorsa.</summary>
    public static readonly DiagLimit PackHours = new("pack.download.hours", "packHours", 24);

    /// <summary>Hepsi.</summary>
    public static IReadOnlyList<DiagLimit> All { get; } =
    [
        Ps5NoReturnSec, TvFlapWindowMin, TvFlapCount, OcrSilentMin, OcrStallSec, FrameStallSec, TrSlowP90Ms,
        TrErrorRate, HangSec, MemHighMB, CpuHighPct, ResourceSec, PackAttempts, PackHours,
    ];
}

/// <summary>Bir eşik: uzak ayar anahtarı, eş adı ve varsayılan değeri.</summary>
public sealed record DiagLimit(string Key, string Alias, double Default);
