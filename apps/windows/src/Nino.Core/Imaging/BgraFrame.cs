// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Imaging;

/// <summary>
/// Görüntü: BGRA baytları (piksel başına 4 bayt: mavi, yeşil, kırmızı, saydamlık). Bu sınıfın ürettiği her kare
/// sıkıdır (satır adımı = genişlik × 4). Kareyi değiştiren işlemler yeni kare döndürür; kaynak dokunulmaz.
/// </summary>
public sealed class BgraFrame
{
    /// <summary>Genişlik (piksel).</summary>
    public int Width { get; }

    /// <summary>Yükseklik (piksel).</summary>
    public int Height { get; }

    /// <summary>Satır adımı (bayt); her zaman genişlik × 4.</summary>
    public int Stride => Width * 4;

    /// <summary>Sıkı BGRA baytları (uzunluk = genişlik × yükseklik × 4). Doğrudan yazılabilir.</summary>
    public byte[] Pixels { get; }

    /// <summary>Verilen sıkı baytlarla kare (kopyalamaz).</summary>
    public BgraFrame(int width, int height, byte[] pixels)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(width);
        ArgumentOutOfRangeException.ThrowIfNegative(height);
        if (pixels.Length != (long)width * height * 4)
            throw new ArgumentException("Bayt sayısı genişlik × yükseklik × 4 olmalı.", nameof(pixels));
        Width = width;
        Height = height;
        Pixels = pixels;
    }

    /// <summary>Bütün baytları 0 olan kare.</summary>
    public static BgraFrame Blank(int width, int height) => new(width, height, new byte[width * height * 4]);

    /// <summary>Bütün piksellerin (saydamlık dahil) her baytı <paramref name="value"/> olan kare.</summary>
    public static BgraFrame Filled(int width, int height, byte value)
    {
        var bytes = new byte[width * height * 4];
        Array.Fill(bytes, value);
        return new(width, height, bytes);
    }

    /// <summary>
    /// Yerel bir tampondan sıkı kopya: her satır kendi satır adımıyla okunur. Akış belleği geri çağrıdan sonra
    /// kullanılamadığı için hemen çağrılmalıdır.
    /// </summary>
    public static BgraFrame CopyFrom(ReadOnlySpan<byte> source, int width, int height, int stride)
    {
        if (stride < width * 4) throw new ArgumentOutOfRangeException(nameof(stride));
        var frame = Blank(width, height);
        var row = width * 4;
        for (var y = 0; y < height; y++)
            source.Slice(y * stride, row).CopyTo(frame.Pixels.AsSpan(y * row, row));
        return frame;
    }

    /// <summary>Pikselin baytlarının başladığı yer.</summary>
    public int IndexOf(int x, int y) => (y * Width + x) * 4;

    /// <summary>Pikseli yazar.</summary>
    public void SetPixel(int x, int y, byte b, byte g, byte r, byte a = 255)
    {
        var i = IndexOf(x, y);
        Pixels[i] = b;
        Pixels[i + 1] = g;
        Pixels[i + 2] = r;
        Pixels[i + 3] = a;
    }

    /// <summary>
    /// Piksel kırpma: x, y önce 0…genişlik / 0…yükseklik arasına, genişlik 0…(genişlik − x), yükseklik
    /// 0…(yükseklik − y) arasına sıkışır. Sonuç yeni, sıkı bir karedir.
    /// </summary>
    public BgraFrame Crop(int x, int y, int width, int height)
    {
        x = Math.Clamp(x, 0, Width);
        y = Math.Clamp(y, 0, Height);
        width = Math.Max(0, Math.Min(width, Width - x));
        height = Math.Max(0, Math.Min(height, Height - y));
        var result = Blank(width, height);
        var row = width * 4;
        for (var j = 0; j < height; j++)
            Pixels.AsSpan(IndexOf(x, y + j), row).CopyTo(result.Pixels.AsSpan(j * row, row));
        return result;
    }

    /// <summary>
    /// Oranla verilen bölgeyi keser: sol/üst aşağı, sağ/alt yukarı yuvarlanıp piksele çevrilir, sonra
    /// <see cref="Crop"/>.
    /// </summary>
    public BgraFrame CropRegion(Box box)
    {
        var left = (int)Math.Floor(Width * box.Left);
        var top = (int)Math.Floor(Height * box.Top);
        var right = (int)Math.Ceiling(Width * box.Right);
        var bottom = (int)Math.Ceiling(Height * box.Bottom);
        return Crop(left, top, right - left, bottom - top);
    }

    /// <summary>
    /// İki doğrusal büyütme (×n). Hedef (tx, ty) için kaynak <c>s = min((t + 0,5) / n − 0,5, boy − 1)</c>, eksiyse
    /// 0; dört kanal ayrı ayrı karıştırılır, sonuç en yakın çifte yuvarlanır.
    /// </summary>
    public BgraFrame Upscale(int factor)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(factor, 1);
        var w = Width * factor;
        var h = Height * factor;
        var result = Blank(w, h);
        if (Width == 0 || Height == 0) return result;
        var x0s = new int[w];
        var x1s = new int[w];
        var fxs = new double[w];
        for (var tx = 0; tx < w; tx++)
        {
            var sx = Math.Min((tx + 0.5) / factor - 0.5, Width - 1);
            if (sx < 0) sx = 0;
            x0s[tx] = (int)sx;
            x1s[tx] = Math.Min(x0s[tx] + 1, Width - 1);
            fxs[tx] = sx - x0s[tx];
        }
        var src = Pixels;
        var dst = result.Pixels;
        for (var ty = 0; ty < h; ty++)
        {
            var sy = Math.Min((ty + 0.5) / factor - 0.5, Height - 1);
            if (sy < 0) sy = 0;
            var y0 = (int)sy;
            var y1 = Math.Min(y0 + 1, Height - 1);
            var fy = sy - y0;
            var row0 = y0 * Width * 4;
            var row1 = y1 * Width * 4;
            var o = ty * w * 4;
            for (var tx = 0; tx < w; tx++)
            {
                var a0 = row0 + x0s[tx] * 4;
                var a1 = row0 + x1s[tx] * 4;
                var b0 = row1 + x0s[tx] * 4;
                var b1 = row1 + x1s[tx] * 4;
                var fx = fxs[tx];
                for (var c = 0; c < 4; c++)
                {
                    double top = src[a0 + c] + (src[a1 + c] - src[a0 + c]) * fx;
                    double bottom = src[b0 + c] + (src[b1 + c] - src[b0 + c]) * fx;
                    var v = Math.Round(top + (bottom - top) * fy, MidpointRounding.ToEven);
                    dst[o + tx * 4 + c] = (byte)Math.Clamp(v, 0, 255);
                }
            }
        }
        return result;
    }

    /// <summary>
    /// Bu kare karede <paramref name="area"/> kutusundan kesilmiş alanken, karedeki <paramref name="frameBox"/>
    /// kutusunun bu alana düşen kısmını siyaha (B=G=R=0, saydamlık 255) boyar. Kutu her yandan 0,01 genişletilir;
    /// alanın dışında kalıyorsa ya da alan boşsa kare olduğu gibi (aynı nesne) döner.
    /// </summary>
    public BgraFrame MaskBlack(Box frameBox, Box area, double margin = 0.01)
    {
        var aw = area.Width;
        var ah = area.Height;
        if (aw <= 0 || ah <= 0) return this;
        var local = frameBox.Inflate(margin).RelativeTo(area);
        if (local.Right <= 0 || local.Left >= 1 || local.Bottom <= 0 || local.Top >= 1) return this;
        var copy = new BgraFrame(Width, Height, (byte[])Pixels.Clone());
        var x0 = (int)Math.Floor(Math.Max(0, local.Left) * Width);
        var x1 = (int)Math.Ceiling(Math.Min(1, local.Right) * Width);
        var y0 = (int)Math.Floor(Math.Max(0, local.Top) * Height);
        var y1 = (int)Math.Ceiling(Math.Min(1, local.Bottom) * Height);
        x1 = Math.Min(x1, Width);
        y1 = Math.Min(y1, Height);
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++)
                copy.SetPixel(x, y, 0, 0, 0, 255);
        return copy;
    }
}
