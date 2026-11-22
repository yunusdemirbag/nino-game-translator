// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices.WindowsRuntime;
using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using OcrLine = Nino.Core.Reading.OcrLine;
using OcrWord = Nino.Core.Reading.OcrWord;

namespace Nino.App.Services;

/// <summary>
/// Windows yazı tanıması (okuma-hatti §3): her okuyucu kendi <see cref="OcrEngine"/>'ini bir kilitle sıraya sokar
/// (bir motor aynı anda iki okuma yapamaz). Altyazı okuyucusu ham tanımayı <see cref="PreparedReader"/>'a verir
/// (hazırlık zinciri, paket eşleşmesi, sözlük puanı); tek geçişli okuyucu görüntüyü olduğu gibi bir kez okur.
/// İngilizce oyunda ve yazım denetleyicisi çalışıyorsa sözlük puanı ve okuma kalitesi ölçüleri açılır.
/// </summary>
public sealed class WindowsOcrReaderFactory : ITextReaderFactory
{
    readonly Func<string, bool>? _isKnownLine;
    readonly Func<bool> _spellingWorks;
    readonly ISpellDictionary _dictionary;

    /// <param name="isKnownLine">Metin paketteki bir satırla birebir eşleşiyor mu (paket kütüphanesi varsa).</param>
    /// <param name="dictionary">Yazım sözlüğü; yoksa <see cref="WindowsSpellDictionary.Shared"/>.</param>
    /// <param name="spellingWorks">Yazım denetleyicisi çalışıyor mu; yoksa paylaşılan sözlüğe sorulur.</param>
    public WindowsOcrReaderFactory(Func<string, bool>? isKnownLine, ISpellDictionary? dictionary = null,
        Func<bool>? spellingWorks = null)
    {
        _isKnownLine = isKnownLine;
        _dictionary = dictionary ?? WindowsSpellDictionary.Shared;
        _spellingWorks = spellingWorks ?? (() => WindowsSpellDictionary.Shared.IsWorking);
    }

    SpellScoring? Scoring(string language) =>
        OcrLanguageRules.UsesSpelling(language) && _spellingWorks() ? new SpellScoring(_dictionary) : null;

    /// <inheritdoc />
    public ITextReader? Create(string language)
    {
        if (CreateEngine(language) is not { } engine) return null;
        var ocr = new LockedOcr(engine);
        var scoring = Scoring(language);
        return new PreparedReader(ocr.Recognize, _isKnownLine, scoring is null ? null : scoring.Score);
    }

    /// <inheritdoc />
    public ITextReader? CreateSinglePass(string language) =>
        CreateEngine(language) is { } engine ? new SinglePassReader(new LockedOcr(engine)) : null;

    /// <inheritdoc />
    public bool HasLanguagePack(string language) => FindLanguage(language) is not null;

    /// <inheritdoc />
    public ReadingQuality? QualityFor(string language) =>
        Scoring(language) is { } s ? new ReadingQuality(s.IsMisread, s.Score) : null;

    /// <inheritdoc />
    public byte[]? SmallJpeg(BgraFrame frame, int maxWidth, int quality) => WicJpegEncoder.SmallJpeg(frame, maxWidth, quality);

    /// <summary>Oyun dilinin kurulu OCR dili (etiketin başı eşleşen ilk kurulu dil).</summary>
    static Language? FindLanguage(string language)
    {
        var tag = (language ?? "").Trim();
        if (tag.Length == 0) return null;
        try
        {
            var primary = tag.Split('-')[0];
            return OcrEngine.AvailableRecognizerLanguages.FirstOrDefault(l =>
                       string.Equals(l.LanguageTag, tag, StringComparison.OrdinalIgnoreCase))
                   ?? OcrEngine.AvailableRecognizerLanguages.FirstOrDefault(l =>
                       string.Equals(l.LanguageTag.Split('-')[0], primary, StringComparison.OrdinalIgnoreCase));
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>Oyun dilinin motoru; olmazsa kullanıcının profil dillerinden.</summary>
    static OcrEngine? CreateEngine(string language)
    {
        try
        {
            if (FindLanguage(language) is { } lang && OcrEngine.TryCreateFromLanguage(lang) is { } engine) return engine;
            return OcrEngine.TryCreateFromUserProfileLanguages();
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>Tek motor, tek okuma: bütün okumalar (derin okumanın paralel yedekleri dahil) bir kilitte sıralanır.</summary>
    sealed class LockedOcr(OcrEngine engine)
    {
        readonly object _gate = new();

        public OcrReading Recognize(BgraFrame image)
        {
            var max = (int)OcrEngine.MaxImageDimension;
            if (image.Width < PreparedReader.MinSize || image.Height < PreparedReader.MinSize
                || image.Width > max || image.Height > max) return OcrReading.Empty;
            lock (_gate)
            {
                try
                {
                    using var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, image.Width, image.Height,
                        BitmapAlphaMode.Premultiplied);
                    bitmap.CopyFromBuffer(image.Pixels.AsBuffer(0, image.Width * image.Height * 4));
                    // Zaman uyumsuz işlem başlatılır ve beklenir (okuma iş parçacıklarında).
                    var result = Thread.CurrentThread.GetApartmentState() == ApartmentState.STA
                        ? Task.Run(() => engine.RecognizeAsync(bitmap).AsTask()).GetAwaiter().GetResult()
                        : engine.RecognizeAsync(bitmap).AsTask().GetAwaiter().GetResult();
                    var lines = new List<OcrLine>();
                    foreach (var line in result.Lines)
                    {
                        var words = line.Words.Select(w => new OcrWord(w.Text, w.BoundingRect.X, w.BoundingRect.Y,
                            w.BoundingRect.X + w.BoundingRect.Width, w.BoundingRect.Y + w.BoundingRect.Height)).ToList();
                        lines.AddRange(WordLineSplitter.Split(line.Text, words, image.Width, image.Height));
                    }
                    return new OcrReading(WordLineSplitter.SortByTop(lines));
                }
                catch (Exception)
                {
                    return OcrReading.Empty;
                }
            }
        }
    }

    /// <summary>Telefon/harita için: hazırlık yok, büyütme yok, seviye yok.</summary>
    sealed class SinglePassReader(LockedOcr ocr) : ITextReader
    {
        public string ReadText(BgraFrame image) => string.Join(" ", ocr.Recognize(image).Lines.Select(l => l.Text));

        public string ReadText(BgraFrame image, bool deep) => ReadText(image);

        public OcrReading ReadLines(BgraFrame image, bool deep) => ocr.Recognize(image);
    }
}
