// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace Nino.Core.Link;

/// <summary>Elle okunan küçük HTTP isteği: ilk satır ve başlıklar.</summary>
public sealed class HttpHead
{
    public string Method { get; init; } = "";
    public string Target { get; init; } = "";
    public IReadOnlyDictionary<string, string> Headers { get; init; } =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    /// <summary>Başlıklardan sonra okunmuş fazla baytlar.</summary>
    public byte[] Leftover { get; init; } = [];

    /// <summary>Hedefin <c>?</c> öncesi.</summary>
    public string Path => Target.IndexOf('?') is var q and >= 0 ? Target[..q] : Target;

    /// <summary>Hedefin <c>?</c> sonrası (yoksa boş).</summary>
    public string Query => Target.IndexOf('?') is var q and >= 0 ? Target[(q + 1)..] : "";

    public string? Header(string name) => Headers.TryGetValue(name, out var v) ? v : null;

    /// <summary>
    /// Başlıkların sonu (<c>\r\n\r\n</c>) görülene kadar parça parça okur. Sınır aşılırsa ya da bağlantı erken
    /// kapanırsa <c>null</c>. Metin ASCII çözülür.
    /// </summary>
    public static async Task<HttpHead?> ReadAsync(Stream stream, int maxBytes, int chunkBytes, CancellationToken ct)
    {
        var buffer = new byte[chunkBytes];
        var all = new MemoryStream();
        while (true)
        {
            var n = await stream.ReadAsync(buffer, ct).ConfigureAwait(false);
            if (n <= 0) return null;
            var searchFrom = (int)Math.Max(0, all.Length - 3);
            all.Write(buffer, 0, n);
            var bytes = all.GetBuffer();
            var end = IndexOfHeaderEnd(bytes, (int)all.Length, searchFrom);
            if (end >= 0) return Parse(bytes, end, (int)all.Length);
            if (all.Length > maxBytes) return null;
        }
    }

    static int IndexOfHeaderEnd(byte[] b, int length, int from)
    {
        for (var i = from; i + 3 < length; i++)
            if (b[i] == '\r' && b[i + 1] == '\n' && b[i + 2] == '\r' && b[i + 3] == '\n') return i;
        return -1;
    }

    static HttpHead Parse(byte[] bytes, int end, int length)
    {
        var text = Encoding.ASCII.GetString(bytes, 0, end);
        var lines = text.Split("\r\n");
        var first = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in lines.Skip(1))
        {
            var colon = line.IndexOf(':');
            if (colon <= 0) continue;
            headers[line[..colon].Trim()] = line[(colon + 1)..].Trim();
        }
        var leftover = bytes.AsSpan(end + 4, length - end - 4).ToArray();
        return new HttpHead
        {
            Method = first.Length > 0 ? first[0] : "",
            Target = first.Length > 1 ? first[1] : "",
            Headers = headers,
            Leftover = leftover,
        };
    }
}

/// <summary>Elle yazılan HTTP/WebSocket parçaları.</summary>
public static class HttpWire
{
    const string WebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    /// <summary>RFC 6455 <c>Sec-WebSocket-Accept</c>: SHA-1(anahtar + GUID), base64.</summary>
    public static string WebSocketAccept(string key) =>
        Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key.Trim() + WebSocketGuid)));

    /// <summary>
    /// Yalnız özel adresler: 10/8, 172.16/12, 192.168/16, 169.254/16, 127/8 (IPv4'e eşlenmiş IPv6 da) ve ::1.
    /// </summary>
    public static bool IsPrivateOrLocal(IPAddress? address)
    {
        if (address is null) return false;
        if (address.IsIPv4MappedToIPv6) address = address.MapToIPv4();
        if (address.AddressFamily == AddressFamily.InterNetworkV6) return IPAddress.IPv6Loopback.Equals(address);
        if (address.AddressFamily != AddressFamily.InterNetwork) return false;
        var b = address.GetAddressBytes();
        return b[0] == 10
            || b[0] == 127
            || (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
            || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254);
    }

    /// <summary>Okunmuş fazla baytları önce veren akış (WebSocket'e geçerken).</summary>
    public static Stream WithPrefix(Stream inner, byte[] prefix) =>
        prefix.Length == 0 ? inner : new PrefixedStream(inner, prefix);

    /// <summary>Port dolu hatası mı.</summary>
    public static bool IsAddressInUse(Exception e) =>
        e is SocketException { SocketErrorCode: SocketError.AddressAlreadyInUse or SocketError.AccessDenied };

    /// <summary>Bütün IPv4 adreslerinde dinleyen soket. Windows'ta başka süreç aynı portu paylaşamaz.</summary>
    public static TcpListener Listen(int port)
    {
        var listener = new TcpListener(new IPEndPoint(IPAddress.Any, port));
        if (OperatingSystem.IsWindows())
        {
            try { listener.ExclusiveAddressUse = true; } catch (SocketException) { }
        }
        listener.Start();
        return listener;
    }

    /// <summary>TCP canlılık (boşta 10 sn, aralık 5 sn, 3 deneme) ve Nagle kapalı; verilemeyen ayar atlanır.</summary>
    public static void Tune(Socket socket)
    {
        try { socket.NoDelay = true; } catch (Exception) { }
        try
        {
            const SocketOptionLevel tcp = SocketOptionLevel.Tcp;
            socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, optionValue: true);
            socket.SetSocketOption(tcp, SocketOptionName.TcpKeepAliveTime, optionValue: 10);
            socket.SetSocketOption(tcp, SocketOptionName.TcpKeepAliveInterval, optionValue: 5);
            socket.SetSocketOption(tcp, SocketOptionName.TcpKeepAliveRetryCount, optionValue: 3);
        }
        catch (Exception) { }
    }

    sealed class PrefixedStream(Stream inner, byte[] prefix) : Stream
    {
        int offset;

        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => inner.CanWrite;
        public override long Length => throw new NotSupportedException("akışın boyu yok");
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => inner.Flush();
        public override Task FlushAsync(CancellationToken ct) => inner.FlushAsync(ct);
        public override long Seek(long o, SeekOrigin s) => throw new NotSupportedException();
        public override void SetLength(long v) => throw new NotSupportedException();

        public override int Read(byte[] buffer, int off, int count) => Read(buffer.AsSpan(off, count));

        public override int Read(Span<byte> buffer)
        {
            if (offset < prefix.Length)
            {
                var n = Math.Min(buffer.Length, prefix.Length - offset);
                prefix.AsSpan(offset, n).CopyTo(buffer);
                offset += n;
                return n;
            }
            return inner.Read(buffer);
        }

        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct = default)
        {
            if (offset < prefix.Length) return ValueTask.FromResult(Read(buffer.Span));
            return inner.ReadAsync(buffer, ct);
        }

        public override Task<int> ReadAsync(byte[] buffer, int off, int count, CancellationToken ct) =>
            ReadAsync(buffer.AsMemory(off, count), ct).AsTask();

        public override void Write(byte[] buffer, int off, int count) => inner.Write(buffer, off, count);

        public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken ct = default) =>
            inner.WriteAsync(buffer, ct);

        public override Task WriteAsync(byte[] buffer, int off, int count, CancellationToken ct) =>
            inner.WriteAsync(buffer, off, count, ct);

        protected override void Dispose(bool disposing)
        {
            if (disposing) inner.Dispose();
            base.Dispose(disposing);
        }
    }
}
