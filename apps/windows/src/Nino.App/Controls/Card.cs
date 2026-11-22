// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;

namespace Nino.App.Controls;

/// <summary>
/// Kart (karo): surface zemin, 1 px tileBorder çerçeve, köşe 22, iç boşluk 16, gölgesiz. İsteğe bağlı başlık karo
/// başlığı stilinde, altında 12 boşluk (verilmezse yer kaplamaz). Etkin kartın çerçevesi accent (yine 1 px).
/// </summary>
public class Card : ContentControl
{
    public static readonly DependencyProperty HeaderProperty =
        DependencyProperty.Register(nameof(Header), typeof(object), typeof(Card), new PropertyMetadata(null));

    public static readonly DependencyProperty IsActiveProperty =
        DependencyProperty.Register(nameof(IsActive), typeof(bool), typeof(Card), new PropertyMetadata(false));

    /// <summary>Başlık (genellikle metin).</summary>
    public object? Header
    {
        get => GetValue(HeaderProperty);
        set => SetValue(HeaderProperty, value);
    }

    /// <summary>Seçili seçenek kartı mı (çerçeve accent).</summary>
    public bool IsActive
    {
        get => (bool)GetValue(IsActiveProperty);
        set => SetValue(IsActiveProperty, value);
    }
}
