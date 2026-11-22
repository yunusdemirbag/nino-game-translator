// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Core.Imaging;

/// <summary>
/// Oranla verilen dikdörtgen (0–1, başlangıç sol üst): sol, üst, sağ, alt. Ya karenin tamamına ya da okunan
/// alana göredir; hangisi olduğu kullanan yerde söylenir.
/// </summary>
public readonly record struct Box(double Left, double Top, double Right, double Bottom)
{
    /// <summary>Karenin tamamı.</summary>
    public static Box Whole { get; } = new(0, 0, 1, 1);

    /// <summary>Genişlik (sağ − sol).</summary>
    public double Width => Right - Left;

    /// <summary>Yükseklik (alt − üst).</summary>
    public double Height => Bottom - Top;

    /// <summary>Yatay orta.</summary>
    public double CenterX => (Left + Right) / 2;

    /// <summary>Dikey orta.</summary>
    public double CenterY => (Top + Bottom) / 2;

    /// <summary>İki kutuyu birlikte çevreleyen en küçük kutu.</summary>
    public Box Union(Box other) => new(
        Math.Min(Left, other.Left), Math.Min(Top, other.Top),
        Math.Max(Right, other.Right), Math.Max(Bottom, other.Bottom));

    /// <summary>
    /// Bu kutu <paramref name="area"/>'nın içindeyken onu dış çerçeveye taşır:
    /// <c>dış_sol = alan_sol + sol × alan_genişliği</c> (öbür kenarlar aynı yolla).
    /// </summary>
    public Box PlaceIn(Box area) => new(
        area.Left + Left * area.Width, area.Top + Top * area.Height,
        area.Left + Right * area.Width, area.Top + Bottom * area.Height);

    /// <summary><see cref="PlaceIn"/>'in tersi: dış çerçevedeki kutuyu alanın oranlarına çevirir (alan boşsa olduğu gibi).</summary>
    public Box RelativeTo(Box area)
    {
        var w = area.Width;
        var h = area.Height;
        if (w <= 0 || h <= 0) return this;
        return new((Left - area.Left) / w, (Top - area.Top) / h, (Right - area.Left) / w, (Bottom - area.Top) / h);
    }

    /// <summary>Her yandan <paramref name="margin"/> kadar genişletilmiş hali (kırpılmaz).</summary>
    public Box Inflate(double margin) => new(Left - margin, Top - margin, Right + margin, Bottom + margin);

    /// <summary>Nokta kutunun içinde mi (kenarlar dahil).</summary>
    public bool Contains(double x, double y) => x >= Left && x <= Right && y >= Top && y <= Bottom;

    /// <summary>Ayarlardaki bölge kaydından (üst, alt, sol, sağ sırası) kutu.</summary>
    public static Box FromRegion(Region region) => new(region.Left, region.Top, region.Right, region.Bottom);

    /// <summary>Ayarlardaki bölge kaydına (üst, alt, sol, sağ) çevirir.</summary>
    public Region ToRegion() => new(Top, Bottom, Left, Right);
}
