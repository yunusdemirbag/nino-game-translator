// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.App.Strings;
using Nino.Core.Design;
using Nino.Shell;
using Nino.Shell.Panels;

namespace Nino.App.Views;

/// <summary>
/// Ana ekran: "Oyun odası tabelası" anahtarı ve "Oda adı" alanı (en çok 16 harf). Değişiklik ana ekrana anında yansır
/// (ad yazılırken her harfte).
/// </summary>
internal sealed class GameRoomSection(SettingsWindow host) : SettingsSection(host)
{
    CheckBox? _toggle;
    TextBox? _name;

    public override SettingsPage Page => SettingsPage.Home;

    protected override void Build()
    {
        AddHeader();
        _toggle = Ui.Toggle(L.Get("settings.gameRoom.sign"));
        _toggle.Checked += (_, _) => { if (!Guard.Busy) C.SetGameRoomSign(true); };
        _toggle.Unchecked += (_, _) => { if (!Guard.Busy) C.SetGameRoomSign(false); };

        _name = new TextBox { MaxLength = GameRoomSign.MaxNameLength, MinWidth = 220 };
        AutomationNames.Set(_name, L.Get("settings.gameRoom.name"));
        _name.TextChanged += (_, _) =>
        {
            if (Guard.Busy || _name.Text == (C.Settings.GameRoomName ?? "")) return;
            C.SetGameRoomName(_name.Text);
        };
        AddCard(Ui.Card(null, _toggle, Ui.Labeled(L.Get("settings.gameRoom.name"), _name).At(0, 12, 0, 0)));
        Update();
    }

    void Update() => Guard.Run(() =>
    {
        var s = C.Settings;
        if (_toggle is not null) _toggle.IsChecked = s.GameRoomSign;
        if (_name is not null)
        {
            // Yazılırken kutu değiştirilmez (temizlenmiş ad baş/son boşluğu atar; imleç kaymasın).
            if (!_name.IsKeyboardFocusWithin) _name.Text = s.GameRoomName ?? "";
            _name.IsEnabled = s.GameRoomSign;
        }
    });

    public override void ControllerChanged(string property)
    {
        if (property == nameof(NinoController.Settings)) Update();
    }
}
