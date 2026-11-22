// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Linux.Imaging;

namespace Nino.Linux.Ocr;

/// <summary>Görüntüye oranla (0–1) bir dikdörtgen.</summary>
public readonly record struct OcrBox(double Left, double Top, double Right, double Bottom)
{
    public double Height => Bottom - Top;

    public OcrBox Merge(OcrBox other) =>
        new(Math.Min(Left, other.Left), Math.Min(Top, other.Top), Math.Max(Right, other.Right), Math.Max(Bottom, other.Bottom));

    /// <summary>Bu kutu bir alt görüntüye göreyse, onu içeren görüntüye göre yeri.</summary>
    public OcrBox Inside(OcrBox outer)
    {
        double w = outer.Right - outer.Left, h = outer.Bottom - outer.Top;
        return new(outer.Left + Left * w, outer.Top + Top * h, outer.Left + Right * w, outer.Top + Bottom * h);
    }
}

public sealed record OcrLine(string Text, OcrBox? Box);

/// <summary>Bir görüntünün okunması: yukarıdan aşağı sıralı satırlar.</summary>
public sealed record OcrReading(IReadOnlyList<OcrLine> Lines)
{
    public static OcrReading Nothing { get; } = new(Array.Empty<OcrLine>());

    public bool IsEmpty => Lines.Count == 0;

    public string Text => string.Join('\n', Lines.Select(line => line.Text));

    /// <summary>Bütün satırları kapsayan kutu.</summary>
    public OcrBox? Bounds
    {
        get
        {
            OcrBox? all = null;
            foreach (var line in Lines)
                if (line.Box is { } box) all = all?.Merge(box) ?? box;
            return all;
        }
    }

    public OcrReading Relocated(OcrBox outer) =>
        new(Lines.Select(line => line with { Box = line.Box?.Inside(outer) }).ToArray());
}

/// <summary>
/// Okuyucunun ortak çekirdekten aldığı kurallar. Çekirdek bağlanınca uyarlayıcı bunları çekirdeğin kendi
/// işlevlerine yönlendirir; böylece Linux ve masaüstü aynı ölçütle karar verir.
/// </summary>
public interface IOcrRules
{
    /// <summary>Yalnız beyaz (altyazı) yazısının kaldığı kopya; gerisi siyah.</summary>
    BgraPicture KeepWhiteText(BgraPicture picture);

    /// <summary>
    /// Görüntüyü tam sayı katla büyütür. Çekirdeğin büyütmesi kullanılır ki Linux ve masaüstü Tesseract'a aynı
    /// pikselleri versin.
    /// </summary>
    BgraPicture Enlarge(BgraPicture picture, int factor);

    /// <summary>Metin ne kadar gerçek sözcüklere benziyor (yüksek = daha iyi).</summary>
    double WordLikeness(string text);

    /// <summary>Aynı hizadaki iki parça arasındaki boşluk ayrı yazı sayılacak kadar geniş mi (pikseller).</summary>
    bool IsSeparateText(double gap, double lineHeight, double imageWidth);
}
