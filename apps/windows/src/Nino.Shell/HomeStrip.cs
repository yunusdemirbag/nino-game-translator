// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;
using Nino.Core.Text;
using Nino.RemotePlay;

namespace Nino.Shell;

// Ana ekranın başlığı, alt şeridin ortası (güncelleme), sağı (çeviri bağlantısı), kısa durum etiketleri ve anahtar
// önerisi. Mac'in ana ekranıyla aynı kurallar; saf, testleri Nino.Shell.Tests/HomeHintTests.cs'te.

/// <summary>Başlıktaki sürüm hapı.</summary>
public static class VersionLabel
{
    /// <summary>Ad: derleme sürümünün tamamı, ön sürüm eki olmadan ("4.5.4" → "V4.5.4", "4.1.0-beta.2" → "V4.1.0"); boşsa "V0.0".</summary>
    public static string Short(string? full)
    {
        var core = (string.IsNullOrWhiteSpace(full) ? "0.0" : full.Trim()).Split('-', '+')[0];
        return "V" + string.Join('.', core.Split('.').Take(3));
    }

    /// <summary>İpucu: "V4.5.4"; ön sürüm ekliyse "V4.1.0 (4.1.0-beta.2)".</summary>
    public static string Tooltip(string? full) => Short(full) == "V" + full?.Trim() ? Short(full) : $"{Short(full)} ({full})";
}

/// <summary>Elle ya da açılışta yapılan güncelleme denetiminin sonucu (alt şeridin ortası).</summary>
public enum UpdateCheckState
{
    /// <summary>Daha bakılmadı.</summary>
    Idle,

    /// <summary>Bakılıyor.</summary>
    Checking,

    /// <summary>Yeni sürüm yok.</summary>
    UpToDate,

    /// <summary>Bakılamadı (ağ yok …).</summary>
    Failed,
}

/// <summary>Alt şeridin ortasında ne yazar.</summary>
public enum UpdateCenterKind
{
    /// <summary>Yeni sürüm iniyor: "%@ alınıyor…".</summary>
    Downloading,

    /// <summary>Yeni sürüm var: tıklanınca kurulan hap.</summary>
    NewVersion,

    /// <summary>"Bakılıyor…" + yenile düğmesi (devre dışı, döner).</summary>
    Checking,

    /// <summary>"Güncel" ya da "Her şey güncel" + yenile düğmesi.</summary>
    UpToDate,

    /// <summary>"Güncellemelere bak" + yenile düğmesi.</summary>
    Check,
}

/// <summary>Alt şeridin ortası (Mac'teki güncelleme durumu).</summary>
/// <param name="Kind">Ne gösterilir.</param>
/// <param name="TextKey">Metin anahtarı.</param>
/// <param name="Version">Yer tutucuya giden sürüm (iniyor / yeni sürüm).</param>
public readonly record struct UpdateCenterState(UpdateCenterKind Kind, string TextKey, string? Version)
{
    /// <summary>İlk uyan: iniyor, yeni sürüm var, bakılıyor, güncel (TV de güncelse "her şey"), değilse "bak".</summary>
    /// <param name="updating">Yeni sürüm iniyor/kuruluyor.</param>
    /// <param name="newVersion">Bulunan yeni sürüm.</param>
    /// <param name="check">Son denetim.</param>
    /// <param name="tvUpToDate">Eşli TV'deki Nino da güncel.</param>
    public static UpdateCenterState Choose(bool updating, string? newVersion, UpdateCheckState check, bool tvUpToDate) =>
        updating ? new(UpdateCenterKind.Downloading, "home.update.downloading", newVersion ?? "")
        : newVersion is { Length: > 0 } ? new(UpdateCenterKind.NewVersion, "home.update.newVersion", newVersion)
        : check == UpdateCheckState.Checking ? new(UpdateCenterKind.Checking, "home.update.checking", null)
        : check == UpdateCheckState.UpToDate
            ? new(UpdateCenterKind.UpToDate, tvUpToDate ? "home.update.allUpToDate" : "home.update.upToDate", null)
        : new(UpdateCenterKind.Check, "home.update.check", null);

    /// <summary>Yenile düğmesi görünür mü (hap ve indirme hâlinde yok).</summary>
    public bool ShowsRecheck => Kind is UpdateCenterKind.Checking or UpdateCenterKind.UpToDate or UpdateCenterKind.Check;
}

/// <summary>Alt şeridin sağındaki "Çeviri …" bağlantısının değeri.</summary>
public static class TranslationLinkRule
{
    /// <summary>
    /// İlk uyan: havuz öncelikli oyun tanındı ve çeviri dili Türkçe ise "Nino · &lt;oyun&gt; Aktif" (kullanıcının kendi
    /// motoru seçili olsa da); kullanıcının kendi çevrimiçi motoru seçiliyse motorun adı; tanınan bir oyun varsa yine
    /// "Nino · &lt;oyun&gt; Aktif"; değilse yalnız "Nino". "Ücretsiz" gibi bir sıfat hiçbir dilde yazılmaz.
    /// </summary>
    /// <param name="game">Tanınan oyunun okunur adı.</param>
    /// <param name="poolFirst">Oyun havuz öncelikli mi.</param>
    /// <param name="targetLanguage">Çeviri dili.</param>
    /// <param name="userEngine">Kullanıcının seçtiği çevrimiçi motorun adı (Nino'nun kendi çevirisiyse null).</param>
    /// <param name="text">Metinler.</param>
    public static string Value(string? game, bool poolFirst, string? targetLanguage, string? userEngine, ITextSource text)
    {
        var known = string.IsNullOrWhiteSpace(game) ? null : game.Trim();
        if (known is not null && poolFirst && targetLanguage == "tr") return text.Format("home.translation.poolGame", known);
        if (!string.IsNullOrEmpty(userEngine)) return userEngine;
        if (known is not null) return text.Format("home.translation.poolGame", known);
        return "Nino";
    }
}

