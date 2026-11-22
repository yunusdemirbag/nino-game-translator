// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Phone;

/// <summary>
/// GTA 6 telefon uygulamalarının Türkçe sözlüğü (yalnız hedef dil Türkçeyken): sadeleştirilmiş tam eşleşme, sonra
/// kalıplar (parantezli tutar, <c>Ad - Seviye</c>, tiresi düşmüş seviye, <c>Level 3/4</c>, <c>… to next goal</c>).
/// </summary>
public static class PhoneGlossary
{
    static readonly Dictionary<string, string> Exact = new(StringComparer.Ordinal)
    {
        ["vice city horn"] = "Vice City Horn",
        ["the leonida journal"] = "The Leonida Journal",
        ["leonida journal"] = "Leonida Journal",
        ["ripped"] = "Kaslı",
        ["toned"] = "Sıkı",
        ["average"] = "Ortalama",
        ["body nutrition"] = "Vücut ve Beslenme",
        ["strength workout"] = "Güç Antrenmanı",
        ["cardio workout"] = "Kardiyo Antrenmanı",
        ["workout window"] = "Antrenman zamanı",
        ["focus"] = "Odak",
        ["fitness"] = "Fitness",
        ["calorie balance"] = "Kalori Dengesi",
        ["you will maintain weight"] = "Kilonu koruyacaksın",
        ["you will gain weight"] = "Kilo alacaksın",
        ["you will lose weight"] = "Kilo vereceksin",
        ["hungry"] = "Aç",
        ["full"] = "Tok",
        ["trip details"] = "Yolculuk Bilgileri",
        ["cost"] = "Ücret",
        ["choose ryde"] = "Ryde Seç",
        ["standard ryde"] = "Standart Ryde",
        ["change destination"] = "Varış Noktasını Değiştir",
        ["book ryde"] = "Ryde Çağır",
        ["cancel ryde"] = "Ryde'ı İptal Et",
        ["checking account"] = "Vadesiz Hesap",
        ["savings account"] = "Birikim Hesabı",
        ["family savings"] = "Aile Birikimi",
        ["family savings video"] = "Aile Birikimi Videosu",
        ["atm finder"] = "ATM Bulucu",
        ["faqs"] = "SSS",
        ["savings"] = "Birikim",
        ["balance"] = "Bakiye",
        ["deposit"] = "Para Yatır",
        ["withdraw"] = "Para Çek",
        ["transfer"] = "Transfer",
        ["transactions"] = "Hesap Hareketleri",
        ["recent transactions"] = "Son Hareketler",
        ["set a goal"] = "Hedef Belirle",
        ["messages encrypted"] = "Mesajlar şifreli",
        ["new message"] = "Yeni mesaj",
        ["all contacts"] = "Tüm Kişiler",
        ["suggested"] = "Önerilenler",
        ["messages"] = "Mesajlar",
        ["map pin expired"] = "Konum süresi doldu",
    };

    static readonly Dictionary<string, string> Stats = new(StringComparer.Ordinal)
    {
        ["muscle"] = "Kas", ["body fat"] = "Vücut Yağı", ["stamina"] = "Dayanıklılık", ["strength"] = "Güç",
        ["fat"] = "Yağ",
    };

    static readonly Dictionary<string, string> Levels = new(StringComparer.Ordinal)
    {
        ["high"] = "Yüksek", ["low"] = "Düşük", ["medium"] = "Orta", ["average"] = "Ortalama",
        ["very high"] = "Çok Yüksek", ["very low"] = "Çok Düşük",
    };

    /// <summary>Sadeleştirilmiş anahtar sözlükte tam olarak var mı.</summary>
    public static bool ContainsKey(string key) => Exact.ContainsKey(key);

    /// <summary>Metnin sözlük çevirisi; yoksa null.</summary>
    public static string? Lookup(string? text)
    {
        var t = PhoneText.TrimSpaces(text);
        var key = PhoneText.Key(t);
        if (key.Length == 0) return null;
        if (Exact.TryGetValue(key, out var exact)) return exact;

        var open = t.IndexOf('(');
        if (open >= 0 && t.EndsWith(')') && Exact.TryGetValue(PhoneText.Key(t[..open]), out var paren))
            return paren + " " + t[open..];

        var halves = t.Split(" - ");
        if (halves.Length == 2 && Stats.TryGetValue(PhoneText.Key(halves[0]), out var stat)
            && Levels.TryGetValue(PhoneText.Key(halves[1]), out var level))
            return stat + " - " + level;

        var words = PhoneText.Words(key);
        if (words.Length >= 2 && Levels.TryGetValue(words[^1], out var lastLevel)
            && Stats.TryGetValue(string.Join(" ", words[..^1]), out var lastStat))
            return lastStat + " - " + lastLevel;

        var raw = PhoneText.Words(t);
        if (key.StartsWith("level ", StringComparison.Ordinal) && raw.Length >= 2 && raw[1].Contains('/'))
            return "Seviye " + raw[1];

        if (key.EndsWith(" to next goal", StringComparison.Ordinal) && raw.Length >= 1 && raw[0].Any(char.IsDigit))
            return "Sonraki hedefe " + raw[0].Replace(',', '.');

        return null;
    }
}
