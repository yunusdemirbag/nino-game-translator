// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>Hazırlık zincirinin bir adımı: ad (yalnız ölçüm kaydı için) ve görüntü süzgeci.</summary>
public sealed record OcrPreparation(string Name, Func<BgraFrame, BgraFrame> Apply);

/// <summary>
/// Hazırlıklı okuma ve okuma seçimi (platformdan bağımsız; Windows okuyucusu kullanır). Yazı tanıma çağrısı
/// <c>recognize</c> arkasındadır: tek bir ham okuma (40 pikselden küçük görüntüde boş okuma döner). Altı hazırlıktan
/// geçen okumalardan pakette birebir bulunan, sözlük puanı en yüksek olan ya da eski kurala göre (beyaz yazı / ham)
/// iyisi seçilir. Bir örnek aynı anda tek okuma yapar varsayılır; sayaçlar örnek başınadır.
/// </summary>
public sealed class PreparedReader : ITextReader
{
    /// <summary>Okuma yapılmayan en küçük boyut.</summary>
    public const int MinSize = 40;

    /// <summary>Iska sınırı: art arda bu kadar okuma pakette bulunamazsa zincir seyrekleşir.</summary>
    public const int MissLimit = 30;

    /// <summary>Seyrek kipte tam zincirin denendiği aralık.</summary>
    public const int SparseEvery = 8;

    readonly Func<BgraFrame, OcrReading> _recognize;
    readonly Func<string, bool>? _isKnownLine;
    readonly Func<string, int>? _dictionaryScore;
    readonly bool _autoLevel;
    readonly IReadOnlyList<OcrPreparation> _chain;
    readonly object _lock = new();
    int _misses;
    int _sparse;

    /// <summary>Hazırlıklı okuyucu.</summary>
    /// <param name="recognize">Tek ham okuma (platformun yazı tanıması).</param>
    /// <param name="isKnownLine">Metin paketteki bir satırla birebir eşleşiyor mu (yoksa null).</param>
    /// <param name="dictionaryScore">Sözlük puanı (Windows'ta yalnız "en" oyunlarında; yoksa null).</param>
    /// <param name="autoLevel">Otomatik seviye (açık varsayılan).</param>
    /// <param name="coloredWords">Renkli sözcük hazırlığı (açık varsayılan).</param>
    public PreparedReader(Func<BgraFrame, OcrReading> recognize, Func<string, bool>? isKnownLine = null,
        Func<string, int>? dictionaryScore = null, bool autoLevel = true, bool coloredWords = true)
    {
        _recognize = recognize;
        _isKnownLine = isKnownLine;
        _dictionaryScore = dictionaryScore;
        _autoLevel = autoLevel;
        _chain = StandardChain(coloredWords);
    }

    /// <summary>Hazırlık listesi, sırasıyla: G1, G2, B (beyaz), G3, GR (renkli), H (ham).</summary>
    public static IReadOnlyList<OcrPreparation> StandardChain(bool coloredWords = true)
    {
        var list = new List<OcrPreparation>
        {
            new("G1", f => TextImageFilters.ShadowText(f, 5, 200, 60, 80)),
            new("G2", f => TextImageFilters.ShadowText(f, 4, 200, 45, 80)),
            new("B", f => TextImageFilters.WhiteText(f, 5, 200, 45, 110)),
            new("G3", f => TextImageFilters.ShadowText(f, 3, 150, 45, 110)),
        };
        if (coloredWords) list.Add(new("GR", f => TextImageFilters.ShadowText(f, 5, 200, 60, 80, colored: true)));
        list.Add(new("H", f => f));
        return list;
    }

    /// <summary>Her karede denenen okumalar (ad, okuma); ölçüm için.</summary>
    public event Action<IReadOnlyList<(string Name, OcrReading Reading)>>? Tried;

    /// <summary>Art arda pakette bulunamayan okuma sayısı.</summary>
    public int Misses { get { lock (_lock) return _misses; } }

    /// <inheritdoc />
    public string ReadText(BgraFrame image) => string.Join(" ", ReadLines(image, true).Lines.Select(l => l.Text));

    /// <inheritdoc />
    public string ReadText(BgraFrame image, bool deep) => ReadText(image);

    /// <inheritdoc />
    public OcrReading ReadLines(BgraFrame image, bool deep) =>
        deep ? DeepRead.Read(image, i => Read(i, false), i => Read(i, true)) : Read(image, false);

    bool Matches(OcrReading reading)
    {
        if (_isKnownLine is not { } known) return false;
        if (reading.Lines.Count > 1 && known(string.Join(" ", reading.Lines.Select(l => l.Text)))) return true;
        return reading.Lines.Any(l => l.Text.Trim().Length > 2 && known(l.Text.Trim()));
    }

    static bool HasText(OcrReading r) => r.Text.Trim().Length >= 3;

    /// <summary>Tek okuma (zincirle); <paramref name="fallback"/> derin okumanın büyütülmüş yedekleri içindir (zincirsiz).</summary>
    public OcrReading Read(BgraFrame image, bool fallback)
    {
        if (image.Width < MinSize || image.Height < MinSize) return _recognize(image);
        var leveled = _autoLevel ? TextImageFilters.AutoLevel(image) : image;
        bool fullChain;
        lock (_lock)
        {
            fullChain = !fallback && (_dictionaryScore is not null || (_isKnownLine is not null && (_misses < MissLimit
                || ++_sparse % SparseEvery == 0)));
        }
        var tried = new List<(string Name, OcrReading Reading)>();
        OcrReading? selected = null;
        var fromPack = false;
        if (fullChain)
        {
            var textSeen = false;
            for (var i = 0; i < _chain.Count; i++)
            {
                var prep = _chain[i];
                var reading = _recognize(prep.Apply(leveled));
                tried.Add((prep.Name, reading));
                if (_isKnownLine is not null && selected is null && Matches(reading))
                {
                    selected = reading;
                    fromPack = true;
                    if (_dictionaryScore is null) break;
                }
                if (HasText(reading)) textSeen = true;
                if (prep.Name == "B" && !textSeen) break;
            }
        }
        var dict = _dictionaryScore;
        if (selected is not null && dict is not null)
        {
            var key = TextKey.Of(selected.Text);
            var score = dict(selected.Text);
            foreach (var (_, r) in tried)
            {
                var k = TextKey.Of(r.Text);
                if (k.Length > key.Length && k.StartsWith(key + " ", StringComparison.Ordinal) && dict(r.Text) > score)
                {
                    selected = r;
                    key = k;
                    score = dict(r.Text);
                }
            }
        }
        if (selected is null && dict is not null && tried.Any(t => HasText(t.Reading)))
        {
            var bestScore = int.MinValue;
            foreach (var (_, r) in tried)
            {
                var s = HasText(r) ? dict(r.Text) : int.MinValue;
                if (selected is null || s > bestScore)
                {
                    selected = r;
                    bestScore = s;
                }
            }
            if (_isKnownLine is not null) lock (_lock) _misses++;
        }
        if (selected is null)
        {
            var raw = tried.FirstOrDefault(t => t.Name == "H").Reading ?? _recognize(leveled);
            var white = tried.FirstOrDefault(t => t.Name == "B").Reading ?? _recognize(TextImageFilters.WhiteText(leveled));
            selected = OcrJunk.Score(white.Text) > OcrJunk.Score(raw.Text) ? white : raw;
            if (fullChain && HasText(selected)) lock (_lock) _misses++;
        }
        if (fromPack) lock (_lock) _misses = 0;
        if (tried.Count > 0) Tried?.Invoke(tried);
        return selected;
    }
}
