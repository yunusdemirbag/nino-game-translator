// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Nino.Core.Library;

namespace Nino.Core.Reading;

/// <summary>Çalışan oyun: PS5 kimliği (isteğe bağlı) ve adı (isteğe bağlı).</summary>
public sealed partial record RunningGame(string? Id, string? Name)
{
    [GeneratedRegex("^[A-Z]{4}[0-9]{5}(?:_[0-9]{2})?$", RegexOptions.CultureInvariant)]
    private static partial Regex IdPattern();

    /// <summary>Kimliği doğrular: kırpılıp büyük harfe çevrilir; 4 harf + 5 rakam (+ "_" + 2 rakam). Geçersizse null.</summary>
    public static string? ParseId(string? id)
    {
        var t = (id ?? "").Trim().ToUpperInvariant();
        return IdPattern().IsMatch(t) ? t : null;
    }

    /// <summary>Adı temizler: denetim/biçim karakterleri boşluk, boşluklar teke, en çok 120 karakter; boşsa null.</summary>
    public static string? CleanName(string? name)
    {
        if (name is null) return null;
        var sb = new StringBuilder(name.Length);
        foreach (var c in name)
            sb.Append(char.GetUnicodeCategory(c) is UnicodeCategory.Control or UnicodeCategory.Format ? ' ' : c);
        var t = string.Join(" ", TextKey.Words(sb.ToString()));
        if (t.Length > 120) t = t[..120];
        t = t.Trim();
        return t.Length == 0 ? null : t;
    }

    /// <summary>Kimlikle oyun (kimlik geçersizse null).</summary>
    public static RunningGame? WithId(string? id, string? name = null) =>
        ParseId(id) is { } valid ? new RunningGame(valid, CleanName(name)) : null;

    /// <summary>Adla oyun (ad yoksa null; kimlik geçerliyse o da tutulur).</summary>
    public static RunningGame? WithName(string? name, string? id = null) =>
        CleanName(name) is { } n ? new RunningGame(ParseId(id), n) : null;
}

/// <summary>Oyunun nereden bilindiği.</summary>
public enum GameSource
{
    /// <summary>PS5'in bildirdiği.</summary>
    Ps5,

    /// <summary>Kullanıcının seçtiği.</summary>
    User,

    /// <summary>Paketten tanınan.</summary>
    Pack,

    /// <summary>Ekrandan tanınan.</summary>
    Screen,
}

/// <summary>
/// Oyun duyusu: oyun dört yoldan bilinir; öncelik PS5 &gt; kullanıcı &gt; paket &gt; ekran. Kilitsizdir.
/// </summary>
public sealed class GameSense
{
    /// <summary>Genel ortak paketin kimliği (oyun değildir).</summary>
    public const string GeneralPoolPack = "pool-genel";

    /// <summary>Tutulan son paket kaydı.</summary>
    public const int RecentCount = 20;

    /// <summary>Paketten tanınmak için son kayıtlarda en az geçme sayısı.</summary>
    public const int VotesNeeded = 5;

    /// <summary>Oyun sorusu için en az çeviri süresi.</summary>
    public static TimeSpan AskAfter { get; } = TimeSpan.FromMinutes(2);

    readonly Queue<string?> _recent = new();
    readonly Dictionary<string, string> _names = new(StringComparer.Ordinal);
    string? _packGameId;

    /// <summary>PS5'in bildirdiği oyun.</summary>
    public RunningGame? Ps5 { get; private set; }

    /// <summary>Kullanıcının seçtiği oyun.</summary>
    public RunningGame? User { get; private set; }

    /// <summary>Paketten tanınan oyun.</summary>
    public RunningGame? Pack { get; private set; }

    /// <summary>Ekrandan tanınan oyun.</summary>
    public RunningGame? Screen { get; private set; }

    /// <summary>Bu oturumda soruldu mu.</summary>
    public bool Asked { get; private set; }

    /// <summary>Bilinen oyun (önceliğe göre).</summary>
    public RunningGame? Current => Ps5 ?? User ?? Pack ?? Screen;

    /// <summary>Bilinen oyunun kaynağı.</summary>
    public GameSource? Source => Ps5 is not null ? GameSource.Ps5 : User is not null ? GameSource.User
        : Pack is not null ? GameSource.Pack : Screen is not null ? GameSource.Screen : null;

    /// <summary>Paket araması sınırı: PS5 bir oyun bildirmiyorsa kullanıcının seçtiği oyunun adı; yoksa null.</summary>
    public string? PackSearchLimit => Ps5 is null ? User?.Name : null;

    /// <summary>"pool-&lt;kimlik&gt;" paket kimliğinden PS5 kimliği ("pool-cusa00419-00" → CUSA00419_00).</summary>
    public static string? IdFromPack(string packId) =>
        packId.StartsWith("pool-", StringComparison.Ordinal) ? RunningGame.ParseId(packId[5..].Replace('-', '_')) : null;

