// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Data;

/// <summary>Cihaz bilgisi satırı: sabit kimlik (çevrilmez) ve değer.</summary>
public sealed record DeviceInfoLine(string Id, string Value);

/// <summary>
/// Cihaz bilgisinin saf kuralları: satır temizliği, tek satırlık özet, Windows adı ve bilgisayar modeli.
/// Kişiyi tanıtan hiçbir şey (bilgisayar adı, kullanıcı adı, seri numarası) kullanılmaz.
/// </summary>
public static class DeviceInfo
{
    /// <summary>Satır kimlikleri, bu sırayla.</summary>
    public static IReadOnlyList<string> LineOrder { get; } = ["app", "device", "system", "tv", "console", "status"];

    /// <summary>Özetin (sunucuya giden alan) en çok uzunluğu.</summary>
    public const int MaxSummaryLength = 600;

    /// <summary>Windows dışı ya da okunamayan model.</summary>
    public const string FallbackModel = "Windows PC";

    static readonly string[] Placeholders =
    [
        "system manufacturer", "system product name", "to be filled by o.e.m.", "to be filled by oem",
        "default string", "not applicable", "not specified", "none", "unknown", "o.e.m.", "oem",
    ];

    /// <summary>Değer temizliği: CRLF/CR/LF boşluk, <c>|</c> → <c>/</c>, kırpılır.</summary>
    public static string CleanValue(string? value) =>
        (value ?? "").Replace("\r\n", " ").Replace('\r', ' ').Replace('\n', ' ').Replace('|', '/').Trim();

    /// <summary>Kimlik/değer çiftlerinden satırlar; boş değerli satır olmaz.</summary>
    public static IReadOnlyList<DeviceInfoLine> Lines(params (string Id, string? Value)[] values) =>
        values.Select(v => new DeviceInfoLine(v.Id, CleanValue(v.Value))).Where(l => l.Value.Length > 0).ToArray();

    /// <summary><c>id: değer</c> çiftleri <c> | </c> ile; en çok 600 karakter.</summary>
    public static string Summary(IEnumerable<DeviceInfoLine> lines)
    {
        var text = string.Join(" | ", lines.Select(l => $"{l.Id}: {l.Value}"));
        return text.Length > MaxSummaryLength ? text[..MaxSummaryLength] : text;
    }

    /// <summary>İstek gövdesine konacak özet: kırpılır, 600'e kesilir; boşsa null (alan gönderilmez).</summary>
    public static string? ForRequest(string? summary)
    {
        var text = (summary ?? "").Trim();
        if (text.Length > MaxSummaryLength) text = text[..MaxSummaryLength];
        return text.Length == 0 ? null : text;
    }

    /// <summary>
    /// Sistem adı: 10.x'te yapı ≥ 22000 → "Windows 11", değilse "Windows 10"; başka sürümde
    /// "Windows &lt;ana&gt;.&lt;alt&gt;"; yapı &gt; 0 ise " (&lt;yapı&gt;)".
    /// </summary>
    public static string WindowsName(int major, int minor, int build)
    {
        var name = major == 10 ? (build >= 22000 ? "Windows 11" : "Windows 10") : $"Windows {major}.{minor}";
        return build > 0 ? $"{name} ({build})" : name;
    }

    /// <summary>
    /// Bilgisayar modeli (BIOS üretici + ürün): yer tutucular sayılmaz; ikisi yoksa "Windows PC"; biri yoksa öbürü;
    /// ürün üretici adıyla başlıyorsa yalnız ürün, değilse "üretici ürün".
    /// </summary>
    public static string ComputerModel(string? manufacturer, string? product)
    {
        var maker = Meaningful(manufacturer);
        var model = Meaningful(product);
        if (maker is null && model is null) return FallbackModel;
        if (maker is null) return model!;
        if (model is null) return maker;
        var repeatsMaker = model.StartsWith(maker, StringComparison.OrdinalIgnoreCase);
        return repeatsMaker ? model : maker + " " + model;
    }

    static string? Meaningful(string? value)
    {
        var text = CleanValue(value);
        if (text.Length == 0) return null;
        return Placeholders.Any(p => string.Equals(p, text, StringComparison.OrdinalIgnoreCase)) ? null : text;
    }
}
