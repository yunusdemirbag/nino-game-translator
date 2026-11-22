// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;

namespace Nino.App.Controls;

/// <summary>Oyun monogramı: 52 × 52, surface2 zemin, köşe 10, ortada textPrimary yazı (oyunun baş harfleri).</summary>
public class GameMonogram : Control
{
    public static readonly DependencyProperty TextProperty =
        DependencyProperty.Register(nameof(Text), typeof(string), typeof(GameMonogram), new PropertyMetadata(null));

    public string? Text
    {
        get => (string?)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    /// <summary>Oyun adından en çok iki baş harf (büyük harf; harf yoksa boş).</summary>
    public static string InitialsOf(string? title)
    {
        if (string.IsNullOrWhiteSpace(title)) return "";
        var words = title.Split([' ', '-', ':', '.'], StringSplitOptions.RemoveEmptyEntries)
            .Where(w => char.IsLetterOrDigit(w[0]))
            .ToList();
        var letters = words.Take(2).Select(w => char.ToUpperInvariant(w[0]));
        return string.Concat(letters);
    }
}
