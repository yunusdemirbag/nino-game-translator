// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Frozen;
using System.Globalization;
using System.Text.Json;

namespace Nino.Core.Text;

/// <summary>Ekrana metin veren her şeyin istediği arayüz: anahtardan o anki arayüz dilindeki metin.</summary>
public interface ITextSource
{
    /// <summary>Arayüz dili ("tr", "en", "fil" …).</summary>
    string Language { get; }

    /// <summary>Anahtarın metni; bu dilde yoksa İngilizcesi, o da yoksa anahtarın kendisi.</summary>
    string Get(string key);

    /// <summary>Anahtarın metni, yer tutucuları (<c>%@</c>, <c>%lld</c>, <c>%1$@</c>) değerlerle doldurulmuş.</summary>
    string Format(string key, params object?[] values);
}

/// <summary>
/// Gömülü metin kataloğu (<c>text/&lt;dil&gt;.json</c>: düz "anahtar → metin" nesnesi). Katalog bir dil için bir kez
/// kurulur; anahtarlar dillerde aynıdır. Platformdan bağımsızdır (Windows ve Linux arayüzleri ile denetleyici kullanır).
/// </summary>
public sealed class TextCatalog : ITextSource
{
    private readonly FrozenDictionary<string, string> _values;
    private readonly FrozenDictionary<string, string> _english;

    private TextCatalog(string language, FrozenDictionary<string, string> values, FrozenDictionary<string, string> english)
    {
        Language = language;
        Culture = UiLanguage.CultureFor(language);
        _values = values;
        _english = english;
    }

    public string Language { get; }

    /// <summary>Dilin kültürü: sayı biçimi ve büyük harf (Türkçede i → İ) için.</summary>
    public CultureInfo Culture { get; }

    /// <summary>Arayüz sağdan sola mı.</summary>
    public bool IsRightToLeft => UiLanguage.IsRightToLeft(Language);

    /// <summary>İngilizce katalogdaki bütün anahtarlar.</summary>
    public IEnumerable<string> Keys => _english.Keys;

    /// <summary>Bu dilin kendi kataloğunda (İngilizceye düşmeden) bu anahtar var mı.</summary>
    public bool HasOwn(string key) => _values.ContainsKey(key);

    /// <summary>Verilen arayüz dilinin kataloğu (bilinmeyen dil İngilizceye düşer).</summary>
    public static TextCatalog For(string language)
    {
        var code = UiLanguage.All.Contains(language) ? language : UiLanguage.FromCultureName(language);
        var english = Load("en");
        return new TextCatalog(code, code == "en" ? english : Load(code), english);
    }

    /// <summary>Sistemin arayüz dilinin kataloğu.</summary>
    public static TextCatalog ForSystem() => For(UiLanguage.FromSystem());

    /// <summary>Elle verilen değerlerle katalog (testler için).</summary>
    public static TextCatalog FromValues(string language, IReadOnlyDictionary<string, string> values,
        IReadOnlyDictionary<string, string>? english = null) =>
        new(language, values.ToFrozenDictionary(StringComparer.Ordinal),
            (english ?? values).ToFrozenDictionary(StringComparer.Ordinal));

    public string Get(string key) =>
        _values.TryGetValue(key, out var v) ? v : _english.TryGetValue(key, out var e) ? e : key;

    public string Format(string key, params object?[] values) => PrintfFormat.Apply(Get(key), Culture, values);

    /// <summary>Metnin arayüz dilinin kültürüyle büyük harfi ("İlk İş" → "İLK İŞ").</summary>
    public string Upper(string key) => Get(key).ToUpper(Culture);

    /// <summary>Gömülü bir dil dosyasını okur. Dosya yoksa boş katalog (İngilizce yoksa hata).</summary>
    internal static FrozenDictionary<string, string> Load(string language)
    {
        var name = $"text/{language}.json";
        using var stream = typeof(TextCatalog).Assembly.GetManifestResourceStream(name);
        if (stream is null)
        {
            if (language == "en") throw new InvalidDataException("Gömülü metin kataloğu bulunamadı: " + name);
            return FrozenDictionary<string, string>.Empty;
        }
        return Parse(stream);
    }

    /// <summary>Düz "anahtar → metin" JSON nesnesini okur; dizge olmayan değerler atlanır.</summary>
    internal static FrozenDictionary<string, string> Parse(Stream json)
    {
        using var doc = JsonDocument.Parse(json);
        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var p in doc.RootElement.EnumerateObject())
            if (p.Value.ValueKind == JsonValueKind.String)
                map[p.Name] = p.Value.GetString()!;
        return map.ToFrozenDictionary(StringComparer.Ordinal);
    }
}
