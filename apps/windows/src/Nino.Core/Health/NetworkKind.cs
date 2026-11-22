// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.NetworkInformation;

namespace Nino.Core.Health;

/// <summary>Yerel bilgisayarın ağ bağlantısının türü.</summary>
public enum NetworkKind
{
    Unknown,
    Wired,
    Wifi,
    Other,
    Offline,
}

/// <summary>Ağ türünün sabit adları (özet, sorun kaydı): <c>wired</c>, <c>wifi</c>, <c>other</c>, <c>offline</c>, <c>unknown</c>.</summary>
public static class NetworkKindNames
{
    /// <summary>Küçük harfli sabit ad.</summary>
    public static string Wire(this NetworkKind kind) => kind switch
    {
        NetworkKind.Wired => "wired",
        NetworkKind.Wifi => "wifi",
        NetworkKind.Other => "other",
        NetworkKind.Offline => "offline",
        _ => "unknown",
    };
}

/// <summary>Ağ türünü bulmada bakılan bir arabirim (saf karar için).</summary>
/// <param name="Up">Çalışıyor mu.</param>
/// <param name="Loopback">Geri döngü mü.</param>
/// <param name="HasGateway">Varsayılan ağ geçidi var mı.</param>
/// <param name="Type">Arabirim türü.</param>
public readonly record struct NetworkAdapter(bool Up, bool Loopback, bool HasGateway, NetworkInterfaceType Type);

/// <summary>Ağ türü kararı: çalışan, geri döngü olmayan, ağ geçitli arabirimlere bakılır.</summary>
public static class NetworkKindDetector
{
    /// <summary>
    /// Hiç uygun arabirim yoksa ağ yok; biri Ethernet türündeyse kablo; biri kablosuzsa Wi-Fi; değilse diğer.
    /// </summary>
    public static NetworkKind Decide(IEnumerable<NetworkAdapter> adapters)
    {
        var usable = adapters.Where(a => a.Up && !a.Loopback && a.HasGateway).ToList();
        if (usable.Count == 0) return NetworkKind.Offline;
        if (usable.Any(a => IsEthernet(a.Type))) return NetworkKind.Wired;
        if (usable.Any(a => a.Type == NetworkInterfaceType.Wireless80211)) return NetworkKind.Wifi;
        return NetworkKind.Other;
    }

    /// <summary>Sistemin arabirim listesinden karar; herhangi bir hata bilinmiyor sayılır. İzin istemez.</summary>
    public static NetworkKind Read()
    {
        try
        {
            var list = new List<NetworkAdapter>();
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                var up = nic.OperationalStatus == OperationalStatus.Up;
                var loopback = nic.NetworkInterfaceType == NetworkInterfaceType.Loopback;
                var gateway = up && !loopback && nic.GetIPProperties().GatewayAddresses.Any(g => IsRealGateway(g.Address));
                list.Add(new NetworkAdapter(up, loopback, gateway, nic.NetworkInterfaceType));
            }
            return Decide(list);
        }
        catch
        {
            return NetworkKind.Unknown;
        }
    }

    static bool IsRealGateway(IPAddress? address) =>
        address is not null && !address.Equals(IPAddress.Any) && !address.Equals(IPAddress.IPv6Any)
        && !address.Equals(IPAddress.None) && !address.Equals(IPAddress.IPv6None);

    static bool IsEthernet(NetworkInterfaceType type) => type is NetworkInterfaceType.Ethernet
        or NetworkInterfaceType.Ethernet3Megabit or NetworkInterfaceType.FastEthernetT
        or NetworkInterfaceType.FastEthernetFx or NetworkInterfaceType.GigabitEthernet;
}

/// <summary>Ağ türünü okuyan ve değişince haber veren hizmet (sorun bekçisi kullanır).</summary>
public interface INetworkWatch
{
    /// <summary>Şu anki tür.</summary>
    NetworkKind Read();

    /// <summary>Ağ değişti (herhangi bir iş parçacığından gelebilir; tür yeniden okunmalı).</summary>
    event Action? Changed;
}

/// <summary>
/// .NET'in ağ bildirimleriyle çalışan izleyici: hem "ağ kullanılabilirliği değişti" hem "ağ adresi değişti" dinlenir
/// (VPN ya da sanal bağdaştırıcı açıkken ilki gelmeyebilir). Abonelik ilk dinleyiciyle kurulur, bırakılınca çözülür.
/// </summary>
public sealed class SystemNetworkWatch : INetworkWatch, IDisposable
{
    readonly object _gate = new();
    Action? _changed;
    bool _subscribed;

    /// <inheritdoc />
    public NetworkKind Read() => NetworkKindDetector.Read();

    /// <inheritdoc />
    public event Action? Changed
    {
        add
        {
            lock (_gate)
            {
                _changed += value;
                if (_subscribed) return;
                try
                {
                    NetworkChange.NetworkAvailabilityChanged += OnAvailability;
                    NetworkChange.NetworkAddressChanged += OnAddress;
                    _subscribed = true;
                }
                catch { }
            }
        }
        remove
        {
            lock (_gate) _changed -= value;
        }
    }

    void OnAvailability(object? sender, NetworkAvailabilityEventArgs e) => Raise();

    void OnAddress(object? sender, EventArgs e) => Raise();

    void Raise()
    {
        Action? handler;
        lock (_gate) handler = _changed;
        try { handler?.Invoke(); }
        catch { }
    }

    /// <inheritdoc />
    public void Dispose()
    {
        lock (_gate)
        {
            _changed = null;
            if (!_subscribed) return;
            try
            {
                NetworkChange.NetworkAvailabilityChanged -= OnAvailability;
                NetworkChange.NetworkAddressChanged -= OnAddress;
            }
            catch { }
            _subscribed = false;
        }
    }
}
