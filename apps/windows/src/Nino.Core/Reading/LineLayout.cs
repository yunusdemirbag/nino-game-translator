// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>
/// Satırların yerine bakan süzgeçler. Okumanın satır kutuları okunan alana göredir; <c>area</c> okunan alanın karedeki
/// kutusudur. Kutusuz satırlar bütün bu kurallardan muaf geçer. Hiçbir şey değişmediyse aynı okuma nesnesi döner.
/// </summary>
public static class LineLayout
{
    /// <summary>İki kenara değen satır sınırları (alana göre).</summary>
    public const double EdgeLeft = 0.015, EdgeRight = 0.985;

    /// <summary>Altyazı satırı yükseklik sınırı (karenin tamamına göre).</summary>
    public const double SubtitleLineLimit = 0.075;

    /// <summary>Cümle satırı yükseklik sınırı (karenin tamamına göre).</summary>
    public const double SentenceLineLimit = 0.13;

    /// <summary>Dev blok: en çok satır sayısı.</summary>
    public const int GiantBlockLines = 5;

    /// <summary>Dev blok: en çok yükseklik (karenin tamamına göre).</summary>
    public const double GiantBlockHeight = 0.26;

    /// <summary>Ortalanmış sayılma payı (karede ortadan uzaklık).</summary>
    public const double CenterTolerance = 0.12;

    /// <summary>
    /// Kutusu alanı soldan sağa baştan sona kaplayan satır (sol ≤ 0,015 ve sağ ≥ 0,985) kesiktir (yasal uyarı, kayan
    /// yazı); atılır.
    /// </summary>
    public static OcrReading RemoveEdgeToEdge(OcrReading reading) =>
        reading.Where(l => l.Box is not { } b || !(b.Left <= EdgeLeft && b.Right >= EdgeRight));

    /// <summary>
    /// Aynı sıradaki parçaları birleştirir (renkli konuşan adı cümleden ayrı okunabilir). En az 2 satır ve bütün
    /// satırların kutusu varken: soldan sağa gezilir; dikey örtüşmesi küçük yüksekliğin en az %60'ı ve solu sıranın
    /// sağından en çok 0,05 uzakta olan parça o sıraya eklenir.
    /// </summary>
    public static OcrReading MergeRows(OcrReading reading)
    {
        if (reading.Lines.Count < 2 || !reading.AllBoxed) return reading;
        var rows = new List<OcrLine>();
        foreach (var part in reading.Lines.OrderBy(l => l.Box!.Value.Left))
        {
            var pb = part.Box!.Value;
            var index = rows.FindIndex(row =>
            {
                var rb = row.Box!.Value;
                var minHeight = Math.Min(rb.Height, pb.Height);
                if (minHeight <= 0) return false;
                var overlap = Math.Min(rb.Bottom, pb.Bottom) - Math.Max(rb.Top, pb.Top);
                return overlap >= minHeight * 0.6 && pb.Left - rb.Right <= 0.05;
            });
            if (index < 0)
            {
                rows.Add(part);
                continue;
            }
            var r = rows[index];
            double? confidence = r.Confidence is { } a && part.Confidence is { } c ? Math.Min(a, c)
                : r.Confidence ?? part.Confidence;
            rows[index] = new OcrLine(r.Text + " " + part.Text, r.Box!.Value.Union(pb), confidence);
        }
        if (rows.Count == reading.Lines.Count) return reading;
        return new OcrReading(rows.Select((l, i) => (l, i)).OrderBy(p => p.l.Box!.Value.Top).ThenBy(p => p.i)
            .Select(p => p.l));
    }

    /// <summary>Etiket gibi satır: harf içeren sözcük sayısı ≤ 4 ve <c>. , ! ? …</c> yok ("OHM BOY").</summary>
    public static bool LooksLikeLabel(string text) =>
        TextKey.Words(text).Count(w => w.Any(char.IsLetter)) <= 4 && text.IndexOfAny(['.', ',', '!', '?', '…']) < 0;

    /// <summary>
    /// Dev satırlar: karedeki yüksekliği 0,13'ten büyük ya da 0,075'ten büyük ve etiket gibi olan satırlar (tabela,
    /// bölüm başlığı). <paramref name="dropped"/> atılan satırların metinleri.
    /// </summary>
    public static OcrReading RemoveGiantLines(OcrReading reading, Box area, out IReadOnlyList<string> dropped)
    {
        var removed = new List<string>();
        var kept = reading.Where(l =>
        {
            if (l.Box is not { } b) return true;
            var h = b.Height * area.Height;
            var giant = h > Math.Max(SubtitleLineLimit, SentenceLineLimit) || (h > SubtitleLineLimit && LooksLikeLabel(l.Text));
            if (giant) removed.Add(l.Text);
            return !giant;
        });
        dropped = removed;
        return kept;
    }

    /// <summary>Blok altyazı olamayacak kadar çok satırlı (5'ten çok) ya da yüksek (karede 0,26'dan çok) mu.</summary>
    public static bool IsGiantBlock(OcrReading block, Box area)
    {
        if (block.Lines.Count > GiantBlockLines) return true;
        return block.Box is { } b && b.Height * area.Height > GiantBlockHeight;
    }

