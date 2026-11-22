// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>
/// Yazı tanımanın bir satırı. <see cref="Box"/> okuyucuya verilen görüntünün kenarlarına oranladır (yoksa okuyucu yer
/// vermiyor); <see cref="Confidence"/> 0–1 (Windows yazı tanıması vermez, Tesseract verebilir).
/// Kutusuz satırlar bütün yer kurallarından muaf geçer.
/// </summary>
public sealed record OcrLine(string Text, Box? Box = null, double? Confidence = null);

/// <summary>
/// Okuma: satırların yukarıdan aşağı listesi. Kurulurken metni boş ya da yalnız boşluk olan satırlar atılır.
/// Bütün platformlar yazı tanımayı bu soyut biçimle verir; hattın geri kalanı hangi okuyucunun çalıştığını bilmez.
/// </summary>
public sealed class OcrReading
{
    /// <summary>Hiç satırı olmayan okuma.</summary>
    public static OcrReading Empty { get; } = new([]);

    /// <summary>Satırlar (boş metinliler atılmış).</summary>
    public IReadOnlyList<OcrLine> Lines { get; }

    /// <summary>Satırlarla okuma (boş satırlar atılır).</summary>
    public OcrReading(IEnumerable<OcrLine> lines) =>
        Lines = lines.Where(l => !string.IsNullOrWhiteSpace(l.Text)).ToArray();

    /// <summary>Satır yok mu.</summary>
    public bool IsEmpty => Lines.Count == 0;

    /// <summary>Satır metinlerinin <c>\n</c> ile birleşmiş hali.</summary>
    public string Text => string.Join("\n", Lines.Select(l => l.Text));

    /// <summary>Yeri bilinen bütün satır kutularının birleşimi; hiçbirinin yeri bilinmiyorsa yok.</summary>
    public Box? Box
    {
        get
        {
            Box? union = null;
            foreach (var l in Lines)
                if (l.Box is { } b) union = union is { } u ? u.Union(b) : b;
            return union;
        }
    }

    /// <summary>Güveni bilinen satırların ortalaması; hiçbiri bilinmiyorsa yok.</summary>
    public double? Confidence
    {
        get
        {
            var known = Lines.Where(l => l.Confidence is not null).Select(l => l.Confidence!.Value).ToArray();
            return known.Length == 0 ? null : known.Average();
        }
    }

    /// <summary>Bütün satırların kutusu var mı (en az bir satır varken).</summary>
    public bool AllBoxed => Lines.Count > 0 && Lines.All(l => l.Box is not null);

    /// <summary>
    /// Yalnız metin veren okuyucunun okuması: <c>\r\n</c> → <c>\n</c>, satırlara bölünür, her satır kırpılır;
    /// satırlar kutusuz ve güvensizdir.
    /// </summary>
    public static OcrReading FromText(string? text) =>
        new((text ?? "").Replace("\r\n", "\n").Split('\n').Select(s => new OcrLine(s.Trim())));

    /// <summary>Bütün satır kutularını <paramref name="area"/>'nın içinden dış çerçeveye taşır (kutusuzlar kutusuz).</summary>
    public OcrReading PlaceIn(Box area) =>
        new(Lines.Select(l => l.Box is { } b ? l with { Box = b.PlaceIn(area) } : l));

    /// <summary>Satırları süzer; hiçbir satır değişmediyse aynı nesneyi döndürür.</summary>
    public OcrReading Where(Func<OcrLine, bool> keep)
    {
        var kept = Lines.Where(keep).ToArray();
        return kept.Length == Lines.Count ? this : new OcrReading(kept);
    }

    /// <inheritdoc />
    public override string ToString() => Text;
}
