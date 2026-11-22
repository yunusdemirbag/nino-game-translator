// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.Core.Translation;

namespace Nino.App.Theme;

/// <summary>
/// Sağdan sola düzen. Yalnız arayüz dili Arapça ya da Urduca iken. Bütün pencerelerin varsayılan yönünü genel olarak
/// değiştirmek Arapça Windows'ta açılışta çöküyordu; bu yüzden yön pencere pencere, yüklenirken verilir.
/// </summary>
public static class RightToLeft
{
    private static bool _installed;

    /// <summary>Arayüz sağdan sola mı (<see cref="Install"/> ile belirlenir).</summary>
    public static bool Enabled { get; private set; }

    /// <summary>
    /// İlk pencereden önce bir kez: arayüz sağdan solaysa her pencere yüklenirken, kendi yönü açıkça verilmemişse
    /// sağdan sola yapılır.
    /// </summary>
    public static void Install(bool rightToLeft)
    {
        Enabled = rightToLeft;
        if (!rightToLeft || _installed) return;
        _installed = true;
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((sender, _) => ApplyTo((Window)sender)));
    }

    /// <summary>
    /// Pencereye aynı kuralı hemen uygular (ana pencere ilk çizimden önce, kurucusunda çağırır): yönü açıkça
    /// verilmemişse ve arayüz sağdan solaysa sağdan sola.
    /// </summary>
    public static void ApplyTo(Window window)
    {
        if (!Enabled) return;
        if (window.ReadLocalValue(FrameworkElement.FlowDirectionProperty) != DependencyProperty.UnsetValue) return;
        window.FlowDirection = FlowDirection.RightToLeft;
    }

    /// <summary>Altyazı ve TV satırı için yön yazının kendisinden: Arap harfi varsa sağdan sola.</summary>
    public static FlowDirection ForText(string? text) =>
        !string.IsNullOrEmpty(text) && text.EnumerateRunes().Any(r => TargetLanguages.IsArabicLetter(r.Value))
            ? FlowDirection.RightToLeft
            : FlowDirection.LeftToRight;

    /// <summary>Gösterilecek altyazı: Arap harfi varsa her paragrafın başına (yoksa) U+200F konur.</summary>
    public static string PrepareText(string text) => TargetLanguages.ApplyRtlMarks(text);
}
