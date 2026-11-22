// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Controls;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Core.Tv;
using Nino.Shell;
using Nino.Shell.Setup;

namespace Nino.App.Views.Setup;

/// <summary>TV'yi bağla (kurulum.md §8): TV arama ve eşleşme, Android TV, "TV'm yok", TV uygulaması kartı.</summary>
internal sealed class TvStep : StepPage
{

    readonly TextBlock _pairedName = SetupUi.Text("", "Text.Success", SetupUi.Bottom(16));
    readonly Button _search;
    readonly TextBlock _notFound = SetupUi.Key("tv.search.notFound", "Text.Callout");
    readonly StackPanel _rows = new();
    readonly StackPanel _choices;
    readonly TextBlock _wait = SetupUi.Text("", "Text.Callout", SetupUi.Top(16));
    readonly TextBlock _error = SetupUi.Text("", "Text.Error", SetupUi.Top(12));
    readonly Card _manual;

    public TvStep(NinoController controller) : base(controller)
    {
        _search = SetupUi.Button(L.Get("tv.search.again"), ButtonKind.Secondary, (_, _) => Fire.AndForget(SearchAsync));
        _notFound.Visibility = Visibility.Collapsed;
        SetupUi.SetText(_wait, null);
        SetupUi.SetText(_error, null);

        var tvCard = SetupUi.Card(SetupUi.Stack(
            SetupUi.TopRow(SetupUi.Key("reading.target.tv", "Text.Headline"), _search, SetupUi.Bottom(12)),
            _notFound, _rows));

        var android = SetupUi.Card(SetupUi.Stack(
            SetupUi.TopRow(SetupUi.Text("Android TV / Google TV"),
                SetupUi.Button(L.Get("setup.select"), ButtonKind.Secondary,
                    (_, _) => Fire.AndForget(() => PairAsync(new TvRecord("Android TV", "", TvBrand.AndroidTv))))),
            SetupUi.Key("setup.tv.androidTvHint", "Text.Callout", SetupUi.Top(8))), margin: SetupUi.Top(16));

        var noTv = SetupUi.Card(SetupUi.Stack(
            SetupUi.TopRow(SetupUi.Strong(L.Get("setup.tv.noTvTitle")),
                SetupUi.Button(L.Get("setup.select"), ButtonKind.Secondary, (_, _) => C.NoTv())),
            SetupUi.Key("setup.tv.noTvHint", "Text.Callout", SetupUi.Top(8))), margin: SetupUi.Top(16));

        _choices = SetupUi.Stack(tvCard, android);

        _manual = SetupUi.Card(SetupUi.Stack(
            SetupUi.Key("setup.tv.manualInstallText"),
            SetupUi.Button(L.Get("tv.manual.openGuide"), ButtonKind.Secondary, (_, _) => SetupUi.Open(Nino.Core.Support.SiteLinks.TvApp(L.Language, C.Tv?.Brand == TvBrand.AndroidTv)), SetupUi.Top(8))),
            L.Get("tvApp.title"), SetupUi.Top(16));

        Layout(L.Get("setup.tv.title"), L.Get("setup.tv.description"), SetupUi.Stack(
            _pairedName, _choices, noTv, _wait,
            SetupUi.Key("tv.pair.hintPrivateNetwork", "Text.Callout", SetupUi.Top(16)),
            SetupUi.Key("setup.tv.firewallHint", "Text.Callout", SetupUi.Top(8)),
            _error,
            new TvAppCard(controller) { Margin = SetupUi.Top(16) },
            _manual));
        RenderPaired();
    }

    protected override void OnFirstShown()
    {
        RenderPaired();
        // Kurulum yarıda kalmış olabilir: eşli TV'nin uygulamasına yeniden bakılır.
        if (C.TvPaired && C.TvApp.Kind == TvAppKind.Unknown) Fire.AndForget(C.RecheckTvAppAsync);
        Fire.AndForget(SearchAsync);
    }

    protected override void OnChanged(string property)
    {
        if (property is nameof(NinoController.Tv) or nameof(NinoController.TvPaired) or nameof(NinoController.CanInstallTvApp))
            RenderPaired();
    }

    void RenderPaired()
    {
        SetupUi.SetText(_pairedName, C.TvPaired ? C.Tv?.Name : null);
        SetupUi.Show(_manual, C.TvPaired && C.Tv is { Brand: not TvBrand.Lg } && !C.CanInstallTvApp);
    }

    async Task SearchAsync()
    {
        _search.IsEnabled = false;
        _rows.Children.Clear();
        try { await C.SearchTvsAsync(); }
        finally { _search.IsEnabled = true; }
        _rows.Children.Clear();
        foreach (var tv in C.FoundTvs)
        {
            var found = tv;
            var connect = SetupUi.Button(L.Get("common.connect"), ButtonKind.Primary,
                (_, _) => Fire.AndForget(() => PairAsync(new TvRecord(found.Name, found.Host, found.Brand))));
            var row = SetupUi.TopRow(SetupUi.Text(L.Format("tv.search.row", tv.Name, tv.Host)), connect, SetupUi.M(0, 4, 0, 4));
            _rows.Children.Add(row);
        }
        SetupUi.Show(_notFound, C.FoundTvs.Count == 0);
    }

    async Task PairAsync(TvRecord tv)
    {
        if (C.PairingTv) return;
        _choices.IsEnabled = false;
        SetupUi.SetText(_wait, L.Get(tv.Brand == TvBrand.Samsung ? "setup.tv.waitSamsung" : "setup.tv.waitOther"));
        SetupUi.SetText(_error, null);
        var timedOut = false;
        var ok = false;
        try { ok = await C.PairTvAsync(tv); }
        catch (OperationCanceledException) { timedOut = true; }
        catch (Exception) { }
        finally
        {
            SetupUi.SetText(_wait, null);
            _choices.IsEnabled = true;
        }
        if (!ok && (timedOut || C.TvPairError is not null))
            SetupUi.SetText(_error, TvPairText.Describe(tv.Brand, C.TvPairError, timedOut, L.Catalog));
        RenderPaired();
    }
}
