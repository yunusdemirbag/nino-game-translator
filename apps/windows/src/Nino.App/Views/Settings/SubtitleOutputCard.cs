// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Settings;
using Nino.Core.Text;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Altyazı çıkışı kartı (ayarlar tarifi §3): konsol, oyun görüntüsü kaynağı, (kartta) altyazı yeri, HDMI yakalama kartı
/// bölmesi ve bilgisayar bölmesi. Ayrıntılı hâli Ayarlar › Bağlantı'da; kısa hâli ana ekranda (açıklamalar kısa,
/// önizleme yok). Görsel ağaca girince denetleyiciyi dinler; ayar, ayar kipi ve çeviri değişince baştan çizilir.
/// </summary>
public sealed class SubtitleOutputCard : Card
{
    readonly NinoController _c;
    readonly bool _detailed;
    readonly StackPanel _body = new();
    readonly LoadGuard _guard = new();
    CardPreview? _preview;
    bool _listening;

    public SubtitleOutputCard(NinoController controller, bool detailed)
    {
        _c = controller;
        _detailed = detailed;
        SetResourceReference(StyleProperty, typeof(Card));
        Content = _body;
        Loaded += (_, _) =>
        {
            if (!_listening)
            {
                _listening = true;
                _c.PropertyChanged += OnChanged;
            }
            Render();
        };
        Unloaded += (_, _) =>
        {
            if (_listening)
            {
                _listening = false;
                _c.PropertyChanged -= OnChanged;
            }
            DropPreview();
        };
    }

