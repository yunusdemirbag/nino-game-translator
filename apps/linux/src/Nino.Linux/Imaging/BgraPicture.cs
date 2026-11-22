// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Linux.Imaging;

/// <summary>
/// PS5'ten gelen bir kare ya da onun bir parçası: 4 bayt/piksel (mavi, yeşil, kırmızı, alfa), satır başına
/// <see cref="Stride"/> bayt. Çekirdeğin kare türüne uyarlayıcıda çevrilir.
/// </summary>
public sealed record BgraPicture(byte[] Pixels, int Width, int Height, int Stride)
{
    public static BgraPicture Packed(byte[] pixels, int width, int height) => new(pixels, width, height, width * 4);

    /// <summary>Dikdörtgen bir parçanın kopyası; görüntü dışına taşan kısım kırpılır.</summary>
    public BgraPicture Cut(int left, int top, int width, int height)
    {
        left = Math.Clamp(left, 0, Width);
        top = Math.Clamp(top, 0, Height);
        width = Math.Clamp(width, 0, Width - left);
        height = Math.Clamp(height, 0, Height - top);
        var copy = new byte[width * height * 4];
        for (var row = 0; row < height; row++)
            Buffer.BlockCopy(Pixels, (top + row) * Stride + left * 4, copy, row * width * 4, width * 4);
        return Packed(copy, width, height);
    }

    /// <summary>
    /// Tek kanallı parlaklık: (3·kırmızı + 6·yeşil + mavi) / 10. <paramref name="inverted"/> ise açık yazı koyuya
    /// döner; Tesseract açık zeminde koyu yazıyı daha iyi okur.
    /// </summary>
    public byte[] Luma(bool inverted)
    {
        var result = new byte[Width * Height];
        var at = 0;
        for (var y = 0; y < Height; y++)
        {
            var row = y * Stride;
            for (var x = 0; x < Width; x++, at++)
            {
                var p = row + x * 4;
                var value = (Pixels[p + 2] * 3 + Pixels[p + 1] * 6 + Pixels[p]) / 10;
                result[at] = (byte)(inverted ? 255 - value : value);
            }
        }
        return result;
    }
}
