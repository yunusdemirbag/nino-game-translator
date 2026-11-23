// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Theme;
using Nino.Core.Settings;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Ayarlar penceresi, Mac'le aynı yapı: açılışta gruplu liste (iPhone Ayarları gibi), satıra basınca bölüm sayfası
/// sağdan kayarak gelir; üstte solda "Ayarlar" başlığı ya da "‹ Ayarlar" geri düğmesi, sağda "Bitti". Liste, gruplar,
/// gizli bölümler ve bölüm renkleri <see cref="SettingsPages"/>'tan gelir (Linux paneliyle ortak). Değişiklikler anında
/// yazılır. Esc ve Enter pencereyi kapatır (kısayol kaydında ve yerel model kutularında hariç); Alt+Sol geri döner.
/// </summary>
public sealed class SettingsWindow : Window
{
    readonly NinoController _controller;
    readonly ScrollViewer _scroller;
    readonly ContentControl _topLeft = new() { Focusable = false, VerticalAlignment = VerticalAlignment.Center };
    readonly Dictionary<SettingsPage, SettingsSection> _sections = [];
    FrameworkElement? _list;
    SettingsSection? _current;

    /// <summary>Yayıncı penceresini açan iş (<c>StreamWindow</c> uygulama yüklenince atar).</summary>
    public static Action<Window>? OpenStreamWindow { get; set; }

    /// <summary>Tek pencere kuralıyla açar; <paramref name="page"/> verilirse doğrudan o bölüm açılır (liste atlanır).</summary>
    public static SettingsWindow Open(NinoController controller, Window? owner, SettingsPage? page = null)
    {
        var window = Ui.ShowSingle(owner, () => new SettingsWindow(controller, page));
        if (page is { } p && window._current?.Page != p) window.ShowPage(p, animate: false);
        return window;
    }

    public SettingsWindow(NinoController controller) : this(controller, null) { }

