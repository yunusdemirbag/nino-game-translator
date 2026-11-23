// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Link;

/// <summary>
/// Buzlu zemin (<c>show.cover</c>): altyazı kutusunun arkasının bulanık, küçük JPEG'i. Platformdan bağımsız C#; JPEG'i
/// dışarıdan verilen kodlayıcı yapar (Windows WIC; kodlayıcı yoksa zemin gönderilmez).
/// <para>Adımlar (Mac ile aynı değerler): kutu x'te 0,04, y'de 0,035 genişletilip kareye kırpılır, kesilir; genişlik
/// 360'tan büyükse oranla küçültülür; Gauss bulanıklığı (yarıçap = en az 8, küçültülmüş yüksekliğin 0,55'i; kenarlar
/// uzatılır); renk: doygunluk ×1,15, parlaklık −0,12, karşıtlık ×0,9; JPEG kalitesi 55.</para>
/// </summary>
public static class FrostCover
{
    public const double ExpandX = 0.04;
    public const double ExpandY = 0.035;
    public const int MaxWidth = 360;
    public const int Quality = 55;
    public const double MinRadius = 8;
    public const double RadiusPerHeight = 0.55;
    public const double Saturation = 1.15;
    public const double Brightness = -0.12;
    public const double Contrast = 0.9;

    /// <summary>Genişletilmiş, kareye kırpılmış kutu.</summary>
    public static Box Expanded(Box b) => new(
        Math.Clamp(b.Left - ExpandX, 0, 1), Math.Clamp(b.Top - ExpandY, 0, 1),
        Math.Clamp(b.Right + ExpandX, 0, 1), Math.Clamp(b.Bottom + ExpandY, 0, 1));

    /// <summary>base64 JPEG; kesilecek yer boşsa ya da kodlayıcı başaramazsa null.</summary>
    public static string? Make(BgraFrame frame, Box box, Func<BgraFrame, int, byte[]?> encode)
    {
        var image = Render(frame, box);
        if (image is null) return null;
        var jpeg = encode(image, Quality);
        return jpeg is { Length: > 0 } ? Convert.ToBase64String(jpeg) : null;
    }

    /// <summary>Kodlanmadan önceki bulanık görüntü (testler ve kodlayıcı için).</summary>
    public static BgraFrame? Render(BgraFrame frame, Box box)
    {
        if (frame.Width <= 0 || frame.Height <= 0) return null;
        var e = Expanded(box);
        if (e.Width <= 0 || e.Height <= 0) return null;
        var left = (int)Math.Floor(frame.Width * e.Left);
        var top = (int)Math.Floor(frame.Height * e.Top);
        var right = Math.Min(frame.Width, (int)Math.Ceiling(frame.Width * e.Right));
        var bottom = Math.Min(frame.Height, (int)Math.Ceiling(frame.Height * e.Bottom));
        if (right - left <= 0 || bottom - top <= 0) return null;
        var cut = frame.Crop(left, top, right - left, bottom - top);

        var scale = Math.Min(1.0, (double)MaxWidth / cut.Width);
        var width = Math.Max(1, (int)Math.Round(cut.Width * scale));
        var height = Math.Max(1, (int)Math.Round(cut.Height * scale));
        var small = scale < 1 ? Shrink(cut, width, height) : cut;

        var radius = Math.Max(MinRadius, cut.Height * scale * RadiusPerHeight);
        var planes = ToPlanes(small);
        foreach (var plane in planes) Blur(plane, small.Width, small.Height, radius);
        return Colorize(planes, small.Width, small.Height);
    }

