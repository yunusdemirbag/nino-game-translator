// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Nino.Core.Data;

/// <summary>Geçmişteki satırın kökeni.</summary>
public enum HistoryOrigin { Pack, Engine }

/// <summary>Geçmişteki bir satır.</summary>
public sealed record HistoryEntry(long Id, DateTimeOffset Date, string Source, string Translation, HistoryOrigin Origin);

/// <summary>
/// Geçmiş altyazılar (<c>history.json</c>, Mac ile aynı biçim). En yeni başta, en çok 200 satır, metin başına en çok 500
/// karakter. Arka plan sıralaması çağıranındır; bu sınıf iş parçacığı güvenlidir.
/// </summary>
public sealed class SubtitleHistory
{
    /// <summary>Dosya adı.</summary>
    public const string FileName = "history.json";

    /// <summary>En çok satır.</summary>
    public const int MaxEntries = 200;

    /// <summary>Metin başına en çok karakter.</summary>
    public const int MaxTextLength = 500;

    static readonly JsonSerializerOptions WriteOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, // Türkçe harfler kaçışsız
    };

    readonly Func<string, string, bool> _similar;
    readonly TimeProvider _clock;
    readonly object _gate = new();
    readonly List<HistoryEntry> _entries = [];
    long _nextId;

    /// <param name="similar">
    /// İki kaynak satırı "aynı satır" mı (okuma hattının benzerlik kuralı). Verilmezse sadeleştirilmiş metinlerde
    /// 0,85 düzenleme benzerliği kullanılır.
    /// </param>
    /// <param name="clock">Yeni kayıtların tarihi.</param>
    public SubtitleHistory(Func<string, string, bool>? similar = null, TimeProvider? clock = null)
    {
        _similar = similar ?? TextSimilarity.SameLine;
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>En yeni başta kayıtlar.</summary>
    public IReadOnlyList<HistoryEntry> Entries
    {
        get { lock (_gate) return _entries.ToArray(); }
    }

    /// <summary>
    /// Satır ekler. Çeviri kırpılır, boşsa eklenmez (false). İlk kaydın kaynağı yenisine benzerse ilk kayıt aynı
    /// kimlikle güncellenir.
    /// </summary>
    public bool Add(string source, string translation, HistoryOrigin origin)
    {
        var tr = Cut(translation.Trim());
        if (tr.Length == 0) return false;
        var src = Cut(source);
        var now = TruncateToSeconds(_clock.GetUtcNow());
        lock (_gate)
        {
            if (_entries.Count > 0 && _similar(_entries[0].Source, src))
            {
                _entries[0] = _entries[0] with { Date = now, Source = src, Translation = tr, Origin = origin };
                return true;
            }
            _entries.Insert(0, new HistoryEntry(_nextId++, now, src, tr, origin));
            if (_entries.Count > MaxEntries) _entries.RemoveRange(MaxEntries, _entries.Count - MaxEntries);
            return true;
        }
    }

    /// <summary>Listeyi boşaltır.</summary>
    public void Clear()
    {
        lock (_gate) _entries.Clear();
    }

    /// <summary>Verilen andan (oturum başı) sonraki kayıtlar, en yeni başta.</summary>
    public IReadOnlyList<HistoryEntry> Since(DateTimeOffset start)
    {
        lock (_gate) return _entries.Where(e => e.Date >= TruncateToSeconds(start)).ToArray();
    }

    /// <summary>
    /// Kopyalama metni: her kayıt <c>[SS:dd:ss] çeviri\nkaynak</c> (yerel saat), kayıtlar boş satırla ayrılır.
    /// </summary>
    public static string CopyText(IEnumerable<HistoryEntry> entries, TimeZoneInfo? zone = null)
    {
        zone ??= TimeZoneInfo.Local;
        return string.Join("\n\n", entries.Select(e =>
        {
            var local = TimeZoneInfo.ConvertTime(e.Date, zone);
            return $"[{local.ToString("HH:mm:ss", CultureInfo.InvariantCulture)}] {e.Translation}\n{e.Source}";
        }));
    }

    /// <summary>Dosyayı okur; dosya yok ya da bozuksa boş geçmiş. Kimlik en büyük + 1'den sürer.</summary>
    public void Load(string path)
    {
        var loaded = Read(path);
        lock (_gate)
        {
            _entries.Clear();
            _entries.AddRange(loaded);
            _nextId = loaded.Count == 0 ? 0 : loaded.Max(e => e.Id) + 1;
        }
    }

    /// <summary>Dosyaya yazar (<c>.tmp</c> + taşıma). Hata fırlatabilir (çağıran sonraki satırda yeniden dener).</summary>
    public void Save(string path) => FileIo.WriteAtomic(path, Serialize(Entries));

    /// <summary>Mac ile aynı JSON.</summary>
    public static string Serialize(IEnumerable<HistoryEntry> entries)
    {
        var list = new JsonArray();
        foreach (var e in entries)
        {
            list.Add(new JsonObject
            {
                ["id"] = e.Id,
                ["date"] = e.Date.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
                ["source"] = e.Source,
                ["translation"] = e.Translation,
                ["origin"] = e.Origin == HistoryOrigin.Pack ? "pack" : "engine",
            });
        }
        return new JsonObject { ["version"] = 1, ["entries"] = list }.ToJsonString(WriteOptions);
    }

    /// <summary>
    /// Okuma: dosya yok, bozuk, tarihi okunamayan ya da bilinmeyen kökenli kayıt → boş. Kaynağı/çevirisi eksik
    /// kayıtlar atlanır; en çok 200 alınır.
    /// </summary>
    public static List<HistoryEntry> Read(string path)
    {
        try
        {
            if (!File.Exists(path)) return [];
            return Parse(File.ReadAllText(path, FileIo.Utf8));
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { return []; }
    }

    /// <summary><see cref="Read"/>'in metin hali.</summary>
    public static List<HistoryEntry> Parse(string json)
    {
        var result = new List<HistoryEntry>();
        try
        {
            if (JsonNode.Parse(json) is not JsonObject root || root["entries"] is not JsonArray items) return [];
            foreach (var item in items)
            {
                if (item is not JsonObject o) return [];
                if (o["date"]?.GetValue<string>() is not { } dateText
                    || !DateTimeOffset.TryParse(dateText, CultureInfo.InvariantCulture,
                        DateTimeStyles.RoundtripKind | DateTimeStyles.AssumeUniversal, out var date))
                    return [];
                var origin = o["origin"]?.GetValue<string>() switch
                {
                    "pack" => HistoryOrigin.Pack,
                    "engine" => HistoryOrigin.Engine,
                    _ => (HistoryOrigin?)null,
                };
                if (origin is null) return [];
                var source = o["source"]?.GetValue<string>();
                var translation = o["translation"]?.GetValue<string>();
                if (source is null || translation is null) continue;
                var id = o["id"]?.GetValue<long>() ?? 0;
                result.Add(new HistoryEntry(id, date.ToUniversalTime(), Cut(source), Cut(translation), origin.Value));
                if (result.Count == MaxEntries) break;
            }
            return result;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException)
        {
            return [];
        }
    }

    static string Cut(string text)
    {
        if (text.Length <= MaxTextLength) return text;
        var end = MaxTextLength;
        if (char.IsHighSurrogate(text[end - 1])) end--;
        return text[..end];
    }

    static DateTimeOffset TruncateToSeconds(DateTimeOffset t) =>
        new(t.UtcTicks - t.UtcTicks % TimeSpan.TicksPerSecond, TimeSpan.Zero);
}

/// <summary>Geçmişin varsayılan benzerlik kuralı (okuma hattındaki tanımın küçük bir kopyası).</summary>
public static class TextSimilarity
{
    /// <summary>Sadeleştirilmiş iki metin 0,85 düzenleme benzerliğindeyse aynı satır.</summary>
    public static bool SameLine(string a, string b) => Similar(Simplify(a), Simplify(b), 0.85);

    /// <summary>Küçük harf; harf, birleşen işaret ve sayı kalır, öbürü boşluk; boşluklar teke iner.</summary>
    public static string Simplify(string text)
    {
        var sb = new StringBuilder(text.Length);
        var space = false;
        foreach (var c in text.ToLowerInvariant())
        {
            var keep = char.GetUnicodeCategory(c) switch
            {
                UnicodeCategory.LowercaseLetter => true,
                UnicodeCategory.UppercaseLetter => true,
                UnicodeCategory.TitlecaseLetter => true,
                UnicodeCategory.ModifierLetter => true,
                UnicodeCategory.OtherLetter => true,
                UnicodeCategory.NonSpacingMark => true,
                UnicodeCategory.SpacingCombiningMark => true,
                UnicodeCategory.EnclosingMark => true,
                UnicodeCategory.DecimalDigitNumber => true,
                UnicodeCategory.LetterNumber => true,
                UnicodeCategory.OtherNumber => true,
                _ => false,
            };
            if (keep)
            {
                if (space && sb.Length > 0) sb.Append(' ');
                space = false;
                sb.Append(c);
            }
            else space = true;
        }
        return sb.ToString();
    }

    /// <summary>1 − düzenleme uzaklığı / uzun olanın uzunluğu ≥ eşik. Boş metin benzer değildir.</summary>
    public static bool Similar(string a, string b, double threshold)
    {
        if (a.Length * b.Length == 0) return false;
        if (a == b) return true;
        var prev = new int[b.Length + 1];
        var cur = new int[b.Length + 1];
        for (var j = 0; j <= b.Length; j++) prev[j] = j;
        for (var i = 1; i <= a.Length; i++)
        {
            cur[0] = i;
            for (var j = 1; j <= b.Length; j++)
                cur[j] = Math.Min(Math.Min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            (prev, cur) = (cur, prev);
        }
        return 1.0 - (double)prev[b.Length] / Math.Max(a.Length, b.Length) >= threshold;
    }
}
