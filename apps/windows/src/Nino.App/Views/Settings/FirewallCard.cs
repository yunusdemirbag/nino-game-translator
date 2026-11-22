// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Güvenlik duvarı uyarı kartı (yan pencereler tarifi §11): ana ekranda ve PS5 eşleştirme adımında, yalnız bağlantı
/// sorunluyken görünür. Denetleyicinin <see cref="NinoController.Firewall"/> durumunu dinler.
/// </summary>
public sealed class FirewallCard : Card
{
    readonly NinoController _c;
    readonly TextBlock _title;
    readonly TextBlock _hint;
    readonly Button _allow;
    bool _listening;

    public FirewallCard(NinoController controller)
    {
        _c = controller;
        SetResourceReference(StyleProperty, typeof(Card));
        _title = new TextBlock { FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
        _title.Res(TextBlock.ForegroundProperty, "warningBrush");
        _hint = Ui.Hint("").At(0, 8, 0, 0);
        _allow = Ui.Button(L.Get("firewall.card.allow"), () => _ = _c.AllowFirewallAsync()).At(0, 12, 0, 0);
        Content = Ui.Column(_title, _hint, _allow);
        Visibility = Visibility.Collapsed;
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
            if (!_listening) return;
            _listening = false;
            _c.PropertyChanged -= OnChanged;
        };
    }

    void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(NinoController.Firewall) or nameof(NinoController.IsTranslating) or nameof(NinoController.IsXbox))
            Dispatcher.BeginInvoke(Render);
    }

    void Render()
    {
        var hint = _c.Firewall;
        Visibility = hint == FirewallHint.None ? Visibility.Collapsed : Visibility.Visible;
        if (hint == FirewallHint.None) return;
        var running = _c.IsTranslating;
        _title.Text = L.Get(hint == FirewallHint.Allowed ? "firewall.card.titleReady" : "firewall.card.titleBlocked");
        _hint.Text = L.Get(hint switch
        {
            FirewallHint.PublicNetwork => "firewall.card.hintPublicNetwork",
            FirewallHint.Working => "firewall.card.hintWaiting",
            FirewallHint.Failed => "firewall.card.hintFailed",
            FirewallHint.Allowed => running ? "status.common.reconnecting" : "firewall.card.hintReadyPairing",
            _ when running && _c.IsXbox => "firewall.card.hintXbox",
            _ when running => "firewall.card.hintRunning",
            _ => "firewall.card.hintPairing",
        });
        _allow.Shown(hint is FirewallHint.Suggest or FirewallHint.Failed or FirewallHint.Working);
        _allow.IsEnabled = hint != FirewallHint.Working;
    }
}
