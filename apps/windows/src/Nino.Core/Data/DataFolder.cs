// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Core.Data;

/// <summary>Veri klasörü kararı. Süreç boyunca değişmez.</summary>
/// <param name="Path">Kullanılan klasörün tam yolu.</param>
/// <param name="FolderName">Kullanılan klasörün adı (<c>Nino</c> ya da eski ad).</param>
/// <param name="Error">Taşıma/kopya hatası (hata günlüğüne yazılır); yoksa null.</param>
/// <param name="Copied">Eski klasör ortak olduğu için veriler kopyalandıysa doğru.</param>
public sealed record DataFolderChoice(string Path, string FolderName, string? Error, bool Copied)
{
    /// <summary>Eski adlı klasör mü kullanılıyor.</summary>
    public bool IsLegacy => !string.Equals(FolderName, DataFolderResolver.FolderName, StringComparison.Ordinal);

    /// <summary>Klasörün içindeki bir dosyanın tam yolu.</summary>
    public string File(params string[] parts) => System.IO.Path.Combine([Path, .. parts]);

    /// <summary>Kullanıcıya gösterilecek yol: <c>%LOCALAPPDATA%\&lt;klasör&gt;\&lt;dosya&gt;</c>.</summary>
    public string DisplayPath(string relative) =>
        $"%LOCALAPPDATA%\\{FolderName}" + (string.IsNullOrEmpty(relative) ? "" : "\\" + relative.Replace('/', '\\'));
}

/// <summary>
/// <c>%LOCALAPPDATA%\Nino</c> klasörünü ve eski adlı klasörden taşıma/kopyalamayı yönetir. Kök klasör, "Windows mu"
/// bilgisi ve açık kopya bulucu dışarıdan verilir (testler geçici klasörde çalışır). Karar bir kez verilir.
/// </summary>
public sealed class DataFolderResolver
{
    /// <summary>Yeni veri klasörünün adı.</summary>
    public const string FolderName = "Nino";

    /// <summary>Kopyalanan klasöre bırakılan bilgi dosyası.</summary>
    public const string CopyNoteFile = "kopyalandi.txt";

    const string CopyPrefix = FolderName + ".kopya-";

    static readonly string[] SkippedTopFolders = ["current", "packages", "models", "webview", "xbox-webview"];
    static readonly string[] SkippedTopSuffixes = [".exe", ".nupkg", ".log", ".log.1", ".tmp"];

    readonly string _root;
    readonly bool _isWindows;
    readonly IRunningCopyProbe? _probe;
    readonly TimeProvider _clock;
    readonly object _gate = new();
    DataFolderChoice? _choice;

