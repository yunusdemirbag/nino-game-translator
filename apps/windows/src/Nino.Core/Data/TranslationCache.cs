// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Nino.Core.Data;

/// <summary>
/// Motor + dil çifti başına çeviri önbelleği (<c>translations\*.jsonl</c>). Her satır <c>["kaynak","çeviri"]</c>;
/// sona eklenir, sonuncusu geçerli. Bellekte en çok <see cref="Capacity"/> kayıt, en uzun süredir kullanılmayanlar
/// atılır. Disk hatası çeviriyi durdurmaz: önbellek yalnız bellekte sürer.
/// </summary>
public sealed class TranslationCache
{
    /// <summary>Varsayılan bellek sınırı.</summary>
    public const int DefaultCapacity = 20_000;

    /// <summary>Dosya adındaki biçim sürümü.</summary>
    public const int FormatVersion = 1;

    static readonly ConcurrentDictionary<string, TranslationCache> Shared = new(StringComparer.OrdinalIgnoreCase);

    // Eski Windows yazımıyla aynı: ASCII dışı ve HTML'e duyarlı karakterler \uXXXX kaçışıyla.
    static readonly JsonSerializerOptions LineOptions = new();

    readonly string? _path;
    readonly object _gate = new();
    readonly Dictionary<string, LinkedListNode<KeyValuePair<string, string>>> _map = new(StringComparer.Ordinal);
    readonly LinkedList<KeyValuePair<string, string>> _order = new(); // baş: en eski kullanılan
    bool _loaded;
    int _fileLines;

    /// <param name="path">Dosya yolu; null ise yalnız bellek.</param>
    /// <param name="capacity">Bellek sınırı (en az 1).</param>
    public TranslationCache(string? path, int capacity = DefaultCapacity)
    {
        _path = path;
        Capacity = Math.Max(1, capacity);
    }

    /// <summary>Bellek sınırı.</summary>
    public int Capacity { get; }

    /// <summary>Bellekteki kayıt sayısı.</summary>
    public int Count
    {
        get { lock (_gate) { EnsureLoaded(); return _map.Count; } }
    }

    /// <summary>Aynı dosya için süreçteki tek önbellek nesnesi (yol harf duyarsız eşlenir).</summary>
    public static TranslationCache ForFile(string path, int capacity = DefaultCapacity) =>
        Shared.GetOrAdd(Path.GetFullPath(path), p => new TranslationCache(p, capacity));

    /// <summary>Önbellek klasöründe motor + dil çiftinin dosyası.</summary>
    public static TranslationCache For(string folder, string engine, string source, string target,
        int capacity = DefaultCapacity) =>
        ForFile(Path.Combine(folder, FileName(engine, source, target)), capacity);

    /// <summary>
    /// Dosya adı: üç parça da yalnız <c>a–z 0–9 -</c> ise <c>v1-&lt;motor&gt;-&lt;kaynak&gt;-&lt;hedef&gt;.jsonl</c>
    /// (her parçada harf/rakam/<c>_</c> dışı <c>_</c> olur); değilse <c>v1h-&lt;sha256&gt;.jsonl</c>.
    /// </summary>
    public static string FileName(string engine, string source, string target)
    {
        if (IsPlain(engine) && IsPlain(source) && IsPlain(target))
            return $"v{FormatVersion}-{Clean(engine)}-{Clean(source)}-{Clean(target)}.jsonl";
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes($"{engine}\0{source}\0{target}"));
        return $"v{FormatVersion}h-{Convert.ToHexStringLower(digest)}.jsonl";
    }

    static bool IsPlain(string segment) =>
        segment.Length > 0 && segment.All(ch => char.IsAsciiLetterLower(ch) || char.IsAsciiDigit(ch) || ch == '-');

    static string Clean(string part) =>
        new(part.Select(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '_' ? c : '_').ToArray());

    /// <summary>Bulursa kaydı "son kullanılan" yapar.</summary>
    public bool TryGet(string source, out string translation)
    {
        lock (_gate)
        {
            EnsureLoaded();
            if (_map.TryGetValue(source, out var node))
            {
                Touch(node);
                translation = node.Value.Value;
                return true;
            }
            translation = "";
            return false;
        }
    }

    /// <summary>Saklar: boş anahtar/değer saklanmaz; aynı değer zaten varsa yalnız "kullanıldı" işaretlenir.</summary>
    public void Store(string source, string translation)
    {
        if (string.IsNullOrEmpty(source) || string.IsNullOrEmpty(translation)) return;
        lock (_gate)
        {
            EnsureLoaded();
            if (_map.TryGetValue(source, out var existing))
            {
                if (existing.Value.Value == translation)
                {
                    Touch(existing);
                    return;
                }
                _order.Remove(existing);
                _map.Remove(source);
            }
            _map[source] = _order.AddLast(new KeyValuePair<string, string>(source, translation));
            TrimIfNeeded();

            if (_path is null) return;
            try
            {
                if (_fileLines >= Capacity * 2) Rewrite();
                else
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                    File.AppendAllText(_path, Line(source, translation), FileIo.Utf8);
                    _fileLines++;
                }
            }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
        }
    }

    void Touch(LinkedListNode<KeyValuePair<string, string>> node)
    {
        _order.Remove(node);
        _order.AddLast(node);
    }

    void TrimIfNeeded()
    {
        if (_map.Count <= Capacity) return;
        var drop = _map.Count - Capacity + Capacity / 10;
        for (var i = 0; i < drop && _order.First is { } oldest; i++)
        {
            _map.Remove(oldest.Value.Key);
            _order.RemoveFirst();
        }
    }

    void EnsureLoaded()
    {
        if (_loaded) return;
        _loaded = true;
        if (_path is null) return;
        try
        {
            if (!File.Exists(_path)) return;
            foreach (var line in File.ReadLines(_path, FileIo.Utf8))
            {
                if (line.Length == 0) continue;
                _fileLines++;
                if (ParseLine(line) is not { } pair) continue;
                if (_map.TryGetValue(pair.Key, out var old))
                {
                    _order.Remove(old);
                    _map.Remove(pair.Key);
                }
                _map[pair.Key] = _order.AddLast(pair);
                TrimIfNeeded();
            }
            if (_fileLines > _map.Count + Capacity / 2) Rewrite();
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }

    static KeyValuePair<string, string>? ParseLine(string line)
    {
        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Array || root.GetArrayLength() != 2) return null;
            if (root[0].ValueKind != JsonValueKind.String || root[1].ValueKind != JsonValueKind.String) return null;
            var key = root[0].GetString()!;
            var value = root[1].GetString()!;
            return key.Length == 0 || value.Length == 0 ? null : new(key, value);
        }
        catch (JsonException) { return null; }
    }

    static string Line(string source, string translation) =>
        JsonSerializer.Serialize(new[] { source, translation }, LineOptions) + "\n";

    void Rewrite()
    {
        var sb = new StringBuilder();
        foreach (var pair in _order) sb.Append(Line(pair.Key, pair.Value));
        FileIo.WriteAtomic(_path!, sb.ToString());
        _fileLines = _map.Count;
    }
}
