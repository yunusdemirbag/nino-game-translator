// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay;

/// <summary>Yerel ağda PS5 arama (her adrese ayrı ayrı sorulur; genel yayına yanıt gelmeyebilir).</summary>
public sealed class Ps5Finder(IRemotePlayBridge bridge)
{
    public const string Broadcast = "255.255.255.255";
    public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(3);
    public static readonly TimeSpan RunningGameTimeout = TimeSpan.FromSeconds(2);

    /// <summary>En çok bu kadar sunuculu ağlar taranır (/22).</summary>
    public const int MaxHostsPerNetwork = 1023;

    /// <summary>
    /// Tek adrese (host verilirse) ya da yerel ağın her adresine sorar. Uzun ömürlü iş parçacığında koşar; iptal
    /// yalnız beklemeyi bırakır (başlamış arama kendi süresince arkada sürer).
    /// </summary>
    public Task<IReadOnlyList<FoundPs5>> SearchAsync(string? host = null, TimeSpan? timeout = null,
                                                      CancellationToken cancel = default)
    {
        IReadOnlyList<string> targets = string.IsNullOrWhiteSpace(host) ? LocalTargets() : [host.Trim()];
        int ms = (int)Math.Max(0, (timeout ?? DefaultTimeout).TotalMilliseconds);
        var work = Task.Factory.StartNew(() => Search(targets, ms), CancellationToken.None,
                                         TaskCreationOptions.LongRunning, TaskScheduler.Default);
        return work.WaitAsync(cancel);
    }

    /// <summary>Bloklayan arama: yanıtlar adrese göre toplanır (sonraki yanıt öncekinin yerine), adrese göre dizilir.</summary>
    public IReadOnlyList<FoundPs5> Search(IReadOnlyList<string> targets, int timeoutMs) =>
        Collapse(bridge.Discover(targets, timeoutMs));

    /// <summary>Bağlı PS5'te açık oyun (2 sn sorulur). Yanıt yoksa null.</summary>
    public async Task<FoundPs5?> RunningGameAsync(string host, CancellationToken cancel = default)
    {
        var found = await SearchAsync(host, RunningGameTimeout, cancel).ConfigureAwait(false);
        return found.Count > 0 ? found[0] : null;
    }

    public static IReadOnlyList<FoundPs5> Collapse(IEnumerable<FoundPs5> replies)
    {
        var byHost = new Dictionary<string, FoundPs5>(StringComparer.Ordinal);
        foreach (var reply in replies)
            byHost[reply.Host] = reply;
        return byHost.Values.OrderBy(r => r.Host, StringComparer.Ordinal).ToArray();
    }

    /// <summary>Kurulumdaki aramanın günlük satırı.</summary>
    public static string Summary(IReadOnlyList<FoundPs5> found) =>
        found.Count == 0
            ? "PS5 araması: bulunamadı"
            : "PS5 araması: " + string.Join(", ", found.Select(f => $"{f.Name} {f.Host}" + (f.Awake ? "" : " (dinlenmede)")));

    /// <summary>
    /// Taşınan PS5'i seçer: tek PS5 varsa o; birden çoksa adı tam eşleşen tek PS5; emin olunamazsa null.
    /// </summary>
    public static FoundPs5? PickMoved(IReadOnlyList<FoundPs5> found, string? registeredName)
    {
        if (found.Count == 1)
            return found[0];
        if (found.Count == 0 || string.IsNullOrEmpty(registeredName))
            return null;
        var named = found.Where(f => f.Name == registeredName).ToArray();
        return named.Length == 1 ? named[0] : null;
    }

    // ---------------- Hedefler ----------------

    /// <summary>
    /// Çalışan, geri döngü olmayan bağdaştırıcıların ağlarındaki diğer adresler, en sonda genel yayın; tekrarsız.
    /// Ağ bilgisi okunamazsa yalnız genel yayın.
    /// </summary>
    public static IReadOnlyList<string> LocalTargets()
    {
        List<(uint Address, uint Mask)> networks;
        try
        {
            networks = LocalNetworks();
        }
        catch (NetworkInformationException)
        {
            networks = [];
        }
        catch (PlatformNotSupportedException)
        {
            networks = [];
        }
        return TargetsFor(networks);
    }

    public static IReadOnlyList<string> TargetsFor(IEnumerable<(uint Address, uint Mask)> networks)
    {
        HashSet<string> seen = new(StringComparer.Ordinal);
        var result = new List<string>();
        foreach (var (address, mask) in networks)
            foreach (uint host in SubnetHosts(address, mask))
            {
                string text = ToText(host);
                if (seen.Add(text))
                    result.Add(text);
            }
        if (seen.Add(Broadcast))
            result.Add(Broadcast);
        return result;
    }

    static List<(uint, uint)> LocalNetworks()
    {
        var list = new List<(uint, uint)>();
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                continue;
            foreach (var unicast in nic.GetIPProperties().UnicastAddresses)
            {
                if (unicast.Address.AddressFamily != AddressFamily.InterNetwork || IPAddress.IsLoopback(unicast.Address))
                    continue;
                uint address = ToUInt(unicast.Address);
                uint mask = unicast.IPv4Mask is { } m ? ToUInt(m) : 0;
                if (address == 0 || mask == 0)
                    continue;
                list.Add((address, mask));
            }
        }
        return list;
    }

    /// <summary>
    /// Ağdaki diğer adresler: ağ adresi + 1 … ağ adresi + (sayı − 1), kendi adresi hariç. Sunucu sayısı
    /// (maskenin tersi) ≤ 1 ya da 1023'ten büyükse boş.
    /// </summary>
    public static IReadOnlyList<uint> SubnetHosts(uint address, uint mask)
    {
        uint count = ~mask;
        if (count <= 1 || count > MaxHostsPerNetwork)
            return [];
        uint network = address & mask;
        var hosts = new List<uint>((int)count);
        for (uint i = 1; i < count; i++)
        {
            uint host = network + i;
            if (host != address)
                hosts.Add(host);
        }
        return hosts;
    }

    public static uint ToUInt(IPAddress address)
    {
        byte[] b = address.GetAddressBytes();
        return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | b[3];
    }

    public static uint ToUInt(string address) => ToUInt(IPAddress.Parse(address));

    public static string ToText(uint address) =>
        $"{(address >> 24) & 0xff}.{(address >> 16) & 0xff}.{(address >> 8) & 0xff}.{address & 0xff}";
}
