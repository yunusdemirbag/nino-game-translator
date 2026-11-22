// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Nino.Core.Imaging;
using Nino.Core.Phone;
using Nino.Core.Support;

namespace Nino.App.Services;

/// <summary>Görüntü dosyasını (JPG, PNG…) BGRA kareye çeviren Windows Imaging Component çözücüsü.</summary>
public sealed class WicFrameDecoder : IFrameDecoder
{
    /// <inheritdoc />
    public BgraFrame? Decode(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
            if (decoder.Frames.Count == 0) return null;
            var converted = new FormatConvertedBitmap(decoder.Frames[0], PixelFormats.Bgra32, null, 0);
            var w = converted.PixelWidth;
            var h = converted.PixelHeight;
            if (w <= 0 || h <= 0) return null;
            var pixels = new byte[w * h * 4];
            converted.CopyPixels(pixels, w * 4, 0);
            return new BgraFrame(w, h, pixels);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or NotSupportedException
            or FileFormatException or ArgumentException or InvalidOperationException or OutOfMemoryException
            or System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }
}

/// <summary>
/// Açılmış görüntüyü JPEG'e çeviren WPF kodlayıcısı (saglik-bildirim-sor §7.4): ilk kare, EXIF yönü uygulanmış,
/// saydamlık beyaz zemine çizilmiş, 24 bit, donmuş (iş parçacıkları arası). <see cref="PhotoFit.Fit"/> ile kullanılır.
/// </summary>
public sealed class WicJpegEncoder : IJpegEncoder
{
    readonly BitmapSource _image;

    WicJpegEncoder(BitmapSource image)
    {
        _image = image;
        _image.Freeze();
    }

    /// <inheritdoc />
    public int Width => _image.PixelWidth;

    /// <inheritdoc />
    public int Height => _image.PixelHeight;

    /// <summary>Dosyayı açar; açılamazsa null.</summary>
    public static WicJpegEncoder? Open(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
            if (decoder.Frames.Count == 0) return null;
            var frame = decoder.Frames[0];
            return FromBitmap(Rotate(frame, Orientation(frame)));
        }
        catch (Exception e) when (IsImageError(e))
        {
            return null;
        }
    }

    /// <summary>Panodaki ya da başka bir görüntüden (alfa yok sayılabilir).</summary>
    public static WicJpegEncoder? FromBitmap(BitmapSource source, bool ignoreAlpha = false)
    {
        try
        {
            return new WicJpegEncoder(OnWhite(source, ignoreAlpha));
        }
        catch (Exception e) when (IsImageError(e))
        {
            return null;
        }
    }

    /// <inheritdoc />
    public byte[]? Encode(int width, int height, int quality)
    {
        try
        {
            BitmapSource scaled = _image;
            if (width != Width || height != Height)
            {
                var t = new TransformedBitmap(_image, new ScaleTransform((double)width / Width, (double)height / Height));
                t.Freeze();
                scaled = t;
            }
            return Jpeg(scaled, quality);
        }
        catch (Exception e) when (IsImageError(e))
        {
            return null;
        }
    }

    /// <summary>
    /// Oyun tanıma karesi (§7.5): kare boşsa ya da piksel dizisi kısaysa null; genişlik en çok
    /// <paramref name="maxWidth"/>'e küçültülür (büyütülmez), kalite 1–100 kırpılır. Her kodlama hatasında null.
    /// </summary>
    public static byte[]? SmallJpeg(BgraFrame frame, int maxWidth, int quality)
    {
        try
        {
            if (frame.Width <= 0 || frame.Height <= 0 || frame.Pixels.Length < frame.Width * frame.Height * 4) return null;
            BitmapSource bitmap = BitmapSource.Create(frame.Width, frame.Height, 96, 96, PixelFormats.Bgra32, null,
                frame.Pixels, frame.Width * 4);
            bitmap.Freeze();
            if (maxWidth > 0 && frame.Width > maxWidth)
            {
                var scale = (double)maxWidth / frame.Width;
                var t = new TransformedBitmap(bitmap, new ScaleTransform(scale, scale));
                t.Freeze();
                bitmap = t;
            }
            var opaque = new FormatConvertedBitmap(bitmap, PixelFormats.Bgr24, null, 0);
            opaque.Freeze();
            return Jpeg(opaque, quality);
        }
        catch (Exception e) when (IsImageError(e))
        {
            return null;
        }
    }

    static byte[] Jpeg(BitmapSource source, int quality)
    {
        var jpeg = new JpegBitmapEncoder { QualityLevel = Math.Clamp(quality, 1, 100) };
        var frame = BitmapFrame.Create(source);
        jpeg.Frames.Add(frame);
        using var ms = new MemoryStream();
        jpeg.Save(ms);
        return ms.ToArray();
    }

    static bool IsImageError(Exception e) => e is IOException or UnauthorizedAccessException or NotSupportedException
        or FileFormatException or ArgumentException or InvalidOperationException or OutOfMemoryException
        or System.Runtime.InteropServices.COMException or OverflowException;

    static int Orientation(BitmapFrame frame)
    {
        try
        {
            if (frame.Metadata is BitmapMetadata m && m.GetQuery("System.Photo.Orientation") is ushort o) return o;
        }
        catch (Exception e) when (e is NotSupportedException or InvalidOperationException or ArgumentException
            or System.Runtime.InteropServices.COMException) { }
        return 1;
    }

    static BitmapSource Rotate(BitmapSource source, int orientation)
    {
        var angle = orientation switch { 6 => 90, 3 => 180, 8 => 270, _ => 0 };
        if (angle == 0) return source;
        var t = new TransformedBitmap(source, new RotateTransform(angle));
        t.Freeze();
        return t;
    }

    /// <summary>Saydamlığı beyaz zemine çizer, 24 bit renge çevirir.</summary>
    static BitmapSource OnWhite(BitmapSource source, bool ignoreAlpha)
    {
        var bgra = new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var w = bgra.PixelWidth;
        var h = bgra.PixelHeight;
        var pixels = new byte[w * h * 4];
        bgra.CopyPixels(pixels, w * 4, 0);
        var stride = (w * 3 + 3) / 4 * 4;
        var rgb = new byte[stride * h];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
            {
                var s = (y * w + x) * 4;
                var d = y * stride + x * 3;
                var a = ignoreAlpha ? 255 : pixels[s + 3];
                for (var c = 0; c < 3; c++) rgb[d + c] = (byte)((pixels[s + c] * a + 255 * (255 - a) + 127) / 255);
            }
        var result = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgr24, null, rgb, stride);
        result.Freeze();
        return result;
    }
}
