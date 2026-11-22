// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.ComponentModel;
using System.Net.NetworkInformation;
using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Views.Setup;
using Nino.Core.Logging;
using Nino.Core.Tv;
using Nino.Shell;
using Nino.Shell.Setup;

namespace Nino.App.Views;

/// <summary>
/// TV'deki Nino kartı (kurulum.md §8.1, tv-kurulum.md §5.8): durum, ayrıntı, marka adımları, LG parolası,
/// Samsung oturumunu yeniden açma, sorun yazısı ve "Tekrar Dene". Durum "bilinmiyor"sa kart gizli. Kendiliğinden yeniden
/// denetlemeyi (3 sn) denetleyici yapar; kart yalnız durum, kalan saat, eşli TV ve bu bilgisayarın adresi değişince
/// yeniden çizilir.
/// </summary>
public sealed class TvAppCard : UserControl
{

    readonly NinoController _c;
    readonly TextBlock _status = SetupUi.Text("");
    readonly TextBlock _detail = SetupUi.Text("", "Text.Callout", SetupUi.Top(4));
    readonly StackPanel _lg;
    readonly StackPanel _samsung;
    readonly TextBlock _samsungHost = SetupUi.Text("", "Text.Callout");
    readonly StackPanel _android;
    readonly StackPanel _passphrase;
    readonly TextBox _passphraseBox = new();
    readonly StackPanel _reopen;
    readonly Button _copy;
    readonly TextBlock _problem = SetupUi.Text("", "Text.Error", SetupUi.Top(8));
    readonly Button _retry;
    TvAppKind? _lastKind;
    bool _listening;

    /// <summary>TV uygulaması kartı.</summary>
    public TvAppCard(NinoController controller)
    {
        _c = controller;
        Focusable = false;

        _lg = SetupUi.Stack(SetupUi.Key("tvApp.lg.step1", "Text.Callout"), SetupUi.Key("tvApp.lg.step2", "Text.Callout"),
            SetupUi.Key("tvApp.lg.step3", "Text.Callout"));
        _lg.Margin = SetupUi.Top(8);

        _samsung = SetupUi.Stack(SetupUi.Key("tvApp.samsung.step1", "Text.Callout"), SetupUi.Key("tvApp.samsung.step2", "Text.Callout"),
            _samsungHost, SetupUi.Key("tvApp.samsung.step4", "Text.Callout"),
            SetupUi.Key("tvApp.samsung.signInLater", "Text.Callout", SetupUi.Top(4)),
            SetupUi.Key("tvApp.samsung.cecTip", "Text.Callout", SetupUi.Top(4)));
        _samsung.Margin = SetupUi.Top(8);

        _android = SetupUi.Stack(SetupUi.Key("tvApp.android.step1", "Text.Callout"), SetupUi.Key("tvApp.android.step2", "Text.Callout"),
            SetupUi.Key("tvApp.android.step3", "Text.Callout"),
            SetupUi.Key("tvApp.android.searching", "Text.Callout", SetupUi.Top(4)),
            SetupUi.Key("tvApp.android.menuHint", "Text.Callout"),
            SetupUi.Button(L.Get("tvApp.android.usbInstead"), ButtonKind.Secondary, (_, _) => SetupUi.Open(Nino.Core.Support.SiteLinks.TvApp(L.Language, androidTv: true)), SetupUi.Top(8)));
        _android.Margin = SetupUi.Top(8);

        var install = SetupUi.Button(L.Get("tvApp.passphrase.install"), ButtonKind.Primary, (_, _) => Install());
        SetupUi.OnEnter(_passphraseBox, Install);
        var passRow = new Grid { Margin = SetupUi.Top(8) };
        passRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        passRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        passRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(install, 2);
        passRow.Children.Add(_passphraseBox);
        passRow.Children.Add(install);
        _passphrase = SetupUi.Stack(SetupUi.Key("tvApp.passphrase.hint", "Text.Callout"), passRow);
        _passphrase.Margin = SetupUi.Top(8);

        _copy = SetupUi.Button(L.Get("tvApp.reopen.copyLink"), ButtonKind.Secondary, (_, _) => CopyLink(), SetupUi.M(8, 0, 0, 0));
        var reopenRow = SetupUi.Row(SetupUi.Button(L.Get("tvApp.reopen.reopenPage"), ButtonKind.Secondary,
            (_, _) => _c.ReopenSamsungSignIn()), _copy);
        reopenRow.Margin = SetupUi.Top(8);
        _reopen = SetupUi.Stack(SetupUi.Key("tvApp.reopen.hint", "Text.Callout"), reopenRow);
        _reopen.Margin = SetupUi.Top(8);

        _retry = SetupUi.Button(L.Get("common.retry"), ButtonKind.Secondary, (_, _) => Fire.AndForget(_c.RecheckTvAppAsync), SetupUi.Top(8));

        Content = SetupUi.Card(SetupUi.Stack(_status, _detail, _lg, _samsung, _android, _passphrase, _reopen, _problem, _retry),
            L.Get("tvApp.title"));

        Loaded += (_, _) =>
        {
            if (!_listening)
            {
                _c.PropertyChanged += OnChanged;
                NetworkChange.NetworkAddressChanged += OnAddressChanged;
                _listening = true;
            }
            Render();
        };
        Unloaded += (_, _) =>
        {
            if (!_listening) return;
            _c.PropertyChanged -= OnChanged;
            NetworkChange.NetworkAddressChanged -= OnAddressChanged;
            _listening = false;
        };
        Render();
    }

