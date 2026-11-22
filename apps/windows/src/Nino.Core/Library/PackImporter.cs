// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Json;

namespace Nino.Core.Library;

/// <summary>İçe aktarma hatasının türü.</summary>
public enum PackImportError
{
    TooLarge, NotUtf8, UnsupportedFileType, InvalidJson, UnsupportedFormat, FormatRequired, EntriesNotObject,
    MissingTitle, NoEntries, SourceIsTarget, AlreadyExists, WriteFailed,
}

/// <summary>İçe aktarılamadı.</summary>
public sealed class PackImportException(PackImportError error, string? message = null)
    : Exception(message ?? error.ToString())
{
    /// <summary>Tür.</summary>
    public PackImportError Error { get; } = error;
}

/// <summary>İçe aktarma önizlemesi.</summary>
/// <param name="Entries">Geçerli kayıtlar (16 hex → Türkçe), ilk geçiş sırasıyla.</param>
/// <param name="Invalid">Geçersiz satır sayısı.</param>
/// <param name="Duplicates">Yinelenen sayısı.</param>
/// <param name="Conflicts">Çelişkili anahtar sayısı.</param>
/// <param name="SuggestedTitle">Önerilen başlık (yoksa null).</param>
public sealed record PackImportPreview(IReadOnlyList<KeyValuePair<string, string>> Entries, int Invalid, int Duplicates,
    int Conflicts, string? SuggestedTitle);

/// <summary>Kullanıcının çeviri dosyasından oyun paketi (havuz/paket tarifi §5): JSON, TXT, SRT.</summary>
public static class PackImporter
{
    /// <summary>En büyük dosya.</summary>
    public const long MaxBytes = 64L * 1024 * 1024;

    static readonly UTF8Encoding StrictUtf8 = new(false, throwOnInvalidBytes: true);

    /// <summary>Dosyayı okuyup önizleme üretir.</summary>
    public static PackImportPreview Read(string path)
    {
        var info = new FileInfo(path);
        if (info.Length > MaxBytes) throw new PackImportException(PackImportError.TooLarge);
        return Parse(File.ReadAllBytes(path), Path.GetExtension(path));
    }

    /// <summary>Baytlardan önizleme (uzantı noktasıyla, ör. <c>.json</c>).</summary>
    public static PackImportPreview Parse(byte[] bytes, string extension)
    {
        if (bytes.Length > MaxBytes) throw new PackImportException(PackImportError.TooLarge);
        var start = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
        string text;
        try { text = StrictUtf8.GetString(bytes, start, bytes.Length - start); }
        catch (DecoderFallbackException) { throw new PackImportException(PackImportError.NotUtf8); }
        var counter = new Counter();
        string? title;
        switch (extension.ToLowerInvariant())
        {
            case ".json": title = ParseJson(text, counter); break;
            case ".txt": title = null; ParseTxt(text, counter); break;
            case ".srt": title = null; ParseSrt(text, counter); break;
            default: throw new PackImportException(PackImportError.UnsupportedFileType);
        }
        return counter.Preview(title);
    }

    sealed class Counter
    {
        readonly List<string> _order = [];
        readonly Dictionary<string, string> _result = new(StringComparer.Ordinal);
        readonly Dictionary<string, HashSet<string>> _conflicted = new(StringComparer.Ordinal);
        public int Invalid;
        public int Duplicates;

        public void AddEnglish(string? english, string? turkish) =>
            Add(english is null ? null : LineKey.Compute(english), turkish);

        public void Add(string? key, string? turkish)
        {
            var tr = turkish?.Trim();
            if (key is null || string.IsNullOrEmpty(tr))
            {
                Invalid++;
                return;
            }
            if (_conflicted.TryGetValue(key, out var targets))
            {
                if (!targets.Add(tr)) Duplicates++;
                return;
            }
            if (_result.TryGetValue(key, out var existing))
            {
                if (existing == tr) Duplicates++;
                else
                {
                    _result.Remove(key);
                    _order.Remove(key);
                    _conflicted[key] = new HashSet<string>(StringComparer.Ordinal) { existing, tr };
                }
                return;
            }
            _result[key] = tr;
            _order.Add(key);
        }

