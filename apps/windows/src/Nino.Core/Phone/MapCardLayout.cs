// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>Harita kartının çevirisinin düzeltmeleri ve TV'deki yerleşimi.</summary>
public static class MapCardLayout
{
    // Sıra önemli: uzun kalıp kısasından önce gelir.
    static readonly (string From, string To)[] TermFixes =
    [
        ("NARKOTİK", "UYUŞTURUCU"),
        ("narkotik", "uyuşturucu"),
        ("kırmızı ışık papağan balığı", "stoplight papağan balığı"),
        ("trafik ışığı papağan balığı", "stoplight papağan balığı"),
        ("kapalı tutulması", "deposu"),
        ("Kapalı Tutulması", "Deposu"),
        ("KAPALI TUTULMASI", "DEPOSU"),
        ("işaretli faturaların", "işaretli banknotların"),
        ("işaretli faturalar", "işaretli banknotlar"),
        ("işaretli fatura", "işaretli banknot"),
    ];

    // Açıklamanın ilk sözcüklerinde geçerse başlık bir mekândır.
    static readonly string[] VenueHints =
    [
        " bar", "bodega", "boutique", "club", "convenience", "dealer", "diner", "distributor", "dive bar", "garage",
        "hotel", "motel", "restaurant", "salon", "shop", "store", "wholesaler",
    ];

    // Başlıkta tek başına geçerse mekân adıdır.
    static readonly HashSet<string> VenueNameWords = new(StringComparer.Ordinal)
    {
        "AMMU-NATION", "ANCHOR", "AUTO", "BAR", "BARBER", "CAFE", "CLUB", "CUSTOMS", "DINER", "GARAGE", "GRILL",
        "HOTEL", "LOUNGE", "MARINA", "MART", "MOTEL", "MOTORS", "PAWN", "SALOON", "SHOP", "SPEEDWAY", "STORE",
        "TACKLE", "TATTOO",
    };

    // Yerleşim ölçüleri (ekranın oranı olarak).
    const double MinLine = 0.024, MaxLine = 0.034, LineScale = 0.9;
    const double PadX = 0.015, PadY = 0.02, Gap = 0.012, Chrome = 0.022;
    const double ScreenTop = 0.02, ScreenBottom = 0.97, LineSpacing = 1.32;

    /// <summary>Terim düzeltmesi (büyük/küçük harf duyarlı, sırayla, her geçtiği yer).</summary>
    public static string FixTerms(string text) =>
        TermFixes.Aggregate(text, (acc, fix) => acc.Replace(fix.From, fix.To, StringComparison.Ordinal));

    /// <summary>Başlık bir mekân adı mı (çevrilmez, İngilizcesi kalır).</summary>
    public static bool IsVenue(string title, string description)
    {
        var opening = PhoneText.Words(description.ToLowerInvariant()).Take(4);
        var probe = " " + string.Join(" ", opening);
        foreach (var hint in VenueHints)
            if (probe.Contains(hint, StringComparison.Ordinal)) return true;

        var shout = title.ToUpperInvariant();
        var titleWords = PhoneText.Words(shout);
        if (titleWords.Any(VenueNameWords.Contains)) return true;
        return titleWords.Length <= 4 && shout.StartsWith("THE ", StringComparison.Ordinal);
    }

    /// <summary>
    /// Kartın TV öğesi: kartın altına (yer yoksa üstüne) koyu kart olarak; ilk satır başlık. <paramref name="frame"/>
    /// görüntüden bulunan çerçevedir (yoksa null).
    /// </summary>
    public static ScreenItem Layout(MapCardText card, IReadOnlyList<string> translated, Box? frame)
    {
        var rowsText = new List<string>(translated.Count);
        foreach (var raw in translated) rowsText.Add(FixTerms(PhoneText.DecodeEntities(raw)));
        var keepTitle = card.Title.Length > 0 && rowsText.Count > 0
            && IsVenue(card.Title, string.Join(" ", card.Sentences));
        if (keepTitle) rowsText[0] = card.Title;

        var cardArea = new Box(card.Box.Left - PadX, card.Box.Top - PadY, card.Box.Right + PadX, card.Box.Bottom + PadY);
        var bounds = frame.HasValue ? frame.Value.Union(cardArea) : cardArea;

        var fontSize = Math.Clamp(card.LineHeight, MinLine, MaxLine) * LineScale;
        var glyph = fontSize * 0.42 * 9 / 16;
        var widest = rowsText.Count == 0 ? 10 : rowsText.Max(r => r.Length);
        var boxWidth = Math.Min(bounds.Width, widest * glyph + 0.035);
        var rowCount = CountRows(rowsText, glyph, boxWidth - 0.03);
        var boxHeight = fontSize * rowCount * LineSpacing + Chrome;

        var roomBelow = ScreenBottom - (bounds.Bottom + Gap);
        var roomAbove = bounds.Top - Gap - ScreenTop;
        double y;
        if (boxHeight <= roomBelow)
        {
            y = bounds.Bottom + Gap;
        }
        else if (boxHeight <= roomAbove || roomAbove > roomBelow)
        {
            (fontSize, boxHeight) = FitInto(fontSize, boxHeight, roomAbove);
            y = bounds.Top - Gap - boxHeight;
        }
        else
        {
            (fontSize, boxHeight) = FitInto(fontSize, boxHeight, roomBelow);
            y = bounds.Bottom + Gap;
        }

        var x = Math.Max(bounds.Left, card.Box.Left - 0.014);
        var place = new Box(x, y, x + boxWidth, y + boxHeight);
        return new ScreenItem(card.All, string.Join("\n", rowsText), place, fontSize) { Card = true };
    }

    // Başlık tek satır; diğer satırlar kutunun iç genişliğine göre kaydırılır.
    static int CountRows(List<string> rows, double glyph, double innerWidth)
    {
        if (rows.Count == 0) return 0;
        var total = 1;
        for (var n = 1; n < rows.Count; n++)
            total += Math.Max(1, (int)Math.Ceiling(rows[n].Length * glyph / innerWidth));
        return total;
    }

    // Kutu yere sığmıyorsa yazıyı küçültüp kutuyu yere eşitler.
    static (double Size, double Height) FitInto(double size, double height, double room) =>
        height <= room ? (size, height) : (size * ((room - Chrome) / (height - Chrome)), room);
}
