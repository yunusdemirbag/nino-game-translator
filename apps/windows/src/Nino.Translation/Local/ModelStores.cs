// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO.Compression;

namespace Nino.Translation.Local;

/// <summary>
/// Ücretsiz model deposu (<c>%LOCALAPPDATA%\Nino\models</c>): hedef başına kurulu mu, indir (çeviri tarifi §8.1–§8.4).
/// </summary>
public sealed class FreeModelStore
{
    readonly string _root;
    readonly ModelDownloader _downloader;
    readonly Action<string>? _log;
    readonly SemaphoreSlim _turkishGate = new(1, 1);
    readonly ModelFile _archive;
    readonly ModelFile _vocab;

    /// <param name="modelsRoot">Modeller klasörü.</param>
    /// <param name="downloader">İndirici.</param>
    /// <param name="log">Günlük (eski modelin silinemediği gibi).</param>
    /// <param name="turkishArchive">Türkçe arşivi (testte küçük sahte arşiv).</param>
    /// <param name="turkishVocab">Türkçe <c>vocab.json</c> (testte sahte).</param>
    /// <param name="keepLegacyTurkish">Eski ONNX Türkçe modelini (<c>models/en-tr</c>) silme ve kuruluysa onu kullan
    /// (Linux sunucusu: Python/CTranslate2 olmadan çalışır).</param>
    public FreeModelStore(string modelsRoot, ModelDownloader downloader, Action<string>? log = null,
        ModelFile? turkishArchive = null, ModelFile? turkishVocab = null, bool keepLegacyTurkish = false)
    {
        KeepLegacyTurkish = keepLegacyTurkish;
        _root = modelsRoot;
        _downloader = downloader;
        _log = log;
        _archive = turkishArchive ?? ModelCatalog.TurkishArchive;
        _vocab = turkishVocab ?? ModelCatalog.TurkishTokenizerFiles.Single(f => f.Name == "vocab.json");
    }

    /// <summary>Modeller klasörü.</summary>
    public string Root => _root;

    /// <summary>Eski ONNX Türkçe modeli korunur ve CTranslate2 modeli yokken kullanılır.</summary>
    public bool KeepLegacyTurkish { get; }

    /// <summary>Kullanılacak eski ONNX Türkçe klasörü; seçenek kapalıysa ya da model yoksa null.</summary>
    public string? LegacyTurkishInUse(string target)
    {
        if (!KeepLegacyTurkish || ModelCatalog.For("en", target) is not { UsesCt2: true } model) return null;
        if (IsCt2Installed(Path.Combine(_root, model.Folder))) return null;
        var legacy = Path.Combine(_root, ModelCatalog.LegacyTurkishFolder);
        return IsOnnxInstalled(legacy) ? legacy : null;
    }

    /// <summary>Hedefin model klasörü; model yoksa null.</summary>
    public string? FolderFor(string target) =>
        ModelCatalog.For("en", target) is { } m ? Path.Combine(_root, m.Folder) : null;

    /// <summary>Türkçe CTranslate2 modeli kurulu mu.</summary>
    public static bool IsCt2Installed(string folder)
    {
        bool Has(string name) => File.Exists(Path.Combine(folder, name));
        return Has("model.bin") && Has("config.json") && Has("source.spm") && Has("vocab.json")
            && (Has("shared_vocabulary.json") || (Has("source_vocabulary.json") && Has("target_vocabulary.json")));
    }

    /// <summary>ONNX modelinin dört dosyası yerinde mi.</summary>
    public static bool IsOnnxInstalled(string folder) =>
        ModelCatalog.OnnxFileNames.All(n => File.Exists(Path.Combine(folder, n)));

    /// <summary>Hedefin modeli kurulu mu.</summary>
    public bool IsInstalled(string target)
    {
        var model = ModelCatalog.For("en", target);
        if (model is null) return false;
        var folder = Path.Combine(_root, model.Folder);
        if (model.UsesCt2) return IsCt2Installed(folder) || LegacyTurkishInUse(target) is not null;
        return IsOnnxInstalled(folder);
    }

    /// <summary>Hedefin modelini indirir; kuruluysa hemen ilerleme 1.</summary>
    public async Task DownloadAsync(string target, IProgress<double>? progress = null,
        CancellationToken
            cancellationToken = default)
    {
        var model = ModelCatalog.For("en", target)
                    ?? throw new ModelDownloadException("bu dil için ücretsiz model yok");
        var folder = Path.Combine(_root, model.Folder);
        if (!model.UsesCt2)
        {
            await _downloader.DownloadAsync(folder, model.Files, progress, cancellationToken).ConfigureAwait(false);
            return;
        }
        await _turkishGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await InstallTurkishAsync(folder, progress, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _turkishGate.Release();
        }
    }

    async Task InstallTurkishAsync(string folder, IProgress<double>? progress, CancellationToken ct)
    {
        if (IsCt2Installed(folder) || LegacyTurkishInUse("tr") is not null)
        {
            progress?.Report(1);
            RemoveLegacyTurkish();
            return;
        }
        await _downloader.DownloadAsync(folder, [_archive], new CappedProgress(progress), ct).ConfigureAwait(false);
        await _downloader.DownloadAsync(folder, [_vocab], null, ct).ConfigureAwait(false);

        var archive = Path.Combine(folder, _archive.Name);
        using (var zip = ZipFile.OpenRead(archive))
            foreach (var entry in zip.Entries)
            {
                ct.ThrowIfCancellationRequested();
                var name = Path.GetFileName(entry.FullName.Replace('\\', '/'));
                if (!ModelCatalog.TurkishArchiveEntries.Contains(name)) continue;
                ArchiveTools.Extract(entry, Path.Combine(folder, name));
            }
        if (!IsCt2Installed(folder)) throw new ModelDownloadException("arşivde model ya da sözlük dosyası eksik");
        File.Delete(archive);
        RemoveLegacyTurkish();
        progress?.Report(1);
    }

