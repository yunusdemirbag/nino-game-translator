// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using System.Text.Json;

namespace Nino.Core.Translation;

/// <summary>Yapay zekâ hizmeti.</summary>
public enum AiService { Gemini, OpenAi, Claude, Local }

/// <summary>Model listesindeki bir model (çeviri tarifi §12.2).</summary>
public sealed record AiModel(string Id, string TextKey, string? Effort, string? Thinking, bool FreeTier,
    int? RequestsPerMinute);

/// <summary>
/// Gömülü <c>ai-models.json</c>: hizmet adı → model dizisi; ilk model varsayılan; dizi olmayan alanlar ve boş diziler
/// atlanır.
/// </summary>
public sealed class AiModelCatalog
{
    readonly Dictionary<string, IReadOnlyList<AiModel>> _services;

    AiModelCatalog(Dictionary<string, IReadOnlyList<AiModel>> services) => _services = services;

    /// <summary>Gömülü liste.</summary>
    public static AiModelCatalog Default => DefaultLazy.Value;

    static readonly Lazy<AiModelCatalog> DefaultLazy = new(() =>
    {
        using var stream = typeof(AiModelCatalog).Assembly.GetManifestResourceStream("ai-models.json")!;
        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        return Parse(ms.ToArray());
    });

    /// <summary>JSON'dan okur.</summary>
    public static AiModelCatalog Parse(byte[] json)
    {
        var services = new Dictionary<string, IReadOnlyList<AiModel>>(StringComparer.Ordinal);
        using var doc = JsonDocument.Parse(json);
        foreach (var service in doc.RootElement.EnumerateObject())
        {
            if (service.Value.ValueKind != JsonValueKind.Array) continue;
            var models = new List<AiModel>();
            foreach (var m in service.Value.EnumerateArray())
            {
                if (m.ValueKind != JsonValueKind.Object || Text(m, "id") is not { Length: > 0 } id) continue;
                int? rpm = m.TryGetProperty("requestsPerMinute", out var r) && r.ValueKind == JsonValueKind.Number
                    && r.TryGetInt32(out var n) ? n : null;
                var free = m.TryGetProperty("freeTier", out var f) && f.ValueKind == JsonValueKind.True;
                models.Add(new AiModel(id, Text(m, "text") ?? id, Text(m, "effort"), Text(m, "thinking"), free, rpm));
            }
            if (models.Count > 0) services[service.Name] = models;
        }
        return new AiModelCatalog(services);
    }

    static string? Text(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>Hizmetin listedeki adı (<c>gemini</c>, <c>openai</c>, <c>claude</c>); yerel model için null.</summary>
    public static string? ServiceName(AiService service) => service switch
    {
        AiService.Gemini => "gemini",
        AiService.OpenAi => "openai",
        AiService.Claude => "claude",
        _ => null,
    };

    /// <summary>Bulut hizmetleri (listedeki adlar).</summary>
    public IReadOnlyCollection<string> Services => _services.Keys;

    /// <summary>Hizmetin modelleri (yoksa boş).</summary>
    public IReadOnlyList<AiModel> Models(AiService service) =>
        ServiceName(service) is { } name && _services.TryGetValue(name, out var list) ? list : [];

    /// <summary>Kayıtlı model listedeyse o, değilse varsayılan (ilk). Liste boşsa null.</summary>
    public AiModel? Resolve(AiService service, string? saved)
    {
        var models = Models(service);
        if (models.Count == 0) return null;
        var trimmed = saved?.Trim();
        return models.FirstOrDefault(m => m.Id == trimmed) ?? models[0];
    }

    /// <summary>Hizmetin ücretsiz katmanı var mı.</summary>
    public bool HasFreeTier(AiService service) => Models(service).Any(m => m.FreeTier);
}

/// <summary>Yerel model sunucusunun türü (hata iletileri için).</summary>
public enum LocalServerKind { Ollama, LmStudio, Other }

/// <summary>Yerel model sunucusu (çeviri tarifi §12.7).</summary>
/// <param name="BaseUrl">Düzeltilmiş temel adres (sondaki <c>/</c> yok, <c>…/v1</c>).</param>
/// <param name="Model">Kırpılmış model adı.</param>
public sealed record LocalServer(string BaseUrl, string Model)
{
    /// <summary>Ollama'nın adresi.</summary>
    public const string OllamaUrl
        = "http://localhost:11434/v1";

    /// <summary>LM Studio'nun adresi.</summary>
    public const string LmStudioUrl
        = "http://localhost:1234/v1";

    /// <summary>Varsayılan model.</summary>
    public const string DefaultModel
        = "translategemma:4b";

