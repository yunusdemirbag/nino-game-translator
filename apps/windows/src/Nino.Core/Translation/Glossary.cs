// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Nino.Core.Translation;

/// <summary>Sözlükteki bir terim.</summary>
/// <param name="English">İngilizcesi (boşluklar teklenmiş).</param>
/// <param name="Turkish">Türkçesi (<c>keep</c> adlarında kendisi).</param>
/// <param name="Exact">Yalnız aynı büyük/küçük harfle eşleşir (<c>keepExact</c>).</param>
public sealed record GlossaryTerm(string English, string Turkish, bool Exact);

/// <summary>Metinde bulunan terim.</summary>
public readonly record struct TermMatch(int Index, int Length, GlossaryTerm Term);

/// <summary>Sözlük dosyası bozuk.</summary>
public sealed class GlossaryFormatException(string message) : Exception(message);

/// <summary>
/// İngilizce → Türkçe terim sözlüğü (çeviri tarifi §5): terimler, olduğu gibi kalacak adlar, argo kuralları, hazır
/// satırlar ve önbellek anahtarına giren iz. Değişmez; birleştirme yeni nesne üretir.
/// </summary>
public sealed partial class Glossary
{
    /// <summary>İngilizcenin en çok UTF-16 uzunluğu.</summary>
    public const int MaxTermLength = 80;

