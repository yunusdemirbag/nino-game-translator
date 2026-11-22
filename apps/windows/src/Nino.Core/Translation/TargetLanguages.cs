// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core.Translation;

/// <summary>Bir hedef dilin bilgileri (çeviri tarifi §13.1).</summary>
/// <param name="Code">İki harfli kod.</param>
/// <param name="NativeName">Kendi adı.</param>
/// <param name="EnglishName">İstemdeki İngilizce adı.</param>
/// <param name="DeepL">DeepL bu dili çeviriyor mu.</param>
/// <param name="FreeModel">Cihaz içi ücretsiz model var mı.</param>
public sealed record TargetLanguage(string Code, string NativeName, string EnglishName, bool DeepL, bool FreeModel);

/// <summary>Hedef diller, sağdan sola gösterim ve "hedefin yazısıyla yazılmış" denetimi.</summary>
public static class TargetLanguages
{
    /// <summary>11 dil; Türkçe ilk.</summary>
    public static IReadOnlyList<TargetLanguage> All { get; } =
    [
        new("tr", "Türkçe", "Turkish", true, true),
        new("ar", "العربية", "Arabic", true, true),
        new("hi", "हिन्दी", "Hindi", false, true),
        new("id", "Bahasa Indonesia", "Indonesian", true, true),
        new("th", "ไทย", "Thai", true, false),
        new("vi", "Tiếng Việt", "Vietnamese", true, true),
        new("ur", "اردو", "Urdu", false, false),
        new("bn", "বাংলা", "Bengali", false, false),
        new("ms", "Bahasa Melayu", "Malay", false, false),
        new("tl", "Filipino", "Filipino", false, false),
        new("nl", "Nederlands", "Dutch", true, true),
    ];

    /// <summary>Dil kodu: ilk iki harf, küçük harf.</summary>
    public static string Code(string? language)
    {
        var code = (language ?? "").Trim().ToLowerInvariant();
        return code.Length > 2 ? code[..2] : code;
    }

    /// <summary>Dilin bilgisi; listede yoksa null.</summary>
    public static TargetLanguage? Find(string? language)
    {
        var code = Code(language);
        return All.FirstOrDefault(l => l.Code == code);
    }

    /// <summary>İstemdeki İngilizce ad; listede yoksa <c>Turkish</c>.</summary>
    public static string EnglishName(string? language) => Find(language)?.EnglishName ?? "Turkish";

    /// <summary>Kendi adı; listede yoksa kod.</summary>
    public static string NativeName(string? language) => Find(language)?.NativeName ?? Code(language);

    /// <summary>Seçilebilir dil mi.</summary>
    public static bool IsSupported(string? language) => Find(language) is not null;

    /// <summary>DeepL bu hedefi çeviriyor mu.</summary>
    public static bool DeepLSupports(string? language) => Find(language)?.DeepL ?? false;

    /// <summary>Ücretsiz model var mı (kaynak <c>en</c> olmalı).</summary>
    public static bool FreeModelSupports(string? source, string? target) =>
        Code(source) == "en" && (Find(target)?.FreeModel ?? false);

    /// <summary>Sağdan sola dil mi (<c>ar</c>, <c>ur</c>).</summary>
    public static bool IsRightToLeft(string? language) => Code(language) is "ar" or "ur";

    /// <summary>Arap harfi mi.</summary>
    public static bool IsArabicLetter(int c) =>
        c is >= 0x0620 and <= 0x064A or >= 0x066E and <= 0x06D3 or >= 0x06FA and <= 0x06FF or >= 0x0750 and <= 0x077F
            or >= 0x08A0 and <= 0x08FF or >= 0xFB50 and <= 0xFDFF or >= 0xFE70 and <= 0xFEFF;

    /// <summary>Arap harfli metinde her paragrafın başına (yoksa) U+200F koyar.</summary>
    public static string ApplyRtlMarks(string text)
    {
        if (!text.EnumerateRunes().Any(r => IsArabicLetter(r.Value))) return text;
        return string.Join("\n", text.Split('\n').Select(p => p.StartsWith('‏') ? p : "‏" + p));
    }

    /// <summary>
    /// Satır hedefin kendi yazısıyla mı yazılmış (çeviri tarifi §13.3): <c>ar</c>/<c>ur</c> Arap harfi, <c>th</c>,
    /// <c>hi</c>, <c>bn</c> kendi yazıları. Türkçede hep hayır.
    /// </summary>
    public static bool IsWrittenInTargetScript(string text, string? target)
    {
        Func<int, bool>? inScript = Code(target) switch
        {
            "ar" or "ur" => IsArabicLetter,
            "th" => c => c is >= 0x0E00 and <= 0x0E7F,
            "hi" => c => c is >= 0x0900 and <= 0x097F,
            "bn" => c => c is >= 0x0980 and <= 0x09FF,
            _ => null,
        };
        return inScript is not null && text.EnumerateRunes().Any(r => inScript(r.Value));
    }
}

/// <summary>
/// En dıştaki katman: hedefin yazısıyla yazılmış satırı çevirmeden geri verir (çeviri tarifi §13.3). Toplu çeviriyi
/// içe geçirir: hedef yazılı parçaları kendisi ayırır, kalanları içteki çevirmenin toplu çevirisine verir (§1.5).
/// </summary>
public sealed class ScriptGuardTranslator(ITranslator inner, string target) : ITranslator
{
    /// <summary>İçteki çevirmen.</summary>
    public ITranslator Inner => inner;

    /// <inheritdoc />
    public string EngineName => inner.EngineName;

    /// <inheritdoc />
    public bool SupportsPretranslation => inner.SupportsPretranslation;

    /// <inheritdoc />
    public bool SupportsBatch => inner.SupportsBatch;

    /// <inheritdoc />
    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
        TargetLanguages.IsWrittenInTargetScript(text, target)
            ? Task.FromResult(new TranslationResult(text, TranslationOrigin.AlreadyTarget))
            : inner.TranslateAsync(text, cancellationToken);

    /// <inheritdoc />
    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) =>
        TargetLanguages.IsWrittenInTargetScript(text, target)
            ? Task.CompletedTask
            : inner.PretranslateAsync(text, cancellationToken);

    /// <inheritdoc />
    public async Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken
            cancellationToken = default)
    {
        var results = new string[texts.Count];
        var pending = new List<int>();
        for (var i = 0; i < texts.Count; i++)
        {
            if (TargetLanguages.IsWrittenInTargetScript(texts[i], target)) results[i] = texts[i];
            else pending.Add(i);
        }
        if (pending.Count > 0)
        {
            var translated = await inner.TranslateBatchAsync(pending.Select(i => texts[i]).ToList(), cancellationToken)
                .ConfigureAwait(false);
            for (var k = 0; k < pending.Count; k++) results[pending[k]] = translated[k];
        }
        return results;
    }
}
