// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Phone;

/// <summary>Renk (her kanal 0–255).</summary>
public readonly record struct Rgb(int R, int G, int B)
{
    /// <summary>En büyük kanal.</summary>
    public int Max => Math.Max(R, Math.Max(G, B));

    /// <summary>En küçük kanal.</summary>
    public int Min => Math.Min(R, Math.Min(G, B));

    /// <summary>Yayılma (en büyük − en küçük).</summary>
    public int Spread => Max - Min;

    /// <summary>Parlaklık × 1000 (<c>R×299 + G×587 + B×114</c>).</summary>
    public int Luma1000 => R * 299 + G * 587 + B * 114;

    /// <summary>Parlaklık (tam bölüm).</summary>
    public int Luma => Luma1000 / 1000;

    /// <summary><c>#rrggbb</c> (küçük harf; kanallar 0–255'e kırpılır).</summary>
    public string Hex => $"#{Math.Clamp(R, 0, 255):x2}{Math.Clamp(G, 0, 255):x2}{Math.Clamp(B, 0, 255):x2}";
}

/// <summary>Kesirli (0–1) bir noktanın rengini veren örnekleyici.</summary>
public interface IColorSampler
{
    /// <summary>Noktanın rengi; okunamıyorsa null.</summary>
    Rgb? At(double x, double y);
}

/// <summary>İşlevle örnekleyici (testler ve yardımcılar).</summary>
public sealed class FuncSampler(Func<double, double, Rgb?> at) : IColorSampler
{
    /// <inheritdoc />
    public Rgb? At(double x, double y) => at(x, y);
}

/// <summary>Kareyi alan ortalamasıyla küçültülmüş RGB ızgarası.</summary>
public sealed class RgbGrid
{
    readonly byte[] _rgb;

    /// <summary>Genişlik.</summary>
    public int Width { get; }

    /// <summary>Yükseklik.</summary>
    public int Height { get; }

    RgbGrid(int width, int height, byte[] rgb)
    {
        Width = width;
        Height = height;
        _rgb = rgb;
    }

    /// <summary>Kırmızı.</summary>
    public int R(int x, int y) => _rgb[(y * Width + x) * 3];

    /// <summary>Yeşil.</summary>
    public int G(int x, int y) => _rgb[(y * Width + x) * 3 + 1];

    /// <summary>Mavi.</summary>
    public int B(int x, int y) => _rgb[(y * Width + x) * 3 + 2];

    /// <summary>Nokta rengi.</summary>
    public Rgb At(int x, int y)
    {
        var i = (y * Width + x) * 3;
        return new Rgb(_rgb[i], _rgb[i + 1], _rgb[i + 2]);
    }

    /// <summary>
    /// Alan ortalamasıyla küçültme: hedef noktanın kaynak alanı x'te <c>⌊tx × G / w⌋</c> ile
    /// <c>max(başlangıç + 1, ⌊(tx+1) × G / w⌋)</c> arası (y için aynı); kanalların tam bölmeli ortalaması. Kare boşsa
    /// null.
    /// </summary>
    public static RgbGrid? Downscale(BgraFrame frame, int width, int height)
    {
        if (frame.Width == 0 || frame.Height == 0 || width <= 0 || height <= 0) return null;
        var rgb = new byte[width * height * 3];
        var px = frame.Pixels;
        var fw = frame.Width;
        var fh = frame.Height;
        var xs = new int[width + 1];
        var xe = new int[width];
        for (var tx = 0; tx < width; tx++)
        {
            xs[tx] = (int)((long)tx * fw / width);
            xe[tx] = Math.Min(fw, Math.Max(xs[tx] + 1, (int)((long)(tx + 1) * fw / width)));
        }
        for (var ty = 0; ty < height; ty++)
        {
            var y0 = (int)((long)ty * fh / height);
            var y1 = Math.Min(fh, Math.Max(y0 + 1, (int)((long)(ty + 1) * fh / height)));
            for (var tx = 0; tx < width; tx++)
            {
                long sb = 0, sg = 0, sr = 0;
                var x0 = xs[tx];
                var x1 = xe[tx];
                for (var y = y0; y < y1; y++)
                {
                    var row = y * fw * 4;
                    for (var x = x0; x < x1; x++)
                    {
                        var i = row + x * 4;
                        sb += px[i];
                        sg += px[i + 1];
                        sr += px[i + 2];
                    }
                }
                long n = (long)(x1 - x0) * (y1 - y0);
                var o = (ty * width + tx) * 3;
                rgb[o] = (byte)(sr / n);
                rgb[o + 1] = (byte)(sg / n);
                rgb[o + 2] = (byte)(sb / n);
            }
        }
        return new RgbGrid(width, height, rgb);
    }
}

