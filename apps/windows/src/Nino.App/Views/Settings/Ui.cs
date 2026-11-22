// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using Nino.App.Controls;
using Nino.App.Strings;

namespace Nino.App.Views;

/// <summary>
/// Ayarlar ve yan pencerelerin koddan kurulan küçük parçaları. Stiller ve renkler temadan (DynamicResource) gelir;
/// tema değişince her şey kendiliğinden yeniden boyanır.
/// </summary>
internal static class Ui
{
    // ---- Genel ----

    public static T Styled<T>(this T element, string styleKey) where T : FrameworkElement
    {
        element.SetResourceReference(FrameworkElement.StyleProperty, styleKey);
        return element;
    }

    public static T At<T>(this T element, double left, double top, double right, double bottom) where T : FrameworkElement
    {
        element.Margin = new(left, top, right, bottom);
        return element;
    }

    public static T Shown<T>(this T element, bool visible) where T : UIElement
    {
        element.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        return element;
    }

    public static T Fg<T>(this T element, string brushKey) where T : FrameworkElement
    {
        element.SetResourceReference(element is Control ? Control.ForegroundProperty : TextBlock.ForegroundProperty, brushKey);
        return element;
    }

    /// <summary>Tema kaynağına bağlar (tema değişince yeniden boyanır).</summary>
    public static T Res<T>(this T element, DependencyProperty property, string key) where T : FrameworkElement
    {
        element.SetResourceReference(property, key);
        return element;
    }

    public static Brush Frozen(Color color)
    {
        var b = new SolidColorBrush(color);
        b.Freeze();
        return b;
    }

    public static StackPanel Column(params UIElement[] children)
    {
        var panel = new StackPanel();
        foreach (var c in children) panel.Children.Add(c);
        return panel;
    }