        public PackImportPreview Preview(string? title) => new(
            _order.Select(k => new KeyValuePair<string, string>(k, _result[k])).ToList(), Invalid, Duplicates,
            _conflicted.Count, title);
    }

    static string? NonEmptyText(JsonElement? e) =>
        e is { ValueKind: JsonValueKind.String } v && v.GetString()!.Trim() is { Length: > 0 } t ? t : null;

    static string? ParseJson(string text, Counter counter)
    {
        try
        {
            using var doc = JsonDocument.Parse(text);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new PackImportException(PackImportError.InvalidJson);
            // Yinelenen adlarda tek değer gereken yerlerde son geçiş geçerli.
            JsonElement? Last(string name)
            {
                JsonElement? found = null;
                foreach (var p in root.EnumerateObject())
                    if (p.NameEquals(name)) found = p.Value;
                return found;
            }
            var format = Last("format");
            var entries = Last("entries");
            if (format is { ValueKind: JsonValueKind.Number } f)
            {
                if (f.GetDouble() != 1) throw new PackImportException(PackImportError.UnsupportedFormat);
                if (entries is not { ValueKind: JsonValueKind.Object } obj)
                    throw new PackImportException(PackImportError.EntriesNotObject);
                foreach (var p in obj.EnumerateObject())
                {
                    var name = p.Name;
                    var key = name.Length == 16 && name.All(char.IsAsciiHexDigit) ? name.ToLowerInvariant() : null;
                    counter.Add(key, p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() : null);
                }
                return NonEmptyText(Last("title")) ?? NonEmptyText(Last("game"));
            }
            if (entries is { ValueKind: JsonValueKind.Object })
                throw new PackImportException(PackImportError.FormatRequired);
            if (Last("subtitles") is { ValueKind: JsonValueKind.Object } subtitles)
            {
                foreach (var p in subtitles.EnumerateObject())
                    counter.AddEnglish(p.Name, p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() : null);
                return NonEmptyText(Last("game")) ?? NonEmptyText(Last("title"));
            }
            foreach (var p in root.EnumerateObject())
                counter.AddEnglish(p.Name, p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() : null);
            return null;
        }
        catch (JsonException)
        {
            throw new PackImportException(PackImportError.InvalidJson);
        }
        catch (InvalidOperationException)
        {
            // Geçersiz Unicode kaçışı (ör. \uD800) metin olarak okunamaz.
            throw new PackImportException(PackImportError.InvalidJson);
        }
    }

    static string[] Lines(string text) => text.Replace("\r\n", "\n").Split('\n');

