// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using Nino.Core.Translation;

namespace Nino.Core.Library;

/// <summary>Ayarlarda gösterilen paket bilgisi.</summary>
public sealed record PackInfo(string Id, string Title, int EntryCount);

/// <summary>
/// Paketlerin birleşimi, tam/parçalı/bulanık arama, kapsam ve elle seçilen oyun (havuz/paket tarifi §2–§3).
/// Paketler yalnız kaynak <c>en</c>, hedef <c>tr</c> ve "Paketler" açıkken kullanılır; bu kararı çağıran verir.
/// Bütün üyeler iş parçacığı güvenlidir. Yükleme ilk sorguda yapılır.
/// </summary>
public sealed class PackLibrary
{
    /// <summary>Genel paketin kimliği (elle seçimde atlanır).</summary>
    public const string GeneralPackId = "pool-genel";

    static readonly (string Read, string Actual)[] Confusions =
    [
        ("rn", "m"), ("m", "rn"), ("cl", "d"), ("d", "cl"),
            ("vv", "w"), ("ri", "n"), ("n", "ri"), ("li", "h"),
        ("l", "i"), ("i", "l"), ("1", "l"), ("1", "i"), ("0",
            "o"), ("5", "s"), ("j", "i"), ("c", "e"), ("e", "c"),
        ("a", "o"), ("o", "a"), ("h", "b"), ("b", "h"), ("f",
            "t"), ("t", "f"), ("u", "v"), ("v", "u"), ("y", "v"),
        ("v", "y"), ("q", "g"), ("g", "q"),
    ];

    readonly string? _userFolder;
    readonly object _gate = new();
    List<GamePack>? _packs;
    Dictionary<ulong, string> _merged = new();
    GamePack? _scope;
    GamePack? _distinctive;
    string? _selectedKey;
    GamePack? _selectedPack;

    /// <param name="userFolder">
    /// Kullanıcı paket klasörü (<c>%LOCALAPPDATA%\Nino\packs</c>; null: yok). Uygulamayla gelen paket yoktur; bütün
    /// paketler buradadır: sunucudan inenler (<c>&lt;id&gt;.json.gz</c>) ve içe aktarılanlar (<c>community-*.json</c>).
    /// </param>
    public PackLibrary(string? userFolder)
    {
        _userFolder = userFolder;
    }

    /// <summary>Kullanıcı paket klasörü.</summary>
    public string? UserFolder => _userFolder;

    /// <summary>Paketleri şimdi yükler (açılışta arka planda "ısıtma").</summary>
    public void WarmUp()
    {
        lock (_gate) EnsureLoaded();
    }

    /// <summary>Tümünü sıfırlar; sonraki sorguda yeniden yüklenir.</summary>
    public void Reload()
    {
        lock (_gate)
        {
            _packs = null;
            _merged = new();
            _scope = null;
            _distinctive = null;
            _selectedPack = null;
        }
    }

    /// <summary>Paket bilgileri (yükleme sırasıyla).</summary>
    public IReadOnlyList<PackInfo> Infos
    {
        get
        {
            lock (_gate)
                return EnsureLoaded().Select(p => new PackInfo(p.Id, p.Title, p.Entries.Count)).ToList();
        }
    }

    /// <summary>Yüklü paketler.</summary>
    public IReadOnlyList<GamePack> Packs
    {
        get { lock (_gate) return EnsureLoaded().ToList(); }
    }

    /// <summary>Kapsam paketinin kimliği (havuza "oyun ipucu" olarak gider); yoksa null.</summary>
    public string? ScopeId
    {
        get { lock (_gate) return _scope?.Id; }
    }

    /// <summary>
    /// Kapsam paketinin sunucuya giden oyun kimliği (asıl kimlik; <c>pool-gta-6</c> → <c>gta-6</c>, içe aktarılan
    /// <c>community-…</c> paketlerde başlıktan); yoksa null. Genel paket kendi kimliğiyle kalır.
    /// </summary>
    public string? ScopeGameId
    {
        get
        {
            lock (_gate)
            {
                if (_scope is null) return null;
                if (_scope.Id == GeneralPackId) return _scope.Id;
                return _scope.Id.StartsWith(GameIds.ImportedPackPrefix, StringComparison.Ordinal)
                    ? GameIds.ForPack(_scope.Id, _scope.Title)
                    : GameIds.Canonical(_scope.Id);
            }
        }
    }