    void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(NinoController.TvApp) or nameof(NinoController.LgHoursLeft)
            or nameof(NinoController.Tv) or nameof(NinoController.TvPaired))
            Render();
    }

    // Wi-Fi değişimi, VPN: gösterilen "Host PC IP" eskide kalmasın (olay ağ iş parçacığından gelir).
    void OnAddressChanged(object? sender, EventArgs e) =>
        Dispatcher.BeginInvoke(() =>
        {
            if (IsLoaded) Render();
        });

    void Render()
    {
        var status = _c.TvApp;
        var brand = _c.Tv?.Brand ?? TvBrand.Lg;
        // Adres yalnız Samsung'da gösterilir; ağı okumak her yenilemede gerekmez.
        var address = brand == TvBrand.Samsung && status.Kind != TvAppKind.Unknown ? _c.ThisComputerAddress() : null;
        var view = TvAppCardView.Build(status, brand, _c.LgHoursLeft, address, SetupUi.DisplayPath(LogNames.TvInstall), L.Catalog);
        SetupUi.Show(this, view.Visible);
        if (!view.Visible) return;
        SetupUi.SetText(_status, view.Status);
        SetupUi.SetText(_detail, view.Detail);
        SetupUi.Show(_lg, view.LgSteps);
        SetupUi.Show(_samsung, view.SamsungSteps);
        _samsungHost.Text = TvAppCardView.SamsungHostStep(address, L.Catalog);
        SetupUi.Show(_android, view.AndroidSteps);
        SetupUi.Show(_passphrase, view.Passphrase);
        SetupUi.Show(_reopen, view.Reopen);
        SetupUi.SetText(_problem, view.Problem);
        SetupUi.Show(_retry, view.Retry);
        if (_lastKind != status.Kind) _copy.Content = L.Get("tvApp.reopen.copyLink");
        _lastKind = status.Kind;
    }

    void Install()
    {
        var text = _passphraseBox.Text;
        if (string.IsNullOrWhiteSpace(text)) return;
        Fire.AndForget(() => _c.InstallLgWithPassphraseAsync(text));
    }

    void CopyLink()
    {
        if (_c.TvApp.SignInUrl is { Length: > 0 } url && SetupUi.TryCopy(url)) _copy.Content = L.Get("common.copied");
    }
}
