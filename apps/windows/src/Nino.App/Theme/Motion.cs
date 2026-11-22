// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;

namespace Nino.App.Theme;

/// <summary>"Hareketi azalt": Windows'ta "Animasyonları göster" kapalıysa (istemci alanı animasyonu yanlış).</summary>
public static class Motion
{
    /// <summary>Hareket azaltılmalı mı (her okunuşta sistemden).</summary>
    public static bool IsReduced
    {
        get
        {
            try
            {
                return !SystemParameters.ClientAreaAnimation;
            }
            catch (Exception)
            {
                return false;
            }
        }
    }

    /// <summary>Hareket azaltılmışsa sıfır, değilse verilen süre.</summary>
    public static TimeSpan Duration(TimeSpan normal) => IsReduced ? TimeSpan.Zero : normal;
}
