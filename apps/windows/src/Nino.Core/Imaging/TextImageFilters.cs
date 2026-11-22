// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Imaging;

/// <summary>
/// Yazı tanımadan önce uygulanan görüntü hazırlıkları. Hepsi platformdan bağımsızdır (Windows ve Linux okuyucuları
/// kullanır). Siyah-beyaz üretenler "yazı" sayılan pikseli siyah (0), geri kalanını beyaz (255) yapar; saydamlık 255.
/// Parlaklık (luma) her yerde <c>(3 × kırmızı + 6 × yeşil + mavi) / 10</c> tam sayı bölmesidir.
/// </summary>
public static class TextImageFilters
{
    /// <summary>Pikselin parlaklığı: <c>(3R + 6G + B) / 10</c>.</summary>
    public static int Luma(byte b, byte g, byte r) => (3 * r + 6 * g + b) / 10;

    /// <summary>
    /// Otomatik seviye: parlaklık çubuk grafiğinde 255'ten aşağı inilerek toplam, piksel sayısının %0,5'ine ulaştığı
    /// ilk değer "tepe"dir (hiç ulaşmazsa 0). Tepe 235 ve üstü ya da 60'ın altıysa kare değişmez (aynı nesne döner).
    /// Değilse her renk kanalı <c>min(255, tam(değer × 250 / tepe))</c>, saydamlık 255.
    /// Karanlık ya da soluk görüntüde beyaz altyazı 120–180'de kalır; bu adım onu beyaz yazı süzgecine hazırlar.
    /// </summary>
    public static BgraFrame AutoLevel(BgraFrame frame)
    {
        var histogram = new int[256];
        var p = frame.Pixels;
        for (var i = 0; i < p.Length; i += 4) histogram[Luma(p[i], p[i + 1], p[i + 2])]++;
        var limit = frame.Width * frame.Height * 0.005;
        var peak = 0;
        long sum = 0;
        for (var v = 255; v >= 0; v--)
        {
            sum += histogram[v];
            if (sum >= limit) { peak = v; break; }
        }
        if (peak >= 235 || peak < 60) return frame;
        var ratio = 250.0 / peak;
        var lut = new byte[256];
        for (var v = 0; v < 256; v++) lut[v] = (byte)Math.Min(255, (int)(v * ratio));
        var result = new byte[p.Length];
        for (var i = 0; i < p.Length; i += 4)
        {
            result[i] = lut[p[i]];
            result[i + 1] = lut[p[i + 1]];
            result[i + 2] = lut[p[i + 2]];
            result[i + 3] = 255;
        }
        return new BgraFrame(frame.Width, frame.Height, result);
    }

    /// <summary>
    /// Yalnız beyaz yazı (simetrik pencere). Parlak piksel: en küçük kanal ≥ <paramref name="minBright"/> ve
    /// (en büyük − en küçük) ≤ <paramref name="maxSpread"/>. Koyu piksel: parlaklık &lt; <paramref name="darkBelow"/>.
    /// Parlak pikselin her yöne <paramref name="radius"/> piksellik kare penceresinde (kenarda kırpılmış) en az bir
    /// koyu piksel varsa o piksel yazıdır (siyah); geri kalan her şey beyaz. Gölgeli/kenarlı beyaz altyazıyı açık
    /// zeminden ayırır. Pencere sayımı toplamlı tabloyla yapılır.
    /// </summary>
    public static BgraFrame WhiteText(BgraFrame frame, int radius = 5, int minBright = 200, int maxSpread = 45,
        int darkBelow = 110)
    {
        var w = frame.Width;
        var h = frame.Height;
        var bright = new bool[w * h];
        var dark = new int[w * h];
        var p = frame.Pixels;
        for (var i = 0; i < w * h; i++)
        {
            var o = i * 4;
            byte b = p[o], g = p[o + 1], r = p[o + 2];
            var min = Math.Min(b, Math.Min(g, r));
            var max = Math.Max(b, Math.Max(g, r));
            bright[i] = min >= minBright && max - min <= maxSpread;
            dark[i] = Luma(b, g, r) < darkBelow ? 1 : 0;
        }
        var table = SummedArea(dark, w, h);
        return Binary(w, h, (x, y) =>
            bright[y * w + x] && WindowSum(table, w, h, x - radius, y - radius, x + radius, y + radius) > 0);
    }

    /// <summary>
    /// Gölgeli yazı. Parlak piksel: (en küçük kanal ≥ <paramref name="minBright"/> ve en büyük − en küçük ≤
    /// <paramref name="maxSpread"/>) ya da (<paramref name="colored"/> açıksa ve en büyük kanal ≥ 170 ve
    /// en büyük − en küçük ≥ 60 ve parlaklık ≥ 120). Koyu: parlaklık &lt; <paramref name="darkBelow"/>. Pencere
    /// yalnız sağ-alta bakar (x…x+r, y…y+r, kenarda kırpılmış): açık zeminde harflerin sol üstündeki zemin yazı
    /// sanılmasın.
    /// </summary>
    public static BgraFrame ShadowText(BgraFrame frame, int radius, int minBright, int maxSpread, int darkBelow,
        bool colored = false)
    {
        var w = frame.Width;
        var h = frame.Height;
        var bright = new bool[w * h];
        var dark = new int[w * h];
        var p = frame.Pixels;
        for (var i = 0; i < w * h; i++)
        {
            var o = i * 4;
            byte b = p[o], g = p[o + 1], r = p[o + 2];
            var min = Math.Min(b, Math.Min(g, r));
            var max = Math.Max(b, Math.Max(g, r));
            var luma = Luma(b, g, r);
            bright[i] = (min >= minBright && max - min <= maxSpread)
                || (colored && max >= 170 && max - min >= 60 && luma >= 120);
            dark[i] = luma < darkBelow ? 1 : 0;
        }
        var table = SummedArea(dark, w, h);
        return Binary(w, h, (x, y) =>
            bright[y * w + x] && WindowSum(table, w, h, x, y, x + radius, y + radius) > 0);
    }

    static BgraFrame Binary(int w, int h, Func<int, int, bool> isText)
    {
        var result = new byte[w * h * 4];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
            {
                var o = (y * w + x) * 4;
                var v = isText(x, y) ? (byte)0 : (byte)255;
                result[o] = v;
                result[o + 1] = v;
                result[o + 2] = v;
                result[o + 3] = 255;
            }
        return new BgraFrame(w, h, result);
    }

    // (w+1) × (h+1) toplamlı tablo.
    static int[] SummedArea(int[] values, int w, int h)
    {
        var t = new int[(w + 1) * (h + 1)];
        for (var y = 0; y < h; y++)
        {
            var rowSum = 0;
            for (var x = 0; x < w; x++)
            {
                rowSum += values[y * w + x];
                t[(y + 1) * (w + 1) + x + 1] = t[y * (w + 1) + x + 1] + rowSum;
            }
        }
        return t;
    }

    static int WindowSum(int[] t, int w, int h, int x0, int y0, int x1, int y1)
    {
        x0 = Math.Max(0, x0);
        y0 = Math.Max(0, y0);
        x1 = Math.Min(w - 1, x1);
        y1 = Math.Min(h - 1, y1);
        if (x1 < x0 || y1 < y0) return 0;
        var stride = w + 1;
        return t[(y1 + 1) * stride + x1 + 1] - t[y0 * stride + x1 + 1] - t[(y1 + 1) * stride + x0] + t[y0 * stride + x0];
    }
}
