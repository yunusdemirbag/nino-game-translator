// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO.Compression;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Nino.Core.Library;

/// <summary>Paket okunamadı ya da reddedildi.</summary>
public sealed class PackFormatException(string message) : Exception(message);

/// <summary>Bellekteki oyun paketi (havuz/paket tarifi §2.1).</summary>
public sealed class GamePack
{
    internal GamePack(string id, string title, Dictionary<ulong, string> entries, Dictionary<ulong, string> segments,
        ulong[] sortedKeys, FuzzyIndex? fuzzy)
    {
        Id = id;
        Title = title;
        Entries = entries;
        Segments = segments;
        SortedKeys = sortedKeys;
        Fuzzy = fuzzy;
    }

    /// <summary>Kimlik.</summary>
    public string Id { get; }

    /// <summary>Başlık.</summary>
    public string Title { get; }

    /// <summary>Tam satırlar (anahtar → Türkçe).</summary>
    public IReadOnlyDictionary<ulong, string> Entries { get; }

    /// <summary>Parçalar (biçim 2).</summary>
    public IReadOnlyDictionary<ulong, string> Segments { get; }

    /// <summary>Bütün geçerli anahtarlar, küçükten büyüğe, tekrarsız (Türkçesi boş kalanlar dahil).</summary>
    public IReadOnlyList<ulong> SortedKeys { get; }

    /// <summary>Bulanık dizin (yoksa ya da bozuksa null).</summary>
    public FuzzyIndex? Fuzzy { get; }

    /// <summary>Anahtar bu paketin anahtar kümesinde mi.</summary>
    public bool ContainsKey(ulong key) => Array.BinarySearch((ulong[])SortedKeys, key) >= 0;

    /// <summary>Paketin kendi Türkçesi: önce tam satırlar, yoksa parçalar.</summary>
    public string? OwnTurkish(ulong key) =>
        Entries.TryGetValue(key, out var t) ? t : Segments.TryGetValue(key, out var s) ? s : null;
}

/// <summary>Paket dosyası okuyucu (gzip'li ya da düz JSON; sarılı ya da düz biçim).</summary>
public static partial class GamePackReader
{
    [GeneratedRegex(@"\s+")]
    private static partial Regex Spaces();

    /// <summary>Dosya adından kimlik: sondan <c>.gz</c>, sonra <c>.json</c> atılır.</summary>
    public static string NameFromFile(string fileName)
    {
        var name = Path.GetFileName(fileName);
        if (name.EndsWith(".gz", StringComparison.Ordinal)) name = name[..^3];
        if (name.EndsWith(".json", StringComparison.Ordinal)) name = name[..^5];
        return name;
    }

    /// <summary>Paketi okur; reddedilirse <see cref="PackFormatException"/>.</summary>
    public static GamePack Read(byte[] bytes, string fileName)
    {
        var json = bytes;
        if (bytes.Length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)
        {
            try
            {
                using var input = new GZipStream(new MemoryStream(bytes), CompressionMode.Decompress);
                using var output = new MemoryStream();
                input.CopyTo(output);
                json = output.ToArray();
            }
            catch (Exception e) when (e is InvalidDataException or IOException)
            {
                throw new PackFormatException("paket bozuk");
            }
        }

        JsonDocument doc;
        try { doc = JsonDocument.Parse(json); }
        catch (JsonException) { throw new PackFormatException("paket JSON değil"); }
        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new PackFormatException("paket kökü nesne değil");
            var fallback = NameFromFile(fileName);
            var keys = new HashSet<ulong>();
            var entries = new Dictionary<ulong, string>();
            var segments = new Dictionary<ulong, string>();
            string id = fallback, title;
            JsonElement? fuzzy = null;

            if (root.TryGetProperty("entries", out var wrapped)
                && wrapped.ValueKind == JsonValueKind.Object)
            {
                if (root.TryGetProperty("format", out var format)
                    && format.ValueKind == JsonValueKind.Number
                    && format.GetDouble() is not (1 or 2))
                    throw new PackFormatException("desteklenmeyen biçim");
                if (NonEmpty(root, "id") is { } i) id = i;
                title = NonEmpty(root, "title") ?? id;
                ReadEntries(wrapped, entries, keys);
                if (root.TryGetProperty("segments", out var seg) && seg.ValueKind == JsonValueKind.Object)
                    ReadEntries(seg, segments, keys);
                if (root.TryGetProperty("fuzzy", out var f)) fuzzy = f;
            }
            else
            {
                title = id;
                ReadEntries(root, entries, keys);
            }

            if (entries.Count == 0) throw new PackFormatException("pakette satır yok");
            var sorted = keys.ToArray();
            Array.Sort(sorted);
            var index = fuzzy is { } fz ? FuzzyIndex.Parse(fz, sorted) : null;
            return new GamePack(id, title, entries, segments, sorted, index);
        }
    }

    static string? NonEmpty(JsonElement root, string name) =>
        root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String && v.GetString() is { Length: > 0 } s
            ? s
            : null;

    static void ReadEntries(JsonElement obj, Dictionary<ulong, string> target, HashSet<ulong> keys)
    {
        foreach (var p in obj.EnumerateObject())
        {
            if (p.Value.ValueKind != JsonValueKind.String) continue;
            if (!LineKey.TryParse(p.Name.ToLowerInvariant(), out var key)) continue;
            keys.Add(key);
            var turkish = CleanTurkish(p.Value.GetString()!);
            if (turkish.Length == 0) continue;
            target[key] = turkish;
        }
    }

    /// <summary>Türkçeyi temizler: etiket varsa silinir ve boşluklar teklenir; yoksa yalnız kırpılır.</summary>
    public static string CleanTurkish(string text)
    {
        if (!text.Contains('<'))
            return text.Trim();
        return Spaces().Replace(LineKey.StripTags(text, ""), " ").Trim();
    }
}
