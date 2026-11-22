// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Phone;

/// <summary>
/// Görüntü dosyasını (JPG, PNG…) BGRA kareye çeviren çözücü. Nino.Core'da platformdan bağımsız bir JPG çözücü yok;
/// Windows'ta WIC, Linux'ta sistem araçları, testlerde macOS'un <c>sips</c> aracı doldurur.
/// </summary>
public interface IFrameDecoder
{
    /// <summary>Dosyanın karesi; çözülemezse null.</summary>
    BgraFrame? Decode(string path);
}

/// <summary>Sıkıştırılmamış BMP (24/32 bit) okuyucu: çözücülerin ara biçimi.</summary>
public static class BmpFile
{
    /// <summary>BMP baytlarından kare; desteklenmeyen biçimde null.</summary>
    public static BgraFrame? Read(ReadOnlySpan<byte> data)
    {
        if (data.Length < 54 || data[0] != 'B' || data[1] != 'M') return null;
        var offset = BitConverter.ToInt32(data[10..]);
        var width = BitConverter.ToInt32(data[18..]);
        var rawHeight = BitConverter.ToInt32(data[22..]);
        var bits = BitConverter.ToInt16(data[28..]);
        var compression = BitConverter.ToInt32(data[30..]);
        if (width <= 0 || rawHeight == 0 || bits is not (24 or 32) || compression is not (0 or 3)) return null;
        var height = Math.Abs(rawHeight);
        var bottomUp = rawHeight > 0;
        var bpp = bits / 8;
        var stride = (width * bpp + 3) / 4 * 4;
        if (offset + (long)stride * height > data.Length) return null;
        var frame = BgraFrame.Blank(width, height);
        for (var y = 0; y < height; y++)
        {
            var src = offset + (bottomUp ? height - 1 - y : y) * stride;
            for (var x = 0; x < width; x++)
            {
                var i = src + x * bpp;
                frame.SetPixel(x, y, data[i], data[i + 1], data[i + 2], 255);
            }
        }
        return frame;
    }
}
