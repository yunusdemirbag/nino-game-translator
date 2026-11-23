// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;
using Nino.Linux.Imaging;

namespace Nino.Linux.Tests;

public sealed class BgraPictureTests
{
    internal static BgraPicture Solid(int width, int height, byte b, byte g, byte r)
    {
        var pixels = new byte[width * height * 4];
        for (var i = 0; i < pixels.Length; i += 4) { pixels[i] = b; pixels[i + 1] = g; pixels[i + 2] = r; pixels[i + 3] = 255; }
        return BgraPicture.Packed(pixels, width, height);
    }

    [Fact]
    public void ParlaklikFormuluVeTersi()
    {
        var picture = Solid(2, 1, b: 10, g: 20, r: 30);
        Assert.Equal((30 * 3 + 20 * 6 + 10) / 10, picture.Luma(false)[0]);
        Assert.Equal(255 - (30 * 3 + 20 * 6 + 10) / 10, picture.Luma(true)[1]);
    }

    [Fact]
    public void Kesme()
    {
        var pixels = new byte[4 * 2 * 4];
        pixels[(1 * 4 + 3) * 4] = 99; // (3,1) noktasının mavisi
        var picture = new BgraPicture(pixels, 4, 2, 16);
        var cut = picture.Cut(2, 1, 5, 5);
        Assert.Equal((2, 1), (cut.Width, cut.Height));
        Assert.Equal(99, cut.Pixels[4]);
        Assert.Equal(0, picture.Cut(-5, -5, 1, 1).Pixels[0]);
    }
}

public sealed class PreviewPngTests
{
    [Fact]
    public void CrcBilinenDeger() => Assert.Equal(0xCBF43926u, PreviewPng.Checksum(Encoding.ASCII.GetBytes("123456789")));

    [Theory]
    [InlineData(null, 960)]
    [InlineData(10, 160)]
    [InlineData(5000, 1920)]
    [InlineData(640, 640)]
    public void GenislikSinirlari(int? asked, int expected) => Assert.Equal(expected, PreviewPng.ClampWidth(asked));

    [Fact]
    public void KucultulmusGecerliPng()
    {
        var picture = BgraPictureTests.Solid(1920, 1080, b: 1, g: 2, r: 3);
        var png = PreviewPng.Render(picture, 640);
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }, png[..8]);
        Assert.Equal("IHDR", Encoding.ASCII.GetString(png, 12, 4));
        Assert.Equal(640, BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(16)));
        Assert.Equal(360, BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(20)));

        // IDAT açılınca ilk piksel RGB sırasıyla gelir.
        var at = 8 + 25;
        var length = BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(at));
        Assert.Equal("IDAT", Encoding.ASCII.GetString(png, at + 4, 4));
        using var inflate = new ZLibStream(new MemoryStream(png, at + 8, length), CompressionMode.Decompress);
        var raw = new MemoryStream();
        inflate.CopyTo(raw);
        var bytes = raw.ToArray();
        Assert.Equal((640 * 3 + 1) * 360, bytes.Length);
        Assert.Equal(new byte[] { 0, 3, 2, 1 }, bytes[..4]);

        // IHDR'nin CRC'si doğru.
        var crc = BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(8 + 8 + 13));
        Assert.Equal(PreviewPng.Checksum(png[(8 + 4)..(8 + 8 + 13)]), crc);
        Assert.EndsWith("IEND", Encoding.ASCII.GetString(png, png.Length - 8, 4));
    }

    [Fact]
    public void TamSayiAdimlaSeyreltilir()
    {
        var png = PreviewPng.Render(BgraPictureTests.Solid(1000, 500, 0, 0, 0), 640);
        Assert.Equal(500, BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(16)));
        Assert.Equal(250, BinaryPrimitives.ReadInt32BigEndian(png.AsSpan(20)));
    }
}

public sealed class JpegWriterTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    private static BgraPicture Pattern(int width, int height)
    {
        var pixels = new byte[width * height * 4];
        for (var y = 0; y < height; y++)
            for (var x = 0; x < width; x++)
            {
                var i = (y * width + x) * 4;
                // sol yarı turuncu, sağ yarı koyu mavi
                if (x < width / 2) { pixels[i] = 40; pixels[i + 1] = 140; pixels[i + 2] = 230; }
                else { pixels[i] = 120; pixels[i + 1] = 40; pixels[i + 2] = 20; }
                pixels[i + 3] = 255;
            }
        return BgraPicture.Packed(pixels, width, height);
    }

    [Fact]
    public void BasVeSonIsaretleriBoyutKucultulur()
    {
        var jpeg = JpegWriter.Encode(Pattern(1920, 1080), 768, 60);
        Assert.Equal(new byte[] { 0xFF, 0xD8 }, jpeg[..2]);
        Assert.Equal(new byte[] { 0xFF, 0xD9 }, jpeg[^2..]);
        var sof = jpeg.AsSpan().IndexOf(new byte[] { 0xFF, 0xC0 });
        Assert.True(sof > 0);
        Assert.Equal(432, jpeg[sof + 5] << 8 | jpeg[sof + 6]); // yükseklik
        Assert.Equal(768, jpeg[sof + 7] << 8 | jpeg[sof + 8]); // genişlik
        Assert.True(jpeg.Length < 60_000);
    }

    [Fact]
    public void KaliteTablosu()
    {
        var table = Enumerable.Repeat((byte)16, 64).ToArray();
        Assert.Equal(16, JpegWriter.Scale(table, 50)[0]);
        Assert.Equal(1, JpegWriter.Scale(table, 100)[0]);
        Assert.Equal(32, JpegWriter.Scale(table, 25)[0]);
    }

    /// <summary>macOS'ta sips ile açılıp renkler karşılaştırılır (başka yerde atlanır).</summary>
    [Fact]
    public void BaskaBirOkuyucuAcabilir()
    {
        if (!File.Exists("/usr/bin/sips")) return;
        var file = temp.File("kare.jpg");
        File.WriteAllBytes(file, JpegWriter.Encode(Pattern(64, 32), 64, 90));
        var info = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("/usr/bin/sips",
            ["-s", "format", "bmp", file, "--out", temp.File("kare.bmp")]) { RedirectStandardOutput = true })!;
        info.WaitForExit();
        var bmp = File.ReadAllBytes(temp.File("kare.bmp"));
        var offset = BitConverter.ToInt32(bmp, 10);
        var bpp = BitConverter.ToInt16(bmp, 28) / 8;
        var rowBytes = (64 * bpp + 3) / 4 * 4;
        // ortadaki satırdan sol ve sağ birer piksel (BGR)
        var left = offset + 16 * rowBytes + 8 * bpp;
        var right = offset + 16 * rowBytes + 56 * bpp;
        Assert.InRange(bmp[left + 2], 200, 255);   // turuncunun kırmızısı
        Assert.InRange(bmp[right], 90, 150);       // mavinin mavisi
        Assert.InRange(bmp[right + 2], 0, 50);
    }
}
