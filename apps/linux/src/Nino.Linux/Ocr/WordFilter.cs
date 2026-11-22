// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Linux.Ocr;

/// <summary>Tesseract'ın bulduğu bir sözcük: metin, güven (0–100) ve piksel kutusu.</summary>
public readonly record struct OcrWord(string Text, float Confidence, int Left, int Top, int Right, int Bottom)
{
    /// <summary>Sözcüğün ağırlığı: harf ve rakam sayısı, en az 1.</summary>
    public int Weight => Math.Max(1, LetterCount);

    public int LetterCount => Text.Count(char.IsLetterOrDigit);
}

/// <summary>
/// Oyun görüntüsündeki dokulardan uydurulan harfleri ayıklar. Gerçek altyazıda sözcüklerin çoğu yüksek güvenle
/// okunur; uydurma satırlarda yüksek güvenli sözcük hemen hiç olmaz.
/// </summary>
public sealed class WordFilter
{
    public WordFilter(float strong, float edge)
    {
        Strong = strong;
        Edge = edge;
    }

    /// <summary>Bu güvenin üstündeki sözcüğe güvenilir.</summary>
    public float Strong { get; }

    /// <summary>Satırın uçlarında bu güvenden düşük parçalar kırpılır.</summary>
    public float Edge { get; }

    public static WordFilter FromEnvironment() =>
        new(Number("NINO_OCR_STRONG", 75), Number("NINO_OCR_MIN_WORD", 60));

    private static float Number(string variable, float fallback) =>
        float.TryParse(Environment.GetEnvironmentVariable(variable), NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            ? value : fallback;

    /// <summary>
    /// Satırı tutar ya da atar. Kesin sözcüklerin ağırlığı satırın yarısına ulaşmıyorsa ya da satırda ikiden az
    /// harf/rakam varsa satır atılır. Tutulan satırın yalnız başı ve sonu kırpılır: Tesseract doğru okuduğu bir
    /// sözcüğe de bazen düşük güven verdiğinden ortaya dokunulmaz.
    /// </summary>
    public IReadOnlyList<OcrWord> Keep(IReadOnlyList<OcrWord> line)
    {
        if (line.Count is 0) return line;
        var total = 0;
        var sure = 0;
        var letters = 0;
        foreach (var word in line)
        {
            total += word.Weight;
            letters += word.LetterCount;
            if (word.Confidence >= Strong) sure += word.Weight;
        }
        if (letters < 2 || sure * 2 < total) return Array.Empty<OcrWord>();

        var first = 0;
        while (first < line.Count && line[first].Confidence < Edge) first++;
        if (first == line.Count) return Array.Empty<OcrWord>();
        var last = line.Count - 1;
        while (line[last].Confidence < Edge) last--;
        return line.Skip(first).Take(last - first + 1).ToArray();
    }

    /// <summary>
    /// Tek başına büyük "I" çoğu kez dik çizgi okunur ("| know", "|'ll"). Sözcük yalnız harf ve noktalamadan
    /// oluşuyorsa içindeki dik çizgiler I'ya çevrilir.
    /// </summary>
    private const string WordMarks = "|'’.,!?";

    public static string RepairCapitalI(string word)
    {
        if (word.IndexOf('|') < 0) return word;
        return word.All(c => char.IsLetter(c) || WordMarks.Contains(c)) ? word.Replace('|', 'I') : word;
    }
}
