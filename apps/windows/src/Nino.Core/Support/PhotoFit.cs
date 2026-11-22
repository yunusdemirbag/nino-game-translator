// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Support;

/// <summary>
/// Açılmış bir görüntüyü verilen boyda ve kalitede JPEG'e çeviren kodlayıcı (Windows'ta WPF, Linux'ta başka).
/// Kodlayamazsa null döner.
/// </summary>
public interface IJpegEncoder
{
    /// <summary>Görüntünün piksel boyu.</summary>
    int Width { get; }

    int Height { get; }

    /// <summary>Görüntüyü <paramref name="width"/>×<paramref name="height"/>'e ölçekleyip kodlar.</summary>
    byte[]? Encode(int width, int height, int quality);
}

/// <summary>Fotoğrafı bir bayt sınırına sığdırma (kodlayıcıdan bağımsız kurallar).</summary>
public static class PhotoFit
{
    /// <summary>Denenen en uzun kenarlar, sırayla.</summary>
    public static IReadOnlyList<int> Edges { get; } = [1600, 1280, 1024, 800, 640];

    /// <summary>Her kenarda denenen kaliteler, sırayla (önce kalite, sonra boyut).</summary>
    public static IReadOnlyList<int> Qualities { get; } = [70, 55, 40];

    /// <summary>Açılabilen görüntü uzantıları.</summary>
    public static IReadOnlyList<string> Extensions { get; } =
        ["png", "jpg", "jpeg", "heic", "heif", "webp", "bmp", "gif", "tif", "tiff"];

    /// <summary>Dosya seçici süzgecinin kalıbı.</summary>
    public static string FilterPattern => string.Join(";", Extensions.Select(e => "*." + e));

    /// <summary>Uzantıya göre görüntü dosyası mı.</summary>
    public static bool IsImageFile(string? path)
    {
        var ext = Path.GetExtension(path ?? "").TrimStart('.');
        return ext.Length > 0 && Extensions.Any(e => string.Equals(e, ext, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>En uzun kenar <paramref name="maxEdge"/>'i geçmesin; oran korunur, büyütülmez.</summary>
    public static (int Width, int Height) FitSize(int width, int height, int maxEdge)
    {
        if (width <= 0 || height <= 0) return (Math.Max(width, 0), Math.Max(height, 0));
        var longest = Math.Max(width, height);
        if (longest <= maxEdge) return (width, height);
        var scale = (double)maxEdge / longest;
        return (Math.Max(1, (int)Math.Round(width * scale)), Math.Max(1, (int)Math.Round(height * scale)));
    }

    /// <summary>
    /// Kenar × kalite denemelerinden sınırın altında kalan ilk sonuç; hiçbiri sığmazsa null.
    /// </summary>
    public static byte[]? Fit(IJpegEncoder encoder, int limitBytes)
    {
        if (encoder.Width <= 0 || encoder.Height <= 0) return null;
        (int, int)? previous = null;
        foreach (var edge in Edges)
        {
            var (w, h) = FitSize(encoder.Width, encoder.Height, edge);
            if (previous == (w, h)) continue; // küçük görüntü: aynı boy yeniden denenmez
            previous = (w, h);
            foreach (var quality in Qualities)
            {
                byte[]? bytes;
                try { bytes = encoder.Encode(w, h, quality); }
                catch { bytes = null; }
                if (bytes is { Length: > 0 } && bytes.Length <= limitBytes) return bytes;
            }
        }
        return null;
    }
}
