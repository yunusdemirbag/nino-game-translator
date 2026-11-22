// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Translation;

/// <summary>
/// Kısa satır bağlamı (çeviri tarifi §4.1): "bu satırdan önce gösterilen satır" kaydı ve <c>***</c> ayracı.
/// </summary>
public sealed class ShortLineContext
{
    /// <summary>Önceki satırın bağlam sayıldığı en uzun süre.</summary>
    public static readonly TimeSpan
        MaxAge = TimeSpan.FromSeconds(20);

    /// <summary>Bağlam ile cümle arasındaki ayraç.</summary>
    public const string
        Separator = " *** ";

    readonly TimeProvider _clock;
    readonly object _gate = new();
    string? _text;
    string? _context;
    DateTimeOffset _seen;

    public ShortLineContext(TimeProvider? clock = null) => _clock = clock ?? TimeProvider.System;

    /// <summary>Satırın bağlamını (önceki satır) verir ve kaydı günceller.</summary>
    public string? ContextFor(string line)
    {
        lock (_gate)
        {
            var now = _clock.GetUtcNow();
            if (_text is not null && string.Equals(_text, line, StringComparison.Ordinal))
            {
                _seen = now;
                return _context;
            }
            var context = _text is not null && now - _seen <= MaxAge ? _text : null;
            _text = line;
            _context = context;
            _seen = now;
            return context;
        }
    }

    /// <summary>Kısa cümle: harf içeren sözcük sayısı 1–3.</summary>
    public static bool IsShort(string sentence)
    {
        var words = sentence.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(w => w.Any(char.IsLetter));
        return words is >= 1 and <= 3;
    }

    /// <summary>Bağlamlı çıktıdan kısa cümlenin çevirisini (<c>***</c> sonrasını) alır; alınamazsa null.</summary>
    public static string? AfterSeparator(string
        output, string source)
    {
        var first = output.IndexOf("***", StringComparison.Ordinal);
        if (first < 0 || output.IndexOf("***", first + 3, StringComparison.Ordinal) >= 0) return null;
        var before = output[..first];
        var after = output[(first + 3)..];
        if (after.StartsWith('*') ||
            before.EndsWith('*')) return null;
        after = after.Trim();
        if (!before.Any(char.IsLetter) ||
            !after.Any(char.IsLetter)) return null;
        if (after.Length > source.Length * 3 + 20) return null;
        return after;
    }
}

/// <summary>
/// Ücretsiz çevirinin cümle başına metin hattı (çeviri tarifi §4): hazır satır, hazırlama (büyük harf düzeni, argo,
/// oyun deyimleri), bağlamla ve tek başına deneme, terim koruma, Türkçe düzeltme. Model çağrısı dışarıdan verilir.
/// </summary>
public sealed class FreeTextPipeline
{
    readonly bool _turkish;

    /// <param name="target">Hedef dil kodu; sözlük ve Türkçe kuralları yalnız <c>tr</c>'de.</param>
    public FreeTextPipeline(string target) => _turkish = TargetLanguages.Code(target) == "tr";

    /// <summary>Hedef Türkçe mi.</summary>
    public bool IsTurkish => _turkish;

    /// <summary>Önbellek anahtarı (§4.4).</summary>
    public string CacheKey(string sentence, string? context, Glossary glossary)
    {
        if (!_turkish) return sentence;
        var basis = context is null ? sentence : context + "\u001F" + sentence;
        var marked = glossary.FindTerms(basis).Count > 0 || glossary.Rewrites(sentence)
            || (context is not null && glossary.Rewrites(context));
        return marked ? glossary.Fingerprint + "\u001F" + basis : basis;
    }

    string Prepare(string text, Glossary glossary, IReadOnlySet<string> known) =>
        GameIdioms.Apply(glossary.FlattenSlang(CapsNormalizer.Normalize(text, known)));

    /// <summary>Tek cümleyi çevirir.</summary>
    /// <param name="sentence">Bölücünün çevrilecek parçası.</param>
    /// <param name="context">Kısa cümlenin bağlamı (önceki cümle) ya da null.</param>
    /// <param name="glossary">Sözlük (Türkçe dışında kullanılmaz).</param>
    /// <param name="known">Büyük harf düzeninde baş harfi büyük kalacak adlar (küçük harfle).</param>
    /// <param name="model">Model çağrısı (metin → çeviri).</param>
    public string Translate(string sentence, string? context, Glossary glossary, IReadOnlySet<string> known,
        Func<string, string> model)
    {
        if (!_turkish) return model(GameIdioms.Apply(CapsNormalizer.Normalize(sentence, known)));

        if (glossary.ReadyLine(sentence) is { } ready) return TurkishPolish.Polish(sentence, ready);
        var apostrophe = sentence.Contains('’') ? '’' : '\'';

        if (context is not null)
        {
            var shield = new TermShield(glossary, sentence, context);
            var shieldedContext = shield.Protect(Prepare(context, glossary, known));
            var shieldedSentence = shield.Protect(Prepare(sentence, glossary, known));
            var output = model(shieldedContext.Text + ShortLineContext.Separator + shieldedSentence.Text);
            if (ShortLineContext.AfterSeparator(output, sentence) is { } after
                && shield.Restore(after, shieldedSentence.Names, shield.AllNames, apostrophe) is { } restored)
                return TurkishPolish.Polish(sentence, restored);
        }

        var alone = new TermShield(glossary, sentence);
        var prepared = Prepare(sentence, glossary, known);
        var shielded = alone.Protect(prepared);
        var result = model(shielded.Text);
        if (shielded.Names.Count == 0) return TurkishPolish.Polish(sentence, result);
        if (alone.Restore(result, shielded.Names, alone.AllNames, apostrophe) is { } back)
            return TurkishPolish.Polish(sentence, back);
        return TurkishPolish.Polish(sentence, model(prepared));
    }
}
