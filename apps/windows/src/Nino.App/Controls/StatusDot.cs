// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.Core.Design;

namespace Nino.App.Controls;

/// <summary>Durum noktası (varsayılan 8 × 8): iyi success, uyarı warning, boşta textSecondary. Her tonda görünür.</summary>
public class StatusDot : Control
{
    public static readonly DependencyProperty ToneProperty =
        DependencyProperty.Register(nameof(Tone), typeof(StatusTone), typeof(StatusDot), new PropertyMetadata(StatusTone.Idle));

    public StatusTone Tone
    {
        get => (StatusTone)GetValue(ToneProperty);
        set => SetValue(ToneProperty, value);
    }
}
