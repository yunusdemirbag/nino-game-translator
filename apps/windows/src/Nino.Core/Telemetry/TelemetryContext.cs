// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Json.Nodes;

namespace Nino.Core.Telemetry;

/// <summary>Yayın kanalı.</summary>
public enum TelemetryChannel { Release, Beta, Dev }

/// <summary>
/// Gönderimin ortak alanları (<c>ctx</c>). <see cref="Device"/> cihazın model kimliğidir, asla kullanıcının verdiği
/// cihaz/bilgisayar adı değil. Geliştirici derlemeleri ve testler <see cref="TelemetryChannel.Dev"/> göndermeli.
/// </summary>
public sealed record TelemetryContext(string Platform, string App, string Os, string Device, TvBrand Tv,
    TelemetryChannel Channel)
{
    /// <summary>Sunucunun tanıdığı platformlar.</summary>
    public static IReadOnlyList<string> Platforms { get; } =
        ["mac", "windows", "linux", "android", "ios", "androidtv", "webos", "tizen"];

    /// <summary>Ölçümdeki Windows adı: <c>Windows 11 26100</c> (parantezsiz).</summary>
    public static string WindowsOs(int major, int minor, int build)
    {
        var name = major == 10 ? (build >= 22000 ? "Windows 11" : "Windows 10") : $"Windows {major}.{minor}";
        return build > 0 ? $"{name} {build.ToString(CultureInfo.InvariantCulture)}" : name;
    }

    /// <summary>Sürümden kanal: ön sürüm parçası varsa beta, yoksa release (geliştirici derlemesi dev'i kendi verir).</summary>
    public static TelemetryChannel ChannelFor(string version) =>
        version.Split('+')[0].Contains('-') ? TelemetryChannel.Beta : TelemetryChannel.Release;

    /// <summary>Gövdedeki <c>ctx</c> nesnesi; kurala uymayan alanlar boş yazılır.</summary>
    public JsonObject ToJson() => new()
    {
        ["platform"] = Platforms.Contains(Platform) ? Platform : "",
        ["app"] = TelemetryText.AppVersion(App),
        ["os"] = TelemetryText.Cut(Os, 40),
        ["device"] = TelemetryText.Cut(Device, 60),
        ["tv"] = TelemetryText.Brand(Tv),
        ["channel"] = Channel switch
        {
            TelemetryChannel.Beta => "beta",
            TelemetryChannel.Dev => "dev",
            _ => "release",
        },
    };
}

/// <summary>Sunucudan gelen ölçüm ayarı (<c>telemetry</c> bloğu).</summary>
public sealed record TelemetryConfig(bool Enabled, double Sample, int MaxPerDay, int FlushSeconds)
{
    /// <summary>Varsayılanlar.</summary>
    public static TelemetryConfig Default { get; } = new(true, 1, 1000, 600);

    /// <summary>
    /// <c>/v1/config</c> ya da <c>/v1/events</c> cevabından ayarı okur: kökte ya da <c>config</c> altında
    /// <c>telemetry</c> nesnesi. Yoksa null; eksik alan şimdiki değerini korur.
    /// </summary>
    public static TelemetryConfig? FromResponse(string? json, TelemetryConfig current)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            if (JsonNode.Parse(json) is not JsonObject root) return null;
            var block = root["telemetry"] as JsonObject ?? (root["config"] as JsonObject)?["telemetry"] as JsonObject;
            if (block is null) return null;
            var enabled = block["enabled"] is JsonValue e && e.TryGetValue<bool>(out var en) ? en : current.Enabled;
            var sample = Number(block["sample"]) is { } s ? Math.Clamp(s, 0, 1) : current.Sample;
            var max = Number(block["maxPerDay"]) is { } m && m >= 0 ? (int)Math.Min(m, int.MaxValue) : current.MaxPerDay;
            var flush = Number(block["flushSeconds"]) is { } f && f >= 1
                ? (int)Math.Min(f, 86_400)
                : current.FlushSeconds;
            return new TelemetryConfig(enabled, sample, max, flush);
        }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or InvalidOperationException
                                       or FormatException)
        {
            return null;
        }
    }

    static double? Number(JsonNode? node) =>
        node is JsonValue v && v.TryGetValue<double>(out var d) && double.IsFinite(d) ? d : null;

    /// <summary>
    /// Bu kurulum süre ölçümü gönderir mi: <c>fnv1a32(install küçük harf) % 10000 &lt; sample × 10000</c>.
    /// </summary>
    public bool SamplesTimings(string install) => Fnv1a32(install.ToLowerInvariant()) % 10000 < Sample * 10000;

    /// <summary>FNV-1a 32 bit (UTF-8 baytları üstünde).</summary>
    public static uint Fnv1a32(string text)
    {
        var hash = 2166136261u;
        foreach (var b in System.Text.Encoding.UTF8.GetBytes(text))
        {
            hash ^= b;
            hash *= 16777619u;
        }
        return hash;
    }
}
