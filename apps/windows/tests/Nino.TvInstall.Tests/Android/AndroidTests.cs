// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Nino.TvInstall.Android;
using Nino.TvInstall.Tests.Common;

namespace Nino.TvInstall.Tests.Android;

/// <summary>127.0.0.1 üstünde küçük sahte adbd.</summary>
sealed class FakeAdbd : IAsyncDisposable
{
    readonly TcpListener _listener = new(IPAddress.Loopback, 0);
    readonly Task _loop;
    public RSA? Trusted;
    public bool Approve = true;
    public Func<string, string> Reply = _ => "";
    public readonly List<string> Services = [];
    public readonly Dictionary<string, byte[]> Inputs = [];
    public string? PublicKeyText;

    public FakeAdbd()
    {
        _listener.Start();
        _loop = Task.Run(AcceptAsync);
    }

    public int Port => ((IPEndPoint)_listener.LocalEndpoint).Port;

    async Task AcceptAsync()
    {
        while (true)
        {
            TcpClient c;
            try { c = await _listener.AcceptTcpClientAsync(); } catch { return; }
            _ = Task.Run(async () => { using (c) { try { await ServeAsync(c.GetStream()); } catch { } } });
        }
    }

    async Task ServeAsync(NetworkStream s)
    {
        var ct = CancellationToken.None;
        var challenge = RandomNumberGenerator.GetBytes(20);
        uint nextRemote = 100;
        while (true)
        {
            var p = await AdbWire.ReadAsync(s, ct);
            switch (p.Command)
            {
                case AdbWire.Cnxn:
                    await AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Auth, AdbWire.AuthToken, 0, challenge), ct);
                    break;
                case AdbWire.Auth when p.Arg0 == AdbWire.AuthSignature:
                    if (Trusted is not null && Trusted.VerifyHash(challenge, p.Data, HashAlgorithmName.SHA1, RSASignaturePadding.Pkcs1))
                        await Connected(s);
                    else await AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Auth, AdbWire.AuthToken, 0, challenge), ct);
                    break;
                case AdbWire.Auth when p.Arg0 == AdbWire.AuthPublicKey:
                    PublicKeyText = Encoding.ASCII.GetString(p.Data).TrimEnd('\0');
                    if (!Approve) return;
                    await Connected(s);
                    break;
                case AdbWire.Open:
                    {
                        var service = Encoding.UTF8.GetString(p.Data).TrimEnd('\0');
                        lock (Services) Services.Add(service);
                        var local = p.Arg0;
                        var remote = nextRemote++;
                        await AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Okay, remote, local, []), ct);
                        var m = Regex.Match(service, @"-S (\d+)");
                        if (m.Success)
                        {
                            var want = int.Parse(m.Groups[1].Value);
                            var got = new MemoryStream();
                            while (got.Length < want)
                            {
                                var w = await AdbWire.ReadAsync(s, ct);
                                if (w.Command != AdbWire.Wrte) continue;
                                got.Write(w.Data);
                                await AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Okay, remote, local, []), ct);
                            }
                            Inputs[service] = got.ToArray();
                        }
                        var reply = Reply(service);
                        if (reply.Length > 0)
                        {
                            await AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Wrte, remote, local, Encoding.UTF8.GetBytes(reply)), ct);
                            AdbPacket ack;
                            do ack = await AdbWire.ReadAsync(s, ct); while (ack.Command != AdbWire.Okay);
                        }
                        await AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Clse, remote, local, []), ct);
                        break;
                    }
            }
        }
    }

    static Task Connected(NetworkStream s) =>
        AdbWire.WriteAsync(s, new AdbPacket(AdbWire.Cnxn, AdbWire.Version, 4096, Encoding.ASCII.GetBytes("device::\0")), default);

    public async ValueTask DisposeAsync()
    {
        _listener.Stop();
        try { await _loop; } catch { }
    }
}

