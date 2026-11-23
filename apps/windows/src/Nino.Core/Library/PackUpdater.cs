// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Nino.Core.Data;

namespace Nino.Core.Library;

/// <summary>Paket güncellemesinin sonucu.</summary>
public sealed record PackUpdateResult(IReadOnlyList<string> Downloaded, IReadOnlyList<string> Removed, bool Skipped,
    bool ListFailed)
{
    /// <summary>Kütüphane yeniden yüklenmeli mi.</summary>
    public bool Changed => Downloaded.Count
        > 0 || Removed.Count > 0;
}

/// <summary>
/// Sunucudan paket güncelleme (havuz/paket tarifi §4): <c>v1/packs</c> listesi, <c>v1/packs/&lt;id&gt;</c> dosyaları,
/// durum dosyası <c>packs-remote.json</c>. Kullanıcının kendi dosyalarına dokunmaz.
/// </summary>
public sealed partial class PackUpdater
{
    /// <summary>Varsayılan izin verilen yaş.</summary>
    public static readonly TimeSpan DefaultMaxAge = TimeSpan.FromHours(24);

    /// <summary>Yeni oyun tanınınca kullanılan yaş.</summary>
    public static readonly TimeSpan NewGameMaxAge = TimeSpan.FromMinutes(10);

    const long MaxPackBytes = 64L * 1024 * 1024;

    readonly string _basePacks;
    readonly string _baseState;
    volatile string _lang = "tr";
    readonly Uri? _base;
    readonly HttpClient _http;
    readonly TimeProvider _clock;
    readonly SemaphoreSlim _gate = new(1, 1);

    [GeneratedRegex("^[a-z0-9][a-z0-9-]{0,63}$")]
    private static partial Regex IdPattern();

    [GeneratedRegex("^[0-9a-fA-F]{64}$")]
    private static partial Regex ShaPattern();

