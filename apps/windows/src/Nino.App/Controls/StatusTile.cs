// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.Core.Design;

namespace Nino.App.Controls;

/// <summary>
/// Durum karosunun içi (ayarlar ve sağlık sayfaları): üstte etiket satırı (simge 18, başlık küçük etiket stilinde,
/// en sağda durum noktası), 8 boşluk, altında değer (karo başlığı stili, kayar). İyi tonda değer textPrimary,
/// öbürlerinde textSecondary. Bir <see cref="Card"/> içine konur.
/// </summary>
public class StatusTile : Control
{
    // Hepsi aynı biçimde kaydedilir: ad, tür, varsayılan.
    static DependencyProperty Define<T>(string name, T fallback) =>
        DependencyProperty.Register(name, typeof(T), typeof(StatusTile), new PropertyMetadata(fallback));

    public static readonly DependencyProperty ToneProperty = Define(nameof(Tone), StatusTone.Idle);
    public static readonly DependencyProperty ValueProperty = Define<string?>(nameof(Value), null);
    public static readonly DependencyProperty LabelProperty = Define<string?>(nameof(Label), null);
    public static readonly DependencyProperty IconProperty = Define<string?>(nameof(Icon), null);

    /// <summary>Durum tonu (nokta rengi; iyi tonda değer textPrimary).</summary>
    public StatusTone Tone { get => (StatusTone)GetValue(ToneProperty); set => SetValue(ToneProperty, value); }

    /// <summary>Değer satırı.</summary>
    public string? Value { get => (string?)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }

    /// <summary>Etiket satırı.</summary>
    public string? Label { get => (string?)GetValue(LabelProperty); set => SetValue(LabelProperty, value); }

    /// <summary>Simge karakteri (Segoe Fluent Icons, ör. <see cref="Glyphs.Globe"/>).</summary>
    public string? Icon { get => (string?)GetValue(IconProperty); set => SetValue(IconProperty, value); }
}
