// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Shell.Panels;

/// <summary>Bölge seçicide farenin yaptığı iş.</summary>
public enum RegionDragMode
{
    /// <summary>Sürükleme yok.</summary>
    None,

    /// <summary>Dışarıdan yeni çerçeve çizimi.</summary>
    Draw,

    /// <summary>Çerçevenin içinden taşıma.</summary>
    Move,

    /// <summary>Kenardan boyutlandırma.</summary>
    Resize,
}

/// <summary>Tutulan kenarlar.</summary>
[Flags]
public enum RegionEdges
{
    None = 0,
    Left = 1,
    Right = 2,
    Top = 4,
    Bottom = 8,
}

/// <summary>Farenin altında gösterilecek imleç.</summary>
public enum RegionCursor
{
    /// <summary>Artı (dışarıda: yeni çizim).</summary>
    Cross,

    /// <summary>Dört yönlü (içeride: taşıma).</summary>
    Move,

    /// <summary>Yatay ok (sol/sağ kenar).</summary>
    WestEast,

    /// <summary>Dikey ok (üst/alt kenar).</summary>
    NorthSouth,

    /// <summary>Sol-üst ya da sağ-alt köşe.</summary>
    NorthWestSouthEast,

    /// <summary>Sağ-üst ya da sol-alt köşe.</summary>
    NorthEastSouthWest,
}

/// <summary>
/// Oyunun görüntüsü üstündeki bölge çerçevesinin hesapları (ayarlar tarifi §8.4). Bölge kenarlara oranla (0–1);
/// fare koordinatları önizlemenin pikselinde.
/// </summary>
public static class RegionPickerMath
{
    /// <summary>Kenar yakalama payı (piksel).</summary>
    public const double EdgeGrab = 10;

    /// <summary>Boyutlandırmada karşı kenara en yakın uzaklık ve çizimin en küçük boyu (oran).</summary>
    public const double MinSize = 0.03;

    /// <summary>Önizlemenin en kısa boyu.</summary>
    public const double MinPreviewHeight = 120;

    /// <summary>Önizlemenin boyu: genişlik ÷ görüntünün en/boy oranı (kare yoksa 16:9), en az 120.</summary>
    public static double PreviewHeight(double width, int frameWidth = 0, int frameHeight = 0)
    {
        var ratio = frameWidth > 0 && frameHeight > 0 ? (double)frameWidth / frameHeight : 16.0 / 9.0;
        if (!double.IsFinite(width) || width <= 0) return 281;
        return Math.Max(MinPreviewHeight, width / ratio);
    }

    /// <summary>Basılan noktanın işi ve tutulan kenarlar.</summary>
    public static RegionDragMode ModeAt(Region region, double x, double y, double width, double height, out RegionEdges edges)
    {
        edges = EdgesAt(region, x, y, width, height);
        if (edges != RegionEdges.None) return RegionDragMode.Resize;
        return Inside(region, x, y, width, height) ? RegionDragMode.Move : RegionDragMode.Draw;
    }

    /// <summary>
    /// İmleç çerçevenin her yandan 10 büyütülmüş hâlinin içindeyse ve bir kenara ≤ 10 uzaktaysa o kenar(lar): yatayda
    /// önce sol, değilse sağ; dikeyde önce üst, değilse alt.
    /// </summary>
    public static RegionEdges EdgesAt(Region region, double x, double y, double width, double height)
    {
        var left = region.Left * width;
        var right = region.Right * width;
        var top = region.Top * height;
        var bottom = region.Bottom * height;
        if (x < left - EdgeGrab || x > right + EdgeGrab || y < top - EdgeGrab || y > bottom + EdgeGrab) return RegionEdges.None;
        var edges = RegionEdges.None;
        if (Math.Abs(x - left) <= EdgeGrab) edges |= RegionEdges.Left;
        else if (Math.Abs(x - right) <= EdgeGrab) edges |= RegionEdges.Right;
        if (Math.Abs(y - top) <= EdgeGrab) edges |= RegionEdges.Top;
        else if (Math.Abs(y - bottom) <= EdgeGrab) edges |= RegionEdges.Bottom;
        return edges;
    }