    static bool Belongs(Box last, Box line)
    {
        var h = Math.Max(last.Height, line.Height);
        if (line.Top - last.Bottom >= h * 0.8 || line.Top < last.Top) return false;
        var overlap = Math.Min(last.Right, line.Right) - Math.Max(last.Left, line.Left);
        var narrow = Math.Min(last.Width, line.Width);
        return overlap > 0 && overlap >= narrow / 2;
    }

    /// <summary>
    /// Altyazı bloğunu seçer (alanda menü ve köşe göstergeleri de okunur). Satırlar bloklara ayrılır, menü blokları
    /// elenir; ortalanmış bloklardan alt kenarı en büyük olan, yoksa en az 3 sözcüklü bloklardan alt kenarı en büyük
    /// olan seçilir; o da yoksa boş okuma.
    /// </summary>
    public static OcrReading SelectSubtitleBlock(OcrReading reading, Box area)
    {
        if (reading.IsEmpty || !reading.AllBoxed) return reading;
        var ordered = reading.Lines.Select((l, i) => (l, i)).OrderBy(p => p.l.Box!.Value.Top).ThenBy(p => p.i)
            .Select(p => p.l).ToArray();
        var blocks = new List<List<OcrLine>>();
        foreach (var line in ordered)
        {
            var frameBox = line.Box!.Value.PlaceIn(area);
            List<OcrLine>? home = null;
            for (var b = blocks.Count - 1; b >= 0; b--)
                if (Belongs(blocks[b][^1].Box!.Value.PlaceIn(area), frameBox))
                {
                    home = blocks[b];
                    break;
                }
            if (home is null) blocks.Add([line]);
            else home.Add(line);
        }
        blocks.RemoveAll(b => b.Count >= 3 && b.All(l => TextKey.Words(l.Text).Length <= 3 && !TextKey.EndsSentence(l.Text)));
        var readings = blocks.Select(b => new OcrReading(b)).ToArray();
        var centered = readings.Where(r => Math.Abs(r.Box!.Value.PlaceIn(area).CenterX - 0.5) <= CenterTolerance).ToArray();
        var pool = centered.Length > 0 ? centered
            : readings.Where(r => r.Lines.Sum(l => TextKey.Words(l.Text).Length) >= 3).ToArray();
        if (pool.Length == 0) return OcrReading.Empty;
        var best = pool[0];
        foreach (var r in pool.Skip(1))
            if (r.Box!.Value.Bottom > best.Box!.Value.Bottom) best = r;
        return best.Lines.Count == reading.Lines.Count ? reading : best;
    }

    /// <summary>
    /// Ortalanmış satırlar (telefon aranırken: konuşma altyazısı hep ortalıdır): karedeki ortası 0,5'ten 0,12'den uzak
    /// satırlar atılır.
    /// </summary>
    public static OcrReading KeepCentered(OcrReading reading, Box area) =>
        reading.Where(l => l.Box is not { } b || Math.Abs(b.PlaceIn(area).CenterX - 0.5) <= CenterTolerance);

    /// <summary>
    /// TV'ye giden kutu: ortası 0,3'ten büyük ve 0,7'den küçükse ortaya göre simetrik genişler (bir ucu okunamayan
    /// satırın İngilizcesi yanda kalmasın); değilse dokunulmaz.
    /// </summary>
    public static Box CenterOnScreen(Box box)
    {
        var c = box.CenterX;
        if (c <= 0.3 || c >= 0.7) return box;
        return box with
        {
            Left = Math.Max(0, Math.Min(box.Left, 1 - box.Right)),
            Right = Math.Min(1, Math.Max(box.Right, 1 - box.Left)),
        };
    }

    /// <summary>
    /// Görev şeridi çizgisi: karede üst kenarı çizginin altında başlayan satırlar atılır. Konuşan adıyla açılan satır
    /// ile hemen altındaki devam satırı (üstü konuşan satırın altından <c>max(0,02, boy × 1,5)</c>'ten az uzakta) kalır.
    /// </summary>
    public static OcrReading RemoveBelowQuestLine(OcrReading reading, Box area, double line)
    {
        var lines = reading.Lines;
        var keep = new bool[lines.Count];
        for (var i = 0; i < lines.Count; i++)
        {
            if (lines[i].Box is not { } b) { keep[i] = true; continue; }
            if (b.PlaceIn(area).Top < line) keep[i] = true;
        }
        for (var i = 0; i < lines.Count; i++)
        {
            if (lines[i].Box is not { } sb || !SpeakerName.Split(lines[i].Text).HasName) continue;
            var speaker = sb.PlaceIn(area);
            keep[i] = true;
            for (var j = 0; j < lines.Count; j++)
            {
                if (j == i || lines[j].Box is not { } cb) continue;
                var c = cb.PlaceIn(area);
                if (c.Top > speaker.Top && c.Top - speaker.Bottom < Math.Max(0.02, speaker.Height * 1.5))
                {
                    keep[j] = true;
                    break;
                }
            }
        }
        return keep.All(k => k) ? reading : new OcrReading(lines.Where((_, i) => keep[i]));
    }
}
