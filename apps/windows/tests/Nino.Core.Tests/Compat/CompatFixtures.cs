// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// Eski Windows uygulamasının ürettiği dosyalar ve kablo baytları (<c>Fixtures/Compat/old</c>) ile yeni kodun yazdığı
/// dosyaların eski kodla okunmuş halleri (<c>Fixtures/Compat/new</c>). Hepsi depodaki eski kodu çağıran ayrı bir deneme
/// programıyla üretildi; testler eski koda başvurmaz.
/// </summary>
static class CompatFixtures
{
    public static string Root => Path.Combine(AppContext.BaseDirectory, "Fixtures", "Compat");

    public static string Old(params string[] parts) => Path.Combine([Root, "old", .. parts]);

    public static string New(params string[] parts) => Path.Combine([Root, "new", .. parts]);

    public static byte[] OldBytes(params string[] parts) => File.ReadAllBytes(Old(parts));

    public static string OldText(params string[] parts) => Encoding.UTF8.GetString(OldBytes(parts));

    /// <summary>Bayt bayt aynı mı; değilse ilk farkın çevresini gösterir.</summary>
    public static void SameBytes(byte[] expected, byte[] actual, string what)
    {
        if (expected.AsSpan().SequenceEqual(actual)) return;
        var i = 0;
        while (i < expected.Length && i < actual.Length && expected[i] == actual[i]) i++;
        string Around(byte[] b) => Encoding.UTF8.GetString(b, Math.Max(0, i - 60), Math.Min(b.Length, i + 60) - Math.Max(0, i - 60));
        Assert.Fail($"{what}: {i}. baytta fark (beklenen {expected.Length}, gelen {actual.Length} bayt)\n" +
                    $"beklenen: …{Around(expected)}…\ngelen:    …{Around(actual)}…");
    }

    /// <summary>
    /// <c>NINO_COMPAT_EXPORT</c> ortam değişkeni verilmişse yeni kodun yazdığı dosyayı oraya kopyalar (deneme programı
    /// onları eski kodla okuyup <c>Fixtures/Compat/new</c> altına beklenen sonuç olarak koyar).
    /// </summary>
    public static void Export(string sourcePath, params string[] target)
    {
        if (Environment.GetEnvironmentVariable("NINO_COMPAT_EXPORT") is not { Length: > 0 } dir) return;
        var path = Path.Combine([dir, .. target]);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        if (Directory.Exists(sourcePath)) CopyFolder(sourcePath, path);
        else File.Copy(sourcePath, path, overwrite: true);
    }

    static void CopyFolder(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (var f in Directory.GetFiles(from)) File.Copy(f, Path.Combine(to, Path.GetFileName(f)), overwrite: true);
        foreach (var d in Directory.GetDirectories(from)) CopyFolder(d, Path.Combine(to, Path.GetFileName(d)));
    }

    /// <summary>
    /// Eski dosyalardaki oyun kimliği takma ad (<c>"gta6"</c>); yeni kod bilerek asıl kimliği (<c>"gta-6"</c>) yazar.
    /// Bayt karşılaştırmasında yalnız bu fark kaldırılır, kalan her bayt aynı olmalı.
    /// </summary>
    public static string Canon(string text) => text.Replace("\"gta6\"", "\"gta-6\"", StringComparison.Ordinal);

    /// <inheritdoc cref="Canon(string)"/>
    public static byte[] CanonBytes(byte[] bytes) => Encoding.UTF8.GetBytes(Canon(Encoding.UTF8.GetString(bytes)));

    public static void SameText(string expected, string actual, string what) =>
        SameBytes(Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(actual), what);
}
