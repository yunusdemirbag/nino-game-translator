// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace Nino.TvInstall;

/// <summary>Kurulum katmanının küçük ağ yardımcıları: özel IPv4 adresleri, /24 hedefleri, port taraması.</summary>
public static class LanScan
{
    /// <summary>10.x, 172.16–31.x, 192.168.x.</summary>
    public static bool IsPrivate(IPAddress ip)
    {
        if (ip.AddressFamily is not AddressFamily.InterNetwork) return false;
        var octets = ip.GetAddressBytes();
        return octets[0] switch
        {
            10 => true,
            172 => octets[1] is >= 16 and <= 31,
            192 => octets[1] == 168,
            _ => false,
        };
    }

    /// <summary>Açık, geri döngü olmayan bağdaştırıcıların özel IPv4 adresleri (sanal süzgeci yok). Okunamazsa boş.</summary>
    public static IReadOnlyList<IPAddress> LocalPrivateAddresses()
    {
        var list = new List<IPAddress>();
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var ua in nic.GetIPProperties().UnicastAddresses)
                {
                    if (IsPrivate(ua.Address) && !list.Contains(ua.Address)) list.Add(ua.Address);
                }
            }
        }
        catch (NetworkInformationException) { }
        catch (PlatformNotSupportedException) { }
        return list;
    }

    /// <summary>Her adres için aynı /24'teki .1–.254 (kendi son baytı hariç), tekrarsız, ekleme sırasıyla.</summary>
    public static IReadOnlyList<IPAddress> Targets(IEnumerable<IPAddress> locals)
    {
        var seen = new HashSet<IPAddress>();
        var all = locals.ToList();
        var own = new HashSet<IPAddress>(all);
        var result = new List<IPAddress>();
        foreach (var local in all)
        {
            if (local.AddressFamily != AddressFamily.InterNetwork) continue;
            var b = local.GetAddressBytes();
            for (var last = 1; last <= 254; last++)
            {
                var ip = new IPAddress([b[0], b[1], b[2], (byte)last]);
                if (own.Contains(ip) || !seen.Add(ip)) continue;
                result.Add(ip);
            }
        }
        return result;
    }

    /// <summary>TCP bağlantı kabul ediyor mu.</summary>
    public static async Task<bool> IsPortOpenAsync(IPAddress host, int port, TimeSpan timeout, CancellationToken ct = default)
    {
        using var client = new TcpClient(host.AddressFamily);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeout);
        try
        {
            await client.ConnectAsync(host, port, cts.Token).ConfigureAwait(false);
            return true;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested is false) { return false; }
        catch (SocketException) { return false; }
    }

    /// <summary>Hedeflerden portu açık olanlar (aynı anda en çok <paramref name="parallel"/>), son bayta göre sıralı.</summary>
    public static async Task<IReadOnlyList<IPAddress>> OpenHostsAsync(
        IEnumerable<IPAddress> targets, int port, TimeSpan timeout, int parallel = 64, CancellationToken ct = default)
    {
        var found = new List<IPAddress>();
        using var throttle = new SemaphoreSlim(parallel);
        var tasks = targets.Select(async ip =>
        {
            await throttle.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                if (await IsPortOpenAsync(ip, port, timeout, ct).ConfigureAwait(false))
                    lock (found) found.Add(ip);
            }
            finally { throttle.Release(); }
        }).ToList();
        await Task.WhenAll(tasks).ConfigureAwait(false);
        ct.ThrowIfCancellationRequested();
        return found.OrderBy(ip => ip.GetAddressBytes()[3]).ThenBy(ip => ip.ToString(), StringComparer.Ordinal).ToList();
    }

    /// <summary>Yerel bilgisayardan hedefe giden yolun kaynak adresi (UDP "bağlanma", paket gönderilmez). Olmazsa null.</summary>
    public static IPAddress? SourceAddressTowards(IPAddress target, int port)
    {
        if (target.AddressFamily is not AddressFamily.InterNetwork) return null;
        try
        {
            using var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            s.Connect(new IPEndPoint(target, port));
            return (s.LocalEndPoint as IPEndPoint)?.Address;
        }
        catch (SocketException) { return null; }
    }
}
