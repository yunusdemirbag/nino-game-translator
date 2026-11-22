// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Linux.Ocr;
using CoreReading = Nino.Core.Reading.OcrReading;

namespace Nino.Linux.Core;

/// <summary>
/// Çekirdeğin okuma hattına Tesseract: <see cref="ITextReader"/> uygulaması. Süre günlüğü yalnız okunan metin
/// değişince yazılır. Okuyucu dil değişmedikçe bir kez açılır.
/// </summary>
public sealed class TesseractTextReader : ITextReader, IDisposable
{
    private readonly TesseractReader reader;
    private readonly ReadTiming timing;
    private readonly Lock gate = new();

    public TesseractTextReader(TesseractReader reader, ReadTiming timing)
    {
        this.reader = reader;
        this.timing = timing;
    }

    public string Language => reader.DataName;

    public string ReadText(BgraFrame image) => ReadLines(image, deep: true).Text;

    public string ReadText(BgraFrame image, bool deep) => ReadLines(image, deep).Text;

    public CoreReading ReadLines(BgraFrame image, bool deep)
    {
        var picture = Pictures.From(image);
        // Renkli kip okuyucunun durumudur; aynı anda iki okuma onu karıştırmasın.
        lock (gate) return Pictures.ToReading(timing.Measure(() => reader.Read(picture, deep), deep));
    }

    public void Dispose() => reader.Dispose();
}

/// <summary>Oyun diline göre okuyucuyu bir kez açar; dil değişince eskisini kapatır.</summary>
public sealed class ReaderCache(IOcrRules rules, Hosting.Journal journal) : IDisposable
{
    private TesseractTextReader? current;
    private string? language;
    private readonly Lock gate = new();

    public ITextReader? For(string gameLanguage)
    {
        lock (gate)
        {
            if (current is not null && language == gameLanguage) return current;
            current?.Dispose();
            current = null;
            language = gameLanguage;
            if (TesseractReader.Open(gameLanguage, rules) is not { } opened)
            {
                journal.Write("ocr", "Tesseract başlatılamadı; libtesseract kütüphanesi ile İngilizce dil verisi (tesseract-ocr-eng paketi) gerekli.");
                return null;
            }
            current = new TesseractTextReader(opened, new ReadTiming(journal));
            return current;
        }
    }

    public void Dispose()
    {
        lock (gate) current?.Dispose();
    }
}