    /// <param name="controller">Denetleyici.</param>
    /// <param name="page">Açılışta gösterilecek bölüm (null: liste). Ekran dökümü de bunu kullanır.</param>
    public SettingsWindow(NinoController controller, SettingsPage? page)
    {
        _controller = controller;
        Ui.Prepare(this, L.Get("settings.title"));
        Width = 1000;
        Height = 720;
        MinWidth = 860;
        MinHeight = 560;
        Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new Uri("pack://application:,,,/Nino;component/Views/Settings/SettingsStyles.xaml", UriKind.Absolute),
        });

        var root = new Grid { Margin = new(24) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var done = Ui.Primary(L.Get("settings.done"), Close);
        done.MinWidth = 100;
        var top = Ui.Split(_topLeft, done, 16);
        top.MinHeight = 40;
        top.Margin = new(0, 0, 0, 16);
        root.Children.Add(top);

        _scroller = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
        };
        Grid.SetRow(_scroller, 1);
        root.Children.Add(_scroller);
        Content = root;

        if (page is { } start) ShowPage(start, animate: false);
        else ShowList(animate: false);

        PreviewKeyDown += OnPreviewKeyDown;
        _controller.PropertyChanged += OnControllerChanged;
        _controller.FrameArrived += OnFrameArrived;
        _controller.SnapshotRequested += OnSnapshotRequested;
        Closed += (_, _) =>
        {
            _controller.PropertyChanged -= OnControllerChanged;
            _controller.FrameArrived -= OnFrameArrived;
            _controller.SnapshotRequested -= OnSnapshotRequested;
            foreach (var s in _sections.Values) s.WindowClosed();
        };
    }

    internal NinoController Controller => _controller;

    /// <summary>Kısayol kaydı sürüyorsa bütün tuşlar ona gider.</summary>
    internal ShortcutsSection? Capturing { get; set; }

    /// <summary>Şu an görünen bölüm bu mu.</summary>
    internal bool IsCurrent(SettingsSection section) => _current == section;

    // ---- Gezinme ----

    void ShowList(bool animate)
    {
        _current?.Hidden();
        _current = null;
        var title = Ui.Display(L.Get("settings.title"));
        title.FontWeight = FontWeights.Bold;
        _topLeft.Content = title;
        _list ??= BuildList();
        Present(Centered(_list, SettingsPages.ContentWidth), fromRight: false, animate);
    }

    /// <summary>Bölümü açar (pencere açan satırlar dahil).</summary>
    internal void Open(SettingsPage page)
    {
        switch (SettingsPages.Opens(page))
        {
            case SettingsPageOpens.Window:
                OpenWindow(page);
                break;
            case SettingsPageOpens.CloseThenAskNino:
                var owner = Application.Current?.MainWindow ?? Owner;
                var controller = _controller;
                Close();
                if (owner is null) return;
                var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(SettingsPages.AskNinoDelayMs) };
                timer.Tick += (_, _) =>
                {
                    timer.Stop();
                    ShellWindows.Show(ShellWindowKind.AskNino, owner, controller);
                };
                timer.Start();
                break;
            default:
                ShowPage(page, animate: true);
                break;
        }
    }

    void OpenWindow(SettingsPage page)
    {
        switch (page)
        {
            case SettingsPage.Health:
                Ui.ShowSingle(this, () => new SystemHealthWindow(_controller));
                break;
            case SettingsPage.Report:
                ReportProblemWindow.Open(_controller, this);
                break;
        }
    }

    void ShowPage(SettingsPage page, bool animate)
    {
        if (SettingsPages.Opens(page) != SettingsPageOpens.Page) return;
        _current?.Hidden();
        var section = Section(page);
        _current = section;
        section.EnsureBuilt();
        _topLeft.Content = BackButton();
        Present(Centered(section, SettingsPages.Width(page)), fromRight: true, animate);
        section.Shown();
    }

    void Back()
    {
        if (_current is not null) ShowList(animate: true);
    }

    SettingsSection Section(SettingsPage page)
    {
        if (_sections.TryGetValue(page, out var s)) return s;
        s = page switch
        {
            SettingsPage.Connection => new ConnectionSection(this),
            SettingsPage.Passcode => new PasscodeSection(this),
            SettingsPage.Appearance => new SubtitleAppearanceSection(this),
            SettingsPage.Translation => new TranslationSection(this),
            SettingsPage.Shortcuts => new ShortcutsSection(this),
            SettingsPage.Obs => new ObsSection(this),
            SettingsPage.Updates => new UpdatesSection(this),
            SettingsPage.Reset => new ResetSection(this),
            SettingsPage.About => new AboutSection(this),
            SettingsPage.Interface => new InterfaceSection(this),
            SettingsPage.Language => new LanguageSection(this),
            SettingsPage.Packs => new GamePacksSection(this),
            SettingsPage.Area => new SubtitleAreaSection(this),
            SettingsPage.Home => new GameRoomSection(this),
            _ => throw new ArgumentOutOfRangeException(nameof(page)),
        };
        _sections[page] = s;
        return s;
    }

    Button BackButton()
    {
        var content = Ui.Row(Ui.Icon("", 14, "accentTextBrush").At(0, 0, 6, 0),
            new TextBlock { Text = L.Get("settings.back"), FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        ((TextBlock)content.Children[1]).Fg("accentTextBrush");
        var back = new Button { Content = content, HorizontalAlignment = HorizontalAlignment.Left }.Styled("Button.Ghost");
        AutomationNames.Set(back, L.Get("settings.back"));
        back.Click += (_, _) => Back();
        return back;
    }

    static FrameworkElement Centered(FrameworkElement content, double width)
    {
        content.RemoveFromParent();
        var holder = new Border
        {
            MaxWidth = width,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Padding = new(0, 0, 0, 24),
            Child = content,
        };
        return new Border { Child = holder, Focusable = false };
    }

    /// <summary>Sayfa sağdan (geri dönüşte soldan) kayarak ve belirerek gelir; hareket azaltılmışsa doğrudan.</summary>
    void Present(FrameworkElement page, bool fromRight, bool animate)
    {
        _scroller.Content = page;
        _scroller.ScrollToTop();
        if (!animate || Motion.IsReduced) return;
        var shift = new TranslateTransform(fromRight ? 40 : -40, 0);
        page.RenderTransform = shift;
        page.Opacity = 0;
        var duration = TimeSpan.FromMilliseconds(260);
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        shift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, duration) { EasingFunction = ease });
        page.BeginAnimation(OpacityProperty, new DoubleAnimation(1, duration) { EasingFunction = ease });
    }

    // ---- Liste görünümü ----

    FrameworkElement BuildList()
    {
        var panel = new StackPanel();
        foreach (var group in SettingsPages.VisibleGroups)
        {
            var rows = new StackPanel();
            for (var i = 0; i < group.Count; i++)
            {
                if (i > 0)
                    rows.Children.Add(new Border { Height = 1, Margin = new(58, 0, 0, 0), Opacity = 0.6 }
                        .Res(Border.BackgroundProperty, "borderBrush"));
                rows.Children.Add(ListRow(group[i]));
            }
            var box = new Border
            {
                BorderThickness = new(1),
                Child = rows,
                ClipToBounds = true,
                Margin = new(0, panel.Children.Count == 0 ? 0 : 24, 0, 0),
            };
            box.Res(Border.BackgroundProperty, "surfaceBrush").Res(Border.BorderBrushProperty, "tileBorderBrush")
                .Res(Border.CornerRadiusProperty, "radius.card");
            panel.Children.Add(box);
        }
        return panel;
    }

    Button ListRow(SettingsPage page)
    {
        var title = L.Get(SettingsPages.TitleKey(page));
        var name = new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        var chevron = Ui.Icon(FlowDirection == FlowDirection.RightToLeft ? "" : "", 12);
        chevron.Opacity = 0.7;
        chevron.VerticalAlignment = VerticalAlignment.Center;
        var line = new DockPanel();
        var icon = SectionIcon(page, large: false);
        icon.Margin = new(0, 0, 12, 0);
        DockPanel.SetDock(icon, Dock.Left);
        DockPanel.SetDock(chevron, Dock.Right);
        line.Children.Add(icon);
        line.Children.Add(chevron);
        line.Children.Add(name);
        var row = new Button { Content = line }.Styled("Settings.ListRow");
        AutomationNames.Set(row, title);
        row.Click += (_, _) => Open(page);
        return row;
    }

    /// <summary>Bölümün renkli simge kutusu: listede 30 (köşe 8), bölüm başında 40 (köşe 11); içinde beyaz simge.</summary>
    internal static Border SectionIcon(SettingsPage page, bool large)
    {
        var (r, g, b) = SettingsPages.Color(page);
        var size = large ? 40 : 30;
        var glyph = new TextBlock
        {
            Text = Glyph(page),
            FontSize = large ? 18 : 14,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        }.Styled("Text.Icon");
        glyph.Foreground = Brushes.White;
        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new(large ? 11 : 8),
            Background = Ui.Frozen(Color.FromRgb(r, g, b)),
            Child = glyph,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    static string Glyph(SettingsPage page) => page switch
    {
        SettingsPage.Connection => Glyphs.Connect,
        SettingsPage.Passcode => Glyphs.Lock,
        SettingsPage.Appearance => Glyphs.Subtitles,
        SettingsPage.Translation => Glyphs.Globe,
        SettingsPage.Shortcuts => Glyphs.Keyboard,
        SettingsPage.Obs => "",
        SettingsPage.Health => "",
        SettingsPage.Updates => Glyphs.Download,
        SettingsPage.AskNino => "",
        SettingsPage.Report => "",
        SettingsPage.About => Glyphs.Info,
        SettingsPage.Reset => "",
        SettingsPage.Interface => "",
        SettingsPage.Language => Glyphs.Characters,
        SettingsPage.Packs => Glyphs.Package,
        SettingsPage.Home => "\uE80F",
        _ => "",
    };

    // ---- Olaylar ----

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        var name = e.PropertyName ?? "";
        foreach (var s in _sections.Values)
        {
            if (!s.IsBuilt) continue;
            try { s.ControllerChanged(name); }
            catch (Exception) { }
        }
    }

    void OnFrameArrived()
    {
        foreach (var s in _sections.Values.OfType<SubtitleAreaSection>()) s.FrameArrived();
    }

    void OnSnapshotRequested()
    {
        foreach (var s in _sections.Values.OfType<SubtitleAreaSection>()) s.RefreshPictureNow();
    }

    void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Capturing is { } capture)
        {
            capture.CaptureKey(e);
            e.Handled = true;
            return;
        }
        var focused = Keyboard.FocusedElement as DependencyObject;
        if (KeyInput.Real(e) == Key.Left && Keyboard.Modifiers == ModifierKeys.Alt && _current is not null)
        {
            Back();
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            if (focused is ComboBox { IsDropDownOpen: true } || FindParent<ComboBox>(focused) is { IsDropDownOpen: true }) return;
            Close();
            e.Handled = true;
        }
        else if (e.Key == Key.Enter)
        {
            if (focused is TextBox box && box.Tag is Action save)
            {
                // Yerel model kutuları: Enter yalnız kaydeder, pencereyi kapatmaz.
                save();
                e.Handled = true;
                return;
            }
            if (focused is PasswordBox { Tag: Action submit })
            {
                submit();
                e.Handled = true;
                return;
            }
            if (focused is ButtonBase or ComboBox or ComboBoxItem or ListBoxItem || (focused is TextBox { AcceptsReturn: true })) return;
            Close();
            e.Handled = true;
        }
    }

    static T? FindParent<T>(DependencyObject? d) where T : DependencyObject
    {
        while (d is not null)
        {
            if (d is T t) return t;
            d = VisualTreeHelper.GetParent(d) ?? LogicalTreeHelper.GetParent(d);
        }
        return null;
    }
}

