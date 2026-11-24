// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.RegularExpressions;
using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// GTA 6'nın telefon ve harita dışındaki köşe öğelerinin kuralları (Android <c>GameCards</c> / <c>GameCorners</c> ile
/// aynı eşik ve kutular): sağ alttaki mesaj/uygulama bildirimi/arama kartı, sol üst ipucu kutusu, sağ üst kısa bildirim.
/// Bütün kutular kareye göre (0–1).
/// </summary>
static partial class GameWords
{
    /// <summary>Tuş simgesi okumaları.</summary>
    public static readonly HashSet<string> Buttons = new(StringComparer.Ordinal)
    {
        "L1", "L2", "L3", "R1", "R2", "R3", "TOUCHPAD", "OPTIONS",
        "✕", "×", "⨯", "✖", "○", "◯", "●", "□", "▢", "◻", "■", "△", "▲", "⨂",
        "&", "®", "©", "@", "⊗", "Ⓧ", "ⓧ", "L", "R", "LZ", "RZ", "LI", "RI", "L7", "R7", "*",
        "↑", "↓", "←", "→", "✜", "▦", "◆",
    };

    /// <summary>Çeviriden atılan simgeler.</summary>
    public static readonly HashSet<string> Icons = new(Buttons.Except(["L", "R", "&", "@", "*", "LI", "RI"]),
        StringComparer.Ordinal);

    public static string[] Words(string? t) => TextKey.Words(t);

    public static string[] KeyWords(string? t) => TextKey.Of(t).Split(' ', StringSplitOptions.RemoveEmptyEntries);

    public static bool HasLower(string? t) => (t ?? "").Any(char.IsLower);

    public static int Letters(string? t) => (t ?? "").Count(char.IsLetter);

    public static string Squeeze(string? t) => string.Join(" ", Words(t));

    public static string WithoutIcons(string? t) => string.Join(" ", Words(t).Where(w => !Icons.Contains(w)));

    /// <summary>Anahtarların benzerliği (biri boşsa 0).</summary>
    public static double Ratio(string a, string b)
    {
        var x = TextKey.Of(a);
        var y = TextKey.Of(b);
        return x.Length == 0 || y.Length == 0 ? 0 : TextKey.Ratio(x, y);
    }

    public static double? Median(IEnumerable<double> values)
    {
        var s = values.OrderBy(v => v).ToArray();
        if (s.Length == 0) return null;
        return s.Length % 2 == 1 ? s[s.Length / 2] : (s[s.Length / 2 - 1] + s[s.Length / 2]) / 2;
    }

    /// <summary>Kutuya sığan satır sayısı (harf genişliği boy × çarpan × 9/16, satırda en az 12 harf).</summary>
    public static int LineCount(string text, double width, double lineHeight, double letterFactor = 0.5)
    {
        var perLine = Math.Max(12, (int)(width / Math.Max(1e-6, lineHeight * letterFactor * 9 / 16)));
        return Math.Max(1, (int)Math.Ceiling((double)text.Length / perLine));
    }

    public static Box? Union(IEnumerable<Box> boxes)
    {
        Box? u = null;
        foreach (var b in boxes) u = u is { } x ? x.Union(b) : b;
        return u;
    }

    /// <summary>Satır kutunun içinde mi (0,02 payla).</summary>
    public static bool Inside(Box b, Box p) =>
        b.Left >= p.Left - 0.02 && b.Right <= p.Right + 0.02 && b.Top >= p.Top - 0.02 && b.Bottom <= p.Bottom + 0.02;

    /// <summary>Hedef dilin (Türkçe) harflerini taşıyor mu: oyun yazısı zaten çevrilmiş.</summary>
    public static bool HasTurkishLetters(string? text) => (text ?? "").Any("ğışĞİŞ".Contains);

    /// <summary>Koyu buzlu köşe kutusu.</summary>
    public static ScreenItem DarkFrost(string source, Box box, string text, double line) =>
        new(source, text, box, line) { Fill = "#1c1c24", Ink = "#f2f2f5", Alpha = 0.62, Side = true };

