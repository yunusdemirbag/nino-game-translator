// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Nino.Core.Data;

namespace Nino.Core.Support;

/// <summary>Bildirime ya da soruya eklenen fotoğraf.</summary>
/// <param name="Mime">Tür (<c>image/jpeg</c>).</param>
/// <param name="Data">Baytlar.</param>
public sealed record SupportImage(string Mime, byte[] Data)
{
    /// <summary>JPEG fotoğraf.</summary>
    public static SupportImage Jpeg(byte[] data) => new("image/jpeg", data);
}

/// <summary>Destek metinlerinin sınırları ve kesim kuralları.</summary>
public static class SupportLimits
{
    public const int Text = 4000;
    public const int Contact = 200;
    public const int Log = 60_000;
    public const int App = 40;
    public const int Images = 3;
    public const int AssistantText = 2000;
    public const int AssistantMessages = 24;
    public const int AssistantPhotoMessages = 2;

    /// <summary>Bir istek gövdesinin en çok boyu (sorun bildirme).</summary>
    public const int ReportBodyBytes = 4 * 1024 * 1024;

    /// <summary>Nino'ya Sor gövdesinin en çok boyu.</summary>
    public const int AssistantBodyBytes = 6 * 1024 * 1024;

    /// <summary>Fotoğraf başına hedef: sorun bildirme 900 KB, Nino'ya Sor 600 KB.</summary>
    public const int ReportPhotoBytes = 900 * 1024;
    public const int AssistantPhotoBytes = 600 * 1024;

    /// <summary>
    /// İlk <paramref name="max"/> UTF-16 birimi; kesim vekil çiftin ortasına düşerse o karakter de atılır.
    /// </summary>
    public static string Head(string text, int max)
    {
        if (text.Length <= max) return text;
        var cut = text[..max];
        return cut.Length > 0 && char.IsHighSurrogate(cut[^1]) ? cut[..^1] : cut;
    }

    /// <summary>Son <paramref name="max"/> UTF-16 birimi; kesim vekil çiftin ortasına düşerse o karakter de atılır.</summary>
    public static string Tail(string text, int max)
    {
        if (text.Length <= max) return text;
        var cut = text[^max..];
        return cut.Length > 0 && char.IsLowSurrogate(cut[0]) ? cut[1..] : cut;
    }

    internal static readonly JsonWriterOptions Writer = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
}

/// <summary>
/// <c>POST /v1/reports</c> gövdesi. JSON'a çevrilirken sınırlar uygulanır; boş alanlar yazılmaz; <c>images</c> her
/// zaman dizidir.
/// </summary>
public sealed record ReportBody
{
    /// <summary>Otomatik bildirimin türü.</summary>
    public const string AutoKind = "auto";

    /// <summary>Kuruluş kimliği (8–64 karakter).</summary>
    public required string Install { get; init; }

    /// <summary>Nino'nun sürümü.</summary>
    public required string App { get; init; }

    /// <summary>Platform adı (<c>windows</c>; Linux kendi adını verir).</summary>
    public string Platform { get; init; } = "windows";

    /// <summary>Çeviri dili kodu.</summary>
    public required string Language { get; init; }

    /// <summary>Bildirim metni ("Nino'nun tespitleri" dahil).</summary>
    public required string Text { get; init; }

    public string? Contact { get; init; }
    public string? Log { get; init; }
    public IReadOnlyList<SupportImage> Images { get; init; } = [];

    /// <summary>Cihaz özeti.</summary>
    public string? Device { get; init; }

    /// <summary>Tür: yalnız otomatik bildirimde <c>auto</c>.</summary>
    public string? Kind { get; init; }

    /// <summary>Gövdenin JSON baytları (UTF-8).</summary>
    public byte[] ToJson()
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms, SupportLimits.Writer))
        {
            w.WriteStartObject();
            w.WriteNumber("v", 1);
            w.WriteString("install", Install);
            w.WriteString("app", SupportLimits.Head((App ?? "").Trim(), SupportLimits.App));
            w.WriteString("platform", Platform);
            if (!string.IsNullOrEmpty(Language)) w.WriteString("language", Language);
            w.WriteString("text", SupportLimits.Head((Text ?? "").Trim(), SupportLimits.Text));
            var contact = SupportLimits.Head((Contact ?? "").Trim(), SupportLimits.Contact);
            if (contact.Length > 0) w.WriteString("contact", contact);
            var log = SupportLimits.Tail(Log ?? "", SupportLimits.Log);
            if (log.Trim().Length > 0) w.WriteString("log", log);
            w.WriteStartArray("images");
            foreach (var image in Images.Where(i => i.Data.Length > 0).Take(SupportLimits.Images))
            {
                w.WriteStartObject();
                w.WriteString("mime", image.Mime);
                w.WriteString("data", Convert.ToBase64String(image.Data));
                w.WriteEndObject();
            }
            w.WriteEndArray();
            if (DeviceInfo.ForRequest(Device) is { } device) w.WriteString("device", device);
            if (!string.IsNullOrEmpty(Kind)) w.WriteString("kind", Kind);
            w.WriteEndObject();
        }
        return ms.ToArray();
    }

    /// <summary>JSON metni.</summary>
    public string ToJsonText() => Encoding.UTF8.GetString(ToJson());

    /// <summary>Kaydedilmiş gövdeyi okur (bekleyen otomatik bildirim); bozuksa null.</summary>
    public static ReportBody? Parse(JsonElement e)
    {
        try
        {
            if (e.ValueKind != JsonValueKind.Object) return null;
            string? Str(string name) =>
                e.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;
            var install = Str("install");
            var text = Str("text");
            if (install is null || text is null) return null;
            var images = new List<SupportImage>();
            if (e.TryGetProperty("images", out var arr) && arr.ValueKind == JsonValueKind.Array)
                foreach (var item in arr.EnumerateArray())
                    if (item.ValueKind == JsonValueKind.Object
                        && item.TryGetProperty("data", out var d) && d.ValueKind == JsonValueKind.String)
                        images.Add(new SupportImage(
                            item.TryGetProperty("mime", out var m) && m.ValueKind == JsonValueKind.String
                                ? m.GetString()!
                                : "image/jpeg",
                            Convert.FromBase64String(d.GetString()!)));
            return new ReportBody
            {
                Install = install,
                App = Str("app") ?? "",
                Platform = Str("platform") ?? "windows",
                Language = Str("language") ?? "",
                Text = text,
                Contact = Str("contact"),
                Log = Str("log"),
                Images = images,
                Device = Str("device"),
                Kind = Str("kind"),
            };
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
