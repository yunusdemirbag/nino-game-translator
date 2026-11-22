// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Shell;

namespace Nino.App.Views.Setup;

/// <summary>Düğme türleri (tasarim-dili.md §8.1).</summary>
internal enum ButtonKind
{
    Secondary,
    Primary,
    Ghost,
}

/// <summary>
/// Sihirbaz ekranlarını koddan kurmak için küçük yardımcılar: yazı stilleri, düğmeler, kartlar, satırlar, pano ve
/// tarayıcı. Stiller uygulama kaynaklarından dinamik bağlanır (tema anında değişir).
/// </summary>
internal static class SetupUi
{
    public static Thickness M(double left, double top, double right, double bottom) => new(left, top, right, bottom);

    public static Thickness Top(double top) => new(0, top, 0, 0);

    public static Thickness Bottom(double bottom) => new(0, 0, 0, bottom);

    /// <summary>Adlı yazı stiliyle yazı bloğu (Text.Body, Text.Callout, Text.Error …).</summary>
    public static TextBlock Text(string text, string style = "Text.Body", Thickness? margin = null)
    {
        var block = new TextBlock { Text = text };
        block.SetResourceReference(FrameworkElement.StyleProperty, style);
        if (margin is { } m) block.Margin = m;
        return block;
    }

    /// <summary>Katalog anahtarından yazı bloğu.</summary>
    public static TextBlock Key(string key, string style = "Text.Body", Thickness? margin = null) => Text(L.Get(key), style, margin);

    /// <summary>Simge yazısıyla tek karakter.</summary>
    public static TextBlock Glyph(string glyph, double size, string brush = "textSecondaryBrush")
    {
        var block = new TextBlock { Text = glyph, FontSize = size };
        block.SetResourceReference(FrameworkElement.StyleProperty, "Text.Icon");
        block.SetResourceReference(TextBlock.ForegroundProperty, brush);
        return block;
    }

    /// <summary>Düğme (tür verilmezse ikincil).</summary>
    public static Button Button(object content, ButtonKind kind = ButtonKind.Secondary, RoutedEventHandler? click = null,
        Thickness? margin = null)
    {
        var button = new Button { Content = content };
        SetKind(button, kind);
        if (click is not null) button.Click += click;
        if (margin is { } m) button.Margin = m;
        return button;
    }

    /// <summary>Düğmenin türünü değiştirir.</summary>
    public static void SetKind(Button button, ButtonKind kind) =>
        button.SetResourceReference(FrameworkElement.StyleProperty, kind switch
        {
            ButtonKind.Primary => "Button.Primary",
            ButtonKind.Ghost => "Button.Ghost",
            _ => "Button.Secondary",
        });

    /// <summary>Büyük düğme (sihirbaz Geri/Devam, rehber): en az 44 yüksek, en az verilen genişlikte.</summary>
    public static Button Large(Button button, double minWidth)
    {
        button.SetResourceReference(FrameworkElement.MinHeightProperty, "size.buttonLarge");
        button.MinWidth = minWidth;
        return button;
    }

    public static StackPanel Stack(params UIElement[] children) => Stack(Orientation.Vertical, children);

    public static StackPanel Row(params UIElement[] children) => Stack(Orientation.Horizontal, children);

    static StackPanel Stack(Orientation orientation, UIElement[] children)
    {
        var panel = new StackPanel { Orientation = orientation };
        foreach (var child in children) panel.Children.Add(child);
        return panel;
    }

    /// <summary>Kart (başlıklı ya da başlıksız).</summary>
    public static Card Card(UIElement content, string? header = null, Thickness? margin = null)
    {
        var card = new Card { Content = content };
        if (header is not null) card.Header = header;
        if (margin is { } m) card.Margin = m;
        return card;
    }

    /// <summary>Numaralı satır.</summary>
    public static NumberedRow Numbered(int number, string text) =>
        new() { Number = number.ToString(System.Globalization.CultureInfo.InvariantCulture), Text = text };

    /// <summary>Kartın üst satırı: solda yazı, sağda (sağdan solada solda) düğme.</summary>
    public static DockPanel TopRow(UIElement left, UIElement right, Thickness? margin = null)
    {
        var dock = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(right, Dock.Right);
        if (right is FrameworkElement fe)
        {
            fe.VerticalAlignment = VerticalAlignment.Center;
            fe.Margin = M(12, 0, 0, 0);
        }
        if (left is FrameworkElement l) l.VerticalAlignment = VerticalAlignment.Center;
        dock.Children.Add(right);
        dock.Children.Add(left);
        if (margin is { } m) dock.Margin = m;
        return dock;
    }

    /// <summary>Yarı kalın gövde yazısı (kart üst satırları).</summary>
    public static TextBlock Strong(string text)
    {
        var block = Text(text);
        block.FontWeight = FontWeights.SemiBold;
        return block;
    }