    /// <summary>Açık buzlu kutu (mesaj kartı).</summary>
    public static ScreenItem LightFrost(string source, Box box, string text, double line) =>
        new(source, text, box, line) { Fill = "#eef0f5", Ink = "#1c1c1e", Alpha = 0.72, Side = true };

    /// <summary>Aynı yazı ve en çok <paramref name="tol"/> oynayan kutu: TV'ye yeniden gönderilmesin diye eski öğe kalır.</summary>
    public static bool Near(ScreenItem e, ScreenItem? o, double tol = 0.02) =>
        o is not null && o.Text == e.Text && o.Italic == e.Italic
        && Math.Abs(o.Box.Left - e.Box.Left) < tol && Math.Abs(o.Box.Top - e.Box.Top) < tol
        && Math.Abs(o.Box.Right - e.Box.Right) < tol && Math.Abs(o.Box.Bottom - e.Box.Bottom) < tol;

    public static readonly Regex BoxWordSplit = BoxWordSplitRegex();

    [GeneratedRegex("[^\\p{L}'’]+")]
    private static partial Regex BoxWordSplitRegex();
}

/// <summary>
/// Sağ alttaki mesaj ve arama kartı. Kişi mesajı (<c>Donnie</c> / gövde), uygulama bildirimi (<c>BuckMe</c> / gövde;
/// ad çevrilmez) ve arama (<c>Harbor Cabs</c> / <c>Calling...</c>, <c>Kirk</c> / <c>00:05</c>, tek satır
/// <c>Kirk 00:05</c>).
/// </summary>
static partial class GameCards
{
    /// <summary>Kartın arandığı köşe.</summary>
    public const double CornerLeft = 0.66, CornerTop = 0.74;

    public sealed record Card(string Name, string Body, Box? Box, double? FirstBodyHeight);

    public enum CallState { Calling, Incoming, Ended, Talking }

    public sealed record Call(string Name, CallState State, Box? Box, double? FirstLineHeight);

    /// <summary>Durumun Türkçesi (konuşma sürüyorsa boş).</summary>
    public static string Turkish(CallState s) => s switch
    {
        CallState.Calling => "aranıyor…",
        CallState.Incoming => "seni arıyor…",
        CallState.Ended => "arama bitti",
        _ => "",
    };

    /// <summary>Durumun İngilizcesi (başka hedef dilde bir kez çevrilir).</summary>
    public static string English(CallState s) => s switch
    {
        CallState.Calling => "Calling…",
        CallState.Incoming => "Incoming call",
        CallState.Ended => "Call ended",
        _ => "",
    };

    const string NameBanned = ".,!?:;…\"";
    static readonly Regex Clock = ClockRegex();
    static readonly Regex OneLineCall = OneLineCallRegex();
    static readonly Regex TickingClock = TickingClockRegex();

    static readonly Dictionary<string, CallState> Status = new(StringComparer.Ordinal)
    {
        ["calling"] = CallState.Calling, ["dialing"] = CallState.Calling, ["dialling"] = CallState.Calling,
        ["connecting"] = CallState.Calling, ["ringing"] = CallState.Calling,
        ["incoming call"] = CallState.Incoming, ["incoming"] = CallState.Incoming,
        ["call ended"] = CallState.Ended, ["ended"] = CallState.Ended, ["call failed"] = CallState.Ended,
        ["busy"] = CallState.Ended, ["no answer"] = CallState.Ended, ["unavailable"] = CallState.Ended,
    };

    /// <summary>Gönderen adı mı? 1–4 sözcük, her biri büyük harfle (ya da <c>&amp;</c>) başlar ve en çok bir büyük harf taşır.</summary>
    public static bool IsName(string s)
    {
        var t = s.Trim();
        var w = GameWords.Words(t);
        if (t.Length is < 2 or > 30 || w.Length is < 1 or > 4) return false;
        if (!w.All(x => (char.IsUpper(x[0]) || x[0] == '&') && x.Count(char.IsUpper) <= 1)) return false;
        return GameWords.HasLower(t) && !t.Any(NameBanned.Contains);
    }

