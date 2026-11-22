// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Imaging;

/// <summary>
/// Bölge izi: yazı tanımadan "alan değişti mi" diye bakmak için 64 sütun × 12 satır = 768 gri bayt.
/// </summary>
public static class RegionSignature
{
    /// <summary>Sütun sayısı.</summary>
    public const int Columns = 64;

    /// <summary>Satır sayısı.</summary>
    public const int Rows = 12;

    /// <summary>Varsayılan değişim eşiği: bir örnek bundan çok değişirse alan değişmiştir.</summary>
    public const int DefaultThreshold = 16;

    /// <summary>
    /// İz: satır y için kaynak satır <c>y × yükseklik / 12</c>, sütun x için <c>x × genişlik / 64</c> (tam sayı bölme);
    /// değer <c>(mavi + 2 × yeşil + kırmızı) / 4</c>. Boş karede 768 sıfır.
    /// </summary>
    public static byte[] Of(BgraFrame frame)
    {
        var sig = new byte[Columns * Rows];
        if (frame.Width == 0 || frame.Height == 0) return sig;
        var p = frame.Pixels;
        for (var y = 0; y < Rows; y++)
        {
            var sy = y * frame.Height / Rows;
            for (var x = 0; x < Columns; x++)
            {
                var sx = x * frame.Width / Columns;
                var i = frame.IndexOf(sx, sy);
                sig[y * Columns + x] = (byte)((p[i] + 2 * p[i + 1] + p[i + 2]) / 4);
            }
        }
        return sig;
    }

    /// <summary>
    /// İki iz farklı mı: uzunluklar farklıysa evet; bir örneğin farkı <paramref name="threshold"/>'dan büyükse evet.
    /// <paramref name="within"/> verilirse (izin alanına oranla) ve iz 64'ün katı uzunluktaysa yalnız kutunun
    /// örttüğü örneklere bakılır.
    /// </summary>
    public static bool Changed(ReadOnlySpan<byte> previous, ReadOnlySpan<byte> current, int threshold = DefaultThreshold,
        Box? within = null)
    {
        if (previous.Length != current.Length) return true;
        var rows = current.Length / Columns;
        if (within is { } b && rows > 0 && current.Length % Columns == 0)
        {
            var left = Math.Clamp((int)Math.Floor(b.Left * Columns), 0, Columns - 1);
            var right = Math.Clamp((int)Math.Ceiling(b.Right * Columns), left + 1, Columns);
            var top = Math.Clamp((int)Math.Floor(b.Top * rows), 0, rows - 1);
            var bottom = Math.Clamp((int)Math.Ceiling(b.Bottom * rows), top + 1, rows);
            for (var y = top; y < bottom; y++)
                for (var x = left; x < right; x++)
                {
                    var i = y * Columns + x;
                    if (Math.Abs(previous[i] - current[i]) > threshold) return true;
                }
            return false;
        }
        for (var i = 0; i < current.Length; i++)
            if (Math.Abs(previous[i] - current[i]) > threshold) return true;
        return false;
    }
}
