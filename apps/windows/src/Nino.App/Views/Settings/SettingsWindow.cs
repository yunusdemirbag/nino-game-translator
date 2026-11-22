// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Ayarlar penceresi (ayarlar tarifi §1): solda 240 genişlikte kenar çubuğu, sağda seçili bölüm, altta "Bitti".
/// Bütün değişiklikler anında yazılır; Enter ve Esc pencereyi kapatır (kısayol kaydında ve yerel model kutularında hariç).
/// Açmak için <see cref="Open"/> (tek pencere kuralı) ya da <c>new SettingsWindow(controller) { Owner = … }.Show()</c>.
/// </summary>
public sealed class SettingsWindow : Window
{
    readonly NinoController _controller;
    readonly ListBox _sidebar;
    readonly ScrollViewer _scroller;
    readonly List<SettingsSection> _sections;
    SettingsSection? _current;

    /// <summary>Yayıncı penceresini açan iş (<c>StreamWindow</c> uygulama yüklenince atar).</summary>
    public static Action<Window>? OpenStreamWindow { get; set; }

    /// <summary>Tek pencere kuralıyla açar.</summary>
    public static SettingsWindow Open(NinoController controller, Window? owner) =>
        Ui.ShowSingle(owner, () => new SettingsWindow(controller));

    public SettingsWindow(NinoController controller)
    {
        _controller = controller;
        Ui.Prepare(this, L.Get("common.settings"));
        Width = 1000;
        Height = 720;
        MinWidth = 860;
        MinHeight = 560;
        Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new Uri("pack://application:,,,/Nino;component/Views/Settings/SettingsStyles.xaml", UriKind.Absolute),
        });

        _sections =
        [
            new InterfaceSection(this),
            new ConnectionSection(this),
            new SubtitleAppearanceSection(this),
            new TranslationSection(this),
            new GamePacksSection(this),
            new LanguageSection(this),
            new SubtitleAreaSection(this),
            new ShortcutsSection(this),
            new ObsSection(this),
            new PictureSourceSection(this),
            new PasscodeSection(this),
            new SystemHealthSection(this),
            new AboutSection(this),
            new ResetSection(this),
        ];

        var root = new Grid { Margin = new(24) };
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(240) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        _sidebar = new ListBox().Styled("Settings.SidebarList");
        _sidebar.Res(ItemsControl.ItemContainerStyleProperty, "Settings.SidebarItem");
        _sidebar.SelectionChanged += (_, _) => ShowSelected();
        var sideTitle = Ui.Title(L.Get("common.settings")).At(12, 0, 12, 12);
        sideTitle.Fg("textPrimaryBrush");
        var sideDock = new DockPanel();
        DockPanel.SetDock(sideTitle, Dock.Top);
        sideDock.Children.Add(sideTitle);
        sideDock.Children.Add(_sidebar);
        var sideCard = new Card { Content = sideDock, Padding = new(12, 20, 12, 20) };
        sideCard.Res(ForegroundProperty, "textPrimaryBrush");
        body.Children.Add(sideCard);

        _scroller = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Margin = new(16, 0, 0, 0),
            Focusable = false,
        };
        Grid.SetColumn(_scroller, 1);
        body.Children.Add(_scroller);
        root.Children.Add(body);

        var done = Ui.Primary(L.Get("common.done"), Close);
        done.MinWidth = 120;
        done.HorizontalAlignment = HorizontalAlignment.Right;
        done.Margin = new(0, 16, 0, 0);
        Grid.SetRow(done, 1);
        root.Children.Add(done);
        Content = root;

        RebuildSidebar();
        _sidebar.SelectedIndex = 0;

        PreviewKeyDown += OnPreviewKeyDown;
        _controller.PropertyChanged += OnControllerChanged;
        _controller.FrameArrived += OnFrameArrived;
        _controller.SnapshotRequested += OnSnapshotRequested;
        Closed += (_, _) =>
        {
            _controller.PropertyChanged -= OnControllerChanged;
            _controller.FrameArrived -= OnFrameArrived;
            _controller.SnapshotRequested -= OnSnapshotRequested;
            foreach (var s in _sections) s.WindowClosed();
        };
    }

    internal NinoController Controller => _controller;

    /// <summary>Kısayol kaydı sürüyorsa bütün tuşlar ona gider.</summary>
    internal ShortcutsSection? Capturing { get; set; }

    void RebuildSidebar()
    {
        var selected = _current;
        _sidebar.Items.Clear();
        foreach (var section in _sections.Where(s => s.Available))
            _sidebar.Items.Add(new ListBoxItem { Content = section.SectionTitle, Tag = section });
        if (selected is not null)
        {
            var item = _sidebar.Items.OfType<ListBoxItem>().FirstOrDefault(i => i.Tag == selected);
            if (item is not null) _sidebar.SelectedItem = item;
            else _sidebar.SelectedIndex = 0;
        }
    }

    void ShowSelected()
    {
        if ((_sidebar.SelectedItem as ListBoxItem)?.Tag is not SettingsSection section || section == _current) return;
        _current?.Hidden();
        _current = section;
        section.EnsureBuilt();
        _scroller.Content = section;
        _scroller.ScrollToTop();
        section.Shown();
    }

    /// <summary>Şu an görünen bölüm bu mu.</summary>
    internal bool IsCurrent(SettingsSection section) => _current == section;

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        var name = e.PropertyName ?? "";
        if (name is nameof(NinoController.IsXbox) or nameof(NinoController.ConsoleKind))
        {
            var before = _sidebar.Items.Count;
            RebuildSidebar();
            if (_sidebar.Items.Count != before && _current is { Available: false }) _sidebar.SelectedIndex = 0;
        }
        foreach (var s in _sections)
        {
            if (!s.IsBuilt) continue;
            try { s.ControllerChanged(name); }
            catch (Exception) { }
        }
    }

    void OnFrameArrived()
    {
        foreach (var s in _sections.OfType<SubtitleAreaSection>()) s.FrameArrived();
    }

    void OnSnapshotRequested()
    {
        foreach (var s in _sections.OfType<SubtitleAreaSection>()) s.RefreshPictureNow();
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
        if (e.Key == Key.Escape)
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
            d = System.Windows.Media.VisualTreeHelper.GetParent(d) ?? LogicalTreeHelper.GetParent(d);
        }
        return null;
    }
}