    /// <summary>
    /// Gösterilen bir satırın paket kaydı: satır yalnız tek bir pakete özgü anahtarla geldiyse o paket, değilse null.
    /// Bir paket son 20 kayıtta 5 kez geçerse oyun o olur; döner: yeni tanındı mı.
    /// </summary>
    public bool NotePackLine(string? packId, string? packName = null)
    {
        if (packId == GeneralPoolPack) packId = null;
        _recent.Enqueue(packId);
        while (_recent.Count > RecentCount) _recent.Dequeue();
        if (packId is null) return false;
        if (!string.IsNullOrWhiteSpace(packName)) _names[packId] = packName;
        if (packId == _packGameId || _recent.Count(r => r == packId) < VotesNeeded) return false;
        var game = RunningGame.WithName(_names.GetValueOrDefault(packId) ?? packId, IdFromPack(packId));
        if (game is null) return false;
        Pack = game;
        _packGameId = packId;
        return true;
    }

    /// <summary>
    /// PS5'in bildirdiği oyun (bırakınca null). PS5 bir ad bildiriyor ve kullanıcının seçtiğiyle anahtarı farklıysa
    /// kullanıcının seçimi silinir.
    /// </summary>
    public void SetPs5(RunningGame? game)
    {
        Ps5 = game;
        if (game?.Name is { } n && User?.Name is { } u && !GameIds.Same(n, u)) User = null;
    }

    /// <summary>Kullanıcının seçimi (boşsa silinir); "soruldu" işaretlenir.</summary>
    public void SetUser(string? name)
    {
        User = RunningGame.WithName(name);
        Asked = true;
    }

    /// <summary>Ekrandan tanınan oyun (boşsa silinir).</summary>
    public void SetScreen(string? name) => Screen = RunningGame.WithName(name);

    /// <summary>Soru kartı gösterildi ya da "Sorma"ya basıldı.</summary>
    public void MarkAsked() => Asked = true;

    /// <summary>Yeni oturum: son kayıtlar, paket oyunu, PS5 oyunu silinir; kullanıcının seçimi ve ekrandan tanınan kalır.</summary>
    public void NewSession()
    {
        _recent.Clear();
        Pack = null;
        _packGameId = null;
        Ps5 = null;
        Asked = false;
    }

    /// <summary>Soru kartı gösterilmeli mi.</summary>
    public bool ShouldAsk(bool settingOn, TimeSpan translatingFor) =>
        settingOn && !Asked && Current is null && translatingFor >= AskAfter;
}

/// <summary>
/// Ekrandan tanıma zamanlaması (sunucuya kare sorma). Oyun bilinmiyorsa 8 sn'den sonra ilk deneme, sonra her 60 sn'den
/// sonra, en çok 6; ekrandan tanındıysa 5 dk'dan sonra, sonra her 20 dk'dan sonra, en çok 12. Aynı anda tek istek.
/// Karşılaştırmalar kesin büyüktür.
/// </summary>
public sealed class ScreenCheckSchedule
{
    DateTimeOffset _start;
    DateTimeOffset? _last;
    int _attempts;
    bool _running;

    /// <summary>Çeviri başladı ya da sıfırlandı.</summary>
    public void Restart(DateTimeOffset now)
    {
        _start = now;
        _last = null;
        _attempts = 0;
        _running = false;
    }

    /// <summary>Şimdi sorulmalı mı.</summary>
    public bool ShouldCheck(DateTimeOffset now, GameSource? source)
    {
        if (_running) return false;
        if (source is GameSource.Ps5 or GameSource.User or GameSource.Pack) return false;
        var verifying = source == GameSource.Screen;
        var (first, every, max) = verifying
            ? (TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(20), 12)
            : (TimeSpan.FromSeconds(8), TimeSpan.FromSeconds(60), 6);
        if (_attempts >= max) return false;
        return _last is { } last ? now - last > every : now - _start > first;
    }

    /// <summary>İstek başladı.</summary>
    public void Begin(DateTimeOffset now)
    {
        _running = true;
        _last = now;
        _attempts++;
    }

    /// <summary>İstek bitti (sonuç ne olursa olsun).</summary>
    public void Finish() => _running = false;
}

/// <summary>Ekrandaki işaretlerden GTA 6 (yalnız GTA 6'da görülen yazılar).</summary>
public static class Gta6Markers
{
    /// <summary>GTA 6'nın anahtarı "Grand Theft Auto VI" ile aynı olan adı.</summary>
    public const string Name = "GTA 6";

