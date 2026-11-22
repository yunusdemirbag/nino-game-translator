// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Translation;

/// <summary>Bir satırın çevirisinin nereden geldiği (günlükteki "son kaynak").</summary>
public enum TranslationOrigin
{
    /// <summary>Temel çevirmen (çevrimiçi motor ya da ücretsiz model temel çevirmense o).</summary>
    Engine,

    /// <summary>Havuz öncelikli oyunda sunucudan geldi.</summary>
    Pool,

    /// <summary>Havuz öncelikli oyunda sunucu yanıt vermedi; cihaz içi ücretsiz çevirmen çevirdi.</summary>
    Free,

    /// <summary>Satır zaten hedefin yazısıyla yazılmış; çevrilmeden olduğu gibi döndü (§13.3).</summary>
    AlreadyTarget,
}

/// <summary>Çeviri sonucu.</summary>
public sealed record TranslationResult(string Text, TranslationOrigin Origin)
{
    /// <summary>Temel çevirmenin sonucu.</summary>
    public static TranslationResult FromEngine(string text) => new(text, TranslationOrigin.Engine);
}

/// <summary>
/// Okuma hattının, telefon/harita okuyucusunun ve "ekranı çevir"in çağırdığı çevirmen. Zincirin her katmanı da bu
/// arayüzü uygular (yazı denetimi → havuz önceliği → temel çevirmen). Hata türleri:
/// <see cref="TranslatorUnavailableException"/> (motor yok/indirilmeli/açılamadı/kapatıldı),
/// <see cref="OperationCanceledException"/> (iptal). Başka hatalar satırı düşürür; okuma hattı sonra yeniden dener.
/// </summary>
public interface ITranslator
{
    /// <summary>Önbellek ve günlük için motor adı (<c>opus-mt-ct2-p3</c>, <c>deepl</c>, <c>gemini:…</c>, <c>local:…</c>).</summary>
    string EngineName { get; }

    /// <summary>Ön çeviriyi (satır kararlı olmadan arka planda çevirmeyi) destekliyor mu.</summary>
    bool SupportsPretranslation { get; }

    /// <summary>Birden çok bağımsız metni tek istekte çevirebiliyor mu ("ekranı çevir").</summary>
    bool SupportsBatch { get; }

    /// <summary>Bir altyazı satırını (birden çok cümle ve satır içerebilir) çevirir.</summary>
    Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default);

    /// <summary>
    /// Ön çeviri: sonucu önbelleğe ısıtır, hata fırlatmaz. Desteklemeyen çevirmen hiçbir şey yapmaz.
    /// </summary>
    Task PretranslateAsync(string text, CancellationToken cancellationToken = default);

    /// <summary>
    /// Bağımsız metinleri sırasıyla çevirir. <see cref="SupportsBatch"/> yanlışsa metinler tek tek
    /// <see cref="TranslateAsync"/> ile çevrilir.
    /// </summary>
    Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken cancellationToken = default);
}

/// <summary>Çevirmenin şu an çeviremeyişinin nedeni.</summary>
public enum UnavailableReason
{
    /// <summary>Bu dil çifti için ücretsiz model yok.</summary>
    Unsupported,

    /// <summary>Model dosyaları indirilmeli.</summary>
    DownloadRequired,

    /// <summary>Motor bu bilgisayarda açılamadı (kalıcı).</summary>
    EngineFailed,

    /// <summary>Çevirmen kapatıldı.</summary>
    Closed,
}

/// <summary>Çevirmen kullanılamıyor.</summary>
public sealed class TranslatorUnavailableException : Exception
{
    public TranslatorUnavailableException(UnavailableReason reason, string? message = null, Exception? inner = null)
        : base(message ?? DefaultMessage(reason), inner)
    {
        Reason = reason;
    }

    /// <summary>Neden.</summary>
    public UnavailableReason Reason { get; }

    static string DefaultMessage(UnavailableReason reason) => reason switch
    {
        UnavailableReason.Unsupported => "Bu dil çifti için ücretsiz çeviri modeli yok.",
        UnavailableReason.DownloadRequired => "Çeviri modeli indirilmeli.",
        UnavailableReason.EngineFailed => "Çeviri için gereken motor bu bilgisayarda başlatılamadı.",
        _ => "Çevirmen kapatıldı.",
    };
}

/// <summary>Çevrimiçi motorun (DeepL, yapay zekâ, yerel model) hata türü.</summary>
public enum OnlineFailure
{
    /// <summary>Anahtar kabul edilmedi.</summary>
    InvalidKey,

    /// <summary>Kredi/kota bitti.</summary>
    QuotaExhausted,

    /// <summary>Model ya da istek reddedildi.</summary>
    ModelRejected,

    /// <summary>Hizmete ulaşılamadı (ağ, zaman aşımı, sunucu hatası, anlaşılmayan yanıt).</summary>
    Unreachable,
}

/// <summary>
/// Çevrimiçi motorun durumu: ana ekranın "şu an çevirmiyor" uyarısı ve ayarlardaki açıklama bunu okur.
/// Hata durumu yalnız değişince bildirilir (başla: tür; düzel: null). Dakikalık sınır hata sayılmaz.
/// </summary>
public interface IOnlineEngineStatus
{
    /// <summary>Son hata; yoksa null.</summary>
    OnlineFailure? LastFailure { get; }

    /// <summary>Son çevrilen satır dakikalık istek sınırına takılıp yedekle çevrildi mi.</summary>
    bool LastLineHitMinuteLimit { get; }

    /// <summary>Hata durumu değişti (herhangi bir iş parçacığından gelebilir).</summary>
    event Action<OnlineFailure?>? FailureChanged;
}

/// <summary>Çevirmenlere ortak yardımcılar.</summary>
public static class TranslatorExtensions
{
    /// <summary>Metinleri tek tek çevirir (toplu çeviriyi desteklemeyenlerin varsayılanı).</summary>
    public static async Task<IReadOnlyList<string>> TranslateOneByOneAsync(this ITranslator translator,
        IReadOnlyList<string> texts, CancellationToken cancellationToken)
    {
        var results = new string[texts.Count];
        for (var i = 0; i < texts.Count; i++)
            results[i] = (await translator.TranslateAsync(texts[i], cancellationToken).ConfigureAwait(false)).Text;
        return results;
    }
}
