// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;

namespace Nino.App.Controls;

/// <summary>
/// Numaralı satır: solda 28 × 28 surface2 daire içinde numara (13 yarı kalın), sağda gövde metni (soldan 12, üstten
/// 4, kayar); altta 16 boşluk. İçerik verilirse metnin yerine o gösterilir.
/// </summary>
public class NumberedRow : ContentControl
{
    public static readonly DependencyProperty NumberProperty =
        DependencyProperty.Register(nameof(Number), typeof(string), typeof(NumberedRow), new PropertyMetadata(null));

    public static readonly DependencyProperty TextProperty =
        DependencyProperty.Register(nameof(Text), typeof(string), typeof(NumberedRow), new PropertyMetadata(null));

    public string? Number
    {
        get => (string?)GetValue(NumberProperty);
        set => SetValue(NumberProperty, value);
    }

    public string? Text
    {
        get => (string?)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }
}
