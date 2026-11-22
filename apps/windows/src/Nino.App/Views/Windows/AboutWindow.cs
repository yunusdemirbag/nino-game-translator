// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using Nino.App.Controls;
using Nino.App.Strings;
using Nino.Shell;

namespace Nino.App.Views;

/// <summary>
/// Hakkında penceresi (yan pencereler tarifi §1): 460 genişlik, içeriğe göre yükseklik, boyutlanmaz. Telif satırı,
/// lisans, üçüncü taraf teşekkürleri ve bağlantılar.
/// </summary>
public sealed class AboutWindow : Window
{
    public const string SourceUrl = "https://github.com/yunusdemirbag/nino-game-translator";
    public const string ChiakiUrl = "https://github.com/chiaki-ng/chiaki-ng";
    public const string GreenlightUrl = "https://github.com/unknownskl/greenlight";

    /// <summary>Gizlilik metni (sitedeki gizlilik sayfasının yayın adresi).</summary>
    public const string PrivacyUrl = "https://github.com/yunusdemirbag/nino-game-translator/blob/main/PRIVACY.md";

    public AboutWindow(NinoController controller)
    {
        Ui.Prepare(this, L.Get("settings.section.about"));
        Width = 460;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;

        var panel = new StackPanel { Margin = new(32) };
        var logo = new LogoBox { Width = 88, Height = 88, HorizontalAlignment = HorizontalAlignment.Center };
        panel.Children.Add(logo);
        panel.Children.Add(Center(Ui.Title("Nino Game Translator")).At(0, 12, 0, 0));
        panel.Children.Add(Center(Ui.Hint(Version(controller))).At(0, 4, 0, 12));
        panel.Children.Add(Center(Ui.Secondary("Nino © 2026 Yunus Demirbağ")));
        panel.Children.Add(Center(Ui.Body(L.Get("about.license"))).At(0, 8, 0, 0));
        panel.Children.Add(Center(Ui.Secondary(L.Get("about.remotePlayCredit"))).At(0, 12, 0, 0));
        panel.Children.Add(Center(Ui.Secondary(L.Get("about.xboxCredit"))).At(0, 4, 0, 0));
        panel.Children.Add(Center(Ui.Secondary(L.Get("about.modelCredit"))).At(0, 4, 0, 0));

        var links = new TextBlock { TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap }.Styled("Text.Body");
        links.Margin = new(0, 12, 0, 0);
        AddLink(links, L.Get("about.sourceCode"), SourceUrl);
        links.Inlines.Add(new Run("  ·  "));
        AddLink(links, "chiaki-ng", ChiakiUrl);
        links.Inlines.Add(new Run("  ·  "));
        AddLink(links, "Greenlight", GreenlightUrl);
        panel.Children.Add(links);

        // Ölçüm kapatılamaz (olcum.md); karşılığında ne gönderildiği burada açıkça yazılır.
        var telemetry = new TextBlock { TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap }.Styled("Text.Caption");
        telemetry.Margin = new(0, 16, 0, 0);
        telemetry.Inlines.Add(new Run(L.Get("about.telemetry") + " "));
        AddLink(telemetry, L.Get("about.privacy"), PrivacyUrl);
        panel.Children.Add(telemetry);

        panel.Children.Add(Center(Ui.Caption(L.Get("about.sonyTrademark"))).At(0, 16, 0, 0));
        panel.Children.Add(Center(Ui.Caption(L.Get("about.microsoftTrademark"))).At(0, 4, 0, 0));

        var close = Ui.Primary(L.Get("common.close"), Close);
        close.IsDefault = true;
        close.IsCancel = true;
        close.HorizontalAlignment = HorizontalAlignment.Center;
        close.Margin = new(0, 20, 0, 0);
        panel.Children.Add(close);
        Content = panel;
    }

    static TextBlock Center(TextBlock t)
    {
        t.TextAlignment = TextAlignment.Center;
        t.HorizontalAlignment = HorizontalAlignment.Stretch;
        return t;
    }

    static void AddLink(TextBlock into, string text, string url)
    {
        var link = new Hyperlink(new Run(text)) { NavigateUri = new Uri(url), ToolTip = url };
        link.RequestNavigate += (_, e) =>
        {
            Ui.Open(e.Uri.AbsoluteUri);
            e.Handled = true;
        };
        into.Inlines.Add(link);
    }

    /// <summary>Uygulamanın bilgi sürümü, "+" ve sonrası atılmış (güncelleme denetimiyle aynı değer).</summary>
    public static string Version(NinoController? controller = null)
    {
        var info = Assembly.GetEntryAssembly()?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (string.IsNullOrWhiteSpace(info)) info = controller?.AppVersion ?? "";
        var plus = info.IndexOf('+');
        return plus >= 0 ? info[..plus] : info;
    }
}
