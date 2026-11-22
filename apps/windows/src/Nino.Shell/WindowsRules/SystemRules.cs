// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Reading;
using Nino.Core.Settings;

namespace Nino.Shell.WindowsRules;

// Windows hizmetlerinin küçük, platformdan bağımsız kuralları (tarif: kimlikler-veri §10, §12).

/// <summary>Güncelleme kaynağı ve kimlikleri.</summary>
public static class UpdateSource
{
    /// <summary>GitHub deposu.</summary>
    public const string Repository = "https://github.com/yunusdemirbag/nino-game-translator";

    /// <summary>Sürüm sayfası.</summary>
    public const string ReleasesPage = Repository + "/releases/latest";

    /// <summary>Zip kopyasının sorduğu adres.</summary>
    public const string LatestApi = "https://api.github.com/repos/yunusdemirbag/nino-game-translator/releases/latest";

    /// <summary>Velopack paket kimliği.</summary>
    public const string PackageId = "NinoGameTranslator";

    /// <summary>Velopack kanalı (Windows varsayılanı).</summary>
    public const string Channel = "win";

    /// <summary>Zip kopyasının isteğindeki User-Agent.</summary>
    public const string UserAgent = "Nino";

    /// <summary>Zip kopyasının zaman aşımı.</summary>
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

    /// <summary>
    /// GitHub'ın "son sürüm" yanıtından daha yeni sürüm: <c>tag_name</c>'in baştaki <c>v</c>'leri atılır; bu sürümden
    /// yeniyse o numara, değilse null. JSON ya da alan hatasında null.
    /// </summary>
    public static string? NewerFromLatestJson(string? json, string currentVersion)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty("tag_name", out var tag) || tag.ValueKind != JsonValueKind.String)
                return null;
            var version = (tag.GetString() ?? "").Trim().TrimStart('v', 'V');
            if (version.Length == 0) return null;
            return AppVersion.IsNewer(version, currentVersion) ? version : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

/// <summary>Uyku engelinin Windows yürütme durumu bayrakları (SetThreadExecutionState).</summary>
public static class ExecutionStateRules
{
    /// <summary>Sürekli.</summary>
    public const uint Continuous = 0x80000000;

    /// <summary>Sistem gerekli.</summary>
    public const uint SystemRequired = 0x1;

    /// <summary>Ekran gerekli.</summary>
    public const uint DisplayRequired = 0x2;

    /// <summary>
    /// Bayraklar: çeviri sürerken sistem uykusu engellenir; ekran isteği (çevirinin ya da kartın oyun penceresinin)
    /// varsa ekran da açık kalır ve sistem uykusu her zaman engellenir. Hiçbiri yoksa yalnız sürekli bayrak.
    /// </summary>
    public static uint Flags(bool translating, bool translationDisplay, bool cardDisplay)
    {
        var display = (translating && translationDisplay) || cardDisplay;
        var flags = Continuous;
        if (translating || display) flags |= SystemRequired;
        if (display) flags |= DisplayRequired;
        return flags;
    }
}

/// <summary>Genel kısayolların Windows kimlikleri ve başarısızlık kaydı (kimlikler-veri §12.1).</summary>
public static class HotkeyIds
{
    /// <summary>İlk kimlik (tablo sırası bununla toplanır).</summary>
    public const int First = 0x4353;

    /// <summary>"Tuş boş mu" denemesinin kimliği.</summary>
    public const int Probe = 0x43FF;

    /// <summary>Tekrar etmeme bayrağı.</summary>
    public const uint NoRepeat = 0x4000;

    /// <summary>WM_HOTKEY.</summary>
    public const int WmHotkey = 0x0312;

    /// <summary>Tablodaki n'inci kısayolun kimliği.</summary>
    public static int For(int index) => First + index;

    /// <summary>RegisterHotKey değiştiricileri (Alt 1, Ctrl 2, Shift 4 Windows'la aynı) + tekrar etmeme.</summary>
    public static uint Modifiers(KeyModifiers modifiers) =>
        (uint)(modifiers & (KeyModifiers.Alt | KeyModifiers.Control | KeyModifiers.Shift)) | NoRepeat;
}

/// <summary>Tutulamayan kısayolların günlük satırı: liste değişince bir kez.</summary>
public sealed class HotkeyFailureNote
{
    string _last = "";

    /// <summary>Başarısız tuşlar; liste öncekinden farklı ve boş değilse günlük satırı, değilse null.</summary>
    public string? Update(IEnumerable<HotkeyKey> failed)
    {
        var labels = string.Join(", ", failed.Select(Hotkeys.DisplayName));
        if (labels == _last) return null;
        _last = labels;
        return labels.Length == 0 ? null : "Bu kısayollar başka bir uygulamada kayıtlı olduğu için Nino'ya verilemedi: " + labels;
    }
}

/// <summary>
/// Önbellekli sözlük: sonuçlar sıra duyarlı önbellekte tutulur (20 000'i geçince boşaltılır), sorgular tek kilitle
/// sıralanır. Sorgu null dönerse (denetleyici yok ya da hata) sözcük sözlükte sayılır.
/// </summary>
public sealed class CachedSpellDictionary(Func<string, bool?> lookup) : ISpellDictionary
{
    /// <summary>Önbellek sınırı.</summary>
    public const int CacheLimit = 20_000;

    readonly Dictionary<string, bool> _cache = new(StringComparer.Ordinal);
    readonly object _gate = new();

    /// <inheritdoc />
    public bool Contains(string word)
    {
        lock (_gate)
        {
            if (_cache.TryGetValue(word, out var known)) return known;
            bool result;
            try { result = lookup(word) ?? true; }
            catch (Exception) { result = true; }
            if (_cache.Count >= CacheLimit) _cache.Clear();
            _cache[word] = result;
            return result;
        }
    }

    /// <summary>Önbellekteki kayıt sayısı.</summary>
    public int CachedCount { get { lock (_gate) return _cache.Count; } }
}

/// <summary>OCR dil seçimi (okuma-hatti §3.1, §3.5).</summary>
public static class OcrLanguageRules
{
    /// <summary>Yazım denetimi (ve ona bağlı dört ayar) bu oyun dilinde açılır mı: dil "en" ile başlıyor mu.</summary>
    public static bool UsesSpelling(string? language) =>
        (language ?? "").Trim().StartsWith("en", StringComparison.OrdinalIgnoreCase);

    /// <summary>Motor için denenecek etiketler: önce oyun dili, sonra profil dilleri (tekrarsız).</summary>
    public static IReadOnlyList<string> Candidates(string? language, IEnumerable<string> profileLanguages)
    {
        var list = new List<string>();
        var lang = (language ?? "").Trim();
        if (lang.Length > 0) list.Add(lang);
        foreach (var p in profileLanguages)
            if (!string.IsNullOrWhiteSpace(p) && !list.Contains(p, StringComparer.OrdinalIgnoreCase)) list.Add(p);
        return list;
    }
}
