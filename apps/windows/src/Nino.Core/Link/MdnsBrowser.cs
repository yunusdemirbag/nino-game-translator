// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Nino.Core.Link;

/// <summary>mDNS ile bulunan bir Nino TV'si.</summary>
public sealed record MdnsService(string Instance, string Address, int Port, IReadOnlyDictionary<string, string> Txt);

/// <summary>
/// Paket kullanmayan küçük mDNS sorgusu: <c>_nino._tcp.local</c> PTR sorusu 224.0.0.251:5353'e rastgele bir yerel
/// porttan gönderilir (RFC 6762 "tek seferlik" sorgu; yanıt doğrudan bu porta gelir, 5353'ü dinlemek gerekmez).
/// Yanıttaki PTR → SRV → A kayıtları birleştirilir.
/// </summary>
public static class MdnsBrowser
{
    public const string NinoService = "_nino._tcp.local";
    static readonly IPEndPoint Group = new(IPAddress.Parse("224.0.0.251"), 5353);

    /// <summary>Sorgu paketi (kimlik 0, tek soru, PTR, IN).</summary>
    public static byte[] BuildQuery(string service)
    {
        var bytes = new List<byte>(64) { 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 };
        WriteName(bytes, service);
        bytes.AddRange([0, 12, 0, 1]);
        return bytes.ToArray();
    }