    /// <summary>
    /// Okumada GTA 6 işareti var mı. <paramref name="isMapScreen"/> (harita ekranı; telefon/harita tarafı) ve
    /// <paramref name="cleanMenu"/> (harita menüsü kırıntılarının temizliği) verilmezse o adımlar atlanır.
    /// </summary>
    public static bool Detect(IReadOnlyList<string> lines, Func<IReadOnlyList<string>, bool>? isMapScreen = null,
        Func<string, string>? cleanMenu = null)
    {
        if (isMapScreen?.Invoke(lines) == true) return true;
        var keys = lines.Select(l => TextKey.Of(cleanMenu is null ? l : cleanMenu(l))).ToArray();
        if (keys.Any(k => k.Contains("jason", StringComparison.Ordinal) && k.Contains("lucia", StringComparison.Ordinal)))
            return true;
        var words = keys.SelectMany(k => k.Split(' ')).ToHashSet(StringComparer.Ordinal);
        if (keys.Contains("brief") && keys.Contains("progress")
            && (words.Contains("jason") || words.Contains("lucia") || keys.Contains("map"))) return true;
        return keys.Contains("whatup");
    }
}

/// <summary>Oyun seçme kartının önerileri.</summary>
public static class GamePicker
{
    /// <summary>Popüler oyunlar (bütün platformlarda aynı liste ve sıra).</summary>
    public static IReadOnlyList<string> Popular { get; } = """
        GTA 6
        GTA 5
        Red Dead Redemption 2
        Ghost of Yōtei
        Marvel's Spider-Man 2
        Death Stranding 2: On the Beach
        Elden Ring
        Elden Ring Nightreign
        Assassin's Creed Shadows
        Call of Duty: Black Ops 7
        Call of Duty: Black Ops 6
        Battlefield 6
        EA Sports FC 26
        Mafia: The Old Country
        The Last of Us Part II Remastered
        God of War Ragnarök
        Cyberpunk 2077
        Hogwarts Legacy
        Resident Evil Requiem
        Silent Hill f
        Metal Gear Solid Delta: Snake Eater
        Borderlands 4
        Kingdom Come: Deliverance II
        Clair Obscur: Expedition 33
        Final Fantasy VII Rebirth
        Stellar Blade
        Black Myth: Wukong
        Baldur's Gate 3
        Horizon Forbidden West
        Alan Wake 2
        Indiana Jones and the Great Circle
        Dying Light: The Beast
        Ghost of Tsushima
        Star Wars Outlaws
        The Witcher 3: Wild Hunt
        Monster Hunter Wilds
        Split Fiction
        Hollow Knight: Silksong
        """.Split('\n').Select(s => s.Trim()).Where(s => s.Length > 0).ToArray();

    /// <summary>Kısa adın uzun adı ("GTA 6" → "Grand Theft Auto VI").</summary>
    public static string LongName(string name) => name switch
    {
        "GTA 6" => "Grand Theft Auto VI",
        "GTA 5" => "Grand Theft Auto V",
        _ => name,
    };

    /// <summary>En çok 8 öneri: son oynanan, paket oyunları (genel ortak paket hariç), popüler oyunlar.</summary>
    /// <param name="query">Arama.</param>
    /// <param name="packGames">Paketlerin oyunları (kimlik, ad).</param>
    /// <param name="lastPlayed">Son oynanan oyunun adı.</param>
    public static IReadOnlyList<string> Suggestions(string? query, IEnumerable<(string Id, string Title)> packGames,
        string? lastPlayed)
    {
        // Aynı oyun bir kez: ad anahtarı ya da asıl kimlik daha önce geçtiyse atlanır ("GTA 6" = "gtavi" = "Grand Theft Auto VI").
        HashSet<string> seen = new(StringComparer.Ordinal);
        HashSet<string> seenIds = new(StringComparer.Ordinal);
        var all = new List<(string Name, string Key)>();
        void Add(string? name)
        {
            if (string.IsNullOrWhiteSpace(name)) return;
            var key = GameNames.Key(name);
            if (key.Length == 0 || seen.Contains(key)) return;
            var id = GameIds.FromName(name);
            if (id is not null && seenIds.Contains(id)) return;
            seen.Add(key);
            if (id is not null) seenIds.Add(id);
            all.Add((name, key));
        }
        Add(lastPlayed);
        foreach (var (id, title) in packGames)
            if (id != GameSense.GeneralPoolPack) Add(title);
        foreach (var p in Popular) Add(p);
        var q = GameNames.Key(query);
        if (q.Length == 0) return all.Take(8).Select(a => a.Name).ToArray();
        var plain = (query ?? "").Trim().ToLowerInvariant();
        var matches = all.Where(a => a.Key.Contains(q, StringComparison.Ordinal)
            || LongName(a.Name).ToLowerInvariant().Contains(plain, StringComparison.Ordinal)).ToArray();
        return matches.Where(a => a.Key.StartsWith(q, StringComparison.Ordinal))
            .Concat(matches.Where(a => !a.Key.StartsWith(q, StringComparison.Ordinal)))
            .Take(8).Select(a => a.Name).ToArray();
    }
}
