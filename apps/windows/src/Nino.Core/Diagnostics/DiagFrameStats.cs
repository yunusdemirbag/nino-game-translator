// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Diagnostics;

/// <summary>
/// Karenin teşhis için kaba özeti: ortalama parlaklık (0–255) ve seyrek örneklerden bir parmak izi (kareler aynı mı).
/// Görüntünün kendisi hiçbir yere gitmez.
/// </summary>
public static class DiagFrameStats
{
    const int Grid = 32;

    /// <summary>Ortalama parlaklık ve parmak izi (32×18 örnek).</summary>
    public static (double Luma, ulong Print) Sample(BgraFrame frame)
    {
        if (frame.Width <= 0 || frame.Height <= 0) return (0, 0);
        var rows = Grid * 9 / 16;
        double sum = 0;
        var count = 0;
        var print = 1469598103934665603UL;
        var pixels = frame.Pixels;
        for (var gy = 0; gy < rows; gy++)
        {
            var y = (int)((gy + 0.5) * frame.Height / rows);
            for (var gx = 0; gx < Grid; gx++)
            {
                var x = (int)((gx + 0.5) * frame.Width / Grid);
                var i = frame.IndexOf(Math.Min(x, frame.Width - 1), Math.Min(y, frame.Height - 1));
                if (i + 2 >= pixels.Length) continue;
                var luma = 0.114 * pixels[i] + 0.587 * pixels[i + 1] + 0.299 * pixels[i + 2];
                sum += luma;
                count++;
                print = (print ^ (byte)((int)luma >> 3)) * 1099511628211UL;
            }
        }
        return (count == 0 ? 0 : sum / count, print);
    }
}
