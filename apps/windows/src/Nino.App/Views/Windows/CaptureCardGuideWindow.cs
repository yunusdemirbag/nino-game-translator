// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.CompilerServices;
using System.Windows;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Kart bağlama rehberi penceresi (yan pencereler tarifi §8.3): 760 × 760, en küçük 620 × 560, kalıcı (modal), sahibinin
/// ortasında. İçerik 24 iç boşluklu üç sayfalık rehber; bitince ya da vazgeçilince kapanır.
/// </summary>
public sealed class CaptureCardGuideWindow : Window
{
    public CaptureCardGuideWindow(NinoController controller)
    {
        Ui.Prepare(this, L.Get("cardGuide.window.title"));
        Width = 760;
        Height = 760;
        MinWidth = 620;
        MinHeight = 560;
        var guide = new CaptureGuide(controller, inWindow: true) { Margin = new(24) };
        guide.CloseRequested += Close;
        Content = guide;
    }
}

/// <summary>Rehberin 3. sayfası: kartı takma çağrısı + 220 yüksekliğinde kart önizlemesi (sihirbaz da kullanır).</summary>
public static class CaptureGuidePlugInPage
{
    /// <summary>Sayfayı kurar.</summary>
    public static FrameworkElement Create(CaptureGuide guide) => new WizardStep
    {
        Title = L.Get("cardGuide.page3.title"),
        Description = L.Get(guide.OnTv ? "cardGuide.page3.descriptionTv" : "cardGuide.page3.descriptionScreen"),
        Content = new CardPreview(guide.Controller, 220),
    };

    /// <summary>Uygulama yüklenince rehberin ortak 3. sayfa kurucusu atanır.</summary>
    [ModuleInitializer]
    internal static void Register() => CaptureGuide.ThirdPageFactory ??= Create;
}
