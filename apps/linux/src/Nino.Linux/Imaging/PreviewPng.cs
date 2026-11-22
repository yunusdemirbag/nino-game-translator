// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers.Binary;
using System.IO.Compression;
using System.Text;

namespace Nino.Linux.Imaging;

/// <summary>
/// Paneldeki bölge seçimi için karenin küçük bir PNG'si. Kütüphane kullanmaz: kare tam sayı adımla seyreltilir,
/// 8 bit RGB satırları en hızlı zlib ile sıkıştırılır.
/// </summary>
public static class PreviewPng
{
    public const int Smallest = 160;
    public const int Largest = 1920;
    public const int Default = 960;

    private static readonly byte[] Signature = [0x89, (byte)'P', (byte)'N', (byte)'G', 0x0D, 0x0A, 0x1A, 0x0A];
    private static readonly Lazy<uint[]> Table = new(BuildTable);

    /// <summary>Panelden gelen genişlik isteğini sınırlar içine alır (yoksa varsayılan).</summary>
    public static int ClampWidth(int? requested) => Math.Clamp(requested ?? Default, Smallest, Largest);

    public static byte[] Render(BgraPicture picture, int widest)
    {
        var step = Math.Max(1, (picture.Width + widest - 1) / widest);
        var width = picture.Width / step;
        var height = picture.Height / step;
        var line = width * 3 + 1;
        var raw = new byte[line * height];
        for (var y = 0; y < height; y++)
        {
            var source = y * step * picture.Stride;
            var target = y * line;
            raw[target++] = 0; // süzgeç yok
            for (var x = 0; x < width; x++)
            {
                var p = source + x * step * 4;
                raw[target++] = picture.Pixels[p + 2];
                raw[target++] = picture.Pixels[p + 1];
                raw[target++] = picture.Pixels[p];
            }
        }

        var packed = new MemoryStream();
        using (var deflate = new ZLibStream(packed, CompressionLevel.Fastest, leaveOpen: true)) deflate.Write(raw);

        var header = new byte[13];
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(0), (uint)width);
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(4), (uint)height);
        header[8] = 8;  // bit derinliği
        header[9] = 2;  // renk türü: RGB
        // 10–12: sıkıştırma, süzgeç, satır atlama hep 0.

        var output = new MemoryStream();
        output.Write(Signature);
        WriteChunk(output, "IHDR", header);
        WriteChunk(output, "IDAT", packed.ToArray());
        WriteChunk(output, "IEND", []);
        return output.ToArray();
    }

    private static void WriteChunk(Stream output, string kind, byte[] body)
    {
        var name = Encoding.ASCII.GetBytes(kind);
        Span<byte> word = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(word, (uint)body.Length);
        output.Write(word);
        output.Write(name);
        output.Write(body);
        var crc = Update(Update(0xFFFFFFFFu, name), body) ^ 0xFFFFFFFFu;
        BinaryPrimitives.WriteUInt32BigEndian(word, crc);
        output.Write(word);
    }

    internal static uint Checksum(byte[] data) => Update(0xFFFFFFFFu, data) ^ 0xFFFFFFFFu;

    private static uint Update(uint crc, byte[] data)
    {
        var table = Table.Value;
        for (var i = 0; i < data.Length; i++) crc = table[(byte)(crc ^ data[i])] ^ (crc >> 8);
        return crc;
    }

    private static uint[] BuildTable()
    {
        const uint polynomial = 0xEDB88320u;
        var table = new uint[256];
        for (uint i = 0; i < table.Length; i++)
        {
            var value = i;
            for (var bit = 0; bit < 8; bit++) value = (value & 1) == 1 ? polynomial ^ (value >> 1) : value >> 1;
            table[i] = value;
        }
        return table;
    }
}
