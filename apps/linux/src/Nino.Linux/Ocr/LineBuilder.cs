// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Linux.Ocr;

/// <summary>Süzgeçten geçen sözcüklerden satırlar ve kutuları.</summary>
public static class LineBuilder
{
    /// <summary>Tesseract kutuları harflere sıkı oturur; satır kutusu üstten ve alttan bu oranda büyütülür.</summary>
    public const double VerticalPad = 0.2;

    /// <summary>
    /// Bir Tesseract satırını bir ya da daha çok satıra çevirir. Aynı hizada ama aralarında sözcük arası olamayacak
    /// kadar boşluk bulunan yazılar (soldaki menü, sağdaki gösterge) ayrı satır olur.
    /// </summary>
    public static IEnumerable<OcrLine> Build(IReadOnlyList<OcrWord> words, int imageWidth, int imageHeight, IOcrRules rules)
    {
        if (words.Count is 0) yield break;
        var tallest = words.Max(word => word.Bottom - word.Top);
        var start = 0;
        for (var i = 1; i <= words.Count; i++)
        {
            var split = i == words.Count || rules.IsSeparateText(words[i].Left - words[i - 1].Right, tallest, imageWidth);
            if (!split) continue;
            yield return Line(words, start, i, imageWidth, imageHeight);
            start = i;
        }
    }

    private static OcrLine Line(IReadOnlyList<OcrWord> words, int from, int to, double width, double height)
    {
        var text = new List<string>(to - from);
        OcrBox? box = null;
        for (var i = from; i < to; i++)
        {
            var word = words[i];
            text.Add(word.Text);
            var own = new OcrBox(word.Left / width, word.Top / height, word.Right / width, word.Bottom / height);
            box = box?.Merge(own) ?? own;
        }
        if (box is { } tight)
        {
            var pad = tight.Height * VerticalPad;
            box = tight with { Top = Math.Max(0, tight.Top - pad), Bottom = Math.Min(1, tight.Bottom + pad) };
        }
        return new OcrLine(string.Join(' ', text), box);
    }
}