    /// <summary>Uygulama bildirimi adı (<c>BuckMe</c>): tek sözcük, harf, büyük harfle başlar, içinde en çok 2 büyük harf daha.</summary>
    public static bool IsAppName(string s)
    {
        var t = s.Trim();
        if (t.Length is < 4 or > 16 || !t.All(char.IsLetter) || !char.IsUpper(t[0])) return false;
        var rest = t[1..];
        if (!rest.Any(char.IsUpper) || !t.Any(char.IsLower)) return false;
        return rest.Count(char.IsUpper) <= 2;
    }

    /// <summary>Saat satırı (arama sayacı): <c>00:05</c> ya da <c>Kirk 00:05</c>.</summary>
    public static bool IsClockLine(string text) => TickingClock.IsMatch(text.Trim());

    /// <summary>İlk satırdan harfsiz parçalar (okundu tikleri) ve sondaki alıcı satırı atılır.</summary>
    public static List<OcrLine> Tidy(IReadOnlyList<OcrLine> lines)
    {
        var ls = lines.ToList();
        if (ls.Count > 0)
            ls[0] = ls[0] with { Text = string.Join(" ", GameWords.Words(ls[0].Text).SkipWhile(w => !w.Any(char.IsLetter))) };
        if (ls.Count >= 3)
        {
            var last = ls[^1];
            var w = GameWords.Words(last.Text).Where(x => x.Any(char.IsLetter)).ToArray();
            var arrow = last.Text.Contains('→') || last.Text.Contains("->", StringComparison.Ordinal);
            if (w.Length is >= 1 and <= 3 && w.All(x => char.IsUpper(x[0])) && (arrow || GameWords.Words(last.Text).Length == 1))
                ls.RemoveAt(ls.Count - 1);
        }
        return ls;
    }

    public static bool IsList(IReadOnlyList<OcrLine> lines)
    {
        if (lines.Count < 3) return false;
        var names = lines.Count(l => IsName(l.Text));
        var dots = lines.Count(l => l.Text.EndsWith("...", StringComparison.Ordinal) || l.Text.EndsWith('…'));
        return names >= 2 || dots >= 2;
    }

    /// <summary>Sağ alt köşedeki satırlar (yukarıdan aşağı). Harfsiz satırlar atılır; saat satırı kalır (arama sayacı).</summary>
    public static List<OcrLine> CornerLines(IEnumerable<OcrLine> lines) => lines
        .Where(l => l.Box is { } b && b.Left >= CornerLeft && b.Top >= CornerTop)
        .Where(l => GameWords.Letters(l.Text) >= 2 || IsClockLine(l.Text))
        .OrderBy(l => l.Box!.Value.Top).ThenBy(l => l.Box!.Value.Left)
        .ToList();

    /// <summary>Mesaj kartı; kart değilse null.</summary>
    public static Card? FindCard(IReadOnlyList<OcrLine> raw)
    {
        var lines = Tidy(raw.Where(l => GameWords.Letters(l.Text) >= 2).ToList());
        if (IsList(lines) || lines.Count < 2 || !(IsName(lines[0].Text) || IsAppName(lines[0].Text))) return null;
        var body = string.Join(" ", lines.Skip(1).Select(l => l.Text));
        var nb = lines[0].Box;
        var bb = lines[1].Box;
        if (nb is { } n && bb is { } b1 && n.Bottom > b1.Top + 0.01) return null;
        if (GameWords.Words(body).Length >= 3)
        {
            if (!GameWords.HasLower(body)) return null;
        }
        else if (!body.Any(char.IsLetter) || nb is not { } n2 || bb is not { } b2 || n2.Left < 0.55 || b2.Left < 0.55) return null;
        var box = GameWords.Union(lines.Where(l => l.Box is not null).Select(l => l.Box!.Value));
        return new Card(lines[0].Text, body, box, bb?.Height);
    }

    /// <summary>Arama kartı; değilse null. Tek satır <c>Kirk 00:05</c> da konuşma sayılır.</summary>
    public static Call? FindCall(IReadOnlyList<OcrLine> raw)
    {
        var lines = Tidy(raw);
        var box = GameWords.Union(lines.Where(l => l.Box is not null).Select(l => l.Box!.Value));
        if (lines.Count == 1)
        {
            var m = OneLineCall.Match(lines[0].Text.Trim());
            if (!m.Success) return null;
            var name = m.Groups[1].Value.Trim();
            return IsName(name) ? new Call(name, CallState.Talking, box, lines[0].Box?.Height) : null;
        }
        if (lines.Count != 2 || !IsName(lines[0].Text)) return null;
        var second = lines[1].Text.Trim().TrimEnd('.', '…', ' ');
        CallState state;
        if (Status.TryGetValue(second.ToLowerInvariant(), out var s)) state = s;
        else if (Clock.IsMatch(second)) state = CallState.Talking;
        else return null;
        return new Call(lines[0].Text.Trim(), state, box, lines[0].Box?.Height);
    }