    /// <summary>Kapsam paketinin başlığı; yoksa null. (Yapay zekâya oyun adı olarak gitmez.)</summary>
    public string? ScopeTitle
    {
        get { lock (_gate) return _scope?.Title; }
    }

    /// <summary>Ayırt edici isabeti (yalnız tek pakette bulunan son satırın paketi) okur ve siler.</summary>
    public GamePack? TakeDistinctiveHit()
    {
        lock (_gate)
        {
            var hit = _distinctive;
            _distinctive = null;
            return hit;
        }
    }

    /// <summary>
    /// Kullanıcının seçtiği oyun (null/boş: seçim yok). Değişince kapsam, ayırt edici isabet ve bulunan paket sıfırlanır.
    /// </summary>
    public void SelectGame(string? gameName)
    {
        var key = GameNames.Key(gameName);
        var normalized = key.Length == 0 ? null : key;
        lock (_gate)
        {
            if (normalized == _selectedKey) return;
            _selectedKey = normalized;
            _selectedPack = null;
            _scope = null;
            _distinctive = null;
            if (normalized is not null) _selectedPack = FindPackFor(normalized);
        }
    }

    /// <summary>Seçilen oyunun paketi (seçim yoksa ya da paketi yoksa null).</summary>
    public GamePack? SelectedPack
    {
        get { lock (_gate) return _selectedKey is null ? null : _selectedPack; }
    }

    /// <summary>Oyun adına uyan paket (sondan başa, genel paket hariç).</summary>
    public GamePack? PackForGame(string? gameName)
    {
        var key = GameNames.Key(gameName);
        if (key.Length == 0) return null;
        lock (_gate) return FindPackFor(key);
    }

    GamePack? FindPackFor(string key)
    {
        var packs = EnsureLoaded();
        // Anahtar ad anahtarıdır ("gta 6"); asıl kimlik de karşılaştırılır (takma adlı paket kimlikleri için).
        var game = GameIds.FromName(key);
        for (var i = packs.Count - 1; i >= 0; i--)
        {
            var p = packs[i];
            if (p.Id == GeneralPackId) continue;
            if (GameNames.Key(p.Title) == key || GameNames.Key(p.Id) == key) return p;
            if (game is not null && GameIds.ForPack(p.Id, p.Title) == game) return p;
        }
        return null;
    }

    /// <summary>
    /// Satırın tamamı herhangi bir pakette var mı (kapsamı ve ayırt edici isabeti değiştirmez); varsa Türkçesi.
    /// </summary>
    public string? FindAnyPack(string text)
    {
        var key = LineKey.ComputeValue(text);
        if (key is null) return null;
        lock (_gate)
        {
            EnsureLoaded();
            return _merged.TryGetValue(key.Value, out var turkish) ? turkish : null;
        }
    }

    /// <summary>Bir metnin tamamının tam araması (§2.3).</summary>
    public string? FindExact(string text)
    {
        var key = LineKey.ComputeValue(text);
        if (key is null) return null;
        lock (_gate) return FindExactLocked(key.Value);
    }

    string? FindExactLocked(ulong key)
    {
        var packs = EnsureLoaded();
        if (_selectedKey is not null)
        {
            if (_selectedPack is null) return null;
            var own = _selectedPack.OwnTurkish(key);
            if (own is null) return null;
            _scope = _selectedPack;
            _distinctive = _selectedPack;
            return own;
        }
        if (_merged.Count == 0 || !_merged.TryGetValue(key, out var turkish)) return null;
        GamePack? first = null;
        var holders = 0;
        var scopeHolds = false;
        foreach (var p in packs)
        {
            if (!p.ContainsKey(key)) continue;
            holders++;
            first ??= p;
            if (ReferenceEquals(p, _scope)) scopeHolds = true;
        }
        if (holders == 1)
        {
            _distinctive = first;
            _scope = first;
        }
        else if (holders > 1 && !scopeHolds) _scope = first;
        return turkish;
    }