    /// <summary>Kullanıcının yazdığı adresi düzeltir; geçersizse null.</summary>
    public static string? NormalizeAddress(string? input)
    {
        var text = (input ?? "").Trim();
        if (text.Length == 0 || text.Any(char.IsWhiteSpace)) return null;
        if (!text.Contains("://",
            StringComparison.Ordinal)) text = "http://" + text;
        text = text.TrimEnd('/');
        if (text.EndsWith("/chat/completions", StringComparison.OrdinalIgnoreCase))
            text = text[..^"/chat/completions".Length].TrimEnd('/');
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return null;
        if (uri.Host.Length == 0) return null;
        var path = uri.AbsolutePath;
        if (path.Length == 0 || path == "/") path = "/v1";
        return (uri.GetLeftPart(UriPartial.Authority) + path).TrimEnd('/');
    }

    /// <summary>Adres ve modelden sunucu; model boşsa ya da adres geçersizse null.</summary>
    public static LocalServer? Create(string? address, string? model)
    {
        var url = NormalizeAddress(address);
        var name = (model ?? "").Trim();
        return url is null || name.Length == 0 ? null : new LocalServer(url, name);
    }

    Uri Uri => new(BaseUrl);

    /// <summary>İstek adresi.</summary>
    public string ChatUrl => BaseUrl + "/chat/completions";

    /// <summary>Gösterilen kısa adres: şema + makine + kapı.</summary>
    public string ShortAddress => Uri.GetLeftPart(UriPartial.Authority);

    /// <summary>Kapıya göre tür.</summary>
    public LocalServerKind Kind => Uri.Port switch
    {
        11434 => LocalServerKind.Ollama,
        1234 => LocalServerKind.LmStudio,
        _ => LocalServerKind.Other,
    };

    /// <summary>Motor adı: <c>local:&lt;makine&gt;[:&lt;kapı&gt;]/&lt;model&gt;</c> (kapı yalnız varsayılan değilse).</summary>
    public string EngineName => "local:" + Uri.Host.ToLowerInvariant() + (Uri.IsDefaultPort ? "" : ":" + Uri.Port) + "/" + Model;

    /// <summary>Model bir çeviri modeli mi (kendi istem kalıbı olan).</summary>
    public bool IsTranslationModel =>
        Model.Contains("translategemma", StringComparison.OrdinalIgnoreCase)
        || Model.Contains("milmmt", StringComparison.OrdinalIgnoreCase);
}

/// <summary>Motor adları (önbellek dosyası ve günlük).</summary>
public static class EngineNames
{
    /// <summary>DeepL.</summary>
    public const string DeepL = "deepl";

    /// <summary>Bulut yapay zekâ motoru: <c>&lt;hizmet&gt;:&lt;model&gt;</c>.</summary>
    public static string Cloud(AiService service, string model) => AiModelCatalog.ServiceName(service) + ":" + model;
}

/// <summary>
/// Dakikalık istek hakkı (çeviri tarifi §9): kayan 60 sn'lik pencere. Sınır yalnız düşürülür.
/// </summary>
public sealed class RequestBudget
{
    /// <summary>Pencere.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromSeconds(60);

    static readonly ConcurrentDictionary<string, RequestBudget> SharedBudgets = new(StringComparer.Ordinal);

    readonly TimeProvider _clock;
    readonly Queue<DateTimeOffset> _sent = new();
    readonly object _gate = new();
    int _limit;

    public RequestBudget(int limit, TimeProvider? clock = null)
    {
        _limit = Math.Max(1, limit);
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>
    /// Motor adı başına uygulama genelinde tek hak (çeviri hattı yeniden kurulsa da sıfırlanmaz). Değer yoksa null
    /// (sınırsız).
    /// </summary>
    public static RequestBudget? Shared(string engineName, int? requestsPerMinute, TimeProvider? clock = null) =>
        requestsPerMinute is not { } rpm ? null : SharedBudgets.GetOrAdd(engineName, _ => new RequestBudget(rpm, clock));

    /// <summary>Şu anki sınır.</summary>
    public int Limit
    {
        get { lock (_gate) return _limit; }
    }

    void Drop(DateTimeOffset now)
    {
        while (_sent.Count > 0 && now - _sent.Peek() >= Window) _sent.Dequeue();
    }

    /// <summary>Hak al: penceredeki istek sayısı sınıra ulaştıysa false (istek gönderilmez).</summary>
    public bool TryAcquire()
    {
        lock (_gate)
        {
            var now = _clock.GetUtcNow();
            Drop(now);
            if (_sent.Count >= _limit) return false;
            _sent.Enqueue(now);
            return true;
        }
    }

    /// <summary>İsteği sayar ama beklemez ("ekranı çevir": kullanıcı tuşa bastı).</summary>
    public void Count()
    {
        lock (_gate)
        {
            var now = _clock.GetUtcNow();
            Drop(now);
            _sent.Enqueue(now);
        }
    }

    /// <summary>Sınırı düşürür: yeni = max(1, min(eski, bildirilen)).</summary>
    public void Lower(int reported)
    {
        lock (_gate) _limit = Math.Max(1, Math.Min(_limit, reported));
    }
}
