// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core.Library;

/// <summary>
/// Sunucunun tek oyun kimliği ("asıl kimlik"). Aynı oyun farklı yazılışlarla gelebilir (tam addan üretilen
/// <c>grand-theft-auto-vi</c>, ekrandan okunan <c>gtavi</c>, havuz paketi <c>pool-gta-6</c>…); sunucuya her zaman asıl
/// kimlik gider (<c>gta-6</c>, <c>gta-v</c>…). Tablolar sunucunun takma ad ve okunur ad tablolarıyla aynıdır.
/// </summary>
public static class GameIds
{
    /// <summary>Takma ad → asıl kimlik (sunucunun tablosu, aynen).</summary>
    public static IReadOnlyDictionary<string, string> Aliases { get; } = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        // GTA 6
        ["grand-theft-auto-vi"] = "gta-6",
        ["gta-vi"] = "gta-6",
        ["gta6"] = "gta-6",
        ["gtavi"] = "gta-6",
        ["pool-gta-6"] = "gta-6",
        // GTA 5
        ["grand-theft-auto-v"] = "gta-v",
        ["gta-5"] = "gta-v",
        ["gta5"] = "gta-v",
        ["gtav"] = "gta-v",
        ["pool-gta-5"] = "gta-v",
        ["pool-gta-v"] = "gta-v",
        // Kesme işareti tireye dönmüş yazılışlar, uzun adlar
        ["assassin-s-creed-shadows"] = "assassins-creed-shadows",
        ["marvel-s-spider-man-2"] = "marvels-spider-man-2",
        ["death-stranding-director-s-cut"] = "death-stranding-directors-cut",
        ["death-stranding-2-on-the-beach"] = "death-stranding-2",
        ["farcry6"] = "far-cry-6",
        ["ghost-of-y-tei"] = "ghost-of-yotei",
    };

    /// <summary>Asıl kimlik → okunur ad (sunucunun tablosu, aynen).</summary>
    public static IReadOnlyDictionary<string, string> Names { get; } = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["gta-6"] = "GTA 6",
        ["gta-v"] = "GTA 5",
        ["grand-theft-auto-iv"] = "GTA 4",
        ["gta-iv"] = "GTA 4",
        ["grand-theft-auto-online"] = "GTA Online",
        ["red-dead-redemption-2"] = "Red Dead Redemption 2",
        ["call-of-duty-modern-warfare-2019"] = "Call of Duty: Modern Warfare (2019)",
        ["assassins-creed-shadows"] = "Assassin's Creed Shadows",
        ["assassin-s-creed-mirage"] = "Assassin's Creed Mirage",
        ["mafia-the-old-country"] = "Mafia: The Old Country",
        ["death-stranding-2"] = "Death Stranding 2",
        ["death-stranding-directors-cut"] = "Death Stranding Director's Cut",
        ["elden-ring"] = "Elden Ring",
        ["elden-ring-shadow-of-the-erdtree"] = "Elden Ring: Shadow of the Erdtree",
        ["marvels-spider-man-2"] = "Marvel's Spider-Man 2",
        ["kingdom-come-deliverance-ii"] = "Kingdom Come: Deliverance II",
        ["the-last-of-us-part-ii"] = "The Last of Us Part II",
        ["the-last-of-us-part-ii-remastered"] = "The Last of Us Part II Remastered",
        ["wuchang-fallen-feathers"] = "Wuchang: Fallen Feathers",
        ["far-cry-6"] = "Far Cry 6",
        ["ghost-of-yotei"] = "Ghost of Yōtei",
        ["astro-s-playroom"] = "Astro's Playroom",
        ["final-fantasy.vii-remake"] = "Final Fantasy VII Remake",
        ["ea-sports-fc-26"] = "EA Sports FC 26",
        ["ea-sports-fc-27"] = "EA Sports FC 27",
        ["nba-2k26"] = "NBA 2K26",
        ["007-first-light"] = "007 First Light",
    };

    /// <summary>Kullanıcının elle eklediği paketlerin kimlik öneki (havuz/paket tarifi §5.2).</summary>
    public const string ImportedPackPrefix = "community-";

    // Okunur ad üretiminde büyük yazılan Romen rakamları (yalnız i–x; sunucudaki kural).
    static readonly HashSet<string> Roman = new(StringComparer.Ordinal)
        { "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x" };

    /// <summary>
    /// Kimliği asıl kimliğe çevirir: küçük harf, art arda tireler teke, sonra takma ad tablosu. Takma ad değilse sadeleşmiş
    /// hâli döner; null ya da boşsa olduğu gibi.
    /// </summary>
    public static string? Canonical(string? id)
    {
        if (string.IsNullOrEmpty(id)) return id;
        var lower = id.ToLowerInvariant();
        var sb = new StringBuilder(lower.Length);
        foreach (var c in lower)
        {
            if (c == '-' && sb.Length > 0 && sb[^1] == '-') continue;
            sb.Append(c);
        }
        var clean = sb.ToString();
        return Aliases.TryGetValue(clean, out var target) ? target : clean;
    }

    /// <summary>
    /// Oyun adından ya da kimliğinden sunucuya giden asıl kimlik (<c>Grand Theft Auto VI</c> → <c>gta-6</c>,
    /// <c>GTA 5</c> → <c>gta-v</c>); ad boşsa ya da kimlik üretilemiyorsa null.
    /// </summary>
    public static string? FromName(string? name) => GameNames.Slug(name) is { } slug ? Canonical(slug) : null;

    /// <summary>Asıl kimlik tabloda (takma adların hedefi ya da okunur adı olan) bilinen bir oyun mu.</summary>
    public static bool IsKnown(string? canonical) =>
        canonical is { Length: > 0 } && (Names.ContainsKey(canonical) || Aliases.Values.Contains(canonical));

    /// <summary>
    /// Okunur ad: tablodaki ad; yoksa kimlik <c>- _ .</c> yerlerinden bölünüp her sözcüğün ilk harfi büyük yazılır
    /// (i–x Romen rakamları tümüyle büyük). Boşsa "".
    /// </summary>
    public static string DisplayName(string? id)
    {
        var game = Canonical(id);
        if (string.IsNullOrEmpty(game)) return "";
        if (Names.TryGetValue(game, out var name)) return name;
        var words = game.Split(['-', '_', '.'], StringSplitOptions.RemoveEmptyEntries)
            .Select(w => Roman.Contains(w) ? w.ToUpperInvariant() : char.ToUpperInvariant(w[0]) + w[1..]);
        return string.Join(' ', words);
    }

    /// <summary>
    /// Gösterilecek ad: adın asıl kimliği tabloda bir okunur ada sahipse o ad ("Grand Theft Auto VI" → "GTA 6"),
    /// kimlik biçiminde gelmiş bir adsa üretilen okunur ad, değilse ad olduğu gibi.
    /// </summary>
    public static string? ReadableName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return name;
        var id = FromName(name);
        if (id is not null && Names.TryGetValue(id, out var known)) return known;
        var trimmed = name.Trim();
        return IsIdLike(trimmed) && id is not null ? DisplayName(id) : name;
    }

    // Kimlik biçimi: boşluksuz, küçük harf ASCII harf/rakam ve - _ .
    static bool IsIdLike(string text) =>
        text.Length > 0 && text.All(c => char.IsAsciiLetterLower(c) || char.IsAsciiDigit(c) || c is '-' or '_' or '.');

    /// <summary>
    /// İki ad/kimlik aynı oyun mu: oyun adı anahtarları (<see cref="GameNames.Key"/>) ya da asıl kimlikleri eşitse.
    /// Boş olanlar hiçbir şeyle aynı değildir.
    /// </summary>
    public static bool Same(string? a, string? b)
    {
        if (string.IsNullOrWhiteSpace(a) || string.IsNullOrWhiteSpace(b)) return false;
        var ka = GameNames.Key(a);
        if (ka.Length > 0 && ka == GameNames.Key(b)) return true;
        return FromName(a) is { } ia && ia == FromName(b);
    }

    /// <summary>
    /// Paketin oyunu (asıl kimlik): önce paket kimliği (içe aktarma öneki atılarak) tabloda biliniyorsa o; yoksa başlıktan
    /// üretilen asıl kimlik; o da yoksa kimliğin kendisi. Kimlik ve dosya adı değişmez; yalnız karşılaştırma ve gönderim
    /// içindir.
    /// </summary>
    public static string? ForPack(string? packId, string? title)
    {
        var bare = packId is not null && packId.StartsWith(ImportedPackPrefix, StringComparison.Ordinal)
            ? packId[ImportedPackPrefix.Length..]
            : packId;
        var fromId = FromName(bare);
        if (IsKnown(fromId)) return fromId;
        return FromName(title) ?? fromId;
    }

    /// <summary>
    /// Aynı oyunun paketlerini tek satıra indirir (Ayarlar, oyun seçici): sıra ilk geçişe göre; ad tablodaki okunur ad ya da
    /// ilk paketin başlığı; satır sayısı en büyüğü (paketler büyük ölçüde aynı satırları taşır). Genel paket kendi başına
    /// kalır.
    /// </summary>
    public static IReadOnlyList<PackInfo> DistinctPacks(IEnumerable<PackInfo> packs)
    {
        var rows = new List<PackInfo>();
        var index = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var p in packs)
        {
            var game = p.Id == PackLibrary.GeneralPackId ? p.Id : ForPack(p.Id, p.Title) ?? p.Id;
            var title = Names.TryGetValue(game, out var known) ? known : p.Title;
            if (index.TryGetValue(game, out var at))
            {
                var prev = rows[at];
                rows[at] = prev with { EntryCount = Math.Max(prev.EntryCount, p.EntryCount) };
                continue;
            }
            index[game] = rows.Count;
            rows.Add(p with { Title = title });
        }
        return rows;
    }
}
