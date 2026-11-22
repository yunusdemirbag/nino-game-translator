// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
// Samsung giriş/sertifika akışı, sertifika uç noktaları ve Tizen kurulum hata kodlarının anlamı MIT lisanslı
// Jellyfin2Samsung (Samsung-Jellyfin-Installer) projesinden uyarlanmıştır.

using System.Net;
using System.Text.Json;

namespace Nino.TvInstall.Samsung;

/// <summary>Samsung TV'nin 8001 bilgisi: geliştirici modu (null = bilinmiyor) ve TV'deki "Host PC IP" (null = yok).</summary>
public sealed record SamsungDeviceInfo(bool? DeveloperMode, string? DeveloperIp)
{
    public static readonly SamsungDeviceInfo Unknown = new(null, null);

    /// <summary><c>http://adres:8001/api/v2/</c> cevabını okur. Okunamazsa <see cref="Unknown"/>.</summary>
    public static SamsungDeviceInfo Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return Unknown;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Object ||
                !doc.RootElement.TryGetProperty("device", out var device) ||
                device.ValueKind != JsonValueKind.Object) return Unknown;
            bool? mode = null;
            if (device.TryGetProperty("developerMode", out var m))
            {
                var text = m.ValueKind switch
                {
                    JsonValueKind.String => m.GetString(),
                    JsonValueKind.Number => m.GetRawText(),
                    JsonValueKind.True => "true",
                    JsonValueKind.False => "false",
                    _ => null,
                };
                text = text?.Trim();
                if (!string.IsNullOrEmpty(text))
                    mode = text == "1" || text.Equals("true", StringComparison.OrdinalIgnoreCase);
            }
            string? ip = null;
            if (device.TryGetProperty("developerIP", out var d) && d.ValueKind == JsonValueKind.String)
            {
                var v = d.GetString()?.Trim();
                if (!string.IsNullOrEmpty(v) && v != "0.0.0.0") ip = v;
            }
            return new SamsungDeviceInfo(mode, ip);
        }
        catch (JsonException) { return Unknown; }
    }

    /// <summary>TV'deki Host PC IP ile bu bilgisayarın adresi ikisi de biliniyor ve farklı mı.</summary>
    public static bool IsHostPcMismatch(string? tvHostPcIp, string? thisComputer)
    {
        var a = tvHostPcIp?.Trim();
        var b = thisComputer?.Trim();
        return !string.IsNullOrEmpty(a) && !string.IsNullOrEmpty(b) && !string.Equals(a, b, StringComparison.Ordinal);
    }

    /// <summary>8001 bilgisini indirir (2 sn). Hata olursa <see cref="Unknown"/>; iptal fırlatılır.</summary>
    public static async Task<SamsungDeviceInfo> FetchAsync(HttpClient http, string host, CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(2));
        try
        {
            var text = await http.GetStringAsync($"http://{host}:8001/api/v2/", cts.Token).ConfigureAwait(false);
            return Parse(text);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested is false) { return Unknown; }
        catch (HttpRequestException) { return Unknown; }
        catch (IOException) { return Unknown; }
    }

    /// <summary>Kurulum kapısı (sdb, TCP 26101) açık mı (2 sn).</summary>
    public static Task<bool> IsInstallPortOpenAsync(string host, CancellationToken ct = default) =>
        IPAddress.TryParse(host, out var ip)
            ? LanScan.IsPortOpenAsync(ip, SamsungInstaller.SdbPort, TimeSpan.FromSeconds(2), ct)
            : Task.FromResult(false);
}
