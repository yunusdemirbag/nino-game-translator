// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.RegularExpressions;

namespace Nino.Core.Link;

/// <summary>
/// Metindeki <c>⟦T1⟧</c> yer tutucusunun yerine çizilecek kumanda tuşu simgesi (protokol "Tuş simgeleri"). <see cref="Name"/>
/// bilinen bir PS5 tuşu (TV vektör çizer), <see cref="Png"/> oyundan kesilmiş base64 PNG; ikisi de varsa TV adı kullanır.
/// </summary>
public sealed record LinkIcon(string Id, string? Name = null, string? Png = null)
{
    /// <summary>Bir mesajdaki en çok simge.</summary>
    public const int MaxCount = 8;

    /// <summary>Adın en uzun boyu.</summary>
    public const int MaxNameLength = 24;

    /// <summary>Görüntünün (base64) en uzun boyu.</summary>
    public const int MaxPngLength = 200_000;

    /// <summary>TV'nin vektörle çizdiği adlar (büyük/küçük harf farksız).</summary>
    public static IReadOnlyList<string> KnownNames { get; } =
    [
        "cross", "circle", "square", "triangle", "dpad-up", "dpad-down", "dpad-left", "dpad-right", "dpad",
        "L1", "L2", "L3", "R1", "R2", "R3", "options", "create", "touchpad",
    ];

    static readonly Regex IdPattern = new(@"^T\d{1,2}$", RegexOptions.CultureInvariant);

    /// <summary><c>T1</c> … <c>T99</c>.</summary>
    public static bool IsValidId(string? id) => id is not null && IdPattern.IsMatch(id);

    bool NameOk => !string.IsNullOrEmpty(Name) && Name.Length <= MaxNameLength;

    bool PngOk => !string.IsNullOrEmpty(Png) && Png.Length <= MaxPngLength;

    /// <summary>Kurala uyuyor mu (kimlik ve ya ad ya görüntü).</summary>
    public bool IsValid => IsValidId(Id) && (NameOk || PngOk);

    /// <summary>JSON nesnesi (yalnız kurala uyan alanlar).</summary>
    public WireObject Body()
    {
        var o = new WireObject { ["id"] = Id };
        if (NameOk) o["name"] = Name!;
        if (PngOk) o["png"] = Png!;
        return o;
    }

    /// <summary>JSON'a yazılacak liste: geçersizler atılır, en çok 8; boşsa null (alan hiç yazılmaz).</summary>
    public static List<WireObject>? Encode(IReadOnlyList<LinkIcon>? icons)
    {
        var ok = (icons ?? []).Where(i => i.IsValid).Take(MaxCount).Select(i => i.Body()).ToList();
        return ok.Count == 0 ? null : ok;
    }

    /// <summary>Simgeyi bilmeyen gösterici için okunur karşılık (<c>[→]</c>, <c>[✕]</c>, <c>[L2]</c>; görüntülüde <c>[■]</c>).</summary>
    public string Readable
    {
        get
        {
            var symbol = Name?.ToLowerInvariant() switch
            {
                "cross" => "✕",
                "circle" => "○",
                "square" => "□",
                "triangle" => "△",
                "dpad-up" => "↑",
                "dpad-down" => "↓",
                "dpad-left" => "←",
                "dpad-right" => "→",
                "dpad" => "✜",
                "options" => "OPTIONS",
                "create" => "CREATE",
                "touchpad" => "TOUCHPAD",
                null => "■",
                _ => Name!.ToUpperInvariant(),
            };
            return "[" + symbol + "]";
        }
    }
}

/// <summary><c>⟦T1⟧</c> yer tutucuları: çeviride korunur, kaybolursa yerine konur, eski göstericide okunur metne döner.</summary>
public static partial class IconPlaceholders
{
    [GeneratedRegex(@"⟦T\d{1,2}⟧", RegexOptions.CultureInvariant)]
    private static partial Regex Pattern();

    public static string Tag(string id) => "⟦" + id + "⟧";

    public static string Tag(int n) => "⟦T" + n.ToString(CultureInfo.InvariantCulture) + "⟧";

    /// <summary>Metindeki yer tutucu kimlikleri (sırayla).</summary>
    public static IReadOnlyList<string> Ids(string? text) =>
        Pattern().Matches(text ?? "").Select(m => m.Value[1..^1]).ToList();

    public static bool Contains(string? text) => Pattern().IsMatch(text ?? "");