public class AdbTests
{
    [Fact]
    public void AndroidPublicKeyFormat()
    {
        using var rsa = RSA.Create(2048);
        var k = AdbKey.AndroidPublicKey(rsa);
        Assert.Equal(524, k.Length);
        Assert.Equal(64u, BinaryPrimitives.ReadUInt32LittleEndian(k));
        var modulus = rsa.ExportParameters(false).Modulus!;
        Assert.Equal(modulus.Reverse().ToArray(), k[8..264]);
        var n0inv = BinaryPrimitives.ReadUInt32LittleEndian(k.AsSpan(4));
        var n0 = BinaryPrimitives.ReadUInt32LittleEndian(k.AsSpan(8));
        Assert.Equal(0xFFFFFFFFu, unchecked(n0inv * n0));
        Assert.Equal(65537u, BinaryPrimitives.ReadUInt32LittleEndian(k.AsSpan(520)));
        var n = new BigInteger(modulus, true, true);
        var rr = new BigInteger(k[264..520], true, false);
        Assert.Equal(BigInteger.ModPow(BigInteger.One << 2048, 2, n), rr);
    }

    [Fact]
    public void KeyIsStable()
    {
        using var dir = new TempDir();
        using var a = AdbKey.LoadOrCreate(dir.Path);
        using var b = AdbKey.LoadOrCreate(dir.Path);
        Assert.Equal(a.ExportParameters(false).Modulus, b.ExportParameters(false).Modulus);
        Assert.Contains("BEGIN PRIVATE KEY", File.ReadAllText(Path.Combine(dir.Path, "adbkey")));
    }

    [Fact]
    public async Task NewComputerAsksApproval()
    {
        await using var adbd = new FakeAdbd { Reply = _ => "Success\n" };
        using var key = RSA.Create(2048);
        var asked = 0;
        await using var conn = await AdbSession.ConnectAsync("127.0.0.1", adbd.Port, key, () => asked++);
        Assert.Equal(1, asked);
        Assert.Equal("Success\n", await conn.RunAsync("shell:echo"));
        var parts = adbd.PublicKeyText!.Split(' ');
        Assert.Equal(2, parts.Length);
        Assert.Equal(AdbKey.AndroidPublicKey(key), Convert.FromBase64String(parts[0]));
        Assert.Equal("nino@Nino", parts[1]);
        Assert.Equal(4096u, conn.MaxPayload);
    }

    [Fact]
    public async Task TrustedKeyNotAsked()
    {
        using var key = RSA.Create(2048);
        await using var adbd = new FakeAdbd { Trusted = key };
        var asked = false;
        await using var conn = await AdbSession.ConnectAsync("127.0.0.1", adbd.Port, key, () => asked = true);
        Assert.False(asked);
        Assert.Null(adbd.PublicKeyText);
    }

    [Fact]
    public async Task NotApproved()
    {
        await using var adbd = new FakeAdbd { Approve = false };
        using var key = RSA.Create(2048);
        var e = await Assert.ThrowsAsync<TvInstallException>(() =>
            AdbSession.ConnectAsync("127.0.0.1", adbd.Port, key, null, TimeSpan.FromSeconds(5)));
        Assert.Equal(TvInstallFailure.NotApproved, e.Failure);
    }

    [Fact]
    public async Task ClosedPortUnreachable()
    {
        using var key = RSA.Create(2048);
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        var e = await Assert.ThrowsAsync<TvInstallException>(() => AdbSession.ConnectAsync("127.0.0.1", port, key));
        Assert.Equal(TvInstallFailure.Unreachable, e.Failure);
        Assert.StartsWith("Unreachable: ", e.Message);
    }

    [Fact]
    public async Task StreamsInputInChunks()
    {
        using var key = RSA.Create(2048);
        await using var adbd = new FakeAdbd { Trusted = key, Reply = _ => "Success\n" };
        await using var conn = await AdbSession.ConnectAsync("127.0.0.1", adbd.Port, key);
        var data = RandomNumberGenerator.GetBytes(10_000);
        var r = await conn.RunAsync("exec:cmd package install -r -S 10000", new MemoryStream(data));
        Assert.Equal("Success\n", r);
        Assert.Equal(data, adbd.Inputs["exec:cmd package install -r -S 10000"]);
    }
}

