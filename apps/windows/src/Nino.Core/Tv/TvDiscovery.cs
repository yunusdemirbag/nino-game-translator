// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace Nino.Core.Tv;

/// <summary>Ağda bulunan TV.</summary>
public sealed record FoundTv(string Name, string Host, TvBrand Brand);

/// <summary>SSDP (UPnP) araması.</summary>
public static class Ssdp
{
    public const string LgTarget = "urn:lge-com:service:webos-second-screen:1";
    public const string SamsungTarget = "urn:samsung.com:device:RemoteControlReceiver:1";
    static readonly IPEndPoint Group = new(IPAddress.Parse("239.255.255.250"), 1900);

    /// <summary>M-SEARCH istek metni.</summary>
    public static string Request(string target) =>
        $"M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: {target}\r\n\r\n";

    /// <summary>Yanıt hedefe eşleşiyorsa LOCATION'ın ana makinesi; değilse <c>null</c>.</summary>
    public static string? ParseResponse(string text, string target)
    {
        string? location = null;
        var matches = false;
        foreach (var line in text.Split("\r\n"))
        {
            var colon = line.IndexOf(':');
            if (colon <= 0) continue;
            var header = line[..colon].Trim().ToUpperInvariant();
            var value = line[(colon + 1)..].Trim();
            switch (header)
            {
                case "LOCATION": location = value; break;
                case "ST" or "NT" when value == target: matches = true; break;
            }
        }
        if (!matches || location is null) return null;
        return Uri.TryCreate(location, UriKind.Absolute, out var uri) ? uri.Host : null;
    }

    /// <summary>
    /// İstek her özel adresin bağdaştırıcısından (liste boşsa varsayılan yoldan) gönderilir; zaman aşımına kadar
    /// gelen yanıtlardan eşleşen adresler, tekrarsız ve sıralı.
    /// </summary>
    public static async Task<IReadOnlyList<string>> SearchAsync(string target, TimeSpan? timeout = null,
        IReadOnlyList<string>? localAddresses = null, CancellationToken ct = default)
    {
        var request = Encoding.ASCII.GetBytes(Request(target));
        var found = new HashSet<string>();
        using var udp = new UdpClient(AddressFamily.InterNetwork);
        udp.Client.Bind(new IPEndPoint(IPAddress.Any, 0));
        var locals = localAddresses ?? LocalNetwork.PrivateAddresses();
        if (locals.Count == 0)
        {
            try { await udp.SendAsync(request, Group, ct).ConfigureAwait(false); } catch (SocketException) { }
        }
        else
        {
            foreach (var local in locals)
            {
                try
                {
                    udp.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface,
                        IPAddress.Parse(local).GetAddressBytes());
                    await udp.SendAsync(request, Group, ct).ConfigureAwait(false);
                }
                catch (Exception e) when (e is SocketException or FormatException) { }
            }
        }

        using var wait = CancellationTokenSource.CreateLinkedTokenSource(ct);
        wait.CancelAfter(timeout ?? TimeSpan.FromSeconds(3));
        try
        {
            while (true)
            {
                var r = await udp.ReceiveAsync(wait.Token).ConfigureAwait(false);
                if (ParseResponse(Encoding.ASCII.GetString(r.Buffer), target) is { } host) found.Add(host);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested is false) { }
        catch (SocketException) { }
        return found.OrderBy(h => h, StringComparer.Ordinal).ToList();
    }
}

/// <summary>LG ve Samsung TV'lerini bulur.</summary>
public sealed class TvDiscovery(HttpClient? http = null)
{
    readonly HttpClient http = http ?? new HttpClient();

    public TimeSpan SsdpTimeout { get; init; } = TimeSpan.FromSeconds(3);

    /// <summary>LG ve Samsung araması birlikte; önce LG, sonra Samsung.</summary>
    public async Task<IReadOnlyList<FoundTv>> FindAllAsync(CancellationToken ct = default)
    {
        var lg = FindLgAsync(ct);
        var samsung = FindSamsungAsync(ct);
        await Task.WhenAll(lg, samsung).ConfigureAwait(false);
        return [.. lg.Result, .. samsung.Result];
    }

