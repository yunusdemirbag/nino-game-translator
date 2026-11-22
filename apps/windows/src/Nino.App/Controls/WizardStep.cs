// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;

namespace Nino.App.Controls;

/// <summary>
/// Sihirbaz adım düzeni, sola yaslı dikey yığın: başlık (ekran başlığı), açıklama (ikincil, üstte 12, en çok 620
/// geniş), içerik (üstte 20). Simge rozeti, logo, belirme animasyonu yok.
/// </summary>
public class WizardStep : ContentControl
{
    public static readonly DependencyProperty TitleProperty =
        DependencyProperty.Register(nameof(Title), typeof(string), typeof(WizardStep), new PropertyMetadata(null));

    public static readonly DependencyProperty DescriptionProperty =
        DependencyProperty.Register(nameof(Description), typeof(string), typeof(WizardStep), new PropertyMetadata(null));

    public string? Title
    {
        get => (string?)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    /// <summary>Açıklama; boşsa yer kaplamaz.</summary>
    public string? Description
    {
        get => (string?)GetValue(DescriptionProperty);
        set => SetValue(DescriptionProperty, value);
    }
}
