// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Reading;
using Nino.Core.Translation;

namespace Nino.Core.Phone;

/// <summary>
/// Toplu havuz sorgusu: satırlar (ve bağlam) tek istekte sorulur; her satırın sonucu (yoksa null/boş) sırayla döner.
/// Havuz kullanılamıyorsa hepsi boş döner (<c>TranslationPool.AskManyAsync</c> ile aynı biçim).
/// </summary>
public delegate Task<IReadOnlyList<string?>> PoolBatchQuery(IReadOnlyList<string> lines, IReadOnlyList<string> context,
    CancellationToken cancellationToken);

/// <summary>
/// Telefon ve harita okuyucularına uygulama denetleyicisinin verdikleri. Bilinen çeviri ve sözlük ayarı okuyucularda
/// ayrıca değiştirilebilir (her güncellemede yeniden verilir).
/// </summary>
public sealed record OverlayServices
{
    /// <summary>Saat.</summary>
    public IMsClock Clock { get; init; } = SystemMsClock.Instance;

    /// <summary>Okuyucunun kendi yazı tanıyıcısı (telefon ve harita için ayrı örnekler).</summary>
    public ITextReader? Ocr { get; init; }

    /// <summary>Toplu havuz sorgusu (bağlı değilse null).</summary>
    public PoolBatchQuery? Pool { get; init; }

    /// <summary>Ortak yedek çevirmen (telefon ve harita aynı nesneyi paylaşır).</summary>
    public ITranslator? Fallback { get; init; }

    /// <summary>Okuyucunun kendi çevirmeni (toplu sorgu bağlı değilken kullanılır).</summary>
    public ITranslator? Own { get; init; }

    /// <summary>Bilinen çeviri (havuz/paket deposunda birebir eşleşme); yoksa null döner.</summary>
    public Func<string, string?>? Ready { get; init; }

    /// <summary>Telefon sözlüğü açık mı (hedef dil Türkçe).</summary>
    public bool Glossary { get; init; }

    /// <summary>Hedef dil (harita başlığının büyük harfi için).</summary>
    public string TargetLanguage { get; init; } = "tr";

    /// <summary>Telefon: duraklatılsın mı (harita yakında açıktı).</summary>
    public Func<bool>? Paused { get; init; }

    /// <summary>Telefon ekranı ya da GTA 6'ya özgü yazı görüldü (oyun = GTA 6).</summary>
    public Action? Gta6Seen { get; init; }

    /// <summary>Örtü değişti (kilit dışında çağrılır; dinleyici öğeleri okur).</summary>
    public Action? Changed { get; init; }

    /// <summary>Günlük.</summary>
    public Action<string>? Log { get; init; }
}
