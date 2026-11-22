// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;

namespace Nino.App.Controls;

/// <summary>
/// Etiket (pill): 24 yüksek, yatay iç boşluk 8, köşe 6, surface2 zemin, 13 orta textSecondary yazı. Paket türünde
/// zemin proSoft, yazı pro. Durum bilgisi etiketle değil, nokta + kelimeyle verilir.
/// </summary>
public class Pill : Control
{
    public static readonly DependencyProperty TextProperty =
        DependencyProperty.Register(nameof(Text), typeof(string), typeof(Pill), new PropertyMetadata(null));

    public static readonly DependencyProperty IsPackProperty =
        DependencyProperty.Register(nameof(IsPack), typeof(bool), typeof(Pill), new PropertyMetadata(false));

    public string? Text
    {
        get => (string?)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    /// <summary>Paket etiketi mi (proSoft zemin, pro yazı).</summary>
    public bool IsPack
    {
        get => (bool)GetValue(IsPackProperty);
        set => SetValue(IsPackProperty, value);
    }
}