    /// <summary>
    /// En yakını arar (§3): yalnız kapsam paketinde (ya da elle seçilen oyunun paketinde); önce tek düzeltme, sonra
    /// Bloom benzerliği.
    /// </summary>
    public string? FindNearest(string text)
    {
        lock (_gate)
        {
            EnsureLoaded();
            var pack = _selectedKey is not null ? _selectedPack : _scope;
            if (pack is null) return null;
            Func<ulong, string?> turkishOf = _selectedKey is not null
                ? pack.OwnTurkish
                : k => _merged.TryGetValue(k, out var t) ? t : null;

            if (SingleEdit(text, pack, turkishOf) is { } edited) return edited;
            if (pack.Fuzzy is null) return null;
            var key = pack.Fuzzy.Nearest(text, turkishOf);
            return key is { } k2 ? turkishOf(k2) : null;
        }
    }

    static string? SingleEdit(string text, GamePack pack, Func<ulong, string?> turkishOf)
    {
        var canon = LineKey.Canon(text);
        var runes = canon.EnumerateRunes().Select(r => r.ToString()).ToArray();
        if (runes.Length is < 6 or > 48) return null;
        var variants = new HashSet<string>(StringComparer.Ordinal);
        for (var i = 0; i < runes.Length; i++)
        {
            var head = string.Concat(runes.Take(i));
            var rest = string.Concat(runes.Skip(i));
            foreach (var (read, actual) in Confusions)
                if (rest.StartsWith(read, StringComparison.Ordinal))
                    variants.Add(head + actual + rest[read.Length..]);
            variants.Add(head + string.Concat(runes.Skip(i + 1)));
            if (i > 0 && runes[i] != " " && runes[i - 1] != " ") variants.Add(head + " " + rest);
        }
        variants.Remove(canon);
        string? found = null;
        foreach (var v in variants.OrderBy(v => v, StringComparer.Ordinal))
        {
            if (v.Length == 0 || v.StartsWith(' ') || v.EndsWith(' ') || v.Contains("  ", StringComparison.Ordinal))
                continue;
            if (!LineKey.TryParse(LineKey.HashCanon(v), out var key) || !pack.ContainsKey(key)) continue;
            var turkish = turkishOf(key);
            if (turkish is null) continue;
            if (found is null) found = turkish;
            else if (!string.Equals(found, turkish, StringComparison.Ordinal)) return null;
        }
        return found;
    }

    /// <summary>
    /// Okuma hattının "paket bakışı" (§2.4): tek satır, birden çok satır, cümle cümle; önce yalnız tam, sonra tam
    /// ya da en yakın arama.
    /// </summary>
    public string? Lookup(string text) =>
        PackLookup.Lookup(text, FindExact, FindNearest);

