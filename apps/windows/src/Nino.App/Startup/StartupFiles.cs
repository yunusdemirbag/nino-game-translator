// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;

namespace Nino.App.Startup;

// BU DOSYA YALNIZ .NET'İN KENDİ TÜRLERİNİ KULLANIR (kimlikler-veri.md §3.3): uygulamanın öbür DLL'leri (Nino.Core,
// Nino.Shell …) eksik olabilir; denetim ve iletisi onlara dokunmadan çalışmalı. Nino.Shell.Tests bu dosyayı bağlantıyla
// derleyip sınar.

/// <summary>Açılışta program klasöründe eksik dosya denetimi (<c>Nino.deps.json</c>).</summary>
public static class StartupFiles
{
    /// <summary>Denetlenen dosya.</summary>
    public const string DepsFile = "Nino.deps.json";

    /// <summary>İletide gösterilen en çok dosya.</summary>
    public const int MaxListed = 8;

    /// <summary>
    /// <c>targets</c> altındaki her kitaplığın <c>runtime</c> bölümündeki dosyaların yalnız adları (büyük/küçük harf
    /// duyarsız, tekil, sıralı). Dosya yoksa ya da okunamazsa boş.
    /// </summary>
    public static IReadOnlyList<string> RuntimeFileNames(string depsJson)
    {
        var found = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var doc = JsonDocument.Parse(depsJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty("targets", out var targets) || targets.ValueKind != JsonValueKind.Object)
                return [];
            foreach (var target in targets.EnumerateObject())
            {
                if (target.Value.ValueKind != JsonValueKind.Object) continue;
                foreach (var lib in target.Value.EnumerateObject())
                {
                    if (lib.Value.ValueKind != JsonValueKind.Object) continue;
                    if (!lib.Value.TryGetProperty("runtime", out var runtime) || runtime.ValueKind != JsonValueKind.Object)
                        continue;
                    foreach (var entry in runtime.EnumerateObject())
                    {
                        var name = Path.GetFileName(entry.Name.Replace('\\', '/'));
                        if (name.Length > 0) found.Add(name);
                    }
                }
            }
        }
        catch (JsonException)
        {
            return [];
        }
        return found.ToArray();
    }

    /// <summary>Klasörde olmayan çalışma dosyaları; <c>Nino.deps.json</c> yoksa ya da okunamazsa boş.</summary>
    public static IReadOnlyList<string> FindMissing(string appFolder)
    {
        string json;
        try
        {
            var path = Path.Combine(appFolder, DepsFile);
            if (!File.Exists(path)) return [];
            json = File.ReadAllText(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return [];
        }
        var present = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (var file in Directory.EnumerateFiles(appFolder)) present.Add(Path.GetFileName(file));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return [];
        }
        return RuntimeFileNames(json).Where(n => !present.Contains(n)).ToArray();
    }
}

/// <summary>
/// Açılış hata iletileri, sabit Türkçe ve İngilizce (katalog yüklenemese de gösterilebilsin). Windows arayüz dilinin
/// iki harfi "tr" ise Türkçe, değilse İngilizce.
/// </summary>
public static class StartupMessages
{
    /// <summary>Sorun bildirme sayfası.</summary>
    public const string IssuesUrl = "https://github.com/yunusdemirbag/nino-game-translator/issues";

    /// <summary>İleti kutusunun başlığı.</summary>
    public const string Title = "Nino";

    /// <summary>Arayüz dili Türkçe mi.</summary>
    public static bool Turkish =>
        string.Equals(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, "tr", StringComparison.OrdinalIgnoreCase);

    /// <summary>Eksik dosya iletisi.</summary>
    public static string MissingFiles(IReadOnlyList<string> missing, bool turkish)
    {
        var text = new StringBuilder();
        text.AppendLine(turkish
            ? "Nino başlatılamadı; program klasöründe bulunması gereken şu dosyalar eksik:"
            : "Nino couldn't open: these files are missing from its program folder:");
        foreach (var name in missing.Take(StartupFiles.MaxListed)) text.Append("• ").AppendLine(name);
        if (missing.Count > StartupFiles.MaxListed) text.AppendLine("…");
        text.AppendLine();
        text.Append(turkish
            ? "Büyük ihtimalle bir antivirüs dosyalardan birini karantinaya aldı. Onu Windows Güvenliği › Virüs ve tehdit "
              + "koruması › Koruma geçmişi bölümünden geri alın ya da Nino-windows-x64.zip'i tekrar indirip “Tümünü ayıkla” "
              + "ile açın. Programı zip'in içinden başlatmayın."
            : "Antivirus software has most likely quarantined one of the files. Bring it back via Windows Security › "
              + "Virus & threat protection › Protection history, or get Nino-windows-x64.zip once more and unpack it using "
              + "“Extract all”. Never start the program straight from the zip.");
        return text.ToString();
    }

    /// <summary>Açılışta beklenmeyen hata.</summary>
    public static string StartupError(Exception error, string? errorLogPath, bool turkish) =>
        WithError(turkish ? "Nino'da öngörülmeyen bir hata oluştu:" : "Something went wrong in Nino that it didn't expect:", error,
            errorLogPath, turkish);

    /// <summary>Arayüz iş parçacığında yakalanmamış hata (uygulama kapanmaz).</summary>
    public static string UnhandledError(Exception error, string? errorLogPath, bool turkish) =>
        WithError(turkish ? "Nino'da öngörülmeyen bir hata oluştu:" : "Something went wrong in Nino that it didn't expect:", error,
            errorLogPath, turkish);

    /// <summary>Süreci kapatan arka plan hatası.</summary>
    public static string Crash(Exception? error, string? errorLogPath, bool turkish) =>
        WithError(turkish ? "Bir hata Nino'nun kapanmasına yol açtı:" : "An error forced Nino to shut down:",
            error, errorLogPath, turkish);

    /// <summary>
    /// Rapor ipucu (her hata iletisinin sonu): hata günlüğünün tam yolu ve sorunlar sayfasının adresi (ileti kutusunda
    /// bağlantı tıklanamaz, adres açıkça yazılır).
    /// </summary>
    public static string ReportHint(string? errorLogPath, bool turkish)
    {
        var path = string.IsNullOrEmpty(errorLogPath) ? "hata.log" : errorLogPath;
        return (turkish
                ? $"Hatanın ayrıntısı {path} içinde. Bu dosyayı ekleyerek Nino'nun GitHub sorunlar sayfasına yazabilirsiniz:"
                : $"Details are in {path}. You can report the problem with this file on Nino's GitHub page:")
            + Environment.NewLine + IssuesUrl;
    }

    static string WithError(string head, Exception? error, string? errorLogPath, bool turkish)
    {
        var nl = Environment.NewLine;
        var detail = error is null ? "" : $"{error.GetType().Name}: {error.Message}";
        return head + nl + detail + nl + nl + ReportHint(errorLogPath, turkish);
    }
}