    /// <param name="localAppDataRoot">%LOCALAPPDATA% (testte geçici klasör).</param>
    /// <param name="isWindows">Yalnız Windows'ta taşıma ve oluşturma yapılır.</param>
    /// <param name="probe">Açık kopyaları bulan hizmet; yoksa "kopya yok".</param>
    /// <param name="clock">Kopya notundaki zaman için.</param>
    public DataFolderResolver(string localAppDataRoot, bool isWindows, IRunningCopyProbe? probe = null,
        TimeProvider? clock = null)
    {
        _root = localAppDataRoot;
        _isWindows = isWindows;
        _probe = probe;
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>Yeni klasörün tam yolu.</summary>
    public string NewPath => Path.Combine(_root, FolderName);

    /// <summary>Eski adlı klasörün tam yolu.</summary>
    public string LegacyPath => Path.Combine(_root, LegacyNames.DataFolder);

    /// <summary>Testler için: klasör taşıma işlemi (varsayılan <see cref="Directory.Move"/>).</summary>
    internal Action<string, string> MoveDirectory { get; set; } = Directory.Move;

    /// <summary>Testler için: kopyalamanın son adımı olan geçici klasörü yerine koyma.</summary>
    internal Action<string, string> PromoteCopy { get; set; } = Directory.Move;

    /// <summary>
    /// Kararı döndürür; daha önce verilmemişse diske dokunmadan verir: yeni klasör varsa o, yoksa eski varsa eski,
    /// ikisi de yoksa yeni (oluşturmadan). Windows dışında hep eski ad.
    /// </summary>
    public DataFolderChoice Current
    {
        get
        {
            lock (_gate)
                return _choice ??= DecideWithoutChanges();
        }
    }

    /// <summary>
    /// Açılıştaki hazırlık: gerekirse taşır, kopyalar ya da oluşturur. Karar zaten verildiyse hiçbir şey yapmaz.
    /// </summary>
    public DataFolderChoice Prepare()
    {
        lock (_gate)
            return _choice ??= _isWindows ? PrepareOnWindows() : DecideWithoutChanges();
    }

    DataFolderChoice DecideWithoutChanges()
    {
        if (!_isWindows) return Legacy(null);
        if (Directory.Exists(NewPath)) return New();
        if (Directory.Exists(LegacyPath)) return Legacy(null);
        return New();
    }

    DataFolderChoice PrepareOnWindows()
    {
        var hasNew = Directory.Exists(NewPath);
        var hasOld = Directory.Exists(LegacyPath);

        if (hasOld && (!hasNew || IsEmpty(NewPath)))
        {
            var copies = SafeProbe();
            var kind = copies is null ? OtherCopyKind.None : RunningCopyRules.Classify(copies.OwnPath, copies.Others);
            if (kind == OtherCopyKind.ThisApp)
                return Legacy("Nino'nun başka bir kopyası açık; veri klasörü bir sonraki açılışta taşınacak.");

            var shared = kind == OtherCopyKind.OtherApp || LooksShared();
            if (hasNew)
            {
                try { Directory.Delete(NewPath, recursive: false); }
                catch (Exception e) when (FileIo.IsIoError(e)) { }
            }

            try
            {
                if (shared) CopyLegacy();
                else MoveDirectory(LegacyPath, NewPath);
                return New(copied: shared);
            }
            catch (Exception e)
            {
                // Aynı anda açılan başka bir kopya önce taşıdıysa onun klasörü kullanılır.
                if (Directory.Exists(NewPath) && (!IsEmpty(NewPath) || !Directory.Exists(LegacyPath))) return New();
                return Legacy(e.Message.Length > 0 ? e.Message : e.GetType().Name);
            }
        }

        if (hasNew) return New();
        if (!hasOld)
        {
            try { Directory.CreateDirectory(NewPath); }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
        }
        return New();
    }

    RunningCopies? SafeProbe()
    {
        try { return _probe?.Find(); }
        catch { return null; }
    }

    bool LooksShared() =>
        File.Exists(Path.Combine(LegacyPath, "Update.exe"))
        || Directory.Exists(Path.Combine(LegacyPath, "current"))
        || Directory.Exists(Path.Combine(LegacyPath, "packages"))
        || Directory.Exists(Path.Combine(_root, LegacyNames.InstallFolder));

    void CopyLegacy()
    {
        foreach (var leftover in SafeEnumerate(_root, CopyPrefix + "*"))
        {
            try { Directory.Delete(leftover, recursive: true); }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
        }

        var temp = Path.Combine(_root, CopyPrefix + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(temp);
            CopyTree(new DirectoryInfo(LegacyPath), temp, top: true);
            var when = _clock.GetLocalNow().ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
            File.WriteAllText(Path.Combine(temp, CopyNoteFile),
                $"Bu klasördeki veriler {LegacyPath} klasöründen kopyalandı ({when}).\n" +
                "Eski klasörü başka bir uygulama da kullandığı için olduğu gibi bırakıldı.\n" +
                "Modeller kopyalanmadı; Nino gerektiğinde onları yeniden indirir.\n", FileIo.Utf8);
            PromoteCopy(temp, NewPath);
        }
        catch
        {
            try { if (Directory.Exists(temp)) Directory.Delete(temp, recursive: true); }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
            throw;
        }
    }

    static void CopyTree(DirectoryInfo source, string target, bool top)
    {
        foreach (var entry in source.EnumerateFileSystemInfos())
        {
            if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint) || entry.LinkTarget is not null) continue;
            var dest = Path.Combine(target, entry.Name);
            if (entry is DirectoryInfo dir)
            {
                if (top && SkipTopFolder(dir.Name)) continue;
                Directory.CreateDirectory(dest);
                CopyTree(dir, dest, top: false);
            }
            else if (entry is FileInfo file)
            {
                if (top && SkipTopFile(file.Name)) continue;
                file.CopyTo(dest, overwrite: false);
            }
        }
    }

    internal static bool SkipTopFolder(string name) =>
        name.StartsWith("cuda-", StringComparison.OrdinalIgnoreCase)
        || SkippedTopFolders.Any(s => string.Equals(s, name, StringComparison.OrdinalIgnoreCase));

    internal static bool SkipTopFile(string name) =>
        SkippedTopSuffixes.Any(s => name.EndsWith(s, StringComparison.OrdinalIgnoreCase));

    static IEnumerable<string> SafeEnumerate(string dir, string pattern)
    {
        try { return Directory.Exists(dir) ? Directory.GetDirectories(dir, pattern) : []; }
        catch (Exception e) when (FileIo.IsIoError(e)) { return []; }
    }

    static bool IsEmpty(string dir)
    {
        try { return !Directory.EnumerateFileSystemEntries(dir).Any(); }
        catch (Exception e) when (FileIo.IsIoError(e)) { return false; }
    }

    DataFolderChoice New(bool copied = false) => new(NewPath, FolderName, null, copied);

    DataFolderChoice Legacy(string? error) => new(LegacyPath, LegacyNames.DataFolder, error, false);
}

/// <summary>
/// Süreç başına tek veri klasörü kararı. Uygulama açılışta <see cref="Configure"/> ile kurar ve
/// <see cref="Prepare"/> çağırır; veriye dokunan her bileşen yolu buradan alır.
/// </summary>
public static class NinoDataFolder
{
    static DataFolderResolver? _resolver;

    /// <summary>Çözücüyü kurar. Karar verildikten sonra yeniden kurmak yalnız testlerde anlamlıdır.</summary>
    public static void Configure(DataFolderResolver resolver) => _resolver = resolver;

    /// <summary>Kurulmuş çözücü; kurulmamışsa gerçek %LOCALAPPDATA% ile varsayılanı.</summary>
    public static DataFolderResolver Resolver => _resolver ??= new DataFolderResolver(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), OperatingSystem.IsWindows());

    /// <summary>Açılıştaki hazırlık (yalnız bu yazabilir).</summary>
    public static DataFolderChoice Prepare() => Resolver.Prepare();

    /// <summary>Kullanılan karar.</summary>
    public static DataFolderChoice Current => Resolver.Current;
}