    static void ParseTxt(string text, Counter counter)
    {
        foreach (var line in Lines(text))
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0 || trimmed.StartsWith('#')) continue;
            string english, turkish;
            var tabs = line.Count(c => c == '\t');
            if (tabs > 0)
            {
                if (tabs > 1)
                {
                    counter.Invalid++;
                    continue;
                }
                var at = line.IndexOf('\t');
                english = line[..at];
                turkish = line[(at + 1)..];
            }
            else
            {
                var at = line.IndexOf(" = ", StringComparison.Ordinal);
                if (at < 0)
                {
                    counter.Invalid++;
                    continue;
                }
                english = line[..at];
                turkish = line[(at + 3)..];
            }
            counter.AddEnglish(english, turkish);
        }
    }

    static void ParseSrt(string text, Counter counter)
    {
        var block = new List<string>();
        void Flush()
        {
            if (block.Count == 0) return;
            if (block.Count == 4 && block[0].All(char.IsAsciiDigit) && IsTimeLine(block[1]))
                counter.AddEnglish(block[2], block[3]);
            else counter.Invalid++;
            block.Clear();
        }
        foreach (var line in Lines(text))
        {
            var trimmed = line.Trim();
            if (trimmed.Length == 0) Flush();
            else block.Add(trimmed);
        }
        Flush();
    }

    static bool IsTimeLine(string line)
    {
        if (line.Length != 29 || line.Substring(12, 5) != " --> ") return false;
        var a = line[..12];
        var b = line[17..];
        return IsStamp(a) && IsStamp(b) && string.CompareOrdinal(a, b) < 0;
    }

    static bool IsStamp(string s)
    {
        if (s.Length != 12 || s[2] != ':' || s[5] != ':' || s[8] != ',') return false;
        foreach (var i in new[] { 0, 1, 3, 4, 6, 7, 9, 10, 11 })
            if (!char.IsAsciiDigit(s[i])) return false;
        return s[3] <= '5' && s[6] <= '5';
    }

    /// <summary>Başlıktan paket kimliği (§5.2): <c>community-…</c>.</summary>
    public static string IdFor(string title)
    {
        var sb = new StringBuilder();
        var pendingDash = false;
        foreach (var c in title)
        {
            if (char.IsAsciiLetterOrDigit(c))
            {
                var add = (pendingDash ? 1 : 0) + 1;
                if (sb.Length + add > 80) break;
                if (pendingDash) sb.Append('-');
                sb.Append(char.ToLowerInvariant(c));
                pendingDash = false;
            }
            else if (sb.Length > 0) pendingDash = true;
        }
        return "community-" + (sb.Length == 0 ? "game" : sb.ToString());
    }

    /// <summary>Hedef dosyanın yolu.</summary>
    public static string TargetPath(string packsFolder, string title) =>
        Path.Combine(packsFolder, IdFor(title.Trim()) + ".json");

    /// <summary>
    /// Paketi yazar (biçim 1, tam 4 alan). <paramref name="replace"/> yoksa ve hedef varsa hata. Kaynak hedefin kendisiyse
    /// hata. <paramref name="sameFile"/> Windows'ta dosya kimliği karşılaştırması (null: bağlantı çözülmüş yol).
    /// </summary>
    public static string Write(PackImportPreview preview, string title, string packsFolder, string? sourcePath,
        bool replace, Func<string, string, bool?>? sameFile = null)
    {
        var trimmed = title.Trim();
        if (trimmed.Length == 0) throw new PackImportException(PackImportError.MissingTitle);
        if (preview.Entries.Count == 0) throw new PackImportException(PackImportError.NoEntries);
        var target = TargetPath(packsFolder, trimmed);
        if (sourcePath is not null && IsSameFile(sourcePath, target, sameFile))
            throw new PackImportException(PackImportError.SourceIsTarget);

        var id = IdFor(trimmed);
        var json = PoolHttp.Json(w =>
        {
            w.WriteStartObject();
            w.WriteNumber("format", 1);
            w.WriteString("id", id);
            w.WriteString("title", trimmed);
            w.WriteStartObject("entries");
            foreach (var (k, v) in preview.Entries) w.WriteString(k, v);
            w.WriteEndObject();
            w.WriteEndObject();
        });
        Directory.CreateDirectory(packsFolder);
        var temp = Path.Combine(packsFolder, "." + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            File.WriteAllBytes(temp, json);
            if (!replace && File.Exists(target)) throw new PackImportException(PackImportError.AlreadyExists);
            File.Move(temp, target, overwrite: replace);
        }
        catch (IOException e)
        {
            throw File.Exists(target) && !replace
                ? new PackImportException(PackImportError.AlreadyExists)
                : new PackImportException(PackImportError.WriteFailed, e.Message);
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); }
            catch (Exception e) when (e is IOException
                or UnauthorizedAccessException) { }
        }
        return target;
    }

    /// <summary>İki yol aynı dosya mı.</summary>
    public static bool IsSameFile(string a, string b, Func<string, string, bool?>? probe = null)
    {
        var fa = Path.GetFullPath(a);
        var fb = Path.GetFullPath(b);
        if (fa == fb) return true;
        if (!File.Exists(fa) || !File.Exists(fb)) return false;
        if (probe?.Invoke(fa, fb) is { } known) return known;
        return string.Equals(Resolve(fa), Resolve(fb), StringComparison.OrdinalIgnoreCase);
    }

    static string Resolve(string path)
    {
        try { return new FileInfo(path).ResolveLinkTarget(true)?.FullName ?? path; }
        catch (IOException) { return path; }
    }
}