    /// <summary>Kartın üstündeki açık buzlu kart: "Ad: çeviri".</summary>
    public static ScreenItem? Layout(Card card, string translation)
    {
        if (card.Box is not { } b) return null;
        var lh = Math.Min(card.FirstBodyHeight ?? 0.03, 0.032) * 0.85;
        var text = $"{card.Name}: {translation}";
        var left = b.Left - 0.012;
        var right = Math.Min(0.995, Math.Max(b.Right + 0.012, left + 0.18));
        var rows = GameWords.LineCount(text, right - left, lh);
        var height = lh * rows * 1.25 + 0.02;
        var top = Math.Max(0.0, b.Top - 0.018 - height - 0.012);
        return GameWords.LightFrost($"{card.Name}: {card.Body}", new Box(left, top, right, top + height), text, lh);
    }

    /// <summary>Arama yazısı ("Kirk aranıyor…"): kartın üstünde, eğik. Konuşma sürüyorsa (<paramref name="status"/> boş) yok.</summary>
    public static ScreenItem? Layout(Call call, string status)
    {
        if (call.Box is not { } b || string.IsNullOrWhiteSpace(status)) return null;
        var lh = Math.Min(call.FirstLineHeight ?? 0.03, 0.032) * 0.8;
        var height = lh * 1.3;
        var top = b.Top - height - 0.035;
        var right = Math.Max(b.Right, b.Left + 0.2);
        return new ScreenItem(call.Name, $"{call.Name} {status}", new Box(b.Left, top, right, top + height), lh) { Italic = true };
    }

    [GeneratedRegex("^\\d{1,2}:\\d{2}$")]
    private static partial Regex ClockRegex();

    [GeneratedRegex("^(.{2,30}?)\\s+(\\d{1,2}:\\d{2})$")]
    private static partial Regex OneLineCallRegex();

    [GeneratedRegex("^(\\S+\\s+)?\\d{1,2}:\\d{2}$")]
    private static partial Regex TickingClockRegex();
}

/// <summary>
/// Sağ üstteki kısa oyun bildirimi (<c>Map updated</c>): x ≥ 0,70, y 0,12–0,45 içinde küçük harfli, 2–8 sözcüklü tek
/// satır. Baştaki/sondaki simge kırıntıları atılır; para ve rakamlı satırlar ile harita tuşları sayılmaz.
/// </summary>
static class TopRightNotice
{
    static readonly HashSet<string> MapButtons = new(StringComparer.Ordinal)
    {
        "recenter", "2d view", "3d view", "add marker", "remove marker", "set destination",
        "remove destination", "close menu", "view on map", "markers", "cinematic",
    };

    static int RealWords(IEnumerable<string> words) => words.Count(w => w.Count(char.IsLetter) >= 2);

    public static OcrLine? Find(IEnumerable<OcrLine> lines)
    {
        OcrLine? best = null;
        foreach (var l in lines)
        {
            if (l.Box is not { } b) continue;
            if (b.Left < 0.70 || b.Top < 0.12 || b.Bottom > 0.45) continue;
            var words = GameWords.Words(l.Text).ToList();
            var lead = 0;
            while (words.Count > 1 && (words[0].Length <= 1 || !words[0].Any(char.IsLetter)))
            {
                lead += words[0].Length + 1;
                words.RemoveAt(0);
            }
            while (words.Count > 1 && (words[^1].Length <= 1 || !words[^1].Any(char.IsLetter))) words.RemoveAt(words.Count - 1);
            var text = string.Join(" ", words);
            var real = RealWords(words);
            if (real is < 2 or > 8 || !GameWords.HasLower(text)) continue;
            if (text.Any(c => char.IsDigit(c) || c == '$') || IsMapButton(text)) continue;
            var left = b.Left + b.Width * lead / Math.Max(1, l.Text.Length);
            var found = new OcrLine(text, b with { Left = left });
            if (best is null || b.Top < best.Box!.Value.Top) best = found;
        }
        return best;
    }

