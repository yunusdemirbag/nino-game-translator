// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Reading;

namespace Nino.Shell.Panels;

/// <summary>
/// Yayıncı penceresinin ("Nino Stream") ölçü hesapları (kaynaklar tarifi §5): tek renk zemin üstüne çizilen altyazı;
/// yazı boyları ve bölge hizası <see cref="OverlayDrawing"/> ile aynı.
/// </summary>
public static class StreamWindowRules
{
    /// <summary>İçeriğin varsayılan boyu (1280 × 720).</summary>
    public const double ContentWidth = 1280, ContentHeight = 720;

    /// <summary>Açılıştaki pencere boyu (başlık çubuğu ve kenarlarla).</summary>
    public const double WindowWidth = 1296, WindowHeight = 759;

    /// <summary>En küçük pencere boyu.</summary>
    public const double MinWidth = 400, MinHeight = 260;

    /// <summary>Ölçek = max(0,2, içerik yüksekliği / 1080); yükseklik yoksa (0, sonsuz, NaN) 720 sayılır.</summary>
    public static double Scale(double contentHeight)
    {
        var h = double.IsFinite(contentHeight) && contentHeight > 0 ? contentHeight : ContentHeight;
        return Math.Max(0.2, h / 1080);
    }

    /// <summary>Yanlardaki iç boşluk: 24 × ölçek.</summary>
    public static double SidePadding(double scale) => 24 * scale;

    /// <summary>Alttaki iç boşluk: içerik yüksekliği × 0,07 (yükseklik yoksa 720).</summary>
    public static double BottomPadding(double contentHeight) =>
        (double.IsFinite(contentHeight) && contentHeight > 0 ? contentHeight : ContentHeight) * 0.07;

    /// <summary>Ek alanların üst boşluğu: 16 × ölçek.</summary>
    public static double RegionTop(double scale) => 16 * scale;

    /// <summary>Satırın kutusu var mı: altyazı stilindeki arka plan yüzdesi &gt; 0 ise tam siyah kutu.</summary>
    public static bool HasBox(int backgroundPercent) => StreamBackgroundColors.BoxOpacity(backgroundPercent) > 0;

    /// <summary>
    /// Yazı renginin saydamlığı: kutu varken satırın yerine göre (şimdiki 1, önceki 0,6, daha eski 0,45); kutu yokken
    /// (yazı gölgeli, doğrudan zemin üstünde) 1, yarı saydam yazı chroma key zeminiyle karışmasın.
    /// </summary>
    public static double TextAlpha(StackRole role, bool boxed) => !boxed ? 1 : role switch
    {
        StackRole.Current => SubtitleStack.CurrentOpacity,
        StackRole.Previous => SubtitleStack.PreviousOpacity,
        _ => SubtitleStack.SecondPreviousOpacity,
    };
}
