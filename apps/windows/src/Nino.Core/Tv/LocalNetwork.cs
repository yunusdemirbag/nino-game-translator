// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace Nino.Core.Tv;

/// <summary>Bir bağdaştırıcının bir IPv4 adresi.</summary>
public sealed record AdapterAddress(
    string Name,
    string Description,
    NetworkInterfaceType Type,
    string Address,
    string Mask = "0.0.0.0",
    bool HasGateway = false);

/// <summary>Yerel bilgisayarın ağ adresleri: TV'ye verilecek adresin seçimi, tarama hedefleri, port yoklama.</summary>
public static class LocalNetwork
{
    // Sanal makine, konteyner, VPN ve tünel bağdaştırıcılarının ad/açıklama işaretleri (küçük harf).
    static readonly string[] VirtualMarkers =
    [
        "virtual", "vethernet", "hyper-v", "virtualbox", "vmware", "vmnet",
        "wsl", "docker", "tailscale", "zerotier", "wireguard", "wintun",
        "tap-", "tap ", "openvpn", "vpn", "hamachi", "radmin",
        "nordlynx", "forticlient", "fortinet", "anyconnect", "globalprotect", "pangp",
        "npcap", "loopback", "bluetooth", "teredo", "isatap",
    ];

    static readonly string[] LinuxBridgePrefixes = ["docker", "br-", "veth", "virbr"];

    /// <summary>10.x, 172.16–31.x, 192.168.x (dört baytlı IPv4).</summary>
    public static bool IsPrivate(string? address) =>
        IPAddress.TryParse(address, out var ip) && ip.AddressFamily == AddressFamily.InterNetwork && IsPrivate(ip);

    public static bool IsPrivate(IPAddress ip)
    {
        if (ip.AddressFamily != AddressFamily.InterNetwork) return false;
        var octets = ip.GetAddressBytes();
        return octets[0] switch
        {
            10 => true,
            172 => octets[1] is >= 16 and <= 31,
            192 => octets[1] == 168,
            _ => false,
        };
    }

    /// <summary>Tünel/PPP türü ya da ad + açıklamada sanal ağ işareti olan bağdaştırıcı.</summary>
    public static bool IsVirtual(string name, string description, NetworkInterfaceType type = NetworkInterfaceType.Ethernet)
    {
        if (type == NetworkInterfaceType.Tunnel || type == NetworkInterfaceType.Ppp) return true;
        var haystack = $"{name} {description}".ToLowerInvariant();
        return Array.Exists(VirtualMarkers, haystack.Contains);
    }

    public static bool IsVirtual(AdapterAddress a) => IsVirtual(a.Name, a.Description, a.Type);