    /// <param name="packsFolder">Kullanıcı paket klasörü.</param>
    /// <param name="stateFile"><c>%LOCALAPPDATA%\Nino\packs-remote.json</c>.</param>
    /// <param name="baseUrl">Sunucu (null: özellik kapalı).</param>
    /// <param name="http">HTTP istemcisi.</param>
    /// <param name="clock">Saat.</param>
    public PackUpdater(string packsFolder, string stateFile, Uri? baseUrl, HttpClient http, TimeProvider? clock = null)
    {
        _basePacks = packsFolder;
        _baseState = stateFile;
        _base = baseUrl;
        _http = http;
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>Testler için: dosya taşıma.</summary>
    internal Action<string, string> MoveFile { get; set; } = (from, to) => File.Move(from, to, overwrite: true);

    /// <summary>
    /// Adres: ortam değişkeni <c>NINO_PACKS_URL</c>, sonra derleme meta verisi <c>NinoPacksUrl</c>; geçersizler atlanır,
    /// hiçbiri yoksa null (özellik kapalı). Sonuç <c>/</c> ile biter.
    /// </summary>
    public static Uri? ResolveAddress(string? environment, string? buildMetadata)
    {
        foreach (var candidate in new[] { environment, buildMetadata })
        {
            if (PoolEndpoint.Parse(candidate) is not { } uri) continue;
            var text = uri.ToString();
            return new Uri(text.EndsWith('/') ? text : text + "/");
        }
        return null;
    }

    /// <summary>Paket dili (<c>tr</c>, <c>ar</c>).</summary>
    public string Language => _lang;

    /// <summary>
    /// Paket dilini değiştirir (hedef dil). Her dilin klasörü ve durum dosyası ayrıdır; dil değişince paketler o dilin
    /// klasöründen okunur ve sunucudan o dilde istenir. Desteklenmeyen dil Türkçe sayılır.
    /// </summary>
    public void SetLanguage(string? target) => _lang = PackLanguage.For(target);

    /// <summary>Dilin paket klasörü.</summary>
    public string FolderFor(string lang) => PackLanguage.Folder(_basePacks, lang);

    /// <summary>Kimlik geçerli mi.</summary>
    public static bool IsValidId(string? id) => id is not null && IdPattern().IsMatch(id);

    sealed record Record(string Id, string Title, long Version, string Sha256);

    /// <summary>Paketleri tazeler. Aynı anda tek yenileme (ikinci çağrı birincinin bitmesini bekler).</summary>
    public async Task<PackUpdateResult> RefreshAsync(bool force, TimeSpan? maxAge = null,
        CancellationToken
            cancellationToken = default)
    {
        var none = new PackUpdateResult([], [], false, false);
        if (_base is null) return none;
        await
            _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var lang = _lang;
            var packsFolder = PackLanguage.Folder(_basePacks, lang);
            var stateFile = PackLanguage.StateFile(_baseState, lang);
            var (checkedAt, records) = ReadState(stateFile);
            var now = PoolHttp.Unix(_clock.GetUtcNow());
            var age = (maxAge ?? DefaultMaxAge).TotalSeconds;
            if (!force && checkedAt > 0 && now - checkedAt < age && records.All(r => r.Version != -1))
                return none with { Skipped = true };

            var list = await GetListAsync(lang, cancellationToken).ConfigureAwait(false);
            if (list is null) return none with { ListFailed = true };

            var byId = records.ToDictionary(r => r.Id, StringComparer.Ordinal);
            var next = new Dictionary<string, Record>(StringComparer.Ordinal);
            var downloaded = new List<string>();
            var removed = new List<string>();
            var retry = false;
            Directory.CreateDirectory(packsFolder);

            foreach (var (id, title, version, shaRaw) in list)
            {
                if (!IsValidId(id) || !ShaPattern().IsMatch(shaRaw)) continue;
                var sha = shaRaw.ToLowerInvariant();
                var file = Path.Combine(packsFolder, id + ".json.gz");
                byId.TryGetValue(id, out var recorded);
                var diskSha = File.Exists(file) ? Sha(file) : null;
                if (recorded is not null && recorded.Version == version && recorded.Sha256 == sha && diskSha == sha)
                {
                    next[id] = recorded;
                    continue;
                }
                if (diskSha is not null && diskSha != recorded?.Sha256 && diskSha != sha) continue;

                var data = await DownloadAsync(id, lang, cancellationToken).ConfigureAwait(false);
                if (data is null || data.Length > MaxPackBytes || Convert.ToHexStringLower(SHA256.HashData(data)) != sha)
                {
                    retry = true;
                    if (recorded is not null && File.Exists(file)) next[id] = recorded with { Version = -1 };
                    continue;
                }
                var temp = Path.Combine(packsFolder, "." + id + ".download");
                try
                {
                    await File.WriteAllBytesAsync(temp, data, cancellationToken).ConfigureAwait(false);
                    MoveFile(temp, file);
                }
                catch (Exception e) when (e is IOException
                    or UnauthorizedAccessException)
                {
                    try { File.Delete(temp); }
                    catch (Exception e2) when (e2 is IOException or UnauthorizedAccessException) { }
                    if (recorded is not null && File.Exists(file)) next[id] = recorded with { Version = -1 };
                    continue;
                }
                next[id] = new Record(id, title, version, sha);
                downloaded.Add(id);
            }

            var listed = list.Select(p => p.Id).ToHashSet(StringComparer.Ordinal);
            foreach (var r in records.Where(r => !listed.Contains(r.Id)))
            {
                var file = Path.Combine(packsFolder, r.Id + ".json.gz");
                if (File.Exists(file) && Sha(file) == r.Sha256)
                {
                    try { File.Delete(file); }
                    catch (Exception e) when (e is IOException
                        or UnauthorizedAccessException) { }
                }
                removed.Add(r.Id);
            }

            WriteState(stateFile, retry ? checkedAt : now, next.Values);
            return new PackUpdateResult(downloaded, removed, false, false);
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>"İndirilen paketleri sil": özeti kayıtlıyla aynı dosyalar silinir, durum dosyası silinir.</summary>
    public void DeleteDownloaded()
    {
        foreach (var lang in PackLanguage.Supported)
            DeleteDownloaded(PackLanguage.Folder(_basePacks, lang), PackLanguage.StateFile(_baseState, lang));
    }

    static void DeleteDownloaded(string packsFolder, string stateFile)
    {
        var (_, records) = ReadState(stateFile);
        foreach (var r in records)
        {
            var file = Path.Combine(packsFolder, r.Id + ".json.gz");
            try
            {
                if (File.Exists(file) && Sha(file) == r.Sha256) File.Delete(file);
            }
            catch (Exception e) when (e is IOException
                or UnauthorizedAccessException) { }
        }
        try { File.Delete(stateFile); }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException) { }
    }

    static string? Sha(string file)
    {
        try
        {
            using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            return Convert.ToHexStringLower(SHA256.HashData(stream));
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException)
        {
            return null;
        }
    }

    async Task<List<(string Id, string Title, long Version, string Sha)>?> GetListAsync(string lang, CancellationToken ct)
    {
        var response = await PoolHttp.SendAsync(_http, new HttpRequestMessage(HttpMethod.Get, new Uri(_base!, "v1/packs?lang=" + lang)),
            TimeSpan.FromSeconds(60), "packs", ct).ConfigureAwait(false);
        if (response is null || !response.Ok) return null;
        using var doc = PoolHttp.Parse(response.Body);
        if (doc?.RootElement.ValueKind != JsonValueKind.Object) return null;
        if (!doc.RootElement.TryGetProperty("packs", out var packs) || packs.ValueKind != JsonValueKind.Array) return null;
        var list = new List<(string, string, long, string)>();
        foreach (var p in packs.EnumerateArray())
        {
            if (p.ValueKind != JsonValueKind.Object) continue;
            // Sunucu dili yanlış ya da eski sunucu dil bilmiyorsa: başka dilin paketi bu klasöre inmez.
            if (p.TryGetProperty("lang", out var pl) && pl.ValueKind == JsonValueKind.String && pl.GetString() != lang) continue;
            if (!p.TryGetProperty("lang", out _) && lang != "tr") continue;
            var id = p.TryGetProperty("id", out var i) && i.ValueKind == JsonValueKind.String ? i.GetString()! : "";
            var title = p.TryGetProperty("title", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString()! : id;
            var version = p.TryGetProperty("version", out var v) && v.TryGetInt64(out var vv) ? vv : 0;
            var sha = p.TryGetProperty("sha256", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString()! : "";
            list.Add((id, title, version, sha));
        }
        return list;
    }

    async Task<byte[]?> DownloadAsync(string id, string lang, CancellationToken ct)
    {
        var response = await PoolHttp.SendAsync(_http, new HttpRequestMessage(HttpMethod.Get, new Uri(_base!, "v1/packs/" + id + "?lang=" + lang)),
            TimeSpan.FromSeconds(60), "packs", ct).ConfigureAwait(false);
        return response is { Ok: true } && response.Body.Length > 0 ? response.Body : null;
    }

    static (double Checked, List<Record> Records) ReadState(string stateFile)
    {
        try
        {
            if (!File.Exists(stateFile)) return (0, []);
            using var doc = JsonDocument.Parse(File.ReadAllBytes(stateFile));
            var root = doc.RootElement;
            var checkedAt = root.TryGetProperty("checked", out var c) && c.TryGetDouble(out var cv) ? cv : 0;
            var records = new List<Record>();
            if (root.TryGetProperty("packs", out var packs) && packs.ValueKind == JsonValueKind.Array)
                foreach (var p in packs.EnumerateArray())
                    records.Add(new Record(p.GetProperty("id").GetString()!, p.GetProperty("title").GetString()!,
                        p.GetProperty("version").GetInt64(), p.GetProperty("sha256").GetString()!.ToLowerInvariant()));
            return (checkedAt, records);
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException
                                      or IOException or UnauthorizedAccessException)
        {
            return (0, []);
        }
    }

    static void WriteState(string stateFile, double checkedAt, IEnumerable<Record> records)
    {
        var json = PoolHttp.Json(w =>
        {
            w.WriteStartObject();
            w.WriteNumber("checked", checkedAt);
            w.WriteStartArray("packs");
            foreach (var r in records)
            {
                w.WriteStartObject();
                w.WriteString("id", r.Id);
                w.WriteString("title", r.Title);
                w.WriteNumber("version", r.Version);
                w.WriteString("sha256", r.Sha256);
                w.WriteEndObject();
            }
            w.WriteEndArray();
            w.WriteEndObject();
        });
        try { FileIo.WriteAtomic(stateFile, json); }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException) { }
    }
}
