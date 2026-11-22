// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace Nino.TvInstall.Android;

/// <summary>Bir ADB paketi.</summary>
public readonly record struct AdbPacket(uint Command, uint Arg0, uint Arg1, byte[] Data);

/// <summary>ADB paket biçimi: 24 baytlık küçük sonlu başlık + veri.</summary>
public static class AdbWire
{
    public const uint Cnxn = 0x4e584e43, Auth = 0x48545541, Open = 0x4e45504f, Okay = 0x59414b4f, Clse = 0x45534c43, Wrte = 0x45545257;
    public const uint AuthToken = 1, AuthSignature = 2, AuthPublicKey = 3;
    public const uint Version = 0x01000001;
    public const uint MaxPayload = 262144;
    public const int MaxPacket = 1024 * 1024;

    public static byte[] Encode(AdbPacket p)
    {
        var buf = new byte[24 + p.Data.Length];
        var s = buf.AsSpan();
        BinaryPrimitives.WriteUInt32LittleEndian(s[0..], p.Command);
        BinaryPrimitives.WriteUInt32LittleEndian(s[4..], p.Arg0);
        BinaryPrimitives.WriteUInt32LittleEndian(s[8..], p.Arg1);
        BinaryPrimitives.WriteUInt32LittleEndian(s[12..], (uint)p.Data.Length);
        uint sum = 0;
        foreach (var b in p.Data) sum += b;
        BinaryPrimitives.WriteUInt32LittleEndian(s[16..], sum);
        BinaryPrimitives.WriteUInt32LittleEndian(s[20..], p.Command ^ 0xffffffff);
        p.Data.CopyTo(s[24..]);
        return buf;
    }

    public static async Task WriteAsync(Stream stream, AdbPacket p, CancellationToken ct)
    {
        await stream.WriteAsync(Encode(p), ct).ConfigureAwait(false);
        await stream.FlushAsync(ct).ConfigureAwait(false);
    }

    public static async Task<AdbPacket> ReadAsync(Stream stream, CancellationToken ct)
    {
        var head = new byte[24];
        await stream.ReadExactlyAsync(head, ct).ConfigureAwait(false);
        var cmd = BinaryPrimitives.ReadUInt32LittleEndian(head.AsSpan(0));
        var length = BinaryPrimitives.ReadUInt32LittleEndian(head.AsSpan(12));
        var magic = BinaryPrimitives.ReadUInt32LittleEndian(head.AsSpan(20));
        if (magic != (cmd ^ 0xffffffff) || length > MaxPacket) throw new IOException("ADB paketi bozuk");
        var data = new byte[length];
        if (length > 0) await stream.ReadExactlyAsync(data, ct).ConfigureAwait(false);
        return new AdbPacket(cmd, BinaryPrimitives.ReadUInt32LittleEndian(head.AsSpan(4)),
            BinaryPrimitives.ReadUInt32LittleEndian(head.AsSpan(8)), data);
    }
}

/// <summary>
/// Ağ üzerinden ADB bağlantısı (Google aracı dağıtılmadan): el sıkışma, RSA kimlik doğrulama ve hizmet çalıştırma.
/// Hatalar: <see cref="TvInstallFailure.Unreachable"/>, <see cref="TvInstallFailure.NotApproved"/>,
/// <see cref="TvInstallFailure.InstallFailed"/>.
/// </summary>
public sealed class AdbSession : IAsyncDisposable
{
    public const string DeviceLabel = "nino@Nino";
    public static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(5);
    public static readonly TimeSpan HandshakeTimeout = TimeSpan.FromSeconds(10);
    public static readonly TimeSpan DefaultApprovalTimeout = TimeSpan.FromSeconds(90);

    readonly TcpClient _client;
    readonly Stream _stream;
    uint _nextLocal = 1;

    AdbSession(TcpClient client)
    {
        _client = client;
        _stream = client.GetStream();
    }

    /// <summary>TV'nin söylediği en büyük yük.</summary>
    public uint MaxPayload { get; private set; } = 4096;

    /// <summary>Bağlanır ve el sıkışır. TV bu bilgisayarı tanımıyorsa <paramref name="onApprovalNeeded"/> çağrılır.</summary>
    public static async Task<AdbSession> ConnectAsync(string host, int port, RSA key, Action? onApproval = null,
        TimeSpan? approvalTimeout = null, CancellationToken ct = default)
    {
        var client = new TcpClient(AddressFamily.InterNetwork) { NoDelay = true };
        try
        {
            using (var cts = CancellationTokenSource.CreateLinkedTokenSource(ct))
            {
                cts.CancelAfter(ConnectTimeout);
                try
                {
                    if (IPAddress.TryParse(host, out var ip)) await client.ConnectAsync(ip, port, cts.Token).ConfigureAwait(false);
                    else await client.ConnectAsync(host, port, cts.Token).ConfigureAwait(false);
                }
                catch (Exception e) when (!ct.IsCancellationRequested && e is SocketException or OperationCanceledException)
                {
                    throw new TvInstallException(TvInstallFailure.Unreachable, $"{host}:{port}: {e.Message}", e);
                }
            }
            var conn = new AdbSession(client);
            await conn.HandshakeAsync(key, onApproval, approvalTimeout ?? DefaultApprovalTimeout, ct).ConfigureAwait(false);
            return conn;
        }
        catch
        {
            client.Dispose();
            throw;
        }
    }

