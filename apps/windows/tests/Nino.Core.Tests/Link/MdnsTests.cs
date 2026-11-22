// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using Nino.Core.Link;

namespace Nino.Core.Tests.Link;

public class MdnsTests
{
    static void Name(List<byte> b, string name)
    {
        foreach (var label in name.Split('.'))
        {
            var bytes = Encoding.UTF8.GetBytes(label);
            b.Add((byte)bytes.Length);
            b.AddRange(bytes);
        }
        b.Add(0);
    }

    static void U16(List<byte> b, int v) => b.AddRange([(byte)(v >> 8), (byte)v]);

    static void Record(List<byte> b, Action<List<byte>> name, int type, Action<List<byte>> data)
    {
        name(b);
        U16(b, type);
        U16(b, 0x8001);
        b.AddRange([0, 0, 0x11, 0x94]);
        var d = new List<byte>();
        data(d);
        U16(b, d.Count);
        b.AddRange(d);
    }

    [Fact]
    public void QueryAsksForPtr()
    {
        var q = MdnsBrowser.BuildQuery("_nino._tcp.local");
        var expected = new List<byte> { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
        Name(expected, "_nino._tcp.local");
        expected.AddRange([0, 12, 0, 1]);
        Assert.Equal(expected, q);
    }

    [Fact]
    public void ResponseIsResolvedWithCompression()
    {
        var b = new List<byte> { 0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 3 };
        var serviceAt = b.Count;
        Record(b, x => Name(x, "_nino._tcp.local"), 12, d => { Name(d, "Salon TV"); d.RemoveAt(d.Count - 1); d.AddRange([0xC0, (byte)serviceAt]); });
        var instanceAt = b.Count;
        Record(b, x => { Name(x, "Salon TV"); x.RemoveAt(x.Count - 1); x.AddRange([0xC0, (byte)serviceAt]); }, 33,
            d => { U16(d, 0); U16(d, 0); U16(d, 47800); Name(d, "tv-1.local"); });
        Record(b, x => x.AddRange([0xC0, (byte)instanceAt]), 16, d =>
        {
            foreach (var entry in new[] { "v=1", "id=b1f2" })
            {
                d.Add((byte)entry.Length);
                d.AddRange(Encoding.ASCII.GetBytes(entry));
            }
        });
        Record(b, x => Name(x, "tv-1.local"), 1, d => d.AddRange([192, 168, 1, 77]));

        var found = Assert.Single(MdnsBrowser.ParseResponse(b.ToArray(), MdnsBrowser.NinoService));
        Assert.Equal("Salon TV", found.Instance);
        Assert.Equal("192.168.1.77", found.Address);
        Assert.Equal(47800, found.Port);
        Assert.Equal("1", found.Txt["v"]);
        Assert.Equal("b1f2", found.Txt["id"]);
    }

    [Fact]
    public void MissingAddressRecordFallsBackToSender()
    {
        var b = new List<byte> { 0, 0, 0x84, 0, 0, 0, 0, 2, 0, 0, 0, 0 };
        Record(b, x => Name(x, "_nino._tcp.local"), 12, d => Name(d, "TV._nino._tcp.local"));
        Record(b, x => Name(x, "TV._nino._tcp.local"), 33, d => { U16(d, 0); U16(d, 0); U16(d, 47800); Name(d, "tv.local"); });
        var found = Assert.Single(MdnsBrowser.ParseResponse(b.ToArray(), MdnsBrowser.NinoService, IPAddress.Parse("10.0.0.9")));
        Assert.Equal("10.0.0.9", found.Address);
    }

    [Fact]
    public void BrokenOrForeignPacketsGiveNothing()
    {
        Assert.Empty(MdnsBrowser.ParseResponse([1, 2, 3], MdnsBrowser.NinoService));
        Assert.Empty(MdnsBrowser.ParseResponse(MdnsBrowser.BuildQuery(MdnsBrowser.NinoService), MdnsBrowser.NinoService));
        var b = new List<byte> { 0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0 };
        Record(b, x => Name(x, "_other._tcp.local"), 12, d => Name(d, "X._other._tcp.local"));
        Assert.Empty(MdnsBrowser.ParseResponse(b.ToArray(), MdnsBrowser.NinoService));
        var truncated = b.Take(b.Count - 3).ToArray();
        Assert.Empty(MdnsBrowser.ParseResponse(truncated, MdnsBrowser.NinoService));
    }
}
