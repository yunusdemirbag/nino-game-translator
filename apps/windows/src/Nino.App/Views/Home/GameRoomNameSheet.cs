// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Design;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Ana ekranın üstünde bir kez çıkan soru: "Oyun odanın adı ne olsun?" (alan + Kaydet + Atla). Zemin karartılır; Enter
/// kaydeder, Esc atlar.
/// </summary>
public sealed class GameRoomNameSheet : Grid
{
    readonly NinoController _c;
    readonly TextBox _name;

    /// <summary>Kaydedildi ya da atlandı.</summary>
    public event Action? Closed;

    public GameRoomNameSheet(NinoController controller)
    {
        _c = controller;
        Background = new SolidColorBrush(Color.FromArgb(0x8C, 0, 0, 0));
        FlowDirection = L.IsRightToLeft ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;

        var title = Ui.Title(L.Get("home.gameRoom.question"));
        title.TextWrapping = TextWrapping.Wrap;
        title.TextAlignment = TextAlignment.Center;
        title.Margin = new Thickness(0, 0, 0, 16);

        _name = new TextBox
        {
            Text = controller.SuggestedGameRoomName,
            MaxLength = GameRoomSign.MaxNameLength,
            FontSize = 18,
            Padding = new Thickness(10, 6, 10, 6),
            HorizontalContentAlignment = HorizontalAlignment.Center,
        };
        AutomationNames.Set(_name, L.Get("settings.gameRoom.name"));
        _name.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) { e.Handled = true; Save(); }
            else if (e.Key == Key.Escape) { e.Handled = true; Skip(); }
        };

        var skip = Ui.Ghost(L.Get("home.gameRoom.skip"), Skip);
        var save = Ui.Primary(L.Get("home.gameRoom.save"), Save);
        save.Margin = new Thickness(8, 0, 0, 0);
        var buttons = Ui.Row(skip, save);
        buttons.HorizontalAlignment = HorizontalAlignment.Right;
        buttons.Margin = new Thickness(0, 16, 0, 0);

        var card = new Card
        {
            Content = Ui.Column(title, _name, buttons),
            Padding = new Thickness(24),
            Width = 380,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        // Sekme tuşu soru kartının içinde döner; alttaki ana ekran düğmelerine (ve Enter'la fişe) geçilmez.
        KeyboardNavigation.SetTabNavigation(card, KeyboardNavigationMode.Cycle);
        KeyboardNavigation.SetControlTabNavigation(card, KeyboardNavigationMode.Cycle);
        Children.Add(card);
        Loaded += (_, _) =>
        {
            _name.Focus();
            _name.SelectAll();
        };
    }

    void Save()
    {
        _c.SaveGameRoomName(_name.Text);
        Closed?.Invoke();
    }

    void Skip()
    {
        _c.SkipGameRoomName();
        Closed?.Invoke();
    }
}