/// <summary>Ayarlar bölümünün ortak işleri: başlık (renkli kare + ad), kartlar arası 12, yükleniyor bayrağı, ayar yazma.</summary>
internal abstract class SettingsSection : StackPanel
{
    protected SettingsSection(SettingsWindow host) => Host = host;

    protected SettingsWindow Host { get; }

    protected NinoController C => Host.Controller;

    protected LoadGuard Guard { get; } = new();

    public bool IsBuilt { get; private set; }

    /// <summary>Bölüm.</summary>
    public abstract SettingsPage Page { get; }

    /// <summary>Bölümün adı (listedekiyle aynı).</summary>
    public string SectionTitle => L.Get(SettingsPages.TitleKey(Page));

    public void EnsureBuilt()
    {
        if (IsBuilt) return;
        IsBuilt = true;
        Guard.Run(Build);
    }

    protected abstract void Build();

    /// <summary>Denetleyicide bir özellik değişti (Settings dahil).</summary>
    public virtual void ControllerChanged(string property) { }

    public virtual void Shown() { }

    public virtual void Hidden() { }

    public virtual void WindowClosed() { }

    /// <summary>Bölümün başı: 40'lık renkli kare + 28 kalın ad (altta 12).</summary>
    protected FrameworkElement AddHeader(FrameworkElement? trailing = null)
    {
        var title = Ui.Display(SectionTitle);
        title.FontWeight = FontWeights.Bold;
        title.VerticalAlignment = VerticalAlignment.Center;
        var icon = SettingsWindow.SectionIcon(Page, large: true);
        icon.Margin = new(0, 0, 12, 0);
        var row = new DockPanel { Margin = new(0, 0, 0, 12), LastChildFill = true };
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        if (trailing is not null)
        {
            DockPanel.SetDock(trailing, Dock.Right);
            trailing.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(trailing);
        }
        row.Children.Add(title);
        Children.Add(row);
        return row;
    }

    /// <summary>Kart ekler (ilk karttan sonrakiler üstte 12).</summary>
    protected T AddCard<T>(T card) where T : FrameworkElement
    {
        if (Children.Count > 1) card.Margin = new(0, 12, 0, 0);
        Children.Add(card);
        return card;
    }

    /// <summary>Ayarın kopyasını değiştirip denetleyiciye verir (yükleniyorken yazmaz).</summary>
    protected void Write(Action<AppSettings> change)
    {
        if (Guard.Busy) return;
        var s = C.Settings;
        change(s);
        C.UpdateSettings(s);
    }
}

/// <summary>Öğeyi bulunduğu kaptan çıkarır (bölüm sayfası yeniden gösterilirken).</summary>
internal static class ElementParents
{
    public static void RemoveFromParent(this FrameworkElement element)
    {
        switch (element.Parent)
        {
            case Panel panel: panel.Children.Remove(element); break;
            case Decorator decorator: decorator.Child = null; break;
            case ContentControl control: control.Content = null; break;
        }
    }
}