/// <summary>Ayarlar bölümünün ortak işleri: başlık, kartlar arası 16, yükleniyor bayrağı, ayar yazma.</summary>
internal abstract class SettingsSection : StackPanel
{
    protected SettingsSection(SettingsWindow host) => Host = host;

    protected SettingsWindow Host { get; }

    protected NinoController C => Host.Controller;

    protected LoadGuard Guard { get; } = new();

    public bool IsBuilt { get; private set; }

    /// <summary>Kenar çubuğundaki ad (bölüm başlığıyla aynı).</summary>
    public abstract string SectionTitle { get; }

    /// <summary>Kenar çubuğunda görünür mü.</summary>
    public virtual bool Available => true;

    public void EnsureBuilt()
    {
        if (IsBuilt) return;
        IsBuilt = true;
        Margin = new(0, 0, 12, 0);
        Guard.Run(Build);
    }

    protected abstract void Build();

    /// <summary>Denetleyicide bir özellik değişti (Settings dahil).</summary>
    public virtual void ControllerChanged(string property) { }

    public virtual void Shown() { }

    public virtual void Hidden() { }

    public virtual void WindowClosed() { }

    /// <summary>Büyük bölüm başlığı (altta 16).</summary>
    protected TextBlock AddHeader(string? text = null)
    {
        var t = Ui.Display(text ?? SectionTitle).At(0, 0, 0, 16);
        Children.Add(t);
        return t;
    }

    /// <summary>Kart ekler (ilk karttan sonrakiler üstte 16).</summary>
    protected T AddCard<T>(T card) where T : FrameworkElement
    {
        if (Children.OfType<FrameworkElement>().Any(c => c is Card or FirewallSettingsCard)) card.Margin = new(0, 16, 0, 0);
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