    /// <summary>Öğe: koyu buzlu kutu, yazının üstünde; sağ kenarı sabit, sola doğru uzar.</summary>
    public static ScreenItem Element(OcrLine notice, string translation)
    {
        var b = notice.Box!.Value;
        var lh = Math.Min(Math.Max(b.Height, 0.026), 0.04) * 0.9;
        var clean = GameWords.WithoutIcons(translation);
        var right = Math.Min(0.995, b.Right + 0.006);
        var width = Math.Min(0.45, Math.Max(b.Width + 0.012, clean.Length * lh * 0.5 * 9 / 16 + 0.02));
        return GameWords.DarkFrost(notice.Text, new Box(Math.Max(0.0, right - width), b.Top - 0.006, right, b.Bottom + 0.006), clean, lh);
    }

    /// <summary>Menü satırı temizliği.</summary>
    public static string CleanMenuLine(string text)
    {
        var parts = GameWords.Words(text).ToList();
        while (parts.Count > 1)
        {
            var f = parts[0];
            if (!f.Any(char.IsLetter) || (f.Length <= 2 && !f.Any(char.IsLetterOrDigit))) parts.RemoveAt(0);
            else break;
        }
        if (parts.Count > 1 && char.IsUpper(parts[1][0]))
        {
            var f = parts[0];
            if ((f.Length <= 2 && f.All(c => char.IsLetter(c) && char.IsLower(c))) || f == "Il" || f == "II") parts.RemoveAt(0);
        }
        while (parts.Count > 1 && !parts[^1].Any(char.IsLetterOrDigit)) parts.RemoveAt(parts.Count - 1);
        return string.Join(" ", parts);
    }

    static readonly char[] Brackets = ['(', ')', '[', ']', '{', '}', '<', '>'];

    /// <summary>Harita tuşu (<c>RECENTER L3</c>, <c>ADD MARKER C</c>): sondaki en çok 2 kısa simge okuması atılır.</summary>
    public static bool IsMapButton(string line)
    {
        var words = GameWords.Words(CleanMenuLine(line).ToLowerInvariant()).ToList();
        var dropped = 0;
        while (words.Count >= 2 && dropped < 2 && words[^1].Trim(Brackets).Length <= 2)
        {
            words.RemoveAt(words.Count - 1);
            dropped++;
        }
        return MapButtons.Contains(string.Join(" ", words));
    }
}

/// <summary>
/// Sol üst ipucu kutusu: karenin sol üstündeki (x &lt; 0,40, y &lt; 0,48) yatay satırlar bloklara ayrılır, en çok
/// sözcüklü blok alınır (en az 4 sözcük ya da işaretle başlayan 2). Menü sütunu (<c>Map / Game / Store</c>) ve harita
/// listesi sayılmaz. Çeviri koyu buzlu kutuda, oyunun kutusunun hemen altında.
/// </summary>
static class TopLeftHint
{
    public static readonly Box Area = new(0.0, 0.0, 0.40, 0.48);

    static readonly HashSet<string> MenuWords = new(StringComparer.Ordinal)
    {
        "map", "brief", "progress", "settings", "stats", "gallery", "online", "inventory", "store", "help", "photo studio",
        "game", "journal", "options", "wardrobe", "outfits", "missions", "show text", "hide text", "flip", "put back",
        "rotate", "inspect", "examine", "read",
    };

    static readonly HashSet<string> ShopWords = new(StringComparer.Ordinal)
    {
        "speed", "acceleration", "handling", "rating", "upgrade", "performance", "respray", "purchase", "owned",
        "braking", "armor", "armour",
    };

    static readonly HashSet<string> MapHeadings = new(StringComparer.Ordinal) { "OPTIONAL", "STORY", "SIDE", "COMPLETED", "ACTIVITIES" };

    static int BoxWords(string t) => GameWords.BoxWordSplit.Split(t).Count(w => w.Length >= 2);

