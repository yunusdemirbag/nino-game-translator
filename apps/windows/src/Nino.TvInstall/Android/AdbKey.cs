// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers.Binary;
using System.Numerics;
using System.Security.Cryptography;

namespace Nino.TvInstall.Android;

/// <summary>ADB kimlik anahtarı: klasördeki <c>adbkey</c> (PKCS#8 PEM, 2048 bit). TV onayı bu anahtara verilir.</summary>
public static class AdbKey
{
    public const string FileName = "adbkey";
    public const int Bits = 2048;

    /// <summary>Anahtarı okur; yoksa, bozuksa ya da boyu farklıysa yenisini üretip yazar (Windows dışında 0600).</summary>
    public static RSA LoadOrCreate(string folder)
    {
        var path = Path.Combine(folder, FileName);
        try
        {
            if (File.Exists(path))
            {
                var rsa = RSA.Create();
                try
                {
                    rsa.ImportFromPem(File.ReadAllText(path));
                    if (rsa.KeySize == Bits) return rsa;
                }
                catch (Exception e) when (e is CryptographicException or ArgumentException) { }
                rsa.Dispose();
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }

        var key = RSA.Create(Bits);
        Directory.CreateDirectory(folder);
        File.WriteAllText(path, key.ExportPkcs8PrivateKeyPem() + "\n");
        if (!OperatingSystem.IsWindows())
        {
            try { File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite); }
            catch (IOException) { }
        }
        return key;
    }

    /// <summary>524 baytlık, Android'e özgü RSA açık anahtar düzeni.</summary>
    public static byte[] AndroidPublicKey(RSA rsa)
    {
        var p = rsa.ExportParameters(false);
        if (p.Modulus is null || p.Modulus.Length != 256 || p.Exponent is null)
            throw new CryptographicException("ADB anahtarı 2048 bit olmalı");
        var n = new BigInteger(p.Modulus, isUnsigned: true, isBigEndian: true);
        var result = new byte[524];
        BinaryPrimitives.WriteUInt32LittleEndian(result.AsSpan(0), 64);
        var n0 = (uint)(n & uint.MaxValue);
        var inv = (uint)BigInteger.ModPow(n0, (BigInteger.One << 31) - 1, BigInteger.One << 32); // n0 tek: n0^(2^31-1) ≡ n0⁻¹ (mod 2³²)
        BinaryPrimitives.WriteUInt32LittleEndian(result.AsSpan(4), unchecked(0u - inv));
        Little(n, result.AsSpan(8, 256));
        var rr = BigInteger.ModPow(BigInteger.One << 2048, 2, n);
        Little(rr, result.AsSpan(264, 256));
        var e = new BigInteger(p.Exponent, isUnsigned: true, isBigEndian: true);
        BinaryPrimitives.WriteUInt32LittleEndian(result.AsSpan(520), (uint)e);
        return result;
    }

    static void Little(BigInteger value, Span<byte> target)
    {
        var bytes = value.ToByteArray(isUnsigned: true, isBigEndian: false);
        target.Clear();
        bytes.AsSpan(0, Math.Min(bytes.Length, target.Length)).CopyTo(target);
    }
}