    /// <summary>Alan ortalamasıyla küçültme (her hedef pikselin kapladığı kaynak piksellerin ortalaması).</summary>
    static BgraFrame Shrink(BgraFrame src, int width, int height)
    {
        var dst = BgraFrame.Blank(width, height);
        var sx = (double)src.Width / width;
        var sy = (double)src.Height / height;
        for (var y = 0; y < height; y++)
        {
            var y0 = (int)Math.Floor(y * sy);
            var y1 = Math.Max(y0 + 1, Math.Min(src.Height, (int)Math.Ceiling((y + 1) * sy)));
            for (var x = 0; x < width; x++)
            {
                var x0 = (int)Math.Floor(x * sx);
                var x1 = Math.Max(x0 + 1, Math.Min(src.Width, (int)Math.Ceiling((x + 1) * sx)));
                long b = 0, g = 0, r = 0, n = 0;
                for (var yy = y0; yy < y1; yy++)
                {
                    var row = yy * src.Width;
                    for (var xx = x0; xx < x1; xx++)
                    {
                        var i = (row + xx) * 4;
                        b += src.Pixels[i];
                        g += src.Pixels[i + 1];
                        r += src.Pixels[i + 2];
                        n++;
                    }
                }
                var o = (y * width + x) * 4;
                dst.Pixels[o] = (byte)((b + n / 2) / n);
                dst.Pixels[o + 1] = (byte)((g + n / 2) / n);
                dst.Pixels[o + 2] = (byte)((r + n / 2) / n);
                dst.Pixels[o + 3] = 255;
            }
        }
        return dst;
    }

    /// <summary>Mavi, yeşil, kırmızı düzlemleri (0–1).</summary>
    static double[][] ToPlanes(BgraFrame f)
    {
        var n = f.Width * f.Height;
        var planes = new[] { new double[n], new double[n], new double[n] };
        for (var i = 0; i < n; i++)
        {
            planes[0][i] = f.Pixels[i * 4] / 255.0;
            planes[1][i] = f.Pixels[i * 4 + 1] / 255.0;
            planes[2][i] = f.Pixels[i * 4 + 2] / 255.0;
        }
        return planes;
    }

    /// <summary>
    /// Gauss bulanıklığının üç ardışık kutu bulanıklığıyla yaklaşığı (σ = yarıçap); kenar pikselleri dışarı uzatılır.
    /// </summary>
    static void Blur(double[] plane, int width, int height, double sigma)
    {
        var tmp = new double[plane.Length];
        foreach (var size in BoxSizes(sigma, 3))
        {
            var r = (size - 1) / 2;
            BoxPass(plane, tmp, width, height, r, horizontal: true);
            BoxPass(tmp, plane, width, height, r, horizontal: false);
        }
    }

    /// <summary>σ'ya denk düşen <paramref name="n"/> kutu genişliği (tek sayılar).</summary>
    static int[] BoxSizes(double sigma, int n)
    {
        var ideal = Math.Sqrt(12 * sigma * sigma / n + 1);
        var lower = (int)Math.Floor(ideal);
        if (lower % 2 == 0) lower--;
        var upper = lower + 2;
        var m = (int)Math.Round((12 * sigma * sigma - n * lower * lower - 4 * n * lower - 3 * n) / (-4.0 * lower - 4));
        return Enumerable.Range(0, n).Select(i => i < m ? lower : upper).ToArray();
    }

    static void BoxPass(double[] src, double[] dst, int width, int height, int r, bool horizontal)
    {
        var lines = horizontal ? height : width;
        var length = horizontal ? width : height;
        var step = horizontal ? 1 : width;
        var span = 2 * r + 1;
        for (var line = 0; line < lines; line++)
        {
            var start = horizontal ? line * width : line;
            double At(int k) => src[start + Math.Clamp(k, 0, length - 1) * step];
            var sum = 0.0;
            for (var k = -r; k <= r; k++) sum += At(k);
            for (var k = 0; k < length; k++)
            {
                dst[start + k * step] = sum / span;
                sum += At(k + r + 1) - At(k - r);
            }
        }
    }

    /// <summary>Doygunluk, parlaklık, karşıtlık; BGRA kare.</summary>
    static BgraFrame Colorize(double[][] p, int width, int height)
    {
        var f = BgraFrame.Blank(width, height);
        for (var i = 0; i < width * height; i++)
        {
            double b = p[0][i], g = p[1][i], r = p[2][i];
            var lum = 0.2125 * r + 0.7154 * g + 0.0721 * b;
            f.Pixels[i * 4] = Channel(b, lum);
            f.Pixels[i * 4 + 1] = Channel(g, lum);
            f.Pixels[i * 4 + 2] = Channel(r, lum);
            f.Pixels[i * 4 + 3] = 255;
        }
        return f;
    }

    static byte Channel(double c, double lum)
    {
        var v = lum + (c - lum) * Saturation;
        v += Brightness;
        v = (v - 0.5) * Contrast + 0.5;
        return (byte)Math.Round(Math.Clamp(v, 0, 1) * 255);
    }
}
