// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>
/// Yazı okuyucu. Windows'ta Windows.Media.Ocr, Linux'ta Tesseract doldurur. Bir okuyucu örneği aynı anda yalnız bir
/// okuma yapabilir varsayılmalı; uygulama altyazı, ek alan ve telefon/harita için ayrı örnekler kurar.
/// </summary>
public interface ITextReader
{
    /// <summary>Görüntünün düz metni.</summary>
    string ReadText(BgraFrame image);

    /// <summary>Düz metin; <paramref name="deep"/> varsayılanda yok sayılır.</summary>
    string ReadText(BgraFrame image, bool deep) => ReadText(image);

    /// <summary>
    /// Satırlar. "Derin" okuma: hiç satır bulunmazsa büyütülmüş yedek okumalar da denenir (<see cref="DeepRead"/>).
    /// Varsayılanı <see cref="ReadText(BgraFrame, bool)"/>'in metninden yalnız-metin okumadır.
    /// </summary>
    OcrReading ReadLines(BgraFrame image, bool deep) => OcrReading.FromText(ReadText(image, deep));
}

/// <summary>
/// Derin okuma (platformdan bağımsız): görüntü bir kez okunur; satır yoksa iki yedek okuma aynı anda yapılır:
/// ortadaki %40'lık şerit 2 kat büyütülmüş ve bütün görüntü 2 kat büyütülmüş. İkisi de bulursa şeridinki seçilir.
/// Kısa satırlar ("Go!") geniş alanda sık sık hiç bulunmaz; bu adım onları yakalar.
/// </summary>
public static class DeepRead
{
    /// <summary>Şeridin genişlik oranı.</summary>
    public const double StripFraction = 0.4;

    /// <summary>Yedek okumaların büyütme katı.</summary>
    public const int Upscale = 2;

    /// <summary>Şeridin piksel aralığı: x = aşağı(sol), w = yukarı(sol + şerit) − x.</summary>
    public static (int X, int Width) StripOf(int imageWidth)
    {
        var strip = imageWidth * StripFraction;
        var left = (imageWidth - strip) / 2;
        var x = (int)Math.Floor(left);
        var w = (int)Math.Ceiling(left + strip) - x;
        return (x, w);
    }

    /// <summary>
    /// Derin okur. <paramref name="primary"/> ilk (tam) okuma, <paramref name="fallback"/> büyütülmüş yedek okumalar
    /// içindir (Windows'ta yedekler hazırlık zinciri olmadan okunur). Şeridin kutuları görüntünün tamamına göre döner.
    /// </summary>
    public static OcrReading Read(BgraFrame image, Func<BgraFrame, OcrReading> primary,
        Func<BgraFrame, OcrReading>? fallback = null)
    {
        fallback ??= primary;
        var first = primary(image);
        if (!first.IsEmpty) return first;
        if (image.Width == 0 || image.Height == 0) return OcrReading.Empty;
        var (x, w) = StripOf(image.Width);
        var stripBox = new Box((double)x / image.Width, 0, (double)(x + w) / image.Width, 1);
        var stripTask = Task.Run(() =>
            fallback(image.Crop(x, 0, w, image.Height).Upscale(Upscale)).PlaceIn(stripBox));
        var wholeTask = Task.Run(() => fallback(image.Upscale(Upscale)));
        var strip = stripTask.GetAwaiter().GetResult();
        var whole = wholeTask.GetAwaiter().GetResult();
        if (!strip.IsEmpty) return strip;
        return whole.IsEmpty ? OcrReading.Empty : whole;
    }
}

/// <summary>
/// Yazı tanıma motorunun bir satırının sözcükleri (piksel kutularıyla). Satırı geniş boşluklardan ayrı yazılara
/// bölmek için (<see cref="WordLineSplitter"/>).
/// </summary>
public sealed record OcrWord(string Text, double Left, double Top, double Right, double Bottom);

/// <summary>
/// "Ayrı yazı" boşluk kuralı (platformdan bağımsız; Windows ve Linux okuyucuları kullanır). Tanıyıcı soldaki menü
/// ile sağdaki göstergeyi tek satır okuyabilir; ardışık iki sözcük arasındaki boşluk hem satır yüksekliğinin 4
/// katından hem görüntü genişliğinin %12'sinden büyükse orada ayrı satır başlar.
/// </summary>
public static class WordLineSplitter
{
    /// <summary>Boşluk / satır yüksekliği sınırı.</summary>
    public const double HeightFactor = 4;

    /// <summary>Boşluk / görüntü genişliği sınırı.</summary>
    public const double WidthFraction = 0.12;

    /// <summary>Boşluk (piksel) orada satırı ayırır mı.</summary>
    public static bool IsSeparateText(double gapPx, double lineHeightPx, double imageWidthPx) =>
        gapPx > lineHeightPx * HeightFactor && gapPx > imageWidthPx * WidthFraction;

    /// <summary>
    /// Bir motor satırını böler. Satır yüksekliği = sözcük kutularının en yükseği. Her parçanın kutusu sözcük
    /// kutularının birleşimidir (görüntüye oranla). Hiç bölünmediyse metin motorun satır metnidir (boşluksuz yazılan
    /// diller birleşik kalsın); bölündüyse parçanın sözcükleri tek boşlukla. Kırpılır; güven yok.
    /// </summary>
    public static IReadOnlyList<OcrLine> Split(string lineText, IReadOnlyList<OcrWord> words, int imageWidth,
        int imageHeight)
    {
        if (words.Count == 0)
        {
            var t = lineText.Trim();
            return t.Length == 0 ? [] : [new OcrLine(t)];
        }
        var height = words.Max(w => w.Bottom - w.Top);
        var groups = new List<List<OcrWord>> { new() { words[0] } };
        for (var i = 1; i < words.Count; i++)
        {
            var gap = words[i].Left - words[i - 1].Right;
            if (IsSeparateText(gap, height, imageWidth)) groups.Add([]);
            groups[^1].Add(words[i]);
        }
        var result = new List<OcrLine>();
        foreach (var g in groups)
        {
            var text = (groups.Count == 1 ? lineText : string.Join(" ", g.Select(w => w.Text))).Trim();
            var box = new Box(g.Min(w => w.Left) / imageWidth, g.Min(w => w.Top) / imageHeight,
                g.Max(w => w.Right) / imageWidth, g.Max(w => w.Bottom) / imageHeight);
            result.Add(new OcrLine(text, box));
        }
        return result;
    }

    /// <summary>Satırları kutularının üst kenarına göre dizer (yeri olmayan 0; eşitlikte geliş sırası).</summary>
    public static IReadOnlyList<OcrLine> SortByTop(IEnumerable<OcrLine> lines) =>
        lines.Select((l, i) => (l, i)).OrderBy(p => p.l.Box?.Top ?? 0).ThenBy(p => p.i).Select(p => p.l).ToArray();
}
