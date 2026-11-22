// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Linux.Imaging;

namespace Nino.Linux.Ocr;

/// <summary>Gri görüntüden sözcük satırları çıkaran motor (gerçekte Tesseract; sınamada sahte).</summary>
public interface IWordRecognizer : IDisposable
{
    List<List<OcrWord>> Recognize(byte[] gray, int width, int height);
}

/// <summary>
/// Altyazı bölgesini Tesseract ile okur. Tesseract oyun görüntüsünün tamamında yavaştır ve zeminden harf uydurur;
/// bu yüzden önce yalnız beyaz yazı bırakılmış görüntü okunur (oyun altyazılarının çoğu beyazdır). Beyaz yazı
/// bulunursa çevresi bir de olduğu gibi okunur ki renkli konuşmacı adı ya da açık zeminde kaçan sözcükler
/// yakalansın; daha sözcüğe benzeyen okuma seçilir. Bölgenin tamamı olduğu gibi yalnız derin okumada ya da renkli
/// bir altyazı ekrandayken okunur.
/// </summary>
public sealed class TesseractReader : IDisposable
{
    /// <summary>Bundan küçük görüntüde okunacak bir altyazı olamaz.</summary>
    public const int MinimumSide = 40;

    /// <summary>Kısa satır araması için ortadaki şeridin genişliği ve büyütme katı.</summary>
    public const double CenterStrip = 0.4;
    public const int CenterZoom = 2;

    private readonly IWordRecognizer engine;
    private readonly IOcrRules rules;
    private readonly WordFilter filter;
    private readonly OcrDump? dump;
    private bool colored;

    public TesseractReader(IWordRecognizer engine, IOcrRules rules, WordFilter filter, string dataName)
        : this(engine, rules, filter, dataName, OcrDump.FromEnvironment()) { }

    internal TesseractReader(IWordRecognizer engine, IOcrRules rules, WordFilter filter, string dataName, OcrDump? dump)
    {
        this.engine = engine;
        this.rules = rules;
        this.filter = filter;
        this.dump = dump;
        DataName = dataName;
    }

    /// <summary>Kullanılan Tesseract verisinin adı (oyun dilinin verisi yoksa İngilizce).</summary>
    public string DataName { get; }

    /// <summary>Son okumada renkli altyazı bulundu: ekranda kaldıkça her karede olduğu gibi de okunur.</summary>
    public bool InColorMode => colored;

    /// <summary>
    /// Oyun dili için okuyucu açar; dilin verisi yoksa İngilizce veriyle dener. Kütüphane ya da veri hiç yoksa null.
    /// </summary>
    public static TesseractReader? Open(string language, IOcrRules rules)
    {
        var wanted = TesseractLanguage.For(language);
        var engine = TesseractEngine.Open(wanted);
        if (engine is null && wanted != TesseractLanguage.English) engine = TesseractEngine.Open(TesseractLanguage.English);
        return engine is null ? null : new TesseractReader(engine, rules, WordFilter.FromEnvironment(), engine.DataName);
    }

    /// <summary>Oyun dilinin kendi Tesseract verisi kurulu mu (panelde "yazı tanıma yok" uyarısı buna bakar).</summary>
    public static bool IsAvailable(string language) => TesseractEngine.CanOpen(TesseractLanguage.For(language));

    public OcrReading Read(BgraPicture picture, bool deep)
    {
        if (picture.Width < MinimumSide || picture.Height < MinimumSide) return OcrReading.Nothing;

        var white = ReadWhite(picture);
        if (!white.IsEmpty)
        {
            colored = false;
            var around = ReadSurroundings(picture, white);
            return rules.WordLikeness(around.Text) > rules.WordLikeness(white.Text) ? around : white;
        }
        if (!deep && !colored) return OcrReading.Nothing;

        var whole = ReadAsIs(picture);
        colored = !whole.IsEmpty;
        if (colored || !deep) return whole;

        // Geniş bölgede "Go!" gibi kısa satırlar kaybolabilir; altyazılar ortalı olduğundan orta şerit büyütülür.
        var stripWidth = (int)(picture.Width * CenterStrip);
        var left = (picture.Width - stripWidth) / 2;
        var strip = rules.Enlarge(picture.Cut(left, 0, stripWidth, picture.Height), CenterZoom);
        var place = new OcrBox((double)left / picture.Width, 0, (double)(left + stripWidth) / picture.Width, 1);
        return ReadWhite(strip).Relocated(place);
    }

    private OcrReading ReadWhite(BgraPicture picture) =>
        Recognize(rules.KeepWhiteText(picture).Luma(inverted: false), picture.Width, picture.Height);

    private OcrReading ReadAsIs(BgraPicture picture) =>
        Recognize(picture.Luma(inverted: true), picture.Width, picture.Height);

    /// <summary>Bulunan yazının satırları boyunca, üstten ve alttan birer satır payıyla bandı olduğu gibi okur.</summary>
    private OcrReading ReadSurroundings(BgraPicture picture, OcrReading found)
    {
        if (found.Bounds is not { } bounds) return OcrReading.Nothing;
        var lineHeight = found.Lines.Where(line => line.Box is not null).Max(line => line.Box!.Value.Height);
        var top = Math.Max(0, (int)((bounds.Top - lineHeight) * picture.Height));
        var bottom = Math.Min(picture.Height, (int)Math.Ceiling((bounds.Bottom + lineHeight) * picture.Height));
        if (bottom - top < MinimumSide) return OcrReading.Nothing;
        var band = picture.Cut(0, top, picture.Width, bottom - top);
        var place = new OcrBox(0, (double)top / picture.Height, 1, (double)bottom / picture.Height);
        return ReadAsIs(band).Relocated(place);
    }

    private OcrReading Recognize(byte[] gray, int width, int height)
    {
        var raw = engine.Recognize(gray, width, height);
        dump?.Save(gray, width, height, raw, filter);
        var lines = raw
            .SelectMany(line => LineBuilder.Build(filter.Keep(line), width, height, rules))
            .OrderBy(line => line.Box?.Top ?? 0)
            .ToArray();
        return lines.Length == 0 ? OcrReading.Nothing : new OcrReading(lines);
    }

    public void Dispose() => engine.Dispose();
}
