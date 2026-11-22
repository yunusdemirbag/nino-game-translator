// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Nino.Core.Translation;

namespace Nino.Translation.Online;

/// <summary>Anahtar denemesinin sonucu.</summary>
public enum KeyCheckStatus { Valid, InvalidKey, QuotaExhausted, ModelRejected, Unreachable }

/// <summary>Yapay zekâ anahtar denemesi: durum ve (geçerliyse) örnek çeviri.</summary>
public sealed record KeyCheckResult(KeyCheckStatus Status, string? Sample)
{
    /// <summary>Anahtar kaydedilmeli mi (geçerli, kota bitmiş ya da model reddedildi).</summary>
    public bool ShouldSave => Status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted or KeyCheckStatus.ModelRejected;
}

/// <summary>DeepL kullanım denetimi: durum, kullanılan ve sınır karakter sayısı.</summary>
public sealed record DeepLUsageResult(KeyCheckStatus Status, long? Used, long? Limit)
{
    /// <summary>Anahtar kaydedilmeli mi (geçerli ya da kota bitmiş).</summary>
    public bool ShouldSave => Status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted;
}

/// <summary>Dakikalık sınır yanıtı: önerilen bekleme ve (biliniyorsa) istek sınırı.</summary>
public sealed record MinuteLimit(TimeSpan? RetryAfter, int? RequestLimit);

/// <summary>Çevrimiçi isteğin hatası (iletisinde anahtar yoktur).</summary>
public sealed class OnlineRequestException(OnlineFailure failure, MinuteLimit? minuteLimit = null)
    : Exception("Çevrimiçi çeviri isteği başarısız: " + failure)
{
    /// <summary>Hata türü.</summary>
    public OnlineFailure Failure { get; } = failure;

    /// <summary>Dakikalık sınırsa ayrıntısı (hata sayılmaz).</summary>
    public MinuteLimit? MinuteLimit { get; } = minuteLimit;
}

/// <summary>Hata durumu, bekleme ve "dakikalık sınırdaydı" işareti; durum yalnız değişince bildirilir.</summary>
internal sealed class OnlineHealth(TimeProvider clock)
{
    public static readonly TimeSpan FailurePause = TimeSpan.FromSeconds(60);

    readonly object _gate = new();
    DateTimeOffset _pausedUntil = DateTimeOffset.MinValue;
    OnlineFailure? _last;

    public event Action<OnlineFailure?>? Changed;

    public OnlineFailure? Last
    {
        get { lock (_gate) return _last; }
    }

    public bool MinuteLimited { get; set; }

    public bool Paused
    {
        get { lock (_gate) return clock.GetUtcNow() < _pausedUntil; }
    }

    /// <summary>Bekleme dakikalık sınırdan mı (bekleme sırasında yedeğe düşen satır da "sınırdaydı" sayılır).</summary>
    public bool PausedForMinute { get; private set; }

    public void PauseFor(TimeSpan span, bool minute = false)
    {
        lock (_gate) _pausedUntil = clock.GetUtcNow() + span;
        PausedForMinute = minute;
    }

    public void Succeeded() => Set(null);

    public void Failed(OnlineFailure failure)
    {
        PauseFor(FailurePause);
        Set(failure);
    }

    void Set(OnlineFailure? value)
    {
        bool changed;
        lock (_gate)
        {
            changed = _last != value;
            _last = value;
        }
        if (changed) Changed?.Invoke(value);
    }
}

/// <summary>HTTP ve JSON yardımcıları.</summary>
internal static class OnlineHttp
{
    public static readonly JsonWriterOptions WriterOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    /// <summary>JSON gövdesini yazar (ASCII dışı kaçışsız).</summary>
    public static string Json(Action<Utf8JsonWriter> write)
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms, WriterOptions)) write(w);
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    public static StringContent JsonContent(string body)
    {
        var content = new StringContent(body, new UTF8Encoding(false));
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json") { CharSet = "utf-8" };
        return content;
    }

    /// <summary>
    /// İsteği gönderir; ağ hatası ve zaman aşımı "ulaşılamadı" olur, çağıranın iptali iptal olarak çıkar.
    /// </summary>
    public static async Task<(HttpStatusCode Status, string Body)> SendAsync(HttpClient http, HttpRequestMessage request,
        TimeSpan timeout, CancellationToken cancellationToken)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(timeout);
        try
        {
            using var response = await http.SendAsync(request, cts.Token).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(cts.Token).ConfigureAwait(false);
            return (response.StatusCode, body);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested is false)
        {
            throw new OnlineRequestException(OnlineFailure.Unreachable);
        }
        catch (HttpRequestException)
        {
            throw new OnlineRequestException(OnlineFailure.Unreachable);
        }
    }

    public static bool Success(HttpStatusCode status) => (int)status is >= 200 and < 300;
}

/// <summary>Yankı denetimi: kaynak ile çeviri sadeleştirilmiş hâlleriyle ≥ 0.90 benzer mi.</summary>
public static class EchoCheck
{
    /// <summary>Eşik.</summary>
    public const double Threshold = 0.90;

