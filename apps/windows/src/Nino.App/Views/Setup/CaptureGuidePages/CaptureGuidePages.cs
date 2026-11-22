// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.App.Views.Setup;

namespace Nino.App.Views;

/// <summary>
/// HDMI yakalama kartı rehberi sayfa 1, bağlantı biçimi (kurulum.md §12.2): monitör ya da uygulamasız TV ve
/// Nino kurulu akıllı TV seçenek karoları. Seçim rehberin <see cref="CaptureGuide.OnTv"/> değeridir.
/// </summary>
public sealed class CaptureGuideConnectionPage : UserControl
{
    /// <summary>Sayfa 1.</summary>
    public CaptureGuideConnectionPage(CaptureGuide guide)
    {
        Focusable = false;
        var monitor = Option(guide, onTv: false, "cardGuide.page1.monitorTitle", "cardGuide.page1.monitorDescription",
            [Glyphs.Game, Glyphs.Connect, Glyphs.Laptop, Glyphs.TvMonitor]);
        var tv = Option(guide, onTv: true, "cardGuide.page1.tvTitle", "cardGuide.page1.tvDescription",
            [Glyphs.Game, Glyphs.Connect, Glyphs.TvMonitor]);
        tv.Margin = SetupUi.Top(12);
        Content = new WizardStep
        {
            Title = L.Get("cardGuide.page1.title"),
            Description = L.Get("cardGuide.page1.description"),
            Content = SetupUi.Stack(monitor, tv),
        };
    }

    static Button Option(CaptureGuide guide, bool onTv, string titleKey, string descriptionKey, string[] diagram)
    {
        var selected = guide.OnTv == onTv;
        var ring = SetupUi.Glyph(selected ? Glyphs.CompletedSolid : Glyphs.CircleRing, 22,
            selected ? "accentBrush" : "textSecondaryBrush");
        ring.VerticalAlignment = VerticalAlignment.Top;
        ring.Margin = SetupUi.M(0, 0, 16, 0);

        var schema = new StackPanel { Orientation = Orientation.Horizontal, Margin = SetupUi.Top(12) };
        var arrow = L.IsRightToLeft ? "←" : "→";
        for (var i = 0; i < diagram.Length; i++)
        {
            if (i > 0)
            {
                var a = SetupUi.Text(arrow, "Text.Caption", SetupUi.M(8, 0, 8, 0));
                a.VerticalAlignment = VerticalAlignment.Center;
                schema.Children.Add(a);
            }
            var tile = new Border
            {
                Width = 36,
                Height = 30,
                CornerRadius = new CornerRadius(8),
                Child = CenteredGlyph(diagram[i]),
            };
            tile.SetResourceReference(Border.BackgroundProperty, "accentSoftBrush");
            schema.Children.Add(tile);
        }

        var texts = SetupUi.Stack(SetupUi.Key(titleKey, "Text.Headline"), SetupUi.Key(descriptionKey, "Text.Callout", SetupUi.Top(6)), schema);
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(texts, 1);
        grid.Children.Add(ring);
        grid.Children.Add(texts);

        var card = new Card { Content = grid, IsActive = selected };
        var button = new Button
        {
            Content = card,
            Template = BareTemplate(),
            Cursor = Cursors.Hand,
            FocusVisualStyle = null,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Style = null,
        };
        button.Click += (_, _) => guide.OnTv = onTv;
        AutomationProperties.SetName(button, L.Get(titleKey));
        if (selected) AutomationProperties.SetItemStatus(button, L.Get("cardGuide.page1.selected"));
        return button;
    }

    static TextBlock CenteredGlyph(string glyph)
    {
        var g = SetupUi.Glyph(glyph, 16, "accentTextBrush");
        g.HorizontalAlignment = HorizontalAlignment.Center;
        return g;
    }

    // İçeriği olduğu gibi gösteren düğme (zemin, çerçeve, odak işareti yok).
    static ControlTemplate BareTemplate()
    {
        var template = new ControlTemplate(typeof(Button));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Stretch);
        template.VisualTree = presenter;
        return template;
    }
}

/// <summary>HDMI yakalama kartı rehberi sayfa 2, HDCP (kurulum.md §12.3).</summary>
public sealed class CaptureGuideHdcpPage : UserControl
{
    /// <summary>Sayfa 2.</summary>
    public CaptureGuideHdcpPage()
    {
        Focusable = false;
        var netflix = Info(Glyphs.Info, "cardGuide.page2.netflixInfo");
        netflix.Margin = SetupUi.M(0, 8, 0, 12);
        Content = new WizardStep
        {
            Title = L.Get("cardGuide.page2.title"),
            Description = L.Get("cardGuide.page2.description"),
            Content = SetupUi.Stack(
                SetupUi.Numbered(1, L.Get("cardGuide.page2.step1")),
                SetupUi.Numbered(2, L.Get("cardGuide.page2.step2")),
                SetupUi.Numbered(3, L.Get("cardGuide.page2.step3")),
                netflix,
                Info(Glyphs.Headphone, "cardGuide.page2.headsetInfo")),
        };
    }

    static Grid Info(string glyph, string key)
    {
        var icon = SetupUi.Glyph(glyph, 16);
        icon.VerticalAlignment = VerticalAlignment.Top;
        icon.Margin = SetupUi.M(0, 0, 10, 0);
        var text = SetupUi.Key(key, "Text.Callout");
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(text, 1);
        grid.Children.Add(icon);
        grid.Children.Add(text);
        return grid;
    }
}
