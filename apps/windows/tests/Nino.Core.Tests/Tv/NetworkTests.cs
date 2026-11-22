// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net.NetworkInformation;
using Nino.Core.Tv;

namespace Nino.Core.Tests.Tv;

public class NetworkTests
{
    const string Mask = "255.255.255.0";
    static readonly AdapterAddress WiFi = new("Wi-Fi", "Intel(R) Wi-Fi 6 AX201 160MHz", NetworkInterfaceType.Wireless80211, "192.168.1.34", Mask, true);
    static readonly AdapterAddress HyperV = new("vEthernet (WSL)", "Hyper-V Virtual Ethernet Adapter", NetworkInterfaceType.Ethernet, "172.24.80.1", Mask);
    static readonly AdapterAddress VirtualBox = new("Ethernet 2", "VirtualBox Host-Only Ethernet Adapter", NetworkInterfaceType.Ethernet, "192.168.56.1", Mask);
    static readonly AdapterAddress Vpn = new("ProtonVPN", "WireGuard Tunnel", NetworkInterfaceType.Ethernet, "10.2.0.2", Mask, true);
    static readonly AdapterAddress Cable = new("Ethernet", "Realtek PCIe GbE Family Controller", NetworkInterfaceType.Ethernet, "192.168.1.35", Mask, true);

    [Theory]
    [InlineData("192.168.0.10", true)]
    [InlineData("172.20.1.1", true)]
    [InlineData("10.1.2.3", true)]
    [InlineData("8.8.8.8", false)]
    [InlineData("172.32.0.1", false)]
    [InlineData("::1", false)]
    [InlineData("nope", false)]
    public void PrivateAddresses(string address, bool expected) => Assert.Equal(expected, LocalNetwork.IsPrivate(address));

    [Fact]
    public void VirtualAdapters()
    {
        Assert.True(LocalNetwork.IsVirtual(HyperV));
        Assert.True(LocalNetwork.IsVirtual(VirtualBox));
        Assert.True(LocalNetwork.IsVirtual(Vpn));
        Assert.False(LocalNetwork.IsVirtual(WiFi));
        Assert.False(LocalNetwork.IsVirtual(Cable));
        Assert.True(LocalNetwork.IsVirtual("x", "y", NetworkInterfaceType.Tunnel));
        Assert.False(LocalNetwork.IsVirtual("Laptop", "Realtek", NetworkInterfaceType.Ethernet));
        Assert.True(LocalNetwork.IsVirtual("tap x", "", NetworkInterfaceType.Ethernet));
    }

    [Fact]
    public void AddressChoiceMatchesExamples()
    {
        Assert.Equal("192.168.1.34", LocalNetwork.Choose([HyperV, VirtualBox, Vpn, WiFi], "192.168.1.171", null));
        Assert.Equal("192.168.1.34", LocalNetwork.Choose([HyperV, VirtualBox, Vpn, WiFi], null, null));
        Assert.Equal("192.168.1.34", LocalNetwork.Choose([Vpn, HyperV, WiFi], "10.0.0.9", null));
        Assert.Equal("192.168.1.35", LocalNetwork.Choose([WiFi, Cable], "192.168.1.171", "192.168.1.35"));
        Assert.Equal("172.24.80.1", LocalNetwork.Choose([HyperV, WiFi], "192.168.1.171", "172.24.80.1"));
        foreach (var route in new string?[] { null, "127.0.0.1", "0.0.0.0", "10.9.9.9" })
            Assert.Equal("192.168.1.34", LocalNetwork.Choose([HyperV, WiFi], "192.168.1.171", route));
        Assert.Equal("10.2.0.2", LocalNetwork.Choose([Vpn], null, null));
        Assert.Null(LocalNetwork.Choose([], null, null));
        Assert.Equal("192.168.5.5", LocalNetwork.Choose([], null, "192.168.5.5"));
    }

    [Fact]
    public void RouteToLoopbackStartsAtLoopback() => Assert.Equal("127.0.0.1", LocalNetwork.RouteSource("127.0.0.1"));

    [Fact]
    public void RouteNeedsIpv4() => Assert.Null(LocalNetwork.RouteSource("tv.local"));

    [Fact]
    public void ScanTargets()
    {
        var one = LocalNetwork.ScanTargets(["192.168.1.40"]);
        Assert.Equal(253, one.Count);
        Assert.Contains("192.168.1.1", one);
        Assert.Contains("192.168.1.254", one);
        Assert.DoesNotContain("192.168.1.40", one);
        var two = LocalNetwork.ScanTargets(["10.0.0.5", "10.0.0.6"]);
        Assert.Equal(two.Count, two.Distinct().Count());
        Assert.Equal(254, two.Count);
        Assert.Equal(253, LocalNetwork.ScanTargets(["192.168.1.20"]).Count);
    }

    [Fact]
    public async Task OpenHostsAreSorted()
    {
        var l = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        l.Start();
        var port = ((System.Net.IPEndPoint)l.LocalEndpoint).Port;
        var found = await LocalNetwork.OpenHostsAsync(["127.0.0.1"], port, TimeSpan.FromSeconds(1));
        Assert.Equal(["127.0.0.1"], found);
        l.Stop();
        Assert.Empty(await LocalNetwork.OpenHostsAsync(["127.0.0.1"], port, TimeSpan.FromMilliseconds(300)));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            LocalNetwork.OpenHostsAsync(["127.0.0.1"], port, TimeSpan.FromSeconds(1), ct: new CancellationToken(true)));
    }

    [Fact]
    public void SsdpRequestAndResponse()
    {
        Assert.Equal("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:x\r\n\r\n",
            Ssdp.Request("urn:x"));
        const string reply = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLOCATION: http://192.168.1.153:1990/abc/description.xml\r\n"
            + "ST: urn:lge-com:service:webos-second-screen:1\r\nSERVER: WebOS/4.4.0 UPnP/1.0\r\n\r\n";
        Assert.Equal("192.168.1.153", Ssdp.ParseResponse(reply, Ssdp.LgTarget));
        Assert.Null(Ssdp.ParseResponse(reply.Replace("ST: urn:lge-com:service:webos-second-screen:1", "ST: urn:other"), Ssdp.LgTarget));
        Assert.Equal("192.168.1.153", Ssdp.ParseResponse(reply.Replace("ST: ", "nt: "), Ssdp.LgTarget));
        Assert.Null(Ssdp.ParseResponse("ST: urn:lge-com:service:webos-second-screen:1\r\n", Ssdp.LgTarget));
    }

    [Fact]
    public void TvNames()
    {
        Assert.Equal("[LG] webOS TV UK7550", TvDiscovery.ParseFriendlyName("<root><friendlyName>[LG] webOS TV UK7550</friendlyName></root>"));
        Assert.Null(TvDiscovery.ParseFriendlyName("<root/>"));
        Assert.Equal("[TV] Samsung QN70F", TvDiscovery.ParseSamsungName("{\"device\":{\"name\":\"[TV] Samsung QN70F\"}}"));
        Assert.Equal("\"Salon\"", TvDiscovery.ParseSamsungName("{\"device\":{\"name\":\"&quot;Salon&quot;\"}}"));
        Assert.Null(TvDiscovery.ParseSamsungName("{}"));
        Assert.Null(TvDiscovery.ParseSamsungName("<html>"));
    }

    [Fact]
    public void TokenToStore()
    {
        Assert.Equal("55", TvRecord.KeyToStore("55", ""));
        Assert.Equal("77", TvRecord.KeyToStore("55", "77"));
        Assert.Equal("", TvRecord.KeyToStore(null, ""));
    }
}