public class AndroidInstallerTests
{
    [Fact]
    public void Parsing()
    {
        Assert.Equal("0.7.0", AndroidTvAppInstaller.ParseVersion("Packages:\n    versionCode=1 minSdk=24\n    versionName=0.7.0\n"));
        Assert.Null(AndroidTvAppInstaller.ParseVersion("Unable to find package: com.ninotranslator.tv"));
        Assert.False(AndroidTvAppInstaller.LooksLikeError(""));
        Assert.True(AndroidTvAppInstaller.LooksLikeError("Error: Unknown operation string: FOO"));
        Assert.True(AndroidTvAppInstaller.LooksLikeError("Security exception: uid 2000 does not have android.permission.MANAGE_APP_OPS_MODES"));
    }

    static async Task<(TvInstallResult, List<string>)> Run(Func<string, string> reply, string version, int apkBytes = 1000)
    {
        using var dir = new TempDir();
        using var key = AdbKey.LoadOrCreate(dir.Path);
        await using var adbd = new FakeAdbd { Trusted = key, Reply = reply };
        var apk = Path.Combine(dir.Path, "nino-androidtv_" + version + ".apk");
        File.WriteAllBytes(apk, new byte[apkBytes]);
        var r = await new AndroidTvAppInstaller { Port = adbd.Port }.InstallAsync("127.0.0.1", apk, version, dir.Path);
        return (r, adbd.Services);
    }

    [Fact]
    public async Task CurrentVersionLeftAlone()
    {
        var (r, s) = await Run(c => c.StartsWith("shell:dumpsys") ? "versionName=0.7.0\n" : c.StartsWith("shell:pidof") ? "1234\n" : "", "0.7.0");
        Assert.Equal(new TvInstallResult("0.7.0", false), r);
        Assert.Contains("shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow", s);
        Assert.DoesNotContain(AndroidTvAppInstaller.LaunchCommand, s);
    }

    [Fact]
    public async Task InstallsWhenMissing()
    {
        var (r, s) = await Run(c => c.StartsWith("exec:") ? "Success\n" : "", "0.9.11");
        Assert.Equal(new TvInstallResult("0.9.11", true), r);
        Assert.True(s.IndexOf("shell:appops set com.ninotranslator.tv SYSTEM_ALERT_WINDOW allow") < s.IndexOf(AndroidTvAppInstaller.LaunchCommand));
        Assert.DoesNotContain(s, x => x.StartsWith("shell:pm grant"));
        Assert.DoesNotContain(s, x => x.StartsWith("shell:pm uninstall"));
        Assert.Contains("exec:cmd package install -r -S 1000", s);
    }

    [Fact]
    public async Task AppopsErrorFallsBackToGrant()
    {
        var (r, s) = await Run(c => c.StartsWith("exec:") ? "Success\n" : c.StartsWith("shell:appops") ? "Error: Unknown operation string: FOO\n" : "", "0.9.11");
        Assert.True(r.Installed);
        Assert.Contains("shell:pm grant com.ninotranslator.tv android.permission.SYSTEM_ALERT_WINDOW", s);
    }

    [Fact]
    public async Task OlderInstalledIsRemovedFirstAndFailureReported()
    {
        var e = await Assert.ThrowsAsync<TvInstallException>(() =>
            Run(c => c.StartsWith("shell:dumpsys") ? "versionName=0.5.0\n" : c.StartsWith("exec:") ? "Failure [INSTALL_FAILED_INVALID_APK]\n" : "", "0.9.11"));
        Assert.Equal(TvInstallFailure.InstallFailed, e.Failure);
        Assert.Contains("INSTALL_FAILED_INVALID_APK", e.Detail);
    }
}
