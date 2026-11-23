// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers;
using System.Collections;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace Nino.Core.Link;

/// <summary>Önceden biçimlenmiş JSON sayısı (yuvarlama kuralı <see cref="WireNumbers"/>'ta).</summary>
public readonly record struct RawNumber(string Text);

/// <summary>
/// TV'ye giden JSON nesnesi. Anahtarlar her zaman ASCII sırasıyla yazılır; harfler kaçışsız kalır (yalnız tırnak,
/// ters bölü ve denetim karakterleri kaçışlanır). Değerler: dizge, bool, int, long, <see cref="RawNumber"/>,
/// <see cref="WireObject"/> ve bunların listesi. Eski 8787 akışı için <see cref="ToLegacyString"/>: eski uygulamanın
/// kaçış kuralı (bkz. orada).
/// </summary>
public sealed class WireObject : IEnumerable<KeyValuePair<string, object>>
{
    readonly SortedDictionary<string, object> fields = new(StringComparer.Ordinal);

    public object this[string key]
    {
        get => fields[key];
        set => fields[key] = value;
    }

    public void Add(string key, object value) => fields[key] = value;

    public bool ContainsKey(string key) => fields.ContainsKey(key);

    public int Count => fields.Count;

    public IEnumerator<KeyValuePair<string, object>> GetEnumerator() => fields.GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();

    /// <summary>Kopya; alanlar sığ kopyalanır.</summary>
    public WireObject Clone()
    {
        var copy = new WireObject();
        foreach (var (k, v) in fields) copy.fields[k] = v;
        return copy;
    }

    public override string ToString()
    {
        var sb = new StringBuilder();
        Write(sb, this, legacy: false);
        return sb.ToString();
    }

    /// <summary>
    /// Eski 8787 akışının yazımı: dizgeler .NET JSON yazıcısının "gevşek" kaçışıyla yazılır (eski uygulama böyle
    /// gönderiyordu; kablo baytları birebir aynı kalsın). Harfler, <c>&lt; &gt; &amp; ' +</c> kaçışsız; denetim
    /// karakterleri büyük harfli <c>\u001B</c>, ayrıca U+007F–U+00A0, U+2028/U+2029 gibi biçim/ayraç karakterleri ve
    /// BMP dışı karakterler (emoji) <c>\uXXXX</c> çiftiyle.
    /// </summary>
    public string ToLegacyString()
    {
        var sb = new StringBuilder();
        Write(sb, this, legacy: true);
        return sb.ToString();
    }

    /// <summary>Önce verilen alanlar (sırasıyla), sonra kalanlar alfabetik.</summary>
    public string ToString(params string[] leading)
    {
        var sb = new StringBuilder("{");
        var first = true;
        foreach (var key in leading)
        {
            if (!fields.TryGetValue(key, out var value)) continue;
            AppendField(sb, key, value, ref first);
        }
        foreach (var (key, value) in fields)
        {
            if (Array.IndexOf(leading, key) >= 0) continue;
            AppendField(sb, key, value, ref first);
        }
        return sb.Append('}').ToString();
    }

    static void AppendField(StringBuilder sb, string key, object value, ref bool first, bool legacy = false)
    {
        if (!first) sb.Append(',');
        first = false;
        WriteString(sb, key, legacy);
        sb.Append(':');
        Write(sb, value, legacy);
    }

    static void Write(StringBuilder sb, object value, bool legacy)
    {
        switch (value)
        {
            case string s: WriteString(sb, s, legacy); break;
            case bool b: sb.Append(b ? "true" : "false"); break;
            case int i: sb.Append(i.ToString(CultureInfo.InvariantCulture)); break;
            case long l: sb.Append(l.ToString(CultureInfo.InvariantCulture)); break;
            case RawNumber n: sb.Append(n.Text); break;
            case WireObject o:
                sb.Append('{');
                var first = true;
                foreach (var (k, v) in o.fields) AppendField(sb, k, v, ref first, legacy);
                sb.Append('}');
                break;
            case IEnumerable list:
                sb.Append('[');
                var any = false;
                foreach (var item in list)
                {
                    if (any) sb.Append(',');
                    any = true;
                    Write(sb, item!, legacy);
                }
                sb.Append(']');
                break;
            default: throw new ArgumentException($"JSON'a yazılamayan değer: {value.GetType().Name}");
        }
    }