/// <summary>
/// Kare örnekleyicisi: kare bir kez istenen boyuta (varsayılan 960 × 540) küçültülür; <c>(x, y)</c> için
/// <c>cx = yuvarla(x × G)</c>, <c>cy = yuvarla(y × Y)</c> (yarımlar sıfırdan uzağa); kenar noktalarında renk yok;
/// renk çevresindeki 3 × 3 noktanın tam bölmeli ortalaması.
/// </summary>
public sealed class FrameSampler : IColorSampler
{
    /// <summary>Varsayılan genişlik.</summary>
    public const int DefaultWidth = 960;

    /// <summary>Varsayılan yükseklik.</summary>
    public const int DefaultHeight = 540;

    readonly RgbGrid? _grid;

    /// <summary>Kareden örnekleyici.</summary>
    public FrameSampler(BgraFrame frame, int width = DefaultWidth, int height = DefaultHeight) =>
        _grid = RgbGrid.Downscale(frame, width, height);

    /// <inheritdoc />
    public Rgb? At(double x, double y)
    {
        if (_grid is not { } g) return null;
        if (double.IsNaN(x) || double.IsNaN(y)) return null;
        var cx = (int)Math.Round(x * g.Width, MidpointRounding.AwayFromZero);
        var cy = (int)Math.Round(y * g.Height, MidpointRounding.AwayFromZero);
        if (cx < 1 || cy < 1 || cx >= g.Width - 1 || cy >= g.Height - 1) return null;
        int r = 0, gg = 0, b = 0;
        for (var dy = -1; dy <= 1; dy++)
            for (var dx = -1; dx <= 1; dx++)
            {
                r += g.R(cx + dx, cy + dy);
                gg += g.G(cx + dx, cy + dy);
                b += g.B(cx + dx, cy + dy);
            }
        return new Rgb(r / 9, gg / 9, b / 9);
    }
}

/// <summary>
/// Aydınlatılmış örnekleyici: kararmış açık telefon ekranını parlatır (koyu temalı uygulama ve renkli ekran olduğu
/// gibi kalır). Telefon yerleşiminde hep bu kullanılır.
/// </summary>
public sealed class BrightenedSampler : IColorSampler
{
    readonly IColorSampler _inner;

    /// <summary>Parlatma katı (1: parlatılmıyor).</summary>
    public double Gain { get; }

    /// <summary>Kareden ve telefondan örnekleyici.</summary>
    public BrightenedSampler(BgraFrame frame, PhoneShape phone) : this(new FrameSampler(frame), phone) { }

    /// <summary>Hazır örnekleyiciden.</summary>
    public BrightenedSampler(IColorSampler inner, PhoneShape phone)
    {
        _inner = inner;
        Gain = GainFor(inner, phone);
    }

    /// <summary>Telefon ekranının parlatma katı (koşullar sağlanmazsa 1).</summary>
    public static double GainFor(IColorSampler sampler, PhoneShape phone)
    {
        var colors = new List<Rgb>();
        var top = phone.Box.Top;
        var bottom = phone.Box.Bottom;
        for (var i = 0; ; i++)
        {
            var y = top + 0.03 + 0.02 * i;
            if (!(y < bottom - 0.02)) break;
            for (var k = 0; k < 10; k++)
            {
                var ratio = 0.05 + 0.1 * k;
                if (sampler.At(phone.LeftAt(y) + phone.Width * ratio, y) is { } c) colors.Add(c);
            }
        }
        if (colors.Count == 0) return 1;
        var sorted = colors.OrderBy(c => c.Max).ToArray();
        var n = sorted.Length;
        var screen = sorted[n * 8 / 10].Max;
        var mid = sorted[n / 2].Max;
        var region = sorted[n * 8 / 10];
        var gray = (double)region.Min / Math.Max(1, region.Max);
        var brightest = sorted[^1].Max;
        if (screen >= 40 && screen < 232 && mid >= screen * 0.8 && gray >= 0.8 && brightest <= screen * 1.3)
            return 238.0 / screen;
        return 1;
    }

    /// <inheritdoc />
    public Rgb? At(double x, double y)
    {
        if (_inner.At(x, y) is not { } c) return null;
        if (Gain == 1) return c;
        static int Scale(int v, double gain) => Math.Min(255, (int)(v * gain));
        return new Rgb(Scale(c.R, Gain), Scale(c.G, Gain), Scale(c.B, Gain));
    }
}
