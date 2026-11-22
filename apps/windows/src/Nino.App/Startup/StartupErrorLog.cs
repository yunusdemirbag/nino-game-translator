// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using Nino.Core;
using Nino.Core.Data;
using Nino.Core.Logging;

namespace Nino.App.Startup;

/// <summary>
/// Açılışın <c>hata.log</c>'u. Çekirdek DLL'i yüklenebiliyorsa veri klasörü kararından (<see cref="NinoDataFolder"/>),
/// yüklenemiyorsa .NET türleriyle <c>%LOCALAPPDATA%\Nino\hata.log</c>'a yazar. Biçim aynı:
/// <c>[yyyy-AA-gg SS:dd:ss] ileti</c> + satır sonu + hatanın tam metni + boş satır. Yazılamazsa sessizce geçilir.
/// </summary>
public static class StartupErrorLog
{
    static readonly object Gate = new();

    /// <summary>Günlüğün tam yolu.</summary>
    public static string FilePath
    {
        get
        {
            try { return CorePath(); }
            catch (Exception) { return FallbackPath; }
        }
    }

    /// <summary>İletilerde gösterilen yol (tam yol).</summary>
    public static string DisplayPath => FilePath;

    static string FallbackPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nino", "hata.log");

    [MethodImpl(MethodImplOptions.NoInlining)]
    static string CorePath() => NinoDataFolder.Current.File(LogNames.Error);

    /// <summary>Bir hata kaydı ekler.</summary>
    public static void Write(string message, Exception? error = null)
    {
        var nl = Environment.NewLine;
        var stamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        var text = $"[{stamp}] {message}{nl}{error?.ToString() ?? ""}{nl}{nl}";
        lock (Gate)
        {
            try
            {
                var path = FilePath;
                if (Path.GetDirectoryName(path) is { Length: > 0 } folder) Directory.CreateDirectory(folder);
                File.AppendAllText(path, text, new UTF8Encoding(false));
            }
            catch (Exception) { }
        }
    }
}

/// <summary>Veri klasörünün açılıştaki hazırlığı (kimlikler-veri.md §3.1 adım 3, §5).</summary>
public static class DataFolderStep
{
    /// <summary>
    /// <see cref="NinoDataFolder.Prepare"/>'i çağırır; taşıma hatasını ve kopyalamayı <c>hata.log</c>'a yazar. İmzası
    /// yalnız .NET türleri taşır: çekirdek DLL'i yoksa hata çağıranın <c>try</c>'ında yakalanabilsin.
    /// </summary>
    [MethodImpl(MethodImplOptions.NoInlining)]
    public static void Prepare()
    {
        var choice = NinoDataFolder.Prepare();
        if (choice.Error is { } error)
            StartupErrorLog.Write($"Veri klasörünün adı Nino olarak değiştirilemedi; bu sefer eski klasörle devam ediliyor: {choice.Path}" +
                Environment.NewLine + error);
        if (choice.Copied)
            StartupErrorLog.Write("Eski veri klasörü (" + LegacyNames.DataFolder + ") başka bir uygulamada da açık olduğundan " +
                $"yerinde bırakıldı; içindekiler {choice.Path} altına kopyalandı. Model dosyaları kopyalanmadı, lazım olunca yeniden indirilecek.");
    }
}

/// <summary>Ekran dökümü kipinin hata dosyası (<c>errors.txt</c>); hata pencere yerine buraya eklenir.</summary>
public static class RenderErrors
{
    /// <summary>Dosya adı.</summary>
    public const string FileName = "errors.txt";

    /// <summary>Klasördeki <c>errors.txt</c>'ye bir kayıt ekler (yazılamazsa sessiz).</summary>
    public static void Append(string folder, string text)
    {
        try
        {
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, FileName), text + Environment.NewLine + Environment.NewLine,
                new UTF8Encoding(false));
        }
        catch (Exception) { }
    }
}
