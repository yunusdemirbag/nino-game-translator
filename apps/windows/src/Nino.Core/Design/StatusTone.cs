// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Design;

/// <summary>
/// Durum tonu: iyi → success, uyarı → warning, boşta → textSecondary. Hangi durumun hangi tonu aldığını denetleyici
/// söyler; arayüz yalnız rengini seçer.
/// </summary>
public enum StatusTone
{
    Idle,
    Good,
    Warning,
}

/// <summary>Tonun renk belirteci.</summary>
public static class StatusToneColors
{
    /// <summary>Durum noktasının rengi.</summary>
    public static string DotColor(StatusTone tone) => tone switch
    {
        StatusTone.Good => "success",
        StatusTone.Warning => "warning",
        _ => "textSecondary",
    };

    /// <summary>Durum karosundaki değerin rengi: iyi → textPrimary, öbürleri textSecondary.</summary>
    public static string ValueColor(StatusTone tone) => tone == StatusTone.Good ? "textPrimary" : "textSecondary";
}
