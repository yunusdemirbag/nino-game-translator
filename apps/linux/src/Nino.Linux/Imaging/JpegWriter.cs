// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Linux.Imaging;

/// <summary>
/// Kütüphanesiz, temel (baseline) JPEG kodlayıcı: TV'deki buzlu zemin ve oyun tanıma için küçük kareler. Renk
/// YCbCr'ye çevrilir, alt örnekleme yapılmaz (4:4:4), 8×8 bloklar ayrık kosinüs dönüşümüyle nicelenir ve standardın
/// (ITU-T T.81, Ek K) örnek nicemleme ve Huffman tablolarıyla yazılır.
/// </summary>
public static class JpegWriter
{
    private static readonly byte[] ZigZag =
    [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
        28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61,
        54, 47, 55, 62, 63,
    ];

    // Ek K.1 ve K.2: parlaklık ve renk için örnek nicemleme tabloları (doğal sırada).
    private static readonly byte[] LumaBase =
    [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51,
        87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120,
        101, 72, 92, 95, 98, 112, 100, 103, 99,
    ];

    private static readonly byte[] ChromaBase =
    [
        17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99,
    ];

    // Ek K.3: standart Huffman tabloları (uzunluk sayıları ve değerler).
    private static readonly byte[] DcLumaCounts = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
    private static readonly byte[] DcChromaCounts = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
    private static readonly byte[] DcValues = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
    private static readonly byte[] AcLumaCounts = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
    private static readonly byte[] AcChromaCounts = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];

    private static readonly byte[] AcLumaValues =
    [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14,
        0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09,
        0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a,
        0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65,
        0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88,
        0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9,
        0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca,
        0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea,
        0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
    ];

    private static readonly byte[] AcChromaValues =
    [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32,
        0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16,
        0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39,
        0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64,
        0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86,
        0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
        0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8,
        0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9,
        0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0xfa,
    ];

    private static readonly double[,] Cosines = BuildCosines();

    /// <summary>Huffman kodu: değer → (kod, bit uzunluğu).</summary>
    private sealed class Code
    {
        public readonly ushort[] Bits = new ushort[256];
        public readonly byte[] Lengths = new byte[256];

        public Code(byte[] counts, byte[] values)
        {
            int k = 0, code = 0;
            for (var length = 1; length <= 16; length++)
            {
                for (var i = 0; i < counts[length - 1]; i++, k++)
                {
                    Bits[values[k]] = (ushort)code++;
                    Lengths[values[k]] = (byte)length;
                }
                code <<= 1;
            }
        }
    }

    private static readonly Code DcLuma = new(DcLumaCounts, DcValues);
    private static readonly Code DcChroma = new(DcChromaCounts, DcValues);
    private static readonly Code AcLuma = new(AcLumaCounts, AcLumaValues);
    private static readonly Code AcChroma = new(AcChromaCounts, AcChromaValues);

    /// <summary>Kareyi en çok <paramref name="maxWidth"/> genişliğe küçültüp <paramref name="quality"/> (1–100) ile kodlar.</summary>
    public static byte[] Encode(BgraPicture picture, int maxWidth, int quality)
    {
        var source = Shrink(picture, Math.Max(8, maxWidth));
        quality = Math.Clamp(quality, 1, 100);
        var luma = Scale(LumaBase, quality);
        var chroma = Scale(ChromaBase, quality);

        var output = new MemoryStream();
        output.Write([0xFF, 0xD8]); // görüntü başı
        WriteQuantTable(output, 0, luma);
        WriteQuantTable(output, 1, chroma);
        WriteFrameHeader(output, source.Width, source.Height);
        WriteHuffman(output, 0x00, DcLumaCounts, DcValues);
        WriteHuffman(output, 0x10, AcLumaCounts, AcLumaValues);
        WriteHuffman(output, 0x01, DcChromaCounts, DcValues);
        WriteHuffman(output, 0x11, AcChromaCounts, AcChromaValues);
        WriteScanHeader(output);

        var bits = new BitSink(output);
        int previousY = 0, previousCb = 0, previousCr = 0;
        Span<double> y = stackalloc double[64], cb = stackalloc double[64], cr = stackalloc double[64];
        for (var top = 0; top < source.Height; top += 8)
        {
            for (var left = 0; left < source.Width; left += 8)
            {
                Sample(source, left, top, y, cb, cr);
                previousY = EncodeBlock(bits, y, luma, previousY, DcLuma, AcLuma);
                previousCb = EncodeBlock(bits, cb, chroma, previousCb, DcChroma, AcChroma);
                previousCr = EncodeBlock(bits, cr, chroma, previousCr, DcChroma, AcChroma);
            }
        }
        bits.Finish();
        output.Write([0xFF, 0xD9]); // görüntü sonu
        return output.ToArray();
    }

    /// <summary>Kalite katsayısıyla tablo (IJG ölçeği): 50 tablonun kendisi, 100'e doğru incelir.</summary>
    internal static byte[] Scale(byte[] table, int quality)
    {
        var factor = quality < 50 ? 5000 / quality : 200 - quality * 2;
        var result = new byte[64];
        for (var i = 0; i < 64; i++) result[i] = (byte)Math.Clamp((table[i] * factor + 50) / 100, 1, 255);
        return result;
    }

    private static BgraPicture Shrink(BgraPicture picture, int maxWidth)
    {
        if (picture.Width <= maxWidth) return picture;
        var width = maxWidth;
        var height = Math.Max(1, (int)((long)picture.Height * width / picture.Width));
        var pixels = new byte[width * height * 4];
        for (var y = 0; y < height; y++)
        {
            var sy = (int)((long)y * picture.Height / height);
            for (var x = 0; x < width; x++)
            {
                var sx = (int)((long)x * picture.Width / width);
                Buffer.BlockCopy(picture.Pixels, sy * picture.Stride + sx * 4, pixels, (y * width + x) * 4, 4);
            }
        }
        return BgraPicture.Packed(pixels, width, height);
    }

    /// <summary>8×8 bloğun YCbCr değerleri (kenarı aşan yerlerde son piksel tekrarlanır), 128 kaydırılmış.</summary>
    private static void Sample(BgraPicture picture, int left, int top, Span<double> y, Span<double> cb, Span<double> cr)
    {
        for (var row = 0; row < 8; row++)
        {
            var py = Math.Min(top + row, picture.Height - 1);
            for (var col = 0; col < 8; col++)
            {
                var px = Math.Min(left + col, picture.Width - 1);
                var at = py * picture.Stride + px * 4;
                double b = picture.Pixels[at], g = picture.Pixels[at + 1], r = picture.Pixels[at + 2];
                var i = row * 8 + col;
                y[i] = 0.299 * r + 0.587 * g + 0.114 * b - 128;
                cb[i] = -0.168736 * r - 0.331264 * g + 0.5 * b;
                cr[i] = 0.5 * r - 0.418688 * g - 0.081312 * b;
            }
        }
    }

    private static double[,] BuildCosines()
    {
        var table = new double[8, 8];
        for (var x = 0; x < 8; x++)
            for (var u = 0; u < 8; u++)
                table[x, u] = Math.Cos((2 * x + 1) * u * Math.PI / 16);
        return table;
    }

    /// <summary>Bloğu dönüştürüp nicelendirir ve Huffman ile yazar; yeni DC değerini döner.</summary>
    private static int EncodeBlock(BitSink bits, ReadOnlySpan<double> block, byte[] table, int previousDc, Code dc, Code ac)
    {
        Span<int> quantized = stackalloc int[64];
        for (var v = 0; v < 8; v++)
        {
            for (var u = 0; u < 8; u++)
            {
                double sum = 0;
                for (var y = 0; y < 8; y++)
                    for (var x = 0; x < 8; x++)
                        sum += block[y * 8 + x] * Cosines[x, u] * Cosines[y, v];
                var cu = u == 0 ? Math.Sqrt(0.5) : 1;
                var cv = v == 0 ? Math.Sqrt(0.5) : 1;
                var coefficient = 0.25 * cu * cv * sum;
                quantized[v * 8 + u] = (int)Math.Round(coefficient / table[v * 8 + u]);
            }
        }

        var dcValue = quantized[0];
        WriteValue(bits, dc, 0, dcValue - previousDc);

        var zeros = 0;
        for (var k = 1; k < 64; k++)
        {
            var value = quantized[ZigZag[k]];
            if (value == 0)
            {
                zeros++;
                continue;
            }
            while (zeros >= 16)
            {
                bits.Write(ac.Bits[0xF0], ac.Lengths[0xF0]); // 16 sıfır
                zeros -= 16;
            }
            WriteValue(bits, ac, zeros, value);
            zeros = 0;
        }
        if (zeros > 0) bits.Write(ac.Bits[0x00], ac.Lengths[0x00]); // blok sonu
        return dcValue;
    }

    /// <summary>(sıfır sayısı, büyüklük sınıfı) simgesi ve ardından değerin bitleri.</summary>
    private static void WriteValue(BitSink bits, Code code, int zeros, int value)
    {
        var magnitude = Math.Abs(value);
        var size = 0;
        while (magnitude >> size != 0) size++;
        var symbol = (zeros << 4) | size;
        bits.Write(code.Bits[symbol], code.Lengths[symbol]);
        if (size == 0) return;
        var extra = value < 0 ? value + (1 << size) - 1 : value;
        bits.Write((ushort)extra, size);
    }

    private static void WriteMarker(Stream output, byte marker, int length)
    {
        output.WriteByte(0xFF);
        output.WriteByte(marker);
        output.WriteByte((byte)(length >> 8));
        output.WriteByte((byte)length);
    }

    private static void WriteQuantTable(Stream output, byte id, byte[] table)
    {
        WriteMarker(output, 0xDB, 67);
        output.WriteByte(id);
        for (var k = 0; k < 64; k++) output.WriteByte(table[ZigZag[k]]);
    }

    private static void WriteFrameHeader(Stream output, int width, int height)
    {
        WriteMarker(output, 0xC0, 17);
        output.WriteByte(8); // örnek başına bit
        output.WriteByte((byte)(height >> 8));
        output.WriteByte((byte)height);
        output.WriteByte((byte)(width >> 8));
        output.WriteByte((byte)width);
        output.WriteByte(3);
        output.Write([1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1]); // Y, Cb, Cr: örnekleme 1×1, tablolar
    }

    private static void WriteHuffman(Stream output, byte classAndId, byte[] counts, byte[] values)
    {
        WriteMarker(output, 0xC4, 19 + values.Length);
        output.WriteByte(classAndId);
        output.Write(counts);
        output.Write(values);
    }

    private static void WriteScanHeader(Stream output)
    {
        WriteMarker(output, 0xDA, 12);
        output.WriteByte(3);
        output.Write([1, 0x00, 2, 0x11, 3, 0x11]);
        output.Write([0, 63, 0]);
    }

    /// <summary>Bit yazıcı; 0xFF baytından sonra 0x00 eklenir (işaretle karışmasın).</summary>
    private sealed class BitSink(Stream output)
    {
        private int buffer;
        private int count;

        public void Write(ushort bits, int length)
        {
            for (var i = length - 1; i >= 0; i--)
            {
                buffer = (buffer << 1) | ((bits >> i) & 1);
                if (++count == 8) Flush();
            }
        }

        private void Flush()
        {
            output.WriteByte((byte)buffer);
            if (buffer == 0xFF) output.WriteByte(0);
            buffer = 0;
            count = 0;
        }

        /// <summary>Kalan bitler 1 ile doldurulur.</summary>
        public void Finish()
        {
            while (count != 0) Write(1, 1);
        }
    }
}
