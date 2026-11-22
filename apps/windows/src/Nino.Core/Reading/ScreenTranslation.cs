// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Translation;

namespace Nino.Core.Reading;

/// <summary>Tam ekran çevirisinin bir grubu: paragrafları, kutusu (karede) ve satır yüksekliği (üst ortanca).</summary>
public sealed record ScreenGroup(IReadOnlyList<string> Parts, Box Box, double LineHeight);

/// <summary>
/// Tam ekran çevirisi: o anki karenin bütün yazıları bir kez okunur, konumlarına göre gruplara ayrılır (menü, panel, kutu,
/// altyazı…) ve her grup ayrı çevrilir. TV her çeviriyi ait olduğu yazının yerine aynı yazı boyuyla koyar.
/// </summary>
public static class ScreenTranslation
{
    /// <summary>En çok grup.</summary>
    public const int MaxGroups = 30;

    /// <summary>Bu yükseklikten kısa kare 2 kat büyütülür.</summary>
    public const int UpscaleBelowHeight = 900;

    /// <summary>TV'de kalma süresi: <c>sıkıştır(8000 + çevirilerin uzunluk toplamı × 50, 12000, 60000)</c> ms.</summary>
    public static int DurationMs(int totalTranslationLength) => Math.Clamp(8000 + totalTranslationLength * 50, 12_000, 60_000);

    /// <summary>Kareyi okur: 900 pikselden kısaysa 2 kat büyütülür; derin değil. Kutular orandır.</summary>
    public static OcrReading Read(BgraFrame frame, ITextReader reader) =>
        reader.ReadLines(frame.Height < UpscaleBelowHeight ? frame.Upscale(2) : frame, false);

    static bool Belongs(Box upper, Box lower)
    {
        double a = upper.Height, b = lower.Height;
        if (Math.Max(a, b) / Math.Min(a, b) > 1.6) return false;
        if (lower.Top < upper.Top) return false;
        if (lower.Top - upper.Bottom >= 0.8 * Math.Max(a, b)) return false;
        var overlap = Math.Min(upper.Right, lower.Right) - Math.Max(upper.Left, lower.Left);
        return overlap > 0 && overlap >= Math.Min(upper.Width, lower.Width) / 2;
    }

    static bool Bridges(Box wide, Box column, IReadOnlyList<Box> all)
    {
        foreach (var peer in all)
        {
            if (peer == wide || peer == column) continue;
            if (Math.Min(peer.Right, column.Right) > Math.Max(peer.Left, column.Left)) continue;
            var v = Math.Min(peer.Bottom, column.Bottom) - Math.Max(peer.Top, column.Top);
            if (v <= 0 || v < Math.Min(peer.Height, column.Height) / 2) continue;
            if ((Belongs(wide, column) && Belongs(wide, peer)) || (Belongs(column, wide) && Belongs(peer, wide))) return true;
        }
        return false;
    }

    /// <summary>Okumayı gruplara ayırır (satır kutuları karenin tamamına göre).</summary>
    public static IReadOnlyList<ScreenGroup> Group(OcrReading reading)
    {
        var lines = OcrJunk.Clean(ButtonHints.Remove(reading)).Lines
            .Where(l => l.Box is not null && Paragraphs.IsText(l.Text))
            .Select((l, i) => (l, i)).OrderBy(p => p.l.Box!.Value.Top).ThenBy(p => p.i).Select(p => p.l).ToArray();
        var boxes = lines.Select(l => l.Box!.Value).ToArray();
        var groups = new List<List<OcrLine>>();
        foreach (var line in lines)
        {
            var box = line.Box!.Value;
            List<OcrLine>? home = null;
            for (var g = groups.Count - 1; g >= 0; g--)
                if (Belongs(groups[g][^1].Box!.Value, box))
                {
                    home = groups[g];
                    break;
                }
            if (home is not null)
            {
                var last = home[^1].Box!.Value;
                if (Bridges(last, box, boxes) || Bridges(box, last, boxes)) home = null;
            }
            if (home is null) groups.Add([line]);
            else home.Add(line);
        }
        return groups.Take(MaxGroups).Select(g =>
        {
            var r = new OcrReading(g);
            return new ScreenGroup(Paragraphs.Build(g.Select(l => l.Text)), r.Box!.Value,
                Paragraphs.UpperMedian(g.Select(l => l.Box!.Value.Height)) ?? 0);
        }).ToArray();
    }

    static ScreenItem? Item(ScreenGroup group, IReadOnlyList<string?> translations)
    {
        var texts = group.Parts.Select((p, i) => i < translations.Count && translations[i]?.Trim() is { Length: > 0 } t ? t : p)
            .ToArray();
        var differs = group.Parts.Select((p, i) => (p, i)).Any(x =>
            !TextKey.Similar(TextKey.Of(x.p), TextKey.Of(texts[x.i]), Stabilizer.SameLanguageThreshold));
        return differs
            ? new ScreenItem(string.Join("\n", group.Parts), string.Join("\n", texts), group.Box, group.LineHeight)
            : null;
    }

    /// <summary>
    /// Grupları çevirir. Toplu çevirebilen çevirmende bütün parçalar tek istekte gider; değilse gruplar sırayla, parçalar
    /// tek tek çevrilir ve her öğe eklendikçe o ana kadarki öğelerle <paramref name="progress"/> bildirilir. Çevirmen
    /// hatası yukarı iletilir.
    /// </summary>
    public static async Task<IReadOnlyList<ScreenItem>> TranslateAsync(IReadOnlyList<ScreenGroup> groups,
        ITranslator translator, Action<IReadOnlyList<ScreenItem>>? progress = null,
        CancellationToken cancellation = default)
    {
        var items = new List<ScreenItem>();
        if (translator.SupportsBatch)
        {
            var all = groups.SelectMany(g => g.Parts).ToArray();
            var results = await translator.TranslateBatchAsync(all, cancellation).ConfigureAwait(false);
            if (cancellation.IsCancellationRequested) return items;
            var at = 0;
            foreach (var g in groups)
            {
                var slice = Enumerable.Range(at, g.Parts.Count).Select(i => i < results.Count ? results[i] : null).ToArray();
                at += g.Parts.Count;
                if (Item(g, slice) is { } item) items.Add(item);
            }
            if (items.Count > 0) progress?.Invoke(items.ToArray());
            return items;
        }
        foreach (var g in groups)
        {
            cancellation.ThrowIfCancellationRequested();
            var translations = new List<string?>();
            foreach (var part in g.Parts)
                translations.Add((await translator.TranslateAsync(part, cancellation).ConfigureAwait(false)).Text);
            if (Item(g, translations) is { } item)
            {
                items.Add(item);
                progress?.Invoke(items.ToArray());
            }
        }
        return items;
    }
}