    static readonly JsonWriterOptions LegacyWriter = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    static void WriteString(StringBuilder sb, string s, bool legacy)
    {
        if (!legacy)
        {
            WriteString(sb, s);
            return;
        }
        var buffer = new ArrayBufferWriter<byte>(s.Length + 16);
        using (var w = new Utf8JsonWriter(buffer, LegacyWriter)) w.WriteStringValue(s);
        sb.Append(Encoding.UTF8.GetString(buffer.WrittenSpan));
    }

    /// <summary>JSON dizgesi: yalnız tırnak, ters bölü ve U+0020 altı kaçışlanır.</summary>
    public static void WriteString(StringBuilder sb, string s)
    {
        sb.Append('"');
        foreach (var c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                case '\b': sb.Append("\\b"); break;
                case '\f': sb.Append("\\f"); break;
                default:
                    if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}

/// <summary>TV'ye giden sayıların yuvarlama kuralları (8787 ve 47800 için aynı).</summary>
public static class WireNumbers
{
    /// <summary>Kutu ve satır yüksekliği: 0–1'e kırp, 4 ondalık (yarıda çifte), sondaki sıfırlar atılır.</summary>
    public static RawNumber Fraction(double value)
    {
        if (double.IsNaN(value)) value = 0;
        var clamped = Math.Clamp(value, 0, 1);
        var rounded = Math.Round((decimal)clamped, 4, MidpointRounding.ToEven);
        return new RawNumber(rounded.ToString("0.####", CultureInfo.InvariantCulture));
    }

    /// <summary>
    /// Açı: |a| &lt; 0.3 ise yok; değilse 1 ondalık, yarıda sıfırdan uzağa. Kırpılmaz. Eski uygulama gibi kayan noktalı
    /// aritmetikle: <c>round(a × 10) / 10</c> (ör. 4.35 × 10 = 43.49999… olursa 4.3).
    /// </summary>
    public static RawNumber? Angle(double? degrees)
    {
        if (degrees is not { } a || double.IsNaN(a) || double.IsInfinity(a) || Math.Abs(a) < 0.3) return null;
        return Shortest(Math.Round(a * 10, MidpointRounding.AwayFromZero) / 10);
    }

    /// <summary>
    /// Saydamlık: 0–1'e kırp, 2 ondalık, yarıda sıfırdan uzağa; eski uygulama gibi kayan noktalı aritmetikle:
    /// <c>round(a × 100) / 100</c>. Bu yüzden 0.285 → 0.28 (0.285 × 100 = 28.4999…), 0.955 → 0.96.
    /// </summary>
    public static RawNumber Alpha(double value)
    {
        if (double.IsNaN(value)) value = 0;
        return Shortest(Math.Round(Math.Clamp(value, 0, 1) * 100, MidpointRounding.AwayFromZero) / 100);
    }

    /// <summary>
    /// Yeni protokolün kutu değeri (Mac ile aynı): 0–1'e kırp, 4 ondalık, kayan noktalı aritmetikle yarıda sıfırdan uzağa
    /// (<c>round(v × 10⁴) / 10⁴</c>), en kısa yazım. Eski 8787'deki <see cref="Fraction"/>'dan yalnız tam yarı
    /// değerlerde ayrılabilir.
    /// </summary>
    public static RawNumber LinkUnit(double value) => LinkRound(double.IsNaN(value) ? 0 : Math.Clamp(value, 0, 1));

    /// <summary>Yeni protokolün satır yüksekliği (Mac ile aynı): kırpılmadan 4 ondalık, yarıda sıfırdan uzağa.</summary>
    public static RawNumber LinkRound(double value)
    {
        if (!double.IsFinite(value)) return new RawNumber("0");
        var r = Math.Round(value * 10000, MidpointRounding.AwayFromZero) / 10000;
        return Shortest(r == 0 ? 0 : r);
    }

    /// <summary>Kayan noktalı sayının en kısa geri dönüşlü yazımı (.NET JSON yazıcısıyla aynı).</summary>
    static RawNumber Shortest(double value) => new(value.ToString("R", CultureInfo.InvariantCulture));
}