    public static StackPanel Row(params UIElement[] children)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var c in children) panel.Children.Add(c);
        return panel;
    }

    public static WrapPanel Wrap(params UIElement[] children)
    {
        var panel = new WrapPanel();
        foreach (var c in children) panel.Children.Add(c);
        return panel;
    }

    /// <summary>İki sütunlu sıra: solda esneyen, sağda kendi boyunda öğe.</summary>
    public static Grid Split(UIElement left, UIElement right, double gap = 12)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (right is FrameworkElement fe) fe.Margin = new(gap, fe.Margin.Top, fe.Margin.Right, fe.Margin.Bottom);
        Grid.SetColumn(right, 1);
        grid.Children.Add(left);
        grid.Children.Add(right);
        return grid;
    }

    /// <summary>Yatay sıra: solda etiket (sağında 16), sağda denetim.</summary>
    public static StackPanel Labeled(string label, FrameworkElement control, double gap = 16)
    {
        var text = Body(label);
        text.VerticalAlignment = VerticalAlignment.Center;
        text.TextWrapping = TextWrapping.NoWrap;
        text.Margin = new(0, 0, gap, 0);
        control.VerticalAlignment = VerticalAlignment.Center;
        return Row(text, control);
    }

    // ---- Yazılar ----

    public static TextBlock Text(string text, string style) =>
        new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap }.Styled(style);

    public static TextBlock Display(string text) => Text(text, "Text.Display");

    public static TextBlock Title(string text) => Text(text, "Text.Title");

    public static TextBlock Headline(string text) => Text(text, "Text.Headline");

    public static TextBlock Body(string text) => Text(text, "Text.Body");

    public static TextBlock Secondary(string text) => Text(text, "Text.Secondary");

    /// <summary>İpucu: 13 orta, textSecondary, satır 17.</summary>
    public static TextBlock Hint(string text) => Text(text, "Text.Callout");

    public static TextBlock Caption(string text) => Text(text, "Text.Caption");

    public static TextBlock Error(string text = "") => Text(text, "Text.Error");

    public static TextBlock Success(string text) => Text(text, "Text.Success");

    public static TextBlock Icon(string glyph, double size, string brushKey = "textSecondaryBrush")
    {
        var t = new TextBlock { Text = glyph, FontSize = size }.Styled("Text.Icon");
        t.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
        return t;
    }

    /// <summary>Bağlantı yazısı (varsayılan tarayıcıda açılır).</summary>
    public static TextBlock Link(string text, string url)
    {
        var link = new Hyperlink(new Run(text)) { NavigateUri = new Uri(url), ToolTip = url };
        link.RequestNavigate += (_, e) =>
        {
            Open(e.Uri.AbsoluteUri);
            e.Handled = true;
        };
        var block = new TextBlock { TextWrapping = TextWrapping.Wrap }.Styled("Text.Callout");
        block.Inlines.Add(link);
        return block;
    }

    // ---- Düğmeler ----

    public static Button Button(string text, Action? click = null, string style = "Button.Secondary")
    {
        var b = new Button { Content = text }.Styled(style);
        if (click is not null) b.Click += (_, _) => click();
        return b;
    }

    public static Button Primary(string text, Action? click = null) => Button(text, click, "Button.Primary");

    public static Button Ghost(string text, Action? click = null) => Button(text, click, "Button.Ghost");

    // ---- Kart ----

    public static Card Card(string? header, params UIElement[] children)
    {
        var card = new Card { Content = Column(children) };
        if (header is not null) card.Header = header;
        return card;
    }

    // ---- Anahtar, liste, kaydırıcı ----

    public static CheckBox Toggle(string? label = null)
    {
        var box = new CheckBox();
        if (label is not null) box.Content = new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap };
        return box;
    }

    public static ComboBox Combo(double minWidth = 220)
    {
        var combo = new ComboBox { MinWidth = minWidth };
        return combo;
    }

    public static ComboBoxItem Item(object tag, string text) => new() { Content = text, Tag = tag };

    public static ComboBoxItem Item(object tag, UIElement content) => new() { Content = content, Tag = tag };

    /// <summary>Listede etiketi verilen öğeyi seçer (yoksa -1).</summary>
    public static void SelectTag(this ComboBox combo, object? tag)
    {
        for (var i = 0; i < combo.Items.Count; i++)
        {
            if (combo.Items[i] is ComboBoxItem item && Equals(item.Tag, tag))
            {
                combo.SelectedIndex = i;
                return;
            }
        }
        combo.SelectedIndex = -1;
    }

    public static object? SelectedTag(this ComboBox combo) => (combo.SelectedItem as ComboBoxItem)?.Tag;

    /// <summary>Gizli (parola) giriş kutusu.</summary>
    public static PasswordBox Secret(double width, int maxLength = 0)
    {
        var box = new PasswordBox { Width = width };
        if (maxLength > 0) box.MaxLength = maxLength;
        return box;
    }

    // ---- Kabuk işleri ----

    /// <summary>Adresi varsayılan tarayıcıda açar (hata yutulur).</summary>
    public static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception) { }
    }

    /// <summary>Panoya yazar; pano başka uygulamada kilitliyse false (sessiz).</summary>
    public static bool Copy(string text)
    {
        try
        {
            Clipboard.SetText(text);
            return true;
        }
        catch (Exception) { return false; }
    }

    /// <summary>Tek pencere kuralı: aynı türden görünür pencere varsa öne getirir, yoksa kurup sahibine bağlar.</summary>
    public static T ShowSingle<T>(Window? owner, Func<T> create) where T : Window
    {
        var existing = Application.Current?.Windows.OfType<T>().FirstOrDefault(w => w.IsVisible);
        if (existing is not null)
        {
            if (existing.WindowState == WindowState.Minimized) existing.WindowState = WindowState.Normal;
            existing.Activate();
            return existing;
        }
        var window = create();
        if (owner is not null && owner != window && owner.IsLoaded)
        {
            window.Owner = owner;
            window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        }
        else window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        window.Show();
        return window;
    }

    /// <summary>Yan pencerelerin ortak özellikleri (görev çubuğunda yok, Nino stili, sahibinin ortası).</summary>
    public static void Prepare(Window window, string title)
    {
        window.Title = title;
        window.ShowInTaskbar = false;
        window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        window.SetResourceReference(FrameworkElement.StyleProperty, "Window.Nino");
    }

    /// <summary>Metin kutusunun üstünde tıklamayı geçiren yer tutucu (boşken görünür).</summary>
    public static Grid WithPlaceholder(TextBox box, string placeholder, bool top)
    {
        var hint = new TextBlock
        {
            Text = placeholder,
            IsHitTestVisible = false,
            Opacity = 0.75,
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = top ? VerticalAlignment.Top : VerticalAlignment.Center,
            Margin = new(box.Padding.Left + 2, top ? box.Padding.Top + 1 : 0, box.Padding.Right, 0),
        };
        hint.SetResourceReference(TextBlock.ForegroundProperty, "textSecondaryBrush");
        AutomationNames.Set(box, placeholder);
        void Update() => hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        box.TextChanged += (_, _) => Update();
        Update();
        var grid = new Grid();
        grid.Children.Add(box);
        grid.Children.Add(hint);
        return grid;
    }
}