    void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(NinoController.Settings) or nameof(NinoController.AdjustMode)
            or nameof(NinoController.IsTranslating) or nameof(NinoController.IsStarting)
            or nameof(NinoController.ShowsOnTv) or nameof(NinoController.ShowsOnComputer))
            RenderSoon();
    }

    bool _renderQueued;

    /// <summary>Yeniden çizim olayın içinden değil, hemen ardından yapılır (basılan parça o anda kaldırılmasın).</summary>
    void RenderSoon()
    {
        if (_renderQueued) return;
        _renderQueued = true;
        Dispatcher.BeginInvoke(() =>
        {
            _renderQueued = false;
            if (_listening) Render();
        });
    }

    void Write(Action<AppSettings> change)
    {
        if (_guard.Busy) return;
        var s = _c.Settings;
        change(s);
        _c.UpdateSettings(s);
    }

    void DropPreview()
    {
        if (_preview is null) return;
        _preview.Detach();
        _preview = null;
    }

    void Render() => _guard.Run(() =>
    {
        var s = _c.Settings;
        var xbox = s.GameConsole == GameConsole.Xbox;
        _body.Children.Clear();

        // 1. Konsol.
        _body.Children.Add(Ui.Caption(L.Get("settings.connection.console")).At(0, 0, 0, 8));
        var console = new SegmentBar(true, "PS5", "Xbox") { Margin = new(0, 0, 0, 12) };
        console.Selected = xbox ? 1 : 0;
        console.Changed += i =>
        {
            var next = i == 1 ? GameConsole.Xbox : GameConsole.Ps5;
            if (_guard.Busy || next == _c.Settings.GameConsole) return;
            // Xbox'a geçerken PS5 yolu oyun penceresine döner, kart kalır (denetleyicinin kuralı).
            _c.SetGameConsole(next);
        };
        _body.Children.Add(console);

        // 2. Oyunun görüntüsü.
        _body.Children.Add(Ui.Caption(L.Get("settings.connection.picture")).At(0, 0, 0, 8));
        var source = new SegmentBar(true, "PS5",
            L.Get(xbox ? "settings.connection.source.xboxWindow" : "settings.connection.source.window"),
            L.Get("settings.connection.source.card")) { Margin = new(0, 0, 0, 12) };
        source.SetVisible(0, !xbox);
        source.Selected = _c.UsesGameWindow ? 1 : _c.UsesCaptureCard ? 2 : 0;
        source.Changed += i => Write(x => x.VideoSource = i switch
        {
            1 => VideoSource.Window,
            2 => VideoSource.Card,
            _ => VideoSource.Ps5,
        });
        _body.Children.Add(source);

        // 3. Kaynak ipucu.
        // Mac'le aynı: Xbox penceresinde Xbox ipucu her zaman; Remote Play ve PS5 ipuçları yalnız ayrıntılı hâlde.
        string? hintKey = _c.UsesCaptureCard ? null
            : _c.UsesGameWindow ? xbox ? "settings.connection.hint.xboxWindow" : _detailed ? "settings.connection.remotePlayHint" : null
            : _detailed ? "settings.connection.ps5Hint" : null;
        if (hintKey is not null) _body.Children.Add(Ui.Hint(L.Get(hintKey)).At(0, 0, 0, 12));

        // 4–5. HDMI yakalama kartı: altyazı yeri ve bölme.
        if (_c.UsesCaptureCard)
        {
            _body.Children.Add(Ui.Caption(L.Get("settings.connection.output")).At(0, 0, 0, 8));
            var output = new SegmentBar(true, L.Get("settings.connection.output.tv"), L.Get("settings.connection.output.computer"),
                L.Get("settings.connection.output.both"));
            output.Selected = s.Output switch
            {
                SubtitleOutput.Computer => 1,
                SubtitleOutput.Both => 2,
                _ => 0,
            };
            output.Changed += i => Write(x => x.Output = i switch
            {
                1 => SubtitleOutput.Computer,
                2 => SubtitleOutput.Both,
                _ => SubtitleOutput.Tv,
            });
            _body.Children.Add(output);
            _body.Children.Add(CardPane());
        }
        else DropPreview();

        // 6. Bilgisayar bölmesi.
        if (_c.ShowsOnComputer) _body.Children.Add(ComputerPane(s));
    });

    FrameworkElement CardPane()
    {
        var pane = new StackPanel { Margin = new(0, 12, 0, 0) };
        if (_detailed)
        {
            var output = _c.Settings.Output;
            if (output != SubtitleOutput.Computer) pane.Children.Add(Ui.Hint(L.Get("settings.connection.cardTVHint")).At(0, 0, 0, 12));
            if (output != SubtitleOutput.Tv) pane.Children.Add(Ui.Hint(L.Get("settings.connection.cardComputerHint")).At(0, 0, 0, 12));
        }
        var busy = _c.IsTranslating || _c.IsStarting;
        if (_detailed && !busy)
        {
            _preview ??= new CardPreview(_c, 170);
            _preview.RemoveFromParent();
            _preview.Margin = new(0, 0, 0, 12);
            pane.Children.Add(_preview);
        }
        else DropPreview();

        var content = Ui.Row(Ui.Icon("\uE8FD", 16, "textPrimaryBrush").At(0, 0, 8, 0),
            new TextBlock { Text = L.Get("settings.connection.guide"), VerticalAlignment = VerticalAlignment.Center });
        var guide = new Button { Content = content, Padding = new(16, 0, 16, 0), IsEnabled = !busy }.Styled("Button.Secondary");
        guide.ToolTip = L.Get("settings.connection.guideHelp");
        AutomationNames.Set(guide, L.Get("settings.connection.guide"));
        guide.Click += (_, _) =>
        {
            DropPreview();
            var window = new CaptureCardGuideWindow(_c) { Owner = Window.GetWindow(this) };
            window.ShowDialog();
            Render();
        };
        pane.Children.Add(guide);
        return pane;
    }

    FrameworkElement ComputerPane(AppSettings s)
    {
        var pane = new StackPanel { Margin = new(0, 12, 0, 0) };
        if (_detailed) pane.Children.Add(Ui.Hint(L.Get("settings.connection.computerHint")).At(0, 0, 0, 12));
        var toggle = Ui.Toggle(L.Get("settings.connection.clickThrough"));
        toggle.IsChecked = s.OverlayClickThrough;
        toggle.Margin = new(0, 0, 16, 8);
        toggle.Checked += (_, _) => Write(x => x.OverlayClickThrough = true);
        toggle.Unchecked += (_, _) => Write(x => x.OverlayClickThrough = false);
        var adjust = Ui.Button(L.Get("settings.connection.adjustWindow"), () => _c.AdjustMode = true);
        adjust.Padding = new(16, 0, 16, 0);
        adjust.Margin = new(0, 0, 0, 8);
        adjust.IsEnabled = !_c.AdjustMode;
        pane.Children.Add(Ui.Wrap(toggle, adjust));
        if (_detailed || s.OverlayClickThrough)
            pane.Children.Add(Ui.Hint(ShortcutText.ForSentence(L.Catalog, "settings.connection.clickThroughHint", s.Hotkeys,
                HotkeyAction.ClickThrough)));
        return pane;
    }
}