    /// <summary>Verilen markadaki TV'ler (Android TV aranmaz).</summary>
    public Task<IReadOnlyList<FoundTv>> FindAsync(TvBrand brand, CancellationToken ct = default) => brand switch
    {
        TvBrand.Lg => FindLgAsync(ct),
        TvBrand.Samsung => FindSamsungAsync(ct),
        _ => Task.FromResult<IReadOnlyList<FoundTv>>([]),
    };

    public async Task<IReadOnlyList<FoundTv>> FindLgAsync(CancellationToken ct = default)
    {
        var hosts = await Ssdp.SearchAsync(Ssdp.LgTarget, SsdpTimeout, ct: ct).ConfigureAwait(false);
        var names = await Task.WhenAll(hosts.Select(async h =>
        {
            var text = await GetAsync($"http://{h}:1990/", ct).ConfigureAwait(false);
            return new FoundTv(text is null ? "LG TV" : ParseFriendlyName(text) ?? "LG TV", h, TvBrand.Lg);
        })).ConfigureAwait(false);
        return names;
    }

    public async Task<IReadOnlyList<FoundTv>> FindSamsungAsync(CancellationToken ct = default)
    {
        var hosts = await Ssdp.SearchAsync(Ssdp.SamsungTarget, SsdpTimeout, ct: ct).ConfigureAwait(false);
        if (hosts.Count > 0)
        {
            return await Task.WhenAll(hosts.Select(async h =>
                new FoundTv(await SamsungNameAsync(h, ct).ConfigureAwait(false) ?? "Samsung TV", h, TvBrand.Samsung)))
                .ConfigureAwait(false);
        }

        var open = await LocalNetwork.OpenHostsAsync(LocalNetwork.ScanTargets(LocalNetwork.PrivateAddresses()), 8001,
            TimeSpan.FromMilliseconds(700), ct: ct).ConfigureAwait(false);
        var result = new List<FoundTv>();
        foreach (var h in open)
            if (await SamsungNameAsync(h, ct).ConfigureAwait(false) is { } name)
                result.Add(new FoundTv(name, h, TvBrand.Samsung));
        return result;
    }

    async Task<string?> SamsungNameAsync(string host, CancellationToken ct)
    {
        var text = await GetAsync($"http://{host}:8001/api/v2/", ct).ConfigureAwait(false);
        return text is null ? null : ParseSamsungName(text);
    }

    async Task<string?> GetAsync(string url, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(2));
        try { return await http.GetStringAsync(url, cts.Token).ConfigureAwait(false); }
        catch (Exception) when (!ct.IsCancellationRequested) { return null; }
    }

    /// <summary>LG açıklamasındaki <c>&lt;friendlyName&gt;</c>.</summary>
    public static string? ParseFriendlyName(string xml)
    {
        const string open = "<friendlyName>";
        var start = xml.IndexOf(open, StringComparison.Ordinal);
        if (start < 0) return null;
        start += open.Length;
        var end = xml.IndexOf("</friendlyName>", start, StringComparison.Ordinal);
        if (end < 0) return null;
        var name = xml[start..end].Trim();
        return name.Length == 0 ? null : name;
    }

    /// <summary>Samsung 8001 cevabındaki <c>device.name</c> (<c>&amp;quot;</c> → <c>"</c>).</summary>
    public static string? ParseSamsungName(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind == JsonValueKind.Object
                && doc.RootElement.TryGetProperty("device", out var device) && device.ValueKind == JsonValueKind.Object
                && device.TryGetProperty("name", out var name) && name.ValueKind == JsonValueKind.String)
            {
                var text = (name.GetString() ?? "").Replace("&quot;", "\"");
                return text.Length == 0 ? null : text;
            }
        }
        catch (JsonException) { }
        return null;
    }
}
