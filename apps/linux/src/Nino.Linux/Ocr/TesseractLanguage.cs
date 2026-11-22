// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Linux.Ocr;

/// <summary>Oyun dilinin (ISO 639-1) Tesseract veri adı (ISO 639-2).</summary>
public static class TesseractLanguage
{
    private static readonly Dictionary<string, string> Known = new(StringComparer.OrdinalIgnoreCase)
    {
        ["en"] = "eng", ["ja"] = "jpn", ["de"] = "deu", ["fr"] = "fra", ["es"] = "spa",
        ["it"] = "ita", ["pt"] = "por", ["ru"] = "rus", ["ko"] = "kor", ["zh"] = "chi_sim",
    };

    public const string English = "eng";

    public static string For(string language) =>
        Known.TryGetValue(language, out var name) ? name : language.ToLowerInvariant();
}