    public static List<OcrLine> Lines(IEnumerable<OcrLine> all)
    {
        var horizontal = all.Where(l => l.Box is { } b && b.Right <= Area.Right + 0.02 && b.Bottom <= Area.Bottom
                && b.Width * 16 / 9 > b.Height * 1.2 && GameWords.Letters(l.Text) >= 3)
            .OrderBy(l => l.Box!.Value.Top).ToList();
        var mh = GameWords.Median(horizontal.Select(l => l.Box!.Value.Height)) ?? 0.0;
        var blocks = new List<List<OcrLine>>();
        foreach (var l in horizontal)
        {
            if (blocks.Count > 0)
            {
                var last = blocks[^1];
                var u = GameWords.Union(last.Select(x => x.Box!.Value))!.Value;
                var b = l.Box!.Value;
                if (b.Top - last[^1].Box!.Value.Bottom < 1.8 * mh && Math.Min(b.Right, u.Right) > Math.Max(b.Left, u.Left))
                {
                    last.Add(l);
                    continue;
                }
            }
            blocks.Add([l]);
        }
        if (blocks.Count == 0) return [];
        var best = blocks[0];
        foreach (var bl in blocks)
            if (bl.Sum(x => BoxWords(x.Text)) > best.Sum(x => BoxWords(x.Text))) best = bl;
        var words = best.Sum(x => BoxWords(x.Text));
        var first = best[0].Text.Length > 0 ? best[0].Text[0] : '\0';
        var marker = best[0].Text.Length > 0 && !(char.IsLetterOrDigit(first) || "\"'“‘([".Contains(first));
        if (!(words >= 4 || (words >= 2 && marker))) return [];
        if (IsMapList(best) || IsMenuScreen(best.Select(x => x.Text))) return [];
        return best;
    }

    /// <summary>Menü ekranı mı (duraklatma menüsünün sütunu, mağaza/garaj ekranı).</summary>
    public static bool IsMenuScreen(IEnumerable<string> lines)
    {
        var cleaned = lines.Select(l => TopRightNotice.CleanMenuLine(l).ToLowerInvariant()).ToList();
        if (cleaned.Count(MenuWords.Contains) >= 2) return true;
        if (cleaned.Count(c => GameWords.KeyWords(c).Any(ShopWords.Contains)) >= 2) return true;
        return cleaned.Any(c => GameWords.KeyWords(c).ToHashSet().Intersect(["map", "brief", "progress"]).Count() >= 2);
    }

    public static bool IsMapList(IReadOnlyList<OcrLine> lines) =>
        lines.Any(l => !GameWords.HasLower(l.Text) && MapHeadings.Contains(l.Text.Trim()))
        || lines.Count(l => l.Text.StartsWith('◆') || l.Text.StartsWith('♦')) >= 2;

    /// <summary>Çevrilecek mi: küçük harfli ve en az 3 gerçek sözcük (tabela ve kısa yazı çevrilmez).</summary>
    public static bool Translatable(string text) =>
        GameWords.HasLower(text) && GameWords.Words(text).Count(w => w.Count(char.IsLetter) >= 2) >= 3;

    public static ScreenItem? Element(IReadOnlyList<OcrLine> lines, string translation)
    {
        if (GameWords.Union(lines.Where(l => l.Box is not null).Select(l => l.Box!.Value)) is not { } b) return null;
        var h = GameWords.Median(lines.Where(l => l.Box is not null).Select(l => l.Box!.Value.Height)) ?? 0.03;
        var lh = Math.Min(Math.Max(h, 0.026), 0.04) * 0.95;
        var right = Math.Max(b.Right + 0.01, b.Left + 0.22);
        var left = b.Left - 0.006;
        var text = GameWords.WithoutIcons(translation);
        if (text.Length == 0) return null;
        var rows = GameWords.LineCount(text, right - left, lh, 0.5);
        var height = lh * rows * 1.25 + 0.02;
        var top = Math.Min(1 - height - 0.01, b.Bottom + 0.012);
        return GameWords.DarkFrost(string.Join("\n", lines.Select(l => l.Text)), new Box(left, top, right, top + height), text, lh);
    }
}
