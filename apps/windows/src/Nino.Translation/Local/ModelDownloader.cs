// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;

namespace Nino.Translation.Local;

/// <summary>İndirme başarısız (takıldı, boy/özet tutmadı, sunucu hatası).</summary>
public sealed class ModelDownloadException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>
/// Model dosyası indirici (çeviri tarifi §8.2): <c>.part</c> üzerinden kaldığı yerden sürer, SHA-256 ve boyu denetler,
/// doğrulanan dosyayı asıl adına taşır. Aynı klasörde aynı anda tek indirme.
/// </summary>
public sealed class ModelDownloader
{
    /// <summary>Hiç veri gelmeden geçebilecek en uzun süre.</summary>
    public static readonly TimeSpan DefaultStallTimeout = TimeSpan.FromSeconds(60);

    static readonly ConcurrentDictionary<string, SemaphoreSlim> FolderLocks = new(StringComparer.OrdinalIgnoreCase);

    readonly HttpClient _http;
    readonly TimeSpan _stall;

    public ModelDownloader(HttpClient http, TimeSpan? stallTimeout = null)
    {
        _http = http;
        _stall = stallTimeout ?? DefaultStallTimeout;
    }

    /// <summary>Dosya kurulu mu: asıl adıyla duruyor ve boyu beklenen.</summary>
    public static bool IsInstalled(string folder, ModelFile file)
    {
        var info = new FileInfo(Path.Combine(folder, file.Name));
        return info.Exists &&
            info.Length == file.Size;
    }

    /// <summary>Hepsi kurulu mu.</summary>
    public static bool AllInstalled(string folder, IEnumerable<ModelFile> files) => files.All(f => IsInstalled(folder, f));

    /// <summary>Dosyaları indirir. İlerleme 0–1 (toplam bayt oranı), en az binde bir artınca bildirilir.</summary>
    public async Task DownloadAsync(string folder, IReadOnlyList<ModelFile> files, IProgress<double>? progress = null,
        CancellationToken
            cancellationToken = default)
    {
        var gate = FolderLocks.GetOrAdd(Path.GetFullPath(folder), _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            Directory.CreateDirectory(folder);
            var reporter = new ProgressReporter(progress, files.Sum(f => f.Size));
            foreach (var file in files)
            {
                if (IsInstalled(folder, file))
                {
                    reporter.Add(file.Size);
                    continue;
                }
                await DownloadOneAsync(folder, file, reporter, cancellationToken).ConfigureAwait(false);
            }
            reporter.Finish();
        }
        finally
        {
            gate.Release();
        }
    }

    async Task DownloadOneAsync(string folder, ModelFile file, ProgressReporter reporter, CancellationToken ct)
    {
        var final = Path.Combine(folder, file.Name);
        var part = final + ".part";
        long existing = 0;
        if (File.Exists(part))
        {
            existing = new FileInfo(part).Length;
            if (existing > file.Size)
            {
                File.Delete(part);
                existing = 0;
            }
        }

        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        if (existing == file.Size)
        {
            await HashFileAsync(part, sha, ct).ConfigureAwait(false);
            reporter.Add(existing);
        }
        else
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, file.Url);
            if (existing > 0) request.Headers.Range = new RangeHeaderValue(existing, null);
            using var stall = CancellationTokenSource.CreateLinkedTokenSource(ct);
            stall.CancelAfter(_stall);
            HttpResponseMessage response;
            try
            {
                response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, stall.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
                when (!ct.IsCancellationRequested)
            {
                throw new ModelDownloadException("indirme takıldı");
            }
            catch (HttpRequestException e)
            {
                throw new ModelDownloadException("indirilemedi: " + file.Name, e);
            }
            using (response)
            {
                var resumed = existing > 0 && response.StatusCode == HttpStatusCode.PartialContent;
                if (!resumed && !response.IsSuccessStatusCode)
                    throw new ModelDownloadException($"indirilemedi: {file.Name} ({(int)response.StatusCode})");
                if (resumed)
                {
                    await HashFileAsync(part, sha, ct).ConfigureAwait(false);
                    reporter.Add(existing);
                }
                await using var output = new FileStream(part, resumed ? FileMode.Append : FileMode.Create,
                    FileAccess.Write, FileShare.None);
                await using var input = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
                var buffer = new byte[81920];
                while (true)
                {
                    stall.CancelAfter(_stall);
                    int read;
                    try { read = await input.ReadAsync(buffer, stall.Token).ConfigureAwait(false); }
                    catch (OperationCanceledException)
                        when (!ct.IsCancellationRequested)
                    {
                        throw new ModelDownloadException("indirme takıldı");
                    }
                    catch (IOException e) when (!ct.IsCancellationRequested)
                    {
                        throw new ModelDownloadException("indirme yarıda kesildi: " + file.Name, e);
                    }
                    if (read == 0) break;
                    await output.WriteAsync(buffer.AsMemory(0,
                        read), ct).ConfigureAwait(false);
                    sha.AppendData(buffer, 0, read);
                    reporter.Add(read);
                }
            }
        }

        var size = new FileInfo(part).Length;
        var digest = Convert.ToHexStringLower(sha.GetHashAndReset());
        if (size != file.Size || !string.Equals(digest, file.Sha256, StringComparison.OrdinalIgnoreCase))
        {
            try { File.Delete(part); }
            catch (IOException) { }
            throw new ModelDownloadException($"boy/özet tutmadı: {file.Name}");
        }
        File.Move(part, final, overwrite: true);
    }

    static async Task HashFileAsync(string path, IncrementalHash sha, CancellationToken ct)
    {
        await using var stream = File.OpenRead(path);
        var buffer = new byte[81920];
        int read;
        while ((read = await stream.ReadAsync(buffer, ct).ConfigureAwait(false)) > 0) sha.AppendData(buffer, 0, read);
    }

    /// <summary>Bir dosyanın SHA-256'sı (küçük hex).</summary>
    public static async Task<string> Sha256Async(string path, CancellationToken ct = default)
    {
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        await HashFileAsync(path, sha, ct).ConfigureAwait(false);
        return Convert.ToHexStringLower(sha.GetHashAndReset());
    }

    sealed class ProgressReporter(IProgress<double>? progress, long total)
    {
        long _done;
        double _reported = -1;

        public void Add(long bytes)
        {
            _done += bytes;
            if (progress is null
                || total <= 0) return;
            var value = Math.Min(1, (double)_done / total);
            if (value - _reported >= 0.001)
            {
                _reported = value;
                progress.Report(value);
            }
        }

        public void Finish()
        {
            if (progress is not null && _reported < 1) progress.Report(1);
            _reported = 1;
        }
    }
}