/// <summary>Ekran okuyucu adları.</summary>
internal static class AutomationNames
{
    public static void Set(DependencyObject element, string name) =>
        System.Windows.Automation.AutomationProperties.SetName(element, name);
}

/// <summary>
/// "Yükleniyor" bayrağı: kod bir denetimi kendisi değiştirirken denetimin olayı ayar yazmasın. İç içe çağrılabilir.
/// </summary>
internal sealed class LoadGuard
{
    int _depth;

    public bool Busy => _depth > 0;

    public void Run(Action action)
    {
        _depth++;
        try { action(); }
        finally { _depth--; }
    }
}

/// <summary>
/// Bölmeli seçici (segment): surface2 ray, köşe 14, iç boşluk 2; parçalar "Segment" stilli seçenek düğmeleri.
/// Yayılan türde parçalar eşit genişliktedir. Seçimi kod değiştirince olay gelmez.
/// </summary>
internal sealed class SegmentBar : Border
{
    readonly List<RadioButton> _items = [];
    readonly Panel _panel;
    readonly string _group = "seg" + Guid.NewGuid().ToString("N");
    bool _silent;

    public SegmentBar(bool stretch, params string[] labels)
    {
        this.Styled("Segment.Rail");
        if (stretch)
        {
            HorizontalAlignment = HorizontalAlignment.Stretch;
            _panel = new UniformGrid { Rows = 1 };
        }
        else _panel = new StackPanel { Orientation = Orientation.Horizontal };
        Child = _panel;
        foreach (var label in labels) Add(label);
    }

    /// <summary>Kullanıcı bir parçayı seçti (dizin).</summary>
    public event Action<int>? Changed;

    public int Count => _items.Count;

    public void Add(string label)
    {
        var index = _items.Count;
        var radio = new RadioButton
        {
            GroupName = _group,
            Content = new TextBlock { Text = label, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center },
        }.Styled("Segment");
        AutomationNames.Set(radio, label);
        radio.Checked += (_, _) =>
        {
            if (!_silent) Changed?.Invoke(index);
        };
        _items.Add(radio);
        _panel.Children.Add(radio);
    }

    /// <summary>Seçili parça (yoksa -1).</summary>
    public int Selected
    {
        get => _items.FindIndex(r => r.IsChecked == true);
        set
        {
            _silent = true;
            try
            {
                for (var i = 0; i < _items.Count; i++) _items[i].IsChecked = i == value;
            }
            finally { _silent = false; }
        }
    }

    public void SetLabel(int index, string label)
    {
        if (_items[index].Content is TextBlock t) t.Text = label;
        AutomationNames.Set(_items[index], label);
    }

    public void SetVisible(int index, bool visible) => _items[index].Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
}

/// <summary>
/// Kaydırıcı satırı: sol uç yazısı | kaydırıcı (iki yandan 12) | sağ uç yazısı | (istenirse) 40 genişliğinde değer.
/// Kaydırıcı tıklanan noktaya atlar.
/// </summary>
internal sealed class SliderRow : Grid
{
    public Slider Slider { get; }

    public TextBlock? ValueText { get; }

    public SliderRow(string? left, string? right, double min, double max, bool showValue, double valueWidth = 40)
    {
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (left is not null) Add(Ui.Hint(left), 0);
        Slider = new Slider { Minimum = min, Maximum = max, IsMoveToPointEnabled = true, Margin = new(12, 0, 12, 0) };
        Add(Slider, 1);
        if (right is not null) Add(Ui.Hint(right), 2);
        if (showValue)
        {
            ValueText = new TextBlock
            {
                MinWidth = valueWidth,
                TextAlignment = TextAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center,
                Typography = { NumeralAlignment = FontNumeralAlignment.Tabular },
            };
            Add(ValueText, 3);
        }
    }

    void Add(FrameworkElement element, int column)
    {
        element.VerticalAlignment = VerticalAlignment.Center;
        if (element is TextBlock t) t.TextWrapping = TextWrapping.NoWrap;
        SetColumn(element, column);
        Children.Add(element);
    }
}

/// <summary>Klavye yardımcıları.</summary>
internal static class KeyInput
{
    /// <summary>Alt'lı tuşta asıl tuş sistem tuşundan, IME işlenmişte asıl tuştan alınır.</summary>
    public static Key Real(KeyEventArgs e) => e.Key switch
    {
        Key.System => e.SystemKey,
        Key.ImeProcessed => e.ImeProcessedKey,
        Key.DeadCharProcessed => e.DeadCharProcessedKey,
        _ => e.Key,
    };
}
