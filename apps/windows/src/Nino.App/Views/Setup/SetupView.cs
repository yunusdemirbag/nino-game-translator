// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
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
/// Kurulum sihirbazı (kurulum.md §1): solda adım listesi (logo, adımlar, sıfırlama, sayaç, ilerleme), sağda adım kartı
/// ve Geri/Devam. Denetleyici "HDMI yakalama kartı kurulumu etkin" derse adım alanının yerine HDMI yakalama kartı rehberi gelir.
/// Kabuk (ana pencere) bunu kurulum bitmemişken gösterir.
/// </summary>
public sealed class SetupView : UserControl
{
    readonly NinoController _c;
    readonly StackPanel _rows = new();
    readonly Button _reset;
    readonly TextBlock _counter;
    readonly ProgressBar _progress = new() { Minimum = 0, Maximum = 1 };
    readonly ContentControl _stepHost = new() { Focusable = false, Margin = new Thickness(32) };
    readonly ScrollViewer _stepScroll;
    readonly Button _back;
    readonly Button _continue;
    readonly Grid _stepArea = new();
    readonly ContentControl _guideHost = new() { Focusable = false };
    (SetupStep Step, bool Xbox)? _built;
    bool? _guideShown;
    bool _listening;

    /// <summary>Kurulum sihirbazı.</summary>
    public SetupView(NinoController controller)
    {
        _c = controller;
        Focusable = false;

        var root = new Grid { Margin = new Thickness(24) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // ---- Sol: adım listesi ----
        var title = SetupUi.Key("setup.sidebar.title", "Text.Title", SetupUi.M(12, 0, 0, 0));
        title.VerticalAlignment = VerticalAlignment.Center;
        var header = SetupUi.Row(new LogoBox { Width = 32, Height = 32 }, title);
        header.Margin = SetupUi.M(12, 0, 12, 16);

        _reset = SetupUi.Button(L.Get("setup.sidebar.reset"), ButtonKind.Secondary, (_, _) =>
        {
            _c.ResetEverything();
            _built = null;
            Render();
        }, SetupUi.Bottom(14));
        _counter = SetupUi.Text("", "Text.Caption", SetupUi.Bottom(8));
        var footer = SetupUi.Stack(_reset, _counter, _progress);
        footer.Margin = SetupUi.M(12, 16, 12, 0);

        var list = new ScrollViewer
        {
            Content = _rows,
            Focusable = false,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        var sideDock = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(header, Dock.Top);
        DockPanel.SetDock(footer, Dock.Bottom);
        sideDock.Children.Add(header);
        sideDock.Children.Add(footer);
        sideDock.Children.Add(list);
        var side = new Card { Content = sideDock, Width = 240, Padding = new Thickness(12, 20, 12, 20), Margin = SetupUi.M(0, 0, 16, 0) };
        Grid.SetColumn(side, 0);
        root.Children.Add(side);

        // ---- Sağ: adım kartı + düğmeler ----
        _stepScroll = new ScrollViewer
        {
            Content = _stepHost,
            Focusable = false,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        var stepCard = new Card { Content = _stepScroll, Padding = new Thickness(0) };

        _back = SetupUi.Large(SetupUi.Button(L.Get("common.back"), ButtonKind.Secondary, (_, _) => _c.Back()), 160);
        _back.HorizontalAlignment = HorizontalAlignment.Left;
        _continue = SetupUi.Large(SetupUi.Button(L.Get("common.continue"), ButtonKind.Primary, (_, _) => _c.Advance()), 200);
        _continue.HorizontalAlignment = HorizontalAlignment.Right;
        var buttons = new Grid { Margin = SetupUi.Top(16) };
        buttons.Children.Add(_back);
        buttons.Children.Add(_continue);

        _stepArea.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _stepArea.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        Grid.SetRow(buttons, 1);
        _stepArea.Children.Add(stepCard);
        _stepArea.Children.Add(buttons);

        var right = new Grid();
        right.Children.Add(_stepArea);
        right.Children.Add(_guideHost);
        Grid.SetColumn(right, 1);
        root.Children.Add(right);

        Content = root;

        Loaded += (_, _) =>
        {
            if (!_listening)
            {
                _c.PropertyChanged += OnChanged;
                _listening = true;
            }
            Render();
        };
        Unloaded += (_, _) =>
        {
            if (_listening) _c.PropertyChanged -= OnChanged;
            _listening = false;
        };
    }

    void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(NinoController.Step):
            case nameof(NinoController.IsXbox):
            case nameof(NinoController.ConsoleKindLocked):
            case nameof(NinoController.CanContinue):
            case nameof(NinoController.UsingFreeGemini):
            case nameof(NinoController.CardGuideOpen):
            case nameof(NinoController.StepNumber):
            case nameof(NinoController.StepCount):
                Render();
                break;
        }
    }

    void Render()
    {
        RenderSidebar();
        RenderGuide();
        RenderStep();
        RenderButtons();
    }

    // ---- Sol liste ----

    void RenderSidebar()
    {
        _rows.Children.Clear();
        foreach (var row in SetupSidebar.Rows(_c.Step, _c.IsXbox, L.Catalog)) _rows.Children.Add(StepRow(row));
        SetupUi.Show(_reset, _c.ConsoleKindLocked);
        var count = Math.Max(1, _c.StepCount);
        _counter.Text = SetupSidebar.Counter(_c.StepNumber, count, L.Catalog);
        _progress.Value = Math.Clamp((double)_c.StepNumber / count, 0, 1);
    }

    static Border StepRow(SetupStepRow row)
    {
        var circle = new Border { Width = 28, Height = 28, CornerRadius = new CornerRadius(14), VerticalAlignment = VerticalAlignment.Center };
        circle.SetResourceReference(Border.BackgroundProperty, row.Mark switch
        {
            StepMark.Done => "successBrush",
            StepMark.Current => "accentBrush",
            _ => "borderBrush",
        });
        var mark = new TextBlock
        {
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.NoWrap,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (row.Mark == StepMark.Done)
        {
            mark.Text = Glyphs.CheckMark;
            mark.SetResourceReference(TextBlock.FontFamilyProperty, "font.icon");
        }
        else mark.Text = row.Number.ToString(System.Globalization.CultureInfo.CurrentCulture);
        mark.SetResourceReference(TextBlock.ForegroundProperty, row.Mark == StepMark.Upcoming ? "textSecondaryBrush" : "onAccentBrush");
        circle.Child = mark;

        var name = SetupUi.Text(row.Name, "Text.Body", SetupUi.M(12, 0, 0, 0));
        name.VerticalAlignment = VerticalAlignment.Center;
        name.SetResourceReference(TextBlock.ForegroundProperty, row.Mark == StepMark.Upcoming ? "textSecondaryBrush" : "textPrimaryBrush");
        if (row.Mark == StepMark.Current) name.FontWeight = FontWeights.SemiBold;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(name, 1);
        grid.Children.Add(circle);
        grid.Children.Add(name);

        var border = new Border
        {
            Child = grid,
            Padding = new Thickness(12, 8, 12, 8),
            Margin = SetupUi.Bottom(4),
            MinHeight = 44,
            CornerRadius = new CornerRadius(14),
            Background = Brushes.Transparent,
            Focusable = false,
        };
        if (row.Mark == StepMark.Current) border.SetResourceReference(Border.BackgroundProperty, "surface2Brush");
        AutomationProperties.SetName(border, row.AccessibleName);
        return border;
    }

    // ---- Sağ alan ----

    void RenderStep()
    {
        var key = (_c.Step, _c.IsXbox);
        if (_built == key) return;
        // Konsol türü yalnız Karşılama'da değişir; orada ekran kendini yeniler, yeniden kurulmaz.
        if (_built is { } old && old.Step == key.Step && key.Step == SetupStep.Welcome)
        {
            _built = key;
            return;
        }
        _built = key;
        _stepHost.Content = CreateStep(_c.Step, _c.IsXbox);
        _stepScroll.ScrollToTop();
    }

    UIElement CreateStep(SetupStep step, bool xbox) => step switch
    {
        SetupStep.Welcome => new WelcomeStep(_c),
        SetupStep.SecondAccount => new SecondAccountStep(_c),
        SetupStep.PsnSignIn => xbox ? new MicrosoftSignInStep(_c) : new PsnSignInStep(_c),
        SetupStep.Console => xbox ? new XboxConsoleStep(_c) : new Ps5PairStep(_c),
        SetupStep.Tv => new TvStep(_c),
        SetupStep.Model => new ModelStep(_c),
        SetupStep.Test => new TestStep(_c),
        _ => new BetterTranslationStep(_c),
    };

    void RenderButtons()
    {
        var state = WizardButtons.For(_c.Step, _c.UsingFreeGemini);
        _back.Visibility = state.BackVisible ? Visibility.Visible : Visibility.Hidden;
        _continue.Visibility = state.ContinueVisible ? Visibility.Visible : Visibility.Hidden;
        _continue.Content = L.Get(state.ContinueKey);
        SetupUi.SetKind(_continue, state.ContinuePrimary ? ButtonKind.Primary : ButtonKind.Secondary);
        _continue.IsDefault = state.ContinueIsDefault && state.ContinueVisible;
        _continue.IsEnabled = _c.CanContinue;
    }

    void RenderGuide()
    {
        var open = _c.CardGuideOpen;
        if (_guideShown == open) return;
        var first = _guideShown is null;
        _guideShown = open;
        if (open) _guideHost.Content = new CaptureGuide(_c, inWindow: false);
        var shown = open ? (UIElement)_guideHost : _stepArea;
        var hidden = open ? (UIElement)_stepArea : _guideHost;
        hidden.Visibility = Visibility.Collapsed;
        shown.Visibility = Visibility.Visible;
        if (!open) _guideHost.Content = null;
        if (first) return;
        // Gösterilen taraf 250 ms'de belirir (hareketi azalt'a bakmaz).
        shown.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(250)));
    }
}