    /// <summary>
    /// Yer tutucuları okunur metne çevirir (<c>[→]</c>); simgesi olmayan atılır, kalan çift boşluk teke iner, uçlar
    /// kırpılır. Yer tutucu yoksa metin olduğu gibi döner (eski 8787 baytları değişmez).
    /// </summary>
    public static string Readable(string text, IReadOnlyList<LinkIcon>? icons)
    {
        if (!Contains(text)) return text;
        var output = text;
        foreach (var id in Ids(text))
        {
            var r = icons?.FirstOrDefault(i => i.Id == id)?.Readable ?? "";
            output = output.Replace(Tag(id), r, StringComparison.Ordinal);
        }
        while (output.Contains("  ", StringComparison.Ordinal)) output = output.Replace("  ", " ", StringComparison.Ordinal);
        return output.Trim(' ');
    }

    /// <summary>Metinde yer tutucusu kalan simgeler (gönderilecekler).</summary>
    public static IReadOnlyList<LinkIcon>? Used(string text, IReadOnlyList<LinkIcon>? icons)
    {
        if (icons is not { Count: > 0 }) return null;
        var used = Ids(text).ToHashSet(StringComparer.Ordinal);
        var list = icons.Where(i => used.Contains(i.Id)).ToList();
        return list.Count == 0 ? null : list;
    }

    // ---- Çeviride kaybolan yer tutucu ----

    static readonly HashSet<string> TurkishButtonWords = new(
        "tuş tuşu tuşunu tuşuna tuşa tuşla tuşuyla düğme düğmeyi düğmesini düğmeye düğmesine düğmeyle".Split(' '),
        StringComparer.Ordinal);

    static readonly string[] TurkishVerbStems = ["bas", "tıkla", "dokun", "çek", "kaydır", "çevir", "kullan"];

    static readonly HashSet<string> OtherButtonWords = new(
        ("button key taste touche bouton botón boton tecla tasto pulsante botão knop przycisk кнопку кнопка клавишу " +
         "زر الزر").Split(' '), StringComparer.Ordinal);

    static readonly CultureInfo Turkish = CultureInfo.GetCultureInfo("tr-TR");

    /// <summary>
    /// Çeviride kaybolan yer tutucuları yerine koyar. Türkçede tuşu anlatan genel sözcüğün (<c>tuşu</c>) yerine, yoksa ilk
    /// fiilin (<c>bas</c>, <c>basılı tut</c>) önüne, o da yoksa sondaki noktalamanın önüne; başka dillerde genel sözcüğün
    /// yerine, yoksa başa. <paramref name="ids"/> kaynaktaki sıradır.
    /// </summary>
    public static string Ensure(string translation, IReadOnlyList<string> ids, string language)
    {
        var missing = ids.Where(id => !translation.Contains(Tag(id), StringComparison.Ordinal)).ToList();
        if (missing.Count == 0) return translation;
        var words = translation.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToList();
        var tr = language.StartsWith("tr", StringComparison.OrdinalIgnoreCase);
        var culture = tr ? Turkish : CultureInfo.InvariantCulture;
        string Core(string w) => TrimPunctuation(w.ToLower(culture));
        foreach (var id in missing)
        {
            var tag = Tag(id);
            var generic = tr ? TurkishButtonWords : OtherButtonWords;
            var g = words.FindIndex(w => generic.Contains(Core(w)));
            if (g >= 0)
            {
                words[g] = tag + TrailingPunctuation(words[g]);
                continue;
            }
            if (!tr)
            {
                words.Insert(0, tag);
                continue;
            }
            var v = words.FindIndex(w =>
            {
                var c = Core(w);
                return TurkishVerbStems.Any(s => c.StartsWith(s, StringComparison.Ordinal))
                    && !c.StartsWith("basit", StringComparison.Ordinal) && !c.StartsWith("çeki", StringComparison.Ordinal);
            });
            if (v >= 0) words.Insert(v, tag);
            else if (words.Count > 0)
            {
                var last = words[^1];
                var tail = TrailingPunctuation(last);
                words[^1] = last[..^tail.Length] + " " + tag + tail;
            }
            else words.Add(tag);
        }
        return string.Join(' ', words);
    }

    static bool IsPunctuation(char c) => char.IsPunctuation(c);

    static string TrailingPunctuation(string w)
    {
        var n = 0;
        while (n < w.Length && IsPunctuation(w[w.Length - 1 - n])) n++;
        return w[(w.Length - n)..];
    }

    static string TrimPunctuation(string w)
    {
        var start = 0;
        var end = w.Length;
        while (start < end && IsPunctuation(w[start])) start++;
        while (end > start && IsPunctuation(w[end - 1])) end--;
        return w[start..end];
    }
}