    void RemoveLegacyTurkish()
    {
        if (KeepLegacyTurkish) return;
        var legacy = Path.Combine(_root, ModelCatalog.LegacyTurkishFolder);
        if (!Directory.Exists(legacy)) return;
        try { Directory.Delete(legacy, recursive: true); }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException)
        {
            _log?.Invoke($"eski Türkçe modeli silinemedi: {e.Message}");
        }
    }

    /// <summary>Arşivin ilerlemesi 1'e varmasın (1, kurulum bitince bildirilir).</summary>
    sealed class CappedProgress(IProgress<double>? inner) : IProgress<double>
    {
        public void Report(double value)
        {
            if (value < 1) inner?.Report(value);
        }
    }
}

/// <summary>Arşivden dosya çıkarma yardımcısı.</summary>
internal static class ArchiveTools
{
    /// <summary>Girdiyi <c>.part</c>'a yazar, sonra asıl adına taşır.</summary>
    public static void Extract(ZipArchiveEntry entry, string target)
    {
        var part = target + ".part";
        using (var input = entry.Open())
        using (var output = new FileStream(part, FileMode.Create, FileAccess.Write, FileShare.None))
            input.CopyTo(output);
        File.Move(part, target,
            overwrite: true);
    }
}

/// <summary>
/// NVIDIA CUDA çalışma zamanı deposu (<c>%LOCALAPPDATA%\Nino\cuda-12.8</c>, çeviri tarifi §8.5). İndirme tek ortak
/// görevdir: sürüyorsa aynısı döner, başarısız olduysa sonraki istekte yeniden başlar.
/// </summary>
public sealed class CudaRuntimeStore
{
    readonly string _folder;
    readonly ModelDownloader _downloader;
    readonly Func<bool> _driverPresent;
    readonly object _gate = new();
    Task? _task;

    /// <param name="folder">CUDA klasörü.</param>
    /// <param name="downloader">İndirici.</param>
    /// <param name="driverPresent">NVIDIA sürücüsü (<c>System32\nvcuda.dll</c>) var mı (Windows hizmeti).</param>
    public CudaRuntimeStore(string folder, ModelDownloader downloader, Func<bool> driverPresent)
    {
        _folder = folder;
        _downloader = downloader;
        _driverPresent = driverPresent;
    }

    /// <summary>CUDA klasörü.</summary>
    public string Folder => _folder;

    /// <summary>NVIDIA sürücüsü var mı.</summary>
    public bool DriverPresent => _driverPresent();

    /// <summary>Üç DLL tam beklenen boyda duruyor mu.</summary>
    public bool IsInstalled => CudaCatalog.Dlls.All(d =>
        new FileInfo(Path.Combine(_folder, d.Key)) is { Exists: true } f && f.Length == d.Value);

    /// <summary>Süren ya da biten indirme görevi (hiç başlamadıysa null).</summary>
    public Task? Current
    {
        get { lock (_gate) return _task; }
    }

    /// <summary>Testler için: süren görevi verir.</summary>
    internal void UseTask(Task task)
    {
        lock (_gate) _task = task;
    }

    /// <summary>İndirmeyi başlatır (sürüyorsa aynı görev; kuruluysa hemen biter).</summary>
    public Task EnsureStarted(CancellationToken cancellationToken = default)
    {
        lock (_gate)
        {
            if (_task is { IsCompleted: false }) return _task;
            if (_task is { IsCompletedSuccessfully: true } && IsInstalled) return _task;
            if (IsInstalled) return _task = Task.CompletedTask;
            return _task = Task.Run(() => InstallAsync(cancellationToken), cancellationToken);
        }
    }

    async Task InstallAsync(CancellationToken ct)
    {
        await _downloader.DownloadAsync(_folder, CudaCatalog.Archives, null, ct).ConfigureAwait(false);
        foreach (var archive in CudaCatalog.Archives)
        {
            var path = Path.Combine(_folder, archive.Name);
            var digest = await ModelDownloader.Sha256Async(path, ct).ConfigureAwait(false);
            if (!string.Equals(digest, archive.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                File.Delete(path);
                throw new ModelDownloadException("CUDA arşivinin özeti tutmadı: " + archive.Name);
            }
        }
        foreach (var archive in CudaCatalog.Archives)
        {
            using var zip = ZipFile.OpenRead(Path.Combine(_folder, archive.Name));
            foreach (var (dll, size) in CudaCatalog.Dlls)
            {
                var entry = zip.Entries.FirstOrDefault(e => e.FullName.EndsWith("/bin/" + dll, StringComparison.Ordinal));
                if (entry is null) continue;
                if (entry.Length != size) throw new ModelDownloadException("CUDA dosyasının boyu tutmadı: " + dll);
                ArchiveTools.Extract(entry, Path.Combine(_folder, dll));
            }
            if (archive == CudaCatalog.Archives[0])
            {
                var licenses = zip.Entries.Where(e => e.FullName.EndsWith("/LICENSE", StringComparison.Ordinal)).ToList();
                if (licenses.Count == 1) ArchiveTools.Extract(licenses[0], Path.Combine(_folder, CudaCatalog.LicenseFile));
            }
        }
        if (!IsInstalled) throw new ModelDownloadException("CUDA dosyaları eksik");
        foreach (var archive in CudaCatalog.Archives) File.Delete(Path.Combine(_folder, archive.Name));
    }
}