    static readonly JsonDocumentOptions JsonOptions = new()
    {
        CommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    readonly Dictionary<string, GlossaryTerm> _terms;
    readonly SortedDictionary<string, string> _phrases;
    readonly Dictionary<string, string> _lines;
    readonly List<(Regex Pattern, string Plain)> _phraseRules;
    readonly List<GlossaryTerm> _ordered;
    readonly Lazy<string> _fingerprint;
    readonly Lazy<HashSet<string>> _keepUpper;

    Glossary(Dictionary<string, GlossaryTerm> terms, SortedDictionary<string, string> phrases,
        Dictionary<string, string> lines)
    {
        _terms = terms;
        _phrases = phrases;
        _lines = lines;
        _phraseRules = phrases.Select(p => (Rule(p.Key)!, p.Value)).ToList();
        _ordered = terms.Values.OrderByDescending(t => t.English.Length)
            .ThenBy(t => t.English, Utf8Comparer.Instance).ToList();
        _fingerprint = new Lazy<string>(ComputeFingerprint);
        _keepUpper = new Lazy<HashSet<string>>(ComputeKeepUpper);
    }

    /// <summary>Boş sözlük.</summary>
    public static Glossary Empty { get; } = new(new(), new(Utf8Comparer.Instance), new());

    /// <summary>Terim sayısı.</summary>
    public int TermCount => _terms.Count;

    /// <summary>Terimler (anahtar = küçük harfli İngilizce).</summary>
    public IReadOnlyDictionary<string, GlossaryTerm> Terms => _terms;

    /// <summary>Uygulamayla gelen genel sözlük (gömülü <c>glossary-en-tr.json</c>).</summary>
    public static Glossary General => GeneralLazy.Value;

    static readonly Lazy<Glossary> GeneralLazy = new(() => Parse(GeneralBytes()));

    /// <summary>Gömülü genel sözlüğün baytları.</summary>
    public static byte[] GeneralBytes()
    {
        using var stream = typeof(Glossary).Assembly.GetManifestResourceStream("glossary-en-tr.json")!;
        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        return ms.ToArray();
    }

    [GeneratedRegex(@"\s+")]
    private static partial Regex Spaces();

    static string Collapse(string text) => Spaces().Replace(text, " ").Trim();

    static Regex? Rule(string pattern)
    {
        try
        {
            return new Regex(@"\b(?:" + pattern + @")\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant,
                TimeSpan.FromMilliseconds(100));
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    /// <summary>Sözlük dosyasını okur; kök nesne değilse ya da JSON bozuksa <see cref="GlossaryFormatException"/>.</summary>
    public static Glossary Parse(byte[] json) => Merge([ParseParts(json)]);

    /// <summary>Metinden okur.</summary>
    public static Glossary Parse(string json) => Parse(Encoding.UTF8.GetBytes(json));

    /// <summary>Sırayla birleştirir; aynı anahtarda sonraki kazanır.</summary>
    public static Glossary Merge(IEnumerable<Glossary> parts)
    {
        var terms = new Dictionary<string, GlossaryTerm>(StringComparer.Ordinal);
        var phrases = new SortedDictionary<string, string>(Utf8Comparer.Instance);
        var lines = new Dictionary<string,
            string>(StringComparer.Ordinal);
        foreach (var g in parts)
        {
            foreach (var (k, v) in g._terms) terms[k] = v;
            foreach (var (k, v) in g._phrases) phrases[k] = v;
            foreach (var (k, v) in g._lines) lines[k] = v;
        }
        return new Glossary(terms,
            phrases, lines);
    }

    static Glossary ParseParts(byte[] json)
    {
        JsonDocument doc;
        try { doc = JsonDocument.Parse(json, JsonOptions); }
        catch (JsonException e) { throw new GlossaryFormatException(e.Message); }
        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new GlossaryFormatException("kök nesne değil");
            var terms = new Dictionary<string, GlossaryTerm>(StringComparer.Ordinal);
            var phrases = new SortedDictionary<string, string>(Utf8Comparer.Instance);
            var lines = new Dictionary<string,
                string>(StringComparer.Ordinal);

            if (root.TryGetProperty("terms", out var t) && t.ValueKind == JsonValueKind.Object)
                foreach (var p in t.EnumerateObject())
                    if (p.Value.ValueKind == JsonValueKind.String) AddTerm(terms, p.Name, p.Value.GetString()!, false);
            foreach (var (name, exact) in new[] { ("keep", false), ("keepExact", true) })
                if (root.TryGetProperty(name, out var arr) && arr.ValueKind == JsonValueKind.Array)
                    foreach (var item in arr.EnumerateArray())
                        if (item.ValueKind == JsonValueKind.String)
                            AddTerm(terms, item.GetString()!, item.GetString()!, exact);
            if (root.TryGetProperty("phrases", out var ph) && ph.ValueKind == JsonValueKind.Object)
                foreach (var p in ph.EnumerateObject())
                    if (p.Value.ValueKind == JsonValueKind.String && p.Name.Length > 0
                        && p.Value.GetString() is { Length: > 0 } plain && Rule(p.Name) is not null)
                        phrases[p.Name] = plain;
            if (root.TryGetProperty("lines", out var ln) && ln.ValueKind == JsonValueKind.Object)
                foreach (var p in ln.EnumerateObject())
                {
                    if (p.Value.ValueKind != JsonValueKind.String) continue;
                    var key = LineKeyOf(p.Name);
                    var value = Collapse(p.Value.GetString()!);
                    if (key.Length > 0 && value.Length > 0) lines[key] = value;
                }
            return new Glossary(terms,
                phrases, lines);
        }
    }

    static void AddTerm(Dictionary<string, GlossaryTerm> terms, string english, string turkish, bool exact)
    {
        var en = Collapse(english);
        var tr = Collapse(turkish);
        if (!en.Any(char.IsLetter) || tr.Length == 0 || en.Length > MaxTermLength) return;
        terms[en.ToLowerInvariant()] = new GlossaryTerm(en, tr, exact);
    }

    /// <summary>Terimin Türkçesi (soru boşlukları teklenip küçük harfle aranır).</summary>
    public string? TurkishOf(string english) =>
        _terms.TryGetValue(Collapse(english).ToLowerInvariant(), out var t) ? t.Turkish : null;

    static bool IsBoundary(string text, int index) =>
        index < 0 || index >= text.Length ||
            !char.IsLetterOrDigit(text[index]);

    /// <summary>Metindeki terimler: uzundan kısaya, çakışmasız, konuma göre sıralı.</summary>
    public IReadOnlyList<TermMatch> FindTerms(string text)
    {
        var found = new List<TermMatch>();
        if (_ordered.Count == 0 ||
            text.Length == 0) return found;
        foreach (var term in _ordered)
        {
            var comparison = term.Exact ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
            var from = 0;
            while (from <= text.Length - term.English.Length)
            {
                var at = text.IndexOf(term.English, from, comparison);
                if (at < 0) break;
                var end = at + term.English.Length;
                if (IsBoundary(text, at - 1) && IsBoundary(text, end)
                    && !found.Any(m => at < m.Index + m.Length && m.Index < end))
                    found.Add(new TermMatch(at, term.English.Length, term));
                from = at + 1;
            }
        }
        found.Sort((a, b) => a.Index.CompareTo(b.Index));
        return found;
    }

    /// <summary>Büyük kalacak sözcükler (küçük harfle): <c>keepExact</c> olmayan, büyük harfli terimlerin sözcükleri.</summary>
    public IReadOnlySet<string> KeepUpperWords => _keepUpper.Value;

    HashSet<string> ComputeKeepUpper()
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        foreach (var term in _terms.Values)
        {
            if (term.Exact || !term.English.Any(char.IsUpper)) continue;
            foreach (var word in term.English.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                if (word.Length >= 2) set.Add(word.ToLowerInvariant());
        }
        return set;
    }

    /// <summary>Satır anahtarı: küçük harf, kıvrık kesme düz, boşluklar tek, baş/son harf-rakam dışı atılmış.</summary>
    public static string LineKeyOf(string text)
    {
        var s = Collapse(text.ToLowerInvariant().Replace('’', '\'').Replace('‘', '\''));
        var start = 0;
        var end = s.Length;
        while (start < end && !char.IsLetterOrDigit(s[start])) start++;
        while (end > start && !char.IsLetterOrDigit(s[end - 1])) end--;
        return s[start..end];
    }

    static bool IsTerminal(char c) => c is '.' or '!' or '?' or '…';

    /// <summary>Cümlenin hazır satırı (Türkçesi; sonuna kaynağın son işaretleri eklenir); yoksa null.</summary>
    public string? ReadyLine(string sentence)
    {
        if (!_lines.TryGetValue(LineKeyOf(sentence), out var turkish)) return null;
        if (IsTerminal(turkish[^1])) return turkish;
        var source = sentence.Trim();
        var i = source.Length;
        while (i > 0 && IsTerminal(source[i - 1])) i--;
        return turkish + source[i..];
    }

    /// <summary>Argo kurallarını (<c>phrases</c>) uygular.</summary>
    public string FlattenSlang(string text)
    {
        foreach (var (pattern, plain) in _phraseRules)
        {
            try { text = pattern.Replace(text, m => GameIdioms.MatchCase(m.Value, plain)); }
            catch (RegexMatchTimeoutException) { }
        }
        return text;
    }

    /// <summary>Metni hazır satır ya da argo kuralı değiştiriyor mu.</summary>
    public bool Rewrites(string text)
    {
        if (_lines.ContainsKey(LineKeyOf(text))) return true;
        foreach (var (pattern, _) in _phraseRules)
        {
            try
            {
                if (pattern.IsMatch(text)) return true;
            }
            catch (RegexMatchTimeoutException) { }
        }
        return false;
    }

    /// <summary>Önbellek anahtarına giren iz (<c>g</c> + 8 hex, FNV-1a 32).</summary>
    public string Fingerprint => _fingerprint.Value;

    string ComputeFingerprint()
    {
        var hash = 2166136261u;
        void Mix(string s)
        {
            foreach (var b in Encoding.UTF8.GetBytes(s))
            {
                hash ^= b;
                hash *= 16777619u;
            }
        }
        foreach (var (key, term) in _terms.OrderBy(p => p.Key, Utf8Comparer.Instance))
            Mix(key + "\u0001" + term.Turkish + (term.Exact ? "\u0003" : "") + "\u0002");
        foreach (var (key, plain) in _phrases) Mix(key + "\u0004" + plain + "\u0005");
        foreach (var (key, turkish) in _lines.OrderBy(p => p.Key, Utf8Comparer.Instance))
            Mix(key + "\u0006" + turkish + "\u0007");
        return "g" + hash.ToString("x8", System.Globalization.CultureInfo.InvariantCulture);
    }
}

/// <summary>UTF-8 bayt sırasıyla karşılaştırma.</summary>
internal sealed class Utf8Comparer : IComparer<string>
{
    public static Utf8Comparer Instance { get; } = new();

    public int Compare(string? x, string? y)
    {
        if (ReferenceEquals(x, y)) return 0;
        if (x is null) return -1;
        if (y is null) return 1;
        return Encoding.UTF8.GetBytes(x).AsSpan().SequenceCompareTo(Encoding.UTF8.GetBytes(y));
    }
}

/// <summary>
/// Genel sözlük + kullanıcı klasörü (<c>glossary\*.json</c>, tam yol sırasıyla). İstendiğinde son bakıştan 5 sn
/// geçtiyse klasörün dosya listesine (yol, boy, yazma zamanı) bakar; değiştiyse yeniden okur.
/// </summary>
public sealed class GlossaryFolder
{
    /// <summary>Yeniden bakma aralığı.</summary>
    public static readonly TimeSpan CheckInterval = TimeSpan.FromSeconds(5);

    readonly string? _folder;
    readonly Glossary _general;
    readonly TimeProvider _clock;
    readonly object _gate = new();
    Glossary? _current;
    string? _signature;
    DateTimeOffset _checked;

    public GlossaryFolder(string? folder, Glossary? general = null, TimeProvider? clock = null)
    {
        _folder = folder;
        _general = general ?? Glossary.General;
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>Şu anki sözlük.</summary>
    public Glossary Current
    {
        get
        {
            lock (_gate)
            {
                var now = _clock.GetUtcNow();
                if (_current is not null && now - _checked < CheckInterval) return _current;
                _checked = now;
                var files = ListFiles();
                var signature = string.Join("\n", files.Select(f => $"{f.FullName}|{f.Length}|{f.LastWriteTimeUtc.Ticks}"));
                if (_current is not null && signature == _signature) return _current;
                _signature = signature;
                var parts = new List<Glossary> { _general };
                foreach (var file in files)
                {
                    try { parts.Add(Glossary.Parse(File.ReadAllBytes(file.FullName))); }
                    catch (Exception e) when (e is GlossaryFormatException or IOException or UnauthorizedAccessException) { }
                }
                return _current = Glossary.Merge(parts);
            }
        }
    }

    List<FileInfo> ListFiles()
    {
        try
        {
            if (_folder is null || !Directory.Exists(_folder)) return [];
            return Directory.GetFiles(_folder).Where(f => f.EndsWith(".json", StringComparison.Ordinal))
                .OrderBy(f => f, StringComparer.Ordinal).Select(f => new FileInfo(f)).ToList();
        }
        catch (Exception e) when (e is IOException
            or UnauthorizedAccessException)
        {
            return [];
        }
    }
}
