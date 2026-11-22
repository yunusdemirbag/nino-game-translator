// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Linux.Hosting;

/// <summary>Sunucunun kendi iletilerinin dili: <c>NINO_LANG</c>, yoksa sistem dili (iki harf).</summary>
public static class Language
{
    public static string Code { get; set; } = FromEnvironment();

    public static bool Turkish => Code == "tr";

    public static string FromEnvironment()
    {
        var chosen = Environment.GetEnvironmentVariable("NINO_LANG");
        if (string.IsNullOrWhiteSpace(chosen)) chosen = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        return chosen.Trim().ToLowerInvariant()[..Math.Min(2, chosen.Trim().Length)];
    }
}
