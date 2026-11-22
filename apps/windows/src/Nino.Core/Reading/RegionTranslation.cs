// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Translation;

namespace Nino.Core.Reading;

/// <summary>Tek seferlik bölge çevirisinin sonucu.</summary>
/// <param name="Source">Blok metinleri <c>\n</c> ile.</param>
/// <param name="Translation">Blok çevirileri <c>\n</c> ile (madde bloklarının başında "• ").</param>
/// <param name="Box">Okumanın karedeki kutusu (yoksa bölgenin kendisi).</param>
/// <param name="Structured">1'den çok blok: TV satır satır, sola yaslı gösterir.</param>
public sealed record RegionTranslationResult(string Source, string Translation, Box Box, bool Structured)
{
    /// <summary>Gösterim süresi: <c>sıkıştır(4000 + çeviri_uzunluğu × 70, 6000, 25000)</c> ms.</summary>
    public int DurationMs => RegionTranslation.DurationMs(Translation.Length);
}

/// <summary>Bölge çevirisinin bir bloğu (başlık, açıklama, madde).</summary>
public sealed record RegionBlock(string Text, bool Bullet);

/// <summary>
/// Tek seferlik bölge çevirisi: ekranda uzun süre duran yazılar (görev listesi, bilgi kutusu) yalnız tuşa basılınca bir
/// kez okunur ve başlık, açıklama, maddeler ayrı bloklar olarak çevrilir.
/// </summary>
public static class RegionTranslation
{
    const string BulletMarks = "◇◆◈◊♦♢•●○◦▪■□▫►▶‣∙·*-–—✓✔✦❖◉⬥";

    /// <summary>Gösterim süresi (ms).</summary>
    public static int DurationMs(int translationLength) => Math.Clamp(4000 + translationLength * 70, 6000, 25000);

    /// <summary>Satırdan madde işaretini ayırır.</summary>
    public static (string Text, bool Bullet) StripBullet(string line)
    {
        var t = line.Trim();
        if (t.Length >= 2 && BulletMarks.Contains(t[0])) return (t[1..].TrimStart(), true);
        if (t.StartsWith("<>", StringComparison.Ordinal)) return (t[2..].TrimStart(), true);
        if (t.Length > 2 && t[1] == ' ' && t[0] is 'o' or '0' && char.IsUpper(t[2])) return (t[2..], true);
        return (t, false);
    }

    static bool StartsNewBlock(OcrLine upper, string lower, OcrLine lowerLine, double typical, int areaWidth, int areaHeight)
    {
        if (!TextKey.EndsSentence(upper.Text) && lower.Length > 0 && char.IsLower(lower[0])) return false;
        if (TextKey.EndsSentence(upper.Text)) return true;
        if (upper.Box is not { } a || lowerLine.Box is not { } b || typical <= 0) return false;
        if ((b.Top - a.Bottom) * areaHeight > typical * 0.4) return true;
        return (a.Left - b.Left) * areaWidth > typical * 0.5;
    }

    /// <summary>Okumayı bloklara ayırır (satırlar okuma sırasıyla gezilir). Alan boyu pikseldir.</summary>
    public static IReadOnlyList<RegionBlock> Blocks(OcrReading reading, int areaWidth, int areaHeight)
    {
        var typical = Paragraphs.UpperMedian(reading.Lines.Where(l => l.Box is not null)
            .Select(l => l.Box!.Value.Height * areaHeight)) ?? 0;
        var blocks = new List<RegionBlock>();
        OcrLine? previous = null;
        foreach (var line in reading.Lines)
        {
            var (text, bullet) = StripBullet(line.Text);
            if (text.Length == 0) continue;
            if (previous is not null && blocks.Count > 0
                && !bullet && !StartsNewBlock(previous, text, line, typical, areaWidth, areaHeight))
                blocks[^1] = blocks[^1] with { Text = blocks[^1].Text + " " + text };
            else blocks.Add(new RegionBlock(text, bullet));
            previous = line;
        }
        return blocks;
    }

    /// <summary>
    /// Bölgeyi bir kez okur (derin), düğme ipuçlarını atar, blokları sırayla çevirir. Yazı yoksa null. Çevirmen
    /// hatası yukarı iletilir.
    /// </summary>
    public static async Task<RegionTranslationResult?> TranslateAsync(BgraFrame frame, Box region, ITextReader reader,
        ITranslator translator, CancellationToken cancellation = default)
    {
        var image = frame.CropRegion(region);
        var reading = ButtonHints.Remove(reader.ReadLines(image, true));
        if (reading.IsEmpty) return null;
        var box = reading.Box is { } b ? b.PlaceIn(region) : region;
        var blocks = Blocks(reading, image.Width, image.Height);
        if (blocks.Count == 0) return null;
        var translations = new List<string>();
        foreach (var block in blocks)
        {
            var t = (await translator.TranslateAsync(block.Text, cancellation).ConfigureAwait(false)).Text;
            translations.Add(block.Bullet ? "• " + t : t);
        }
        return new RegionTranslationResult(string.Join("\n", blocks.Select(x => x.Text)), string.Join("\n", translations), box,
            blocks.Count > 1);
    }
}
