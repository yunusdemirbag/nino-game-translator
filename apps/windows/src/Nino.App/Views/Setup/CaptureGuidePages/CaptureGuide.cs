// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Views.Setup;
using Nino.Shell;
using Nino.Shell.Setup;

namespace Nino.App.Views;

/// <summary>
/// HDMI yakalama kartı rehberinin çerçevesi (kurulum.md §12.1): üç sayfa, altta sayfa noktaları, solda hayalet "Geri"
/// (pencerede ilk sayfada "Vazgeç"), sağda birincil "Devam"/"Bitti". Hem sihirbazda (adım alanının yerinde) hem
/// Ayarlar'dan açılan <c>CaptureCardGuideWindow</c>'da kullanılır.
/// <para>Sayfa 3 (kart önizlemesi) ayarlar tarafında yazılır: kurucuya <c>thirdPage</c> verin ya da bir kez
/// <see cref="ThirdPageFactory"/>'yi atayın. İkisi de yoksa yalnız başlık ve açıklama gösterilir.</para>
/// </summary>
public sealed class CaptureGuide : UserControl
{
    readonly NinoController _c;
    readonly bool _inWindow;
    readonly Func<CaptureGuide, FrameworkElement>? _thirdPage;
    readonly ContentControl _pageHost = new() { Focusable = false, Margin = new Thickness(32) };
    readonly ScrollViewer _scroll;
    readonly StackPanel _dots = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    readonly Button _back;
    readonly Button _next;
    bool _onTv;
    bool _rendered;

    /// <summary>Sayfa 3'ü kuran ortak işlev (ayarlar tarafı atar); kurucuya verilen öncelikli.</summary>
    public static Func<CaptureGuide, FrameworkElement>? ThirdPageFactory { get; set; }

    /// <summary>HDMI yakalama kartı rehberi.</summary>
    /// <param name="controller">Denetleyici.</param>
    /// <param name="inWindow">Ayarlar'dan açılan pencerede mi (ilk sayfada "Vazgeç"; bitince/vazgeçince
    /// <see cref="CloseRequested"/>).</param>
    /// <param name="thirdPage">Sayfa 3'ü kuran işlev (kart önizlemesi); yoksa <see cref="ThirdPageFactory"/>.</param>
    public CaptureGuide(NinoController controller, bool inWindow, Func<CaptureGuide, FrameworkElement>? thirdPage = null)
    {
        _c = controller;
        _inWindow = inWindow;
        _thirdPage = thirdPage;
        Focusable = false;
        // Başlangıçta "TV'ye mi" = HDMI yakalama kartı kullanılıyor ve altyazı TV'de gösteriliyor.
        _onTv = controller.UsesCaptureCard && controller.ShowsOnTv;

        _scroll = new ScrollViewer
        {
            Content = _pageHost,
            Focusable = false,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        var card = new Card { Content = _scroll, Padding = new Thickness(0) };

        _back = SetupUi.Large(SetupUi.Button("", ButtonKind.Ghost, (_, _) => GoBack()), 120);
        _back.HorizontalAlignment = HorizontalAlignment.Left;
        _next = SetupUi.Large(SetupUi.Button("", ButtonKind.Primary, (_, _) => GoNext()), 200);
        _next.HorizontalAlignment = HorizontalAlignment.Right;
        _next.IsDefault = true;
        var bottom = new Grid { Margin = SetupUi.Top(16) };
        bottom.Children.Add(_dots);
        bottom.Children.Add(_back);
        bottom.Children.Add(_next);

        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(bottom, 1);
        root.Children.Add(card);
        root.Children.Add(bottom);
        Content = root;

        ShowPage(0, animate: false);
    }

    /// <summary>Pencerede: kapatılmalı (vazgeçildi ya da bitti).</summary>
    public event Action? CloseRequested;

    /// <summary>Şimdiki sayfa (0–2).</summary>
    public int Page { get; private set; }

    /// <summary>"TV'ye mi" (sayfa 1'deki seçim). Değişince sayfa yeniden kurulur.</summary>
    public bool OnTv
    {
        get => _onTv;
        set
        {
            if (_onTv == value) return;
            _onTv = value;
            ShowPage(Page, animate: false);
        }
    }

    /// <summary>Denetleyici (sayfa 3 için).</summary>
    public NinoController Controller => _c;

    void GoBack()
    {
        if (Page > 0) ShowPage(Page - 1, animate: true);
        else if (_inWindow) CloseRequested?.Invoke();
        else _c.CancelCardGuide();
    }

    void GoNext()
    {
        if (Page < CaptureGuideSteps.PageCount - 1)
        {
            ShowPage(Page + 1, animate: true);
            return;
        }
        _c.FinishCardGuide(_onTv);
        if (_inWindow) CloseRequested?.Invoke();
    }

    void ShowPage(int page, bool animate)
    {
        Page = page;
        var element = page switch
        {
            0 => new CaptureGuideConnectionPage(this),
            1 => new CaptureGuideHdcpPage(),
            _ => (_thirdPage ?? ThirdPageFactory)?.Invoke(this) ?? FallbackThirdPage(),
        };
        _pageHost.Content = element;
        _scroll.ScrollToTop();
        RenderChrome();
        if (animate && _rendered) Slide(element);
        _rendered = true;
    }

    FrameworkElement FallbackThirdPage() => new WizardStep
    {
        Title = L.Get("cardGuide.page3.title"),
        Description = L.Get(_onTv ? "cardGuide.page3.descriptionTv" : "cardGuide.page3.descriptionScreen"),
    };

    void RenderChrome()
    {
        _back.Content = L.Get(CaptureGuideSteps.BackKey(Page, _inWindow));
        _next.Content = L.Get(CaptureGuideSteps.NextKey(Page));
        _dots.Children.Clear();
        for (var i = 0; i < CaptureGuideSteps.PageCount; i++)
        {
            var (current, accent) = CaptureGuideSteps.Dot(i, Page);
            var dot = new Border
            {
                Height = 7,
                Width = current ? 24 : 7,
                CornerRadius = new CornerRadius(3.5),
                Margin = new Thickness(3.5, 0, 3.5, 0),
            };
            dot.SetResourceReference(Border.BackgroundProperty, accent ? "accentBrush" : "borderBrush");
            _dots.Children.Add(dot);
        }
        AutomationProperties.SetName(_dots, SetupSidebar.Counter(Page + 1, CaptureGuideSteps.PageCount, L.Catalog));
    }

    // Yeni sayfa 28 px sağdan (sağdan sola düzende soldan; dönüşüm de aynalanır) 320 ms'de kübik ease-out ile kayar ve
    // 260 ms'de belirir. Hareketi azalt'a bakmaz.
    static void Slide(FrameworkElement element)
    {
        var shift = new TranslateTransform(28, 0);
        element.RenderTransform = shift;
        shift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(28, 0, TimeSpan.FromMilliseconds(320))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
        });
        element.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(260)));
    }
}