    public static void Show(UIElement element, bool visible) =>
        element.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Yazıyı verir, boşsa gizler.</summary>
    public static void SetText(TextBlock block, string? text)
    {
        block.Text = text ?? "";
        Show(block, !string.IsNullOrEmpty(text));
    }

    /// <summary>Alanda Enter: olay tüketilir (adımın Devam'ına gitmez), verilen iş çalışır.</summary>
    public static void OnEnter(UIElement field, Action action) =>
        field.PreviewKeyDown += (_, e) =>
        {
            if (e.Key != System.Windows.Input.Key.Enter) return;
            e.Handled = true;
            action();
        };

    /// <summary>Adresi varsayılan tarayıcıda açar (açılamazsa sessiz).</summary>
    public static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
        catch (Exception) { }
    }

    /// <summary>Panoya yazar; pano kilitliyse false (sessiz).</summary>
    public static bool TryCopy(string text)
    {
        try
        {
            Clipboard.SetText(text);
            return true;
        }
        catch (Exception) { return false; }
    }

    /// <summary>Panodaki metin; okunamazsa null.</summary>
    public static string? TryReadClipboard()
    {
        try { return Clipboard.ContainsText() ? Clipboard.GetText() : null; }
        catch (Exception) { return null; }
    }

    /// <summary>Panoyu temizler (kilitliyse sessiz).</summary>
    public static void TryClearClipboard()
    {
        try { Clipboard.Clear(); }
        catch (Exception) { }
    }

    /// <summary>Uygulamanın veri klasörü (%LOCALAPPDATA%\Nino).</summary>
    public static string DataFolder
    {
        get
        {
            try { return NinoDataFolder.Current.Path; }
            catch (Exception)
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nino");
            }
        }
    }

    /// <summary>Kullanıcıya gösterilen yol (%LOCALAPPDATA%\Nino\dosya).</summary>
    public static string DisplayPath(string file)
    {
        try { return NinoDataFolder.Current.DisplayPath(file); }
        catch (Exception) { return @"%LOCALAPPDATA%\Nino\" + file; }
    }

    /// <summary>Dosyayı Dosya Gezgini'nde seçili gösterir; yoksa klasörünü açar (klasör yoksa oluşturulur).</summary>
    public static void ShowInExplorer(string path)
    {
        try
        {
            var folder = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
            if (File.Exists(path)) Process.Start("explorer.exe", $"/select,\"{path}\"");
            else if (!string.IsNullOrEmpty(folder)) Process.Start("explorer.exe", $"\"{folder}\"");
        }
        catch (Exception) { }
    }

    /// <summary>Etkin pencere (yoksa ana pencere).</summary>
    public static Window? ActiveWindow()
    {
        var app = Application.Current;
        if (app is null) return null;
        foreach (Window w in app.Windows)
            if (w.IsActive) return w;
        return app.MainWindow;
    }
}

/// <summary>
/// Sihirbazın bir adım ekranı. Her gösterilişte yeni kurulur; yüklenince bir kez kendi işini başlatır
/// (<see cref="OnFirstShown"/>). Denetleyicinin değişikliklerini yalnız ekrandayken dinler.
/// </summary>
internal abstract class StepPage : UserControl
{
    protected readonly NinoController C;
    bool _shown;
    bool _listening;

    protected StepPage(NinoController controller)
    {
        C = controller;
        Focusable = false;
        Loaded += (_, _) =>
        {
            if (!_listening)
            {
                C.PropertyChanged += OnControllerChanged;
                _listening = true;
            }
            Attached();
            if (_shown) return;
            _shown = true;
            OnFirstShown();
        };
        Unloaded += (_, _) =>
        {
            if (_listening)
            {
                C.PropertyChanged -= OnControllerChanged;
                _listening = false;
            }
            Detached();
        };
    }

    void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!IsLoaded) return;
        try { OnChanged(e.PropertyName ?? ""); }
        catch (Exception) { }
    }

    /// <summary>İlk gösterilişte bir kez (aramalar, indirme başlatma).</summary>
    protected virtual void OnFirstShown() { }

    /// <summary>Her yüklenişte (pencere olaylarına abone olmak için).</summary>
    protected virtual void Attached() { }

    /// <summary>Her kaldırılışta (abonelikleri bırakmak için).</summary>
    protected virtual void Detached() { }

    /// <summary>Denetleyicinin bir özelliği değişti (arayüz iş parçacığında).</summary>
    protected virtual void OnChanged(string property) { }

    /// <summary>Adım düzenini içerik olarak kurar.</summary>
    protected WizardStep Layout(string title, string? description, UIElement content)
    {
        var step = new WizardStep { Title = title, Description = description, Content = content };
        Content = step;
        return step;
    }
}

/// <summary>Uzun süren eylemler için "await edilmeyen" çağrı: hataları yutar (denetleyici zaten günlüğe yazar).</summary>
internal static class Fire
{
    public static async void AndForget(Func<Task> work)
    {
        try { await work(); }
        catch (Exception) { }
    }
}