    static bool Inside(Region r, double x, double y, double width, double height) =>
        x >= r.Left * width && x <= r.Right * width && y >= r.Top * height && y <= r.Bottom * height;

    /// <summary>Basılı değilken imleç.</summary>
    public static RegionCursor CursorAt(Region region, double x, double y, double width, double height)
    {
        var e = EdgesAt(region, x, y, width, height);
        var horizontal = e & (RegionEdges.Left | RegionEdges.Right);
        var vertical = e & (RegionEdges.Top | RegionEdges.Bottom);
        if (horizontal != 0 && vertical != 0)
            return e == (RegionEdges.Left | RegionEdges.Top) || e == (RegionEdges.Right | RegionEdges.Bottom)
                ? RegionCursor.NorthWestSouthEast
                : RegionCursor.NorthEastSouthWest;
        if (horizontal != 0) return RegionCursor.WestEast;
        if (vertical != 0) return RegionCursor.NorthSouth;
        return Inside(region, x, y, width, height) ? RegionCursor.Move : RegionCursor.Cross;
    }

    /// <summary>Piksel → 0–1 oranı (kırpılmış).</summary>
    public static double Unit(double value, double size) => size > 0 && double.IsFinite(value) ? Math.Clamp(value / size, 0, 1) : 0;

    /// <summary>Çizim: başlangıç ile şimdiki noktanın kapsadığı dikdörtgen (oran).</summary>
    public static Region Draw(double startX, double startY, double nowX, double nowY) =>
        new(Math.Min(startY, nowY), Math.Max(startY, nowY), Math.Min(startX, nowX), Math.Max(startX, nowX));

    /// <summary>Taşıma: boyut aynı; sol/üst 0 ile 1 − boyut arasında.</summary>
    public static Region Move(Region start, double dx, double dy)
    {
        var w = start.Right - start.Left;
        var h = start.Bottom - start.Top;
        var left = Math.Clamp(start.Left + dx, 0, Math.Max(0, 1 - w));
        var top = Math.Clamp(start.Top + dy, 0, Math.Max(0, 1 - h));
        return new Region(top, top + h, left, left + w);
    }

    /// <summary>Boyutlandırma: tutulan kenar fareyi izler, karşı kenara en çok 0.03 yaklaşır.</summary>
    public static Region Resize(Region start, RegionEdges edges, double x, double y)
    {
        x = Math.Clamp(x, 0, 1);
        y = Math.Clamp(y, 0, 1);
        var (top, bottom, left, right) = (start.Top, start.Bottom, start.Left, start.Right);
        if (edges.HasFlag(RegionEdges.Left)) left = Math.Min(x, right - MinSize);
        if (edges.HasFlag(RegionEdges.Right)) right = Math.Max(x, left + MinSize);
        if (edges.HasFlag(RegionEdges.Top)) top = Math.Min(y, bottom - MinSize);
        if (edges.HasFlag(RegionEdges.Bottom)) bottom = Math.Max(y, top + MinSize);
        return new Region(Math.Clamp(top, 0, 1), Math.Clamp(bottom, 0, 1), Math.Clamp(left, 0, 1), Math.Clamp(right, 0, 1));
    }

    /// <summary>Bırakınca: çizimde genişlik ya da yükseklik 0.03'ten küçükse önceki bölge geri gelir.</summary>
    public static Region Finish(RegionDragMode mode, Region before, Region now) =>
        mode == RegionDragMode.Draw && (now.Right - now.Left < MinSize || now.Bottom - now.Top < MinSize) ? before : now;

    /// <summary>İki bölge aynı mı (olay ancak değiştiyse gelir).</summary>
    public static bool Same(Region a, Region b) =>
        a.Top == b.Top && a.Bottom == b.Bottom && a.Left == b.Left && a.Right == b.Right;
}
