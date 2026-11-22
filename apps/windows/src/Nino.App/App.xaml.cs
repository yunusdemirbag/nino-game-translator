// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.App.Strings;
using Nino.App.Theme;

namespace Nino.App;

/// <summary>
/// WPF uygulaması: ana pencere kapanınca kapanır. Kurulurken ortak stiller yüklenir, tasarım belirteçleri kaynaklara
/// konur (görünüm varsayılanı "Sistem"; ayar okununca <see cref="ThemeManager.Apply"/> çağrılır) ve arayüz sağdan
/// solaysa pencere başına yön kuralı kaydedilir. Pencereler burada açılmaz.
/// <para>Her pencere <c>Style="{DynamicResource Window.Nino}"</c> almalıdır: zemin, ana yazı rengi, metin yazısı ve
/// 15'lik boy oradan kalıtılır (genel yazı stili boy ve renk vermez; verirse düğme ve etiketlerin içini ezer).</para>
/// </summary>
public partial class App : Application
{
    public App()
    {
        InitializeComponent();
        ShutdownMode = ShutdownMode.OnMainWindowClose;
        RightToLeft.Install(L.IsRightToLeft);
        ThemeManager.Install(this);
    }
}
