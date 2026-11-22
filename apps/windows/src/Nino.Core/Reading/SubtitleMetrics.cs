// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Reading;

/// <summary>Gösterilen satırın çevirisinin nereden geldiği.</summary>
public enum ShownOrigin
{
    /// <summary>Kullanılan motor.</summary>
    Engine,

    /// <summary>Hazır paket (ya da havuz sözlüğü) satırı.</summary>
    Pack,

    /// <summary>Sonradan gelen daha iyi havuz çevirisi.</summary>
    Pool,
}

/// <summary>Ölçüm satırının bir parçasının türü (sözcükleri arayüz kendi dilinde yazar).</summary>
public enum MetricPartKind
{
    /// <summary>Yazı tanıma süresi (ms).</summary>
    Ocr,

    /// <summary>Çeviri süresi (ms).</summary>
    Translation,

    /// <summary>"Hazır paketten geldi".</summary>
    FromPack,

    /// <summary>Karenin gelişinden TV'ye gönderilişine geçen süre (ms).</summary>
    Latency,

    /// <summary>Güven yüzdesi.</summary>
    Confidence,
}

/// <summary>Ölçüm satırının bir parçası.</summary>
public readonly record struct MetricPart(MetricPartKind Kind, long Value = 0);

/// <summary>
/// TV'ye giden her yeni satırın gerçek ölçümleri (aynı milisaniye saatiyle). Bilinmeyen değerler null.
/// </summary>
public sealed record SubtitleMetrics(long? OcrMs, long? TranslationMs, long? TotalMs, int? ConfidencePercent,
    ShownOrigin Origin)
{
    /// <summary>
    /// Ölçümleri kurar: OCR süresi eksiyse 0; çeviri süresi bitiş − başlangıç (eksiyse 0); toplam gönderim − geliş
    /// (eksiyse 0); güven 0–1'e sıkıştırılıp yüzdeye, sıfırdan uzağa yuvarlanır.
    /// </summary>
    public static SubtitleMetrics Build(long? arrivedAt, long? ocrMs, long? translateStart, long? translateEnd,
        long? sentAt, double? confidence, ShownOrigin origin)
    {
        long? ocr = ocrMs is { } o ? Math.Max(0, o) : null;
        long? translation = translateStart is { } s && translateEnd is { } e ? Math.Max(0, e - s) : null;
        long? total = arrivedAt is { } a && sentAt is { } t ? Math.Max(0, t - a) : null;
        return new(ocr, translation, total, Percent(confidence), origin);
    }

    /// <summary>Güven yüzdesi: 0–1'e sıkıştırılır, × 100, sıfırdan uzağa yuvarlanır.</summary>
    public static int? Percent(double? confidence) =>
        confidence is { } c ? (int)Math.Round(Math.Clamp(c, 0, 1) * 100, MidpointRounding.AwayFromZero) : null;

    /// <summary>
    /// Ana ekrandaki satırın parçaları, sırayla: OCR süresi; paketse "hazır paket", değilse çeviri süresi; toplam
    /// gecikme; güven. Bilinmeyenler yazılmaz. Parçalar arayüzde <c> · </c> ile ayrılır.
    /// </summary>
    public IReadOnlyList<MetricPart> Parts()
    {
        var parts = new List<MetricPart>();
        if (OcrMs is { } o) parts.Add(new(MetricPartKind.Ocr, o));
        if (Origin == ShownOrigin.Pack) parts.Add(new(MetricPartKind.FromPack));
        else if (TranslationMs is { } t) parts.Add(new(MetricPartKind.Translation, t));
        if (TotalMs is { } total) parts.Add(new(MetricPartKind.Latency, total));
        if (ConfidencePercent is { } c) parts.Add(new(MetricPartKind.Confidence, c));
        return parts;
    }
}