/// <summary>Kaynağın (PS5, pencere, kart) alt şeritteki kısa etiketleri (uzun metin ipucunda kalır).</summary>
public static class HomeShortStatus
{
    /// <summary>PS5 kopma nedeninin kısa etiketi; bilinmeyen/diğer neden için null (uzun "yeniden bağlanılıyor" kalır).</summary>
    public static string? DropKey(DisconnectReason? reason) => reason switch
    {
        DisconnectReason.ConsoleAsleep => "home.short.asleep",
        DisconnectReason.InUse => "home.short.busy",
        DisconnectReason.Refused or DisconnectReason.RegistrationInvalid => "home.short.pairAgain",
        DisconnectReason.LoginPasscode => "home.short.passcode",
        DisconnectReason.LoginPasscodeIncorrect => "home.short.passcodeWrong",
        DisconnectReason.RemotePlayDisabled => "home.short.remotePlayOff",
        DisconnectReason.NotFound => "home.short.notFound",
        DisconnectReason.Network => "home.short.noReply",
        DisconnectReason.Rejected => "home.short.sessionRefused",
        _ => null,
    };

    /// <summary>Şeritte kullanılan bütün kısa anahtarlar (testler 12 dilde bulunduklarını sınar).</summary>
    public static IReadOnlyList<string> Keys { get; } =
    [
        "home.short.asleep", "home.short.busy", "home.short.pairAgain", "home.short.passcode", "home.short.passcodeWrong",
        "home.short.remotePlayOff", "home.short.notFound", "home.short.noReply", "home.short.sessionRefused",
        "home.short.paired", "home.short.waiting", "home.short.searching", "home.short.permission", "home.short.noCard",
        "home.short.darkScreen", "home.short.appMissing", "home.short.tvWaiting", "home.short.tvSetUp",
    ];
}

/// <summary>Ana ekranın "Bu oyun için çeviri anahtarı ekle" önerisi (kapatılabilir, oyun başına).</summary>
public static class KeySuggestionRule
{
    /// <summary>Kapatılan oyunların dosyası (veri klasöründe; satır başına bir oyun kimliği).</summary>
    public const string DismissedFile = "key-suggestion-dismissed.txt";

    /// <summary>
    /// Öneri hangi oyun için (gösterilmeyecekse null): kurulum bitti, kullanıcının anahtarlı motoru yok, oyunun dili
    /// İngilizce, tanınan bir oyun var, o oyunda kapatılmadı ve Nino'da önceden çevrilmiş satırı bulunmuyor (havuz öncelikli değil, paketten
    /// tanınmadı, aynı adlı kurulu paket yok).
    /// </summary>
    public static string? Game(bool setupComplete, bool hasUserEngine, string? sourceLanguage, string? game, bool poolFirst,
        bool recognizedFromPack, IEnumerable<PackInfo> packs, IReadOnlySet<string> dismissed)
    {
        if (!setupComplete || hasUserEngine || sourceLanguage != "en" || string.IsNullOrWhiteSpace(game)) return null;
        if (dismissed.Contains(IdOf(game))) return null;
        if (poolFirst || recognizedFromPack) return null;
        if (packs.Any(p => GameIds.Same(p.Title, game) || GameIds.Same(p.Id, game))) return null;
        return game;
    }

    /// <summary>Oyunun kalıcı kimliği (asıl oyun kimliği; bulunamazsa küçük harfli ad).</summary>
    public static string IdOf(string game) => GameIds.FromName(game) ?? game.Trim().ToLowerInvariant();

    /// <summary>Kapatılanlar okunur (dosya yoksa boş).</summary>
    public static HashSet<string> ReadDismissed(string? folder)
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrEmpty(folder)) return set;
        try
        {
            var path = Path.Combine(folder, DismissedFile);
            if (!File.Exists(path)) return set;
            foreach (var line in File.ReadAllLines(path))
                if (line.Trim() is { Length: > 0 } id) set.Add(id);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { }
        return set;
    }

    /// <summary>Kapatılanlar yazılır (sıralı; yazılamazsa sessizce geçer).</summary>
    public static void WriteDismissed(string? folder, IEnumerable<string> ids)
    {
        if (string.IsNullOrEmpty(folder)) return;
        try
        {
            Directory.CreateDirectory(folder);
            File.WriteAllLines(Path.Combine(folder, DismissedFile), ids.Order(StringComparer.Ordinal));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { }
    }
}