    /// <summary>Açık, geri döngü olmayan bağdaştırıcıların her IPv4 adresi.</summary>
    public static IReadOnlyList<AdapterAddress> Adapters()
    {
        var result = new List<AdapterAddress>();
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                    continue;
                IPInterfaceProperties props;
                try { props = nic.GetIPProperties(); } catch (Exception) { continue; }
                var gateway = props.GatewayAddresses.Any(g =>
                    g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any));
                foreach (var u in props.UnicastAddresses)
                {
                    if (u.Address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(u.Address)) continue;
                    string mask;
                    try { mask = u.IPv4Mask?.ToString() ?? "0.0.0.0"; } catch (Exception) { mask = "0.0.0.0"; }
                    result.Add(new AdapterAddress(nic.Name, nic.Description, nic.NetworkInterfaceType,
                        u.Address.ToString(), mask, gateway));
                }
            }
        }
        catch (Exception) { }
        return result;
    }

    /// <summary>
    /// Tarama ve SSDP için özel adresler (açık, geri döngü olmayan bağdaştırıcılar). Linux'ta konteyner/sanal
    /// makine köprüleri atlanır.
    /// </summary>
    public static IReadOnlyList<string> PrivateAddresses(bool skipLinuxBridges = true)
    {
        var linux = skipLinuxBridges && OperatingSystem.IsLinux();
        return Adapters()
            .Where(a => IsPrivate(a.Address))
            .Where(a => !linux || !LinuxBridgePrefixes.Any(p => a.Name.StartsWith(p, StringComparison.Ordinal)))
            .Select(a => a.Address)
            .Distinct()
            .ToList();
    }

    /// <summary>
    /// TV'ye giden yolun bu bilgisayardaki kaynak adresi: UDP soketi hedefe "bağlanır" (paket gitmez), yerel uç okunur.
    /// </summary>
    public static string? RouteSource(string? target, int port = 8001)
    {
        if (!IPAddress.TryParse(target, out var ip) || ip.AddressFamily != AddressFamily.InterNetwork) return null;
        try
        {
            using var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            s.Connect(new IPEndPoint(ip, port));
            return (s.LocalEndPoint as IPEndPoint)?.Address.ToString();
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>
    /// TV'ye verilecek adresi seçer: yolun kaynağı (listede varsa) → TV ile aynı alt ağdaki gerçek (ağ geçitli önce)
    /// → herhangi bir aynı alt ağdaki → ağ geçitli özel gerçek → özel gerçek → gerçek → özel → herhangi biri.
    /// </summary>
    public static string? Choose(IReadOnlyList<AdapterAddress> adapters, string? tv, string? routeSource)
    {
        if (IPAddress.TryParse(routeSource, out var src) && src.AddressFamily == AddressFamily.InterNetwork
            && !IPAddress.IsLoopback(src) && !src.Equals(IPAddress.Any)
            && (adapters.Count == 0 || adapters.Any(a => a.Address == src.ToString())))
            return src.ToString();

        var real = adapters.Where(a => !IsVirtual(a)).ToList();
        if (IPAddress.TryParse(tv, out var tvIp) && tvIp.AddressFamily == AddressFamily.InterNetwork)
        {
            var same = real.Where(a => SameSubnet(a, tvIp)).OrderByDescending(a => a.HasGateway).FirstOrDefault()
                ?? adapters.FirstOrDefault(a => SameSubnet(a, tvIp));
            if (same is not null) return same.Address;
        }
        // Sırayla ilk tutan: ağ geçitli özel gerçek, özel gerçek, gerçek, özel, herhangi biri.
        (IReadOnlyList<AdapterAddress> From, Func<AdapterAddress, bool> Test)[] order =
        [
            (real, a => a.HasGateway && IsPrivate(a.Address)),
            (real, a => IsPrivate(a.Address)),
            (real, _ => true),
            (adapters, a => IsPrivate(a.Address)),
            (adapters, _ => true),
        ];
        foreach (var (from, test) in order)
            if (from.FirstOrDefault(test) is { } hit) return hit.Address;
        return null;
    }

    /// <summary>"Yerel bilgisayarın adresi (yakın X)": yolun kaynağı hesaplanıp seçim yapılır.</summary>
    public static string? AddressNear(string? tv) => Choose(Adapters(), tv, RouteSource(tv));

    static bool SameSubnet(AdapterAddress a, IPAddress tv)
    {
        if (!IPAddress.TryParse(a.Address, out var ip) || !IPAddress.TryParse(a.Mask, out var mask)) return false;
        var m = mask.GetAddressBytes();
        if (m.Length != 4 || m.All(x => x == 0)) return false;
        var x = ip.GetAddressBytes();
        var t = tv.GetAddressBytes();
        for (var i = 0; i < 4; i++)
            if ((x[i] & m[i]) != (t[i] & m[i])) return false;
        return true;
    }

    /// <summary>Her yerel adresin /24'ündeki .1–.254 (kendi son baytı hariç), tekrarsız, ekleme sırasıyla.</summary>
    public static IReadOnlyList<string> ScanTargets(IEnumerable<string> locals)
    {
        var seen = new HashSet<string>();
        var result = new List<string>();
        foreach (var local in locals)
        {
            if (!IPAddress.TryParse(local, out var ip) || ip.AddressFamily != AddressFamily.InterNetwork) continue;
            var b = ip.GetAddressBytes();
            for (var last = 1; last <= 254; last++)
            {
                if (last == b[3]) continue;
                var target = $"{b[0]}.{b[1]}.{b[2]}.{last}";
                if (seen.Add(target)) result.Add(target);
            }
        }
        return result;
    }

    /// <summary>TCP portu verilen süre içinde bağlantı kabul ediyor mu.</summary>
    public static async Task<bool> IsPortOpenAsync(string host, int port, TimeSpan timeout, CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeout);
        try
        {
            using var tcp = new TcpClient();
            await tcp.ConnectAsync(host, port, cts.Token).ConfigureAwait(false);
            return true;
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return false;
        }
    }

    /// <summary>Hedeflerden portu açık olanlar (aynı anda en çok <paramref name="parallel"/>), son bayta göre sıralı.</summary>
    public static async Task<IReadOnlyList<string>> OpenHostsAsync(IEnumerable<string> targets, int port, TimeSpan timeout,
        int parallel = 64, CancellationToken ct = default)
    {
        var found = new List<string>();
        await Parallel.ForEachAsync(targets, new ParallelOptions { MaxDegreeOfParallelism = parallel, CancellationToken = ct },
            async (host, token) =>
            {
                if (await IsPortOpenAsync(host, port, timeout, token).ConfigureAwait(false))
                    lock (found) found.Add(host);
            }).ConfigureAwait(false);
        return found.OrderBy(LastByte).ThenBy(h => h, StringComparer.Ordinal).ToList();
    }

    static int LastByte(string host) =>
        IPAddress.TryParse(host, out var ip) ? ip.GetAddressBytes()[^1] : 0;
}