    async Task HandshakeAsync(RSA key, Action? onApprovalNeeded, TimeSpan approvalTimeout, CancellationToken ct)
    {
        await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Cnxn, AdbWire.Version, AdbWire.MaxPayload,
            Encoding.ASCII.GetBytes("host::\0")), ct).ConfigureAwait(false);
        var signed = false;
        var awaiting = false;
        using var timer = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timer.CancelAfter(HandshakeTimeout);
        while (true)
        {
            AdbPacket p;
            try
            {
                p = await AdbWire.ReadAsync(_stream, timer.Token).ConfigureAwait(false);
            }
            catch (Exception e) when (!ct.IsCancellationRequested && e is OperationCanceledException or IOException or SocketException)
            {
                throw new TvInstallException(awaiting ? TvInstallFailure.NotApproved : TvInstallFailure.Unreachable,
                    awaiting ? "TV'de izin verilmedi" : e.Message, e);
            }
            if (p.Command == AdbWire.Cnxn)
            {
                MaxPayload = Math.Min(AdbWire.MaxPayload, p.Arg1 == 0 ? 4096u : p.Arg1);
                return;
            }
            if (p.Command == AdbWire.Auth && p.Arg0 == AdbWire.AuthToken)
            {
                if (!signed)
                {
                    signed = true;
                    // Jeton yeniden özetlenmez: SHA-1 özetinin yerine konup PKCS#1 v1.5 ile imzalanır.
                    var signature = key.SignHash(p.Data, HashAlgorithmName.SHA1, RSASignaturePadding.Pkcs1);
                    await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Auth, AdbWire.AuthSignature, 0, signature), ct).ConfigureAwait(false);
                }
                else if (!awaiting)
                {
                    awaiting = true;
                    var text = Convert.ToBase64String(AdbKey.AndroidPublicKey(key)) + " " + DeviceLabel + "\0";
                    await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Auth, AdbWire.AuthPublicKey, 0,
                        Encoding.ASCII.GetBytes(text)), ct).ConfigureAwait(false);
                    timer.CancelAfter(approvalTimeout);
                    onApprovalNeeded?.Invoke();
                }
                continue;
            }
            throw new TvInstallException(TvInstallFailure.Unreachable, $"unexpected packet {p.Command:x8}");
        }
    }

    /// <summary>Bir hizmeti (<c>shell:…</c>, <c>exec:…</c>) çalıştırır; varsa girdiyi akıtır; çıktıyı UTF-8 metin döner.</summary>
    public async Task<string> RunAsync(string service, Stream? input = null, CancellationToken ct = default)
    {
        var local = _nextLocal++;
        uint remote = 0;
        var closed = false;
        var received = new MemoryStream();
        await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Open, local, 0, Encoding.UTF8.GetBytes(service + "\0")), ct).ConfigureAwait(false);

        // Bir paketi işler; OKAY (bizim kanal) gelince true döner.
        async Task<bool> HandleAsync(AdbPacket p)
        {
            switch (p.Command)
            {
                case AdbWire.Okay when p.Arg1 == local:
                    if (remote == 0) remote = p.Arg0;
                    return true;
                case AdbWire.Wrte when p.Arg1 == local:
                    received.Write(p.Data);
                    await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Okay, local, p.Arg0, []), ct).ConfigureAwait(false);
                    return false;
                case AdbWire.Clse when p.Arg1 == local || p.Arg1 == 0:
                    closed = true;
                    return false;
                default:
                    return false;
            }
        }

        while (remote == 0 && !closed) await HandleAsync(await AdbWire.ReadAsync(_stream, ct).ConfigureAwait(false)).ConfigureAwait(false);
        if (closed && remote == 0) throw new TvInstallException(TvInstallFailure.InstallFailed, $"{service} açılamadı");

        if (input is not null)
        {
            var buffer = new byte[MaxPayload];
            var first = true;
            while (!closed)
            {
                if (!first)
                {
                    var acked = false;
                    while (!acked && !closed) acked = await HandleAsync(await AdbWire.ReadAsync(_stream, ct).ConfigureAwait(false)).ConfigureAwait(false);
                    if (closed) break;
                }
                var n = await input.ReadAsync(buffer, ct).ConfigureAwait(false);
                if (n == 0) break;
                await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Wrte, local, remote, buffer[..n]), ct).ConfigureAwait(false);
                first = false;
            }
        }

        while (!closed) await HandleAsync(await AdbWire.ReadAsync(_stream, ct).ConfigureAwait(false)).ConfigureAwait(false);
        try { await AdbWire.WriteAsync(_stream, new AdbPacket(AdbWire.Clse, local, remote, []), ct).ConfigureAwait(false); }
        catch (IOException) { }
        return Encoding.UTF8.GetString(received.ToArray());
    }

    public ValueTask DisposeAsync()
    {
        _client.Dispose();
        return ValueTask.CompletedTask;
    }
}