    List<GamePack> EnsureLoaded()
    {
        if (_packs is not null) return _packs;
        var packs = new List<GamePack>();
        void Add(GamePack pack)
        {
            packs.RemoveAll(p => p.Id == pack.Id);
            packs.Add(pack);
        }

        if (_userFolder is not null && Directory.Exists(_userFolder))
        {
            string[] files;
            try { files = Directory.GetFiles(_userFolder); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { files = []; }
            Array.Sort(files, StringComparer.Ordinal);
            foreach (var file in files)
            {
                if (!IsPackName(Path.GetFileName(file))) continue;
                try { Add(GamePackReader.Read(File.ReadAllBytes(file), file)); }
                catch (Exception e) when (e is PackFormatException or IOException or UnauthorizedAccessException) { }
            }
        }

        var merged = new Dictionary<ulong, string>();
        foreach (var p in packs)
            foreach (var (k, v) in p.Segments) merged[k] = v;
        foreach (var p in packs)
            foreach (var (k, v) in p.Entries) merged[k] = v;
        _merged = merged;
        _packs = packs;
        if (_selectedKey is not null) _selectedPack = FindPackFor(_selectedKey);
        return packs;
    }

    static bool IsPackName(string name) =>
        name.EndsWith(".json.gz", StringComparison.Ordinal)
            || name.EndsWith(".json", StringComparison.Ordinal);
}

/// <summary>Parçalı paket araması (§2.4) ve bozuk konuşmacı etiketi (§2.4.1).</summary>
public static class PackLookup
{
    /// <summary>
    /// Bakışın tamamı: önce yalnız <paramref name="exact"/>, bulunmazsa "önce tam, sonra en yakın". En yakın sonuçları
    /// bu bakış boyunca metne göre hatırlanır.
    /// </summary>
    public static string? Lookup(string text, Func<string, string?> exact, Func<string, string?> nearest)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) return null;
        if (Stage(trimmed, exact) is { } found) return found;
        var memo = new Dictionary<string, string?>(StringComparer.Ordinal);
        string? ExactOrNearest(string t)
        {
            if (exact(t) is { } e) return e;
            if (!memo.TryGetValue(t, out var n)) memo[t] = n = nearest(t);
            return n;
        }
        return Stage(trimmed, ExactOrNearest);
    }

    static string? Stage(string text, Func<string, string?> find)
    {
        if (SingleLine(text, find) is { } single) return single;

        var lines = text.Replace("\r\n", "\n").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
        if (lines.Count > 1)
        {
            var found = new List<string>();
            var failed = false;
            foreach (var line in lines)
            {
                if (SingleLine(line, find) is { } t) found.Add(t);
                else if (!IsCornerText(line))
                {
                    failed = true;
                    break;
                }
            }
            if (!failed && found.Count > 0) return string.Join("\n", found);
        }

        var pieces = SubtitleSplitter.Split(text);
        if (pieces.Count(p => p.Translatable) <= 1) return null;
        var sb = new System.Text.StringBuilder();
        foreach (var piece in pieces)
        {
            if (!piece.Translatable)
            {
                sb.Append(piece.Text);
                continue;
            }
            if (find(piece.Text) is not { } t) return null;
            sb.Append(t);
        }
        return sb.ToString();
    }

    static string? SingleLine(string line, Func<string, string?> find)
    {
        var pieces = SubtitleSplitter.Split(line);
        var lead = 0;
        while (lead < pieces.Count && !pieces[lead].Translatable) lead++;
        if (lead > 0 && lead < pieces.Count && pieces.All(p => p.Text != "\n"))
        {
            var body = SubtitleSplitter.Join(pieces.Skip(lead));
            if (find(body) is { } t) return SubtitleSplitter.Join(pieces.Take(lead)) + t;
        }
        if (find(line) is { } whole) return whole;
        if (LooseLabel(line) is { } loose && find(loose.Body) is { } bodyTurkish) return loose.Label + bodyTurkish;
        return null;
    }

    /// <summary>Köşe yazısı: 1–4 sözcük ve (<c>•</c> var ya da her sözcük büyük harfle başlayıp harf/rakam).</summary>
    public static bool IsCornerText(string line)
    {
        var words = line.Split((char[]?)null,
            StringSplitOptions.RemoveEmptyEntries);
        if (words.Length is < 1 or > 4) return false;
        return line.Contains('•') || words.All(w => char.IsUpper(w[0]) && w.All(char.IsLetterOrDigit));
    }

    /// <summary>OCR'ın bozduğu konuşmacı etiketi (<c>M]: </c>, <c>SEBASTIAN </c>); yoksa null.</summary>
    public static (string Label, string Body)? LooseLabel(string line)
    {
        var runes = LineKey.SafeRunes(line).ToArray();
        string Text(int from, int to) => string.Concat(runes[from..to].Select(r => r.ToString()));
        static bool NameLike(string word, int minLetters) =>
            word.Count(char.IsLetter) >= minLetters && !word.Any(char.IsLower);

        var limit = Math.Min(runes.Length, 33);
        for (var i = 1; i < limit; i++)
        {
            if (runes[i].Value is not (':' or '•')) continue;
            var before = Text(0, i).Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (before.Length == 0 || !NameLike(before[^1], 1)) continue;
            var j = i + 1;
            while (j < runes.Length && !Rune.IsLetterOrDigit(runes[j])) j++;
            var body = Text(j, runes.Length).Trim();
            if (!body.Any(char.IsLetter)) return null;
            return (Text(0, i + 1).Trim() + " ", body);
        }

        var at = 0;
        while (at < runes.Length && !Rune.IsLetter(runes[at])) at++;
        for (var n = 0; n < 3 && at < runes.Length; n++)
        {
            var end = at;
            while (end < runes.Length && runes[end].Value != ' ') end++;
            if (end >= runes.Length) break;
            var word = Text(at, end);
            if (!Rune.IsUpper(runes[at]) || !NameLike(word, 2)) break;
            at = end;
            while (at < runes.Length && runes[at].Value == ' ') at++;
            if (at + 1 < runes.Length && Rune.IsUpper(runes[at]) && Rune.IsLower(runes[at + 1]))
                return (Text(0, at).Trim() + " ", Text(at, runes.Length).Trim());
        }
        return null;
    }
}