    /// <summary>Küçük harf, harf/rakam dışı boşluk, tek boşluk.</summary>
    public static string Simplify(string text)
    {
        var sb = new StringBuilder(text.Length);
        foreach (var c in text.ToLowerInvariant()) sb.Append(char.IsLetterOrDigit(c) ? c : ' ');
        return string.Join(' ', sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>Levenshtein oranı (1 − uzaklık / uzun olanın boyu).</summary>
    public static double Ratio(string a, string b)
    {
        if (a.Length == 0 && b.Length == 0) return 1;
        var prev = new int[b.Length + 1];
        var cur = new int[b.Length + 1];
        for (var j = 0; j <= b.Length; j++) prev[j] = j;
        for (var i = 1; i <= a.Length; i++)
        {
            cur[0] = i;
            for (var j = 1; j <= b.Length; j++)
                cur[j] = Math.Min(Math.Min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            (prev, cur) = (cur, prev);
        }
        return 1 - (double)prev[b.Length] / Math.Max(a.Length, b.Length);
    }

    /// <summary>Çeviri kaynağın yankısı mı.</summary>
    public static bool IsEcho(string source, string translation) =>
        Ratio(Simplify(source), Simplify(translation)) >= Threshold;
}

/// <summary>Çevrimiçi motor hata metinleri (ayarlar ve ana ekran aynı metni kullanır).</summary>
public static class OnlineFailureText
{
    /// <summary>Hizmetin marka adı (yerel model çevrilir: "Yerel model").</summary>
    public static string Brand(AiService service) => service switch
    {
        AiService.Gemini => "Gemini",
        AiService.OpenAi => "OpenAI",
        AiService.Claude => "Claude",
        _ => "Yerel model",
    };

    /// <summary>DeepL'in marka adı.</summary>
    public const string DeepLBrand = "DeepL";

    /// <summary>Anahtar sayfası.</summary>
    public static string KeyPage(AiService service) => service switch
    {
        AiService.Gemini => "https://aistudio.google.com/apikey",
        AiService.OpenAi => "https://platform.openai.com/api-keys",
        AiService.Claude => "https://platform.claude.com/settings/keys",
        _ => "https://ollama.com/download",
    };

    /// <summary>Durumun açıklaması. <paramref name="local"/> yerel model için (yoksa bulut metinleri).</summary>
    public static string Describe(KeyCheckStatus status, string brand, LocalServer? local = null)
    {
        if (status == KeyCheckStatus.Valid) return "Çalışıyor.";
        if (local is null)
            return status switch
            {
                KeyCheckStatus.InvalidKey => $"{brand} bu anahtarı tanımadı. Anahtarı hesap sayfanızdan yeniden kopyalayıp yapıştırın.",
                KeyCheckStatus.QuotaExhausted => $"{brand} hesabınızın kredisi bitti ya da kullanım sınırı doldu.",
                KeyCheckStatus.ModelRejected => $"{brand} bu isteği geri çevirdi. Diğer modeli seçin ya da biraz sonra yeniden deneyin.",
                _ => $"{brand} hizmetine bağlanılamadı. İnternet bağlantınıza bakın.",
            };
        return status switch
        {
            KeyCheckStatus.InvalidKey => "Yerel sunucu anahtarı geri çevirdi. Anahtara bakın; gerekmiyorsa silin.",
            KeyCheckStatus.QuotaExhausted => "Yerel sunucu şu an yoğun. Biraz sonra yeniden deneyin.",
            KeyCheckStatus.ModelRejected => local.Kind == LocalServerKind.LmStudio
                ? $"LM Studio'da {local.Model} adlı model yok. İndirip yükleyin ya da adının doğru yazıldığına bakın."
                : $"{local.Model} yerel sunucuda bulunamadı. Şununla indirin: ollama pull {local.Model}",
            _ => local.Kind switch
            {
                LocalServerKind.Ollama =>
                    $"Ollama çalışmıyor: {local.ShortAddress} yanıt vermedi ya da model zamanında dönmedi. Ollama'yı açın ve modeli indirin: ollama pull {local.Model}",
                LocalServerKind.LmStudio =>
                    $"LM Studio çalışmıyor: {local.ShortAddress} yanıt vermedi. Modeli yükleyip yerel sunucuyu başlatın.",
                _ => $"{local.ShortAddress} adresindeki yerel sunucuya bağlanılamadı. Adrese ve sunucunun açık olduğuna bakın.",
            },
        };
    }

    /// <summary>Hata türünün açıklaması.</summary>
    public static string Describe(OnlineFailure failure, string brand, LocalServer? local = null) =>
        Describe(ToStatus(failure), brand, local);

    /// <summary>Hata türü → deneme durumu.</summary>
    public static KeyCheckStatus ToStatus(OnlineFailure failure) => failure switch
    {
        OnlineFailure.InvalidKey => KeyCheckStatus.InvalidKey,
        OnlineFailure.QuotaExhausted => KeyCheckStatus.QuotaExhausted,
        OnlineFailure.ModelRejected => KeyCheckStatus.ModelRejected,
        _ => KeyCheckStatus.Unreachable,
    };
}