    /// <summary>
    /// Verilen arayüz adreslerinden (boşsa varsayılan yoldan) sorar, <paramref name="timeout"/> boyunca yanıt toplar.
    /// </summary>
    public static async Task<IReadOnlyList<MdnsService>> BrowseAsync(IEnumerable<IPAddress> localAddresses,
        TimeSpan timeout, string service = NinoService, CancellationToken ct = default)
    {
        var query = BuildQuery(service);
        var sockets = new List<UdpClient>();
        var locals = localAddresses.ToList();
        try
        {
            if (locals.Count == 0) locals.Add(IPAddress.Any);
            foreach (var local in locals)
            {
                try
                {
                    var udp = new UdpClient(new IPEndPoint(local, 0));
                    if (!local.Equals(IPAddress.Any))
                    {
                        var iface = local.GetAddressBytes();
                        udp.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastInterface, iface);
                    }
                    udp.Client.SetSocketOption(SocketOptionLevel.IP, SocketOptionName.MulticastTimeToLive, 255);
                    await udp.SendAsync(query, Group, ct).ConfigureAwait(false);
                    sockets.Add(udp);
                }
                catch (SocketException) { }
            }

            var found = new Dictionary<string, MdnsService>(StringComparer.OrdinalIgnoreCase);
            using var wait = CancellationTokenSource.CreateLinkedTokenSource(ct);
            wait.CancelAfter(timeout);
            var readers = sockets.Select(async udp =>
            {
                try
                {
                    while (true)
                    {
                        var r = await udp.ReceiveAsync(wait.Token).ConfigureAwait(false);
                        foreach (var s in ParseResponse(r.Buffer, service, r.RemoteEndPoint.Address))
                            lock (found) found.TryAdd(s.Address + ":" + s.Port, s);
                    }
                }
                catch (OperationCanceledException) { }
                catch (SocketException) { }
                catch (ObjectDisposedException) { }
            }).ToArray();
            await Task.WhenAll(readers).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested();
            lock (found) return found.Values.ToList();
        }
        finally
        {
            foreach (var s in sockets) s.Dispose();
        }
    }

    /// <summary>
    /// Yanıt paketini çözer: hizmete ait PTR'ler, onların SRV (port, ana makine) ve A (IPv4) kayıtları. A kaydı
    /// yoksa yanıtı gönderen adres kullanılır.
    /// </summary>
    public static IReadOnlyList<MdnsService> ParseResponse(byte[] packet, string service, IPAddress? sender = null)
    {
        var result = new List<MdnsService>();
        try
        {
            if (packet.Length < 12) return result;
            var flags = BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(2));
            if ((flags & 0x8000) == 0) return result;
            int qd = BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(4));
            int total = BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(6))
                + BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(8))
                + BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(10));
            var pos = 12;
            for (var i = 0; i < qd; i++)
            {
                ReadName(packet, ref pos);
                pos += 4;
            }

            var instances = new List<string>();
            var srv = new Dictionary<string, (string Target, int Port)>(StringComparer.OrdinalIgnoreCase);
            var a = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var txt = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
            for (var i = 0; i < total && pos < packet.Length; i++)
            {
                var name = ReadName(packet, ref pos);
                var type = BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(pos));
                var length = BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(pos + 8));
                var data = pos + 10;
                if (data + length > packet.Length) break;
                switch (type)
                {
                    case 12 when string.Equals(name, service, StringComparison.OrdinalIgnoreCase):
                        var p = data;
                        instances.Add(ReadName(packet, ref p));
                        break;
                    case 33 when length >= 7:
                        var port = BinaryPrimitives.ReadUInt16BigEndian(packet.AsSpan(data + 4));
                        var t = data + 6;
                        srv[name] = (ReadName(packet, ref t), port);
                        break;
                    case 1 when length == 4:
                        a[name] = new IPAddress(packet.AsSpan(data, 4)).ToString();
                        break;
                    case 16:
                        txt[name] = ReadTxt(packet.AsSpan(data, length));
                        break;
                }
                pos = data + length;
            }

            foreach (var instance in instances.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (!srv.TryGetValue(instance, out var s)) continue;
                var address = a.TryGetValue(s.Target, out var ip) ? ip : sender?.ToString();
                if (address is null) continue;
                var label = instance.EndsWith("." + service, StringComparison.OrdinalIgnoreCase)
                    ? instance[..^(service.Length + 1)]
                    : instance;
                result.Add(new MdnsService(label, address, s.Port,
                    txt.TryGetValue(instance, out var tx) ? tx : new Dictionary<string, string>()));
            }
        }
        catch (Exception e) when (e is IndexOutOfRangeException or ArgumentOutOfRangeException or InvalidDataException) { }
        return result;
    }

    static void WriteName(List<byte> bytes, string name)
    {
        foreach (var label in name.TrimEnd('.').Split('.'))
        {
            var b = Encoding.UTF8.GetBytes(label);
            bytes.Add((byte)b.Length);
            bytes.AddRange(b);
        }
        bytes.Add(0);
    }

    /// <summary>Sıkıştırmalı DNS adı (en çok 20 atlama).</summary>
    static string ReadName(byte[] packet, ref int pos)
    {
        var labels = new List<string>();
        var p = pos;
        var jumped = false;
        for (var hops = 0; hops < 20; hops++)
        {
            var len = packet[p];
            if (len == 0)
            {
                if (!jumped) pos = p + 1;
                return string.Join('.', labels);
            }
            if ((len & 0xC0) == 0xC0)
            {
                var target = ((len & 0x3F) << 8) | packet[p + 1];
                if (!jumped) pos = p + 2;
                jumped = true;
                p = target;
                continue;
            }
            labels.Add(Encoding.UTF8.GetString(packet, p + 1, len));
            p += 1 + len;
        }
        throw new InvalidDataException("DNS adı çözülemedi");
    }

    static Dictionary<string, string> ReadTxt(ReadOnlySpan<byte> data)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var i = 0;
        while (i < data.Length)
        {
            var len = data[i];
            if (i + 1 + len > data.Length) break;
            var entry = Encoding.UTF8.GetString(data.Slice(i + 1, len));
            var eq = entry.IndexOf('=');
            if (eq > 0) result[entry[..eq]] = entry[(eq + 1)..];
            else if (entry.Length > 0) result[entry] = "";
            i += 1 + len;
        }
        return result;
    }
}
