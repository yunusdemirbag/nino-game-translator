// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Formats.Asn1;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Nino.TvInstall.Samsung;
using Nino.TvInstall.Tests.Common;

namespace Nino.TvInstall.Tests.Samsung;

public class DeviceInfoTests
{
    [Fact]
    public void Parses8001()
    {
        var a = SamsungDeviceInfo.Parse("{\"device\":{\"name\":\"[TV] Samsung Q60\",\"developerMode\":\"1\",\"developerIP\":\"192.168.1.50\",\"ip\":\"192.168.1.20\"},\"type\":\"Samsung SmartTV\"}");
        Assert.Equal(new SamsungDeviceInfo(true, "192.168.1.50"), a);
        Assert.Equal(new SamsungDeviceInfo(false, null), SamsungDeviceInfo.Parse("{\"device\":{\"developerMode\":\"0\",\"developerIP\":\"0.0.0.0\"}}"));
        Assert.Null(SamsungDeviceInfo.Parse("{\"device\":{\"developerIP\":\"\"}}").DeveloperIp);
        Assert.Null(SamsungDeviceInfo.Parse("{\"device\":{\"name\":\"TV\"}}").DeveloperMode);
        Assert.Equal(SamsungDeviceInfo.Unknown, SamsungDeviceInfo.Parse("<html>"));
        Assert.Null(SamsungDeviceInfo.Parse("{\"device\":[]}").DeveloperIp);
        Assert.True(SamsungDeviceInfo.Parse("{\"device\":{\"developerMode\":1}}").DeveloperMode);
    }

    [Fact]
    public void HostPcMismatch()
    {
        Assert.True(SamsungDeviceInfo.IsHostPcMismatch("192.168.1.50", "192.168.1.34"));
        Assert.False(SamsungDeviceInfo.IsHostPcMismatch("192.168.1.34", "192.168.1.34"));
        Assert.False(SamsungDeviceInfo.IsHostPcMismatch(null, "192.168.1.34"));
        Assert.False(SamsungDeviceInfo.IsHostPcMismatch("192.168.1.50", null));
    }
}

public class InstallOutputTests
{
    [Fact]
    public void AppListVersion()
    {
        const string list =
            "\t-------------app_title  =  Jellyfin-------------\n\t-------------app_tizen_id  =  AprZAARz4r.Jellyfin-------------\n" +
            "\t-------------app_version  =  1.2.3-------------\n\t---------------------------------------------\n" +
            "\t-------------app_title  =  Nino-------------\n\t-------------app_tizen_id  =  NinoTVApps.Nino-------------\n" +
            "\t-------------app_version  =  0.9.7-------------\n\t---------------------------------------------\n";
        Assert.Equal("0.9.7", SamsungInstallOutput.AppListVersion(list));
        Assert.Null(SamsungInstallOutput.AppListVersion(list.Replace("NinoTVApps.Nino", "Other.App")));
        Assert.Null(SamsungInstallOutput.AppListVersion("closed"));
        Assert.Null(SamsungInstallOutput.AppListVersion(""));
    }

    [Fact]
    public void Duid()
    {
        Assert.Equal("CJCHTFRXVXQDQ", SamsungInstallOutput.ParseDuid("CJCHTFRXVXQDQ\n"));
        Assert.Null(SamsungInstallOutput.ParseDuid(""));
        Assert.Null(SamsungInstallOutput.ParseDuid("error: closed"));
    }

    [Theory]
    [InlineData("Push complete.\napp_id[NinoTVApps.Nino] installing[100]\nspend time for pkgcmd is [1234]ms\ncmd_ret:0", SamsungInstallProblem.None)]
    [InlineData("app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Package with the same id and different certificate has been already installed.:<-12>\ncmd_ret:0", SamsungInstallProblem.OldCopyOtherCertificate)]
    [InlineData("app_id[NinoTVApps.Nino] install failed[118, -11], reason: Author certificate not match :", SamsungInstallProblem.OldCopyOtherCertificate)]
    [InlineData("install failed[118012]", SamsungInstallProblem.OldCopyOtherCertificate)]
    [InlineData("app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Invalid format of certificate in signature.:<-2>", SamsungInstallProblem.CertificateRejected)]
    [InlineData("install failed[118, -12] Check certificate error : :Certificate in signature is expired.:<-6>", SamsungInstallProblem.CertificateRejected)]
    [InlineData("install failed[118, -12] Check certificate error : :Certificate in signature is not valid yet.:<-7>", SamsungInstallProblem.TvClockBehind)]
    [InlineData("app_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error : :Invalid function parameter was given:<2>", SamsungInstallProblem.OldRegistration)]
    [InlineData("install failed[118022]", SamsungInstallProblem.OldRegistration)]
    [InlineData("app_id[NinoTVApps.Nino] download failed[116]", SamsungInstallProblem.NoSpace)]
    [InlineData("install failed[118, -4] operation not allowed", SamsungInstallProblem.NotEligible)]
    [InlineData("error: transport connection closed", SamsungInstallProblem.ConnectionLost)]
    [InlineData("install failed: IOException: Remote closed channel before sending OKAY", SamsungInstallProblem.Other)]
    [InlineData("app_id[NinoTVApps.Nino] install failed[118]", SamsungInstallProblem.Other)]
    [InlineData("Pull skipped or failed: not found\ninstalling[100]", SamsungInstallProblem.None)]
    [InlineData("", SamsungInstallProblem.None)]
    public void Classify(string output, SamsungInstallProblem expected) => Assert.Equal(expected, SamsungInstallOutput.Classify(output));

    [Fact]
    public void Summary()
    {
        var s = SamsungInstallOutput.Summary("Push complete.\napp_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error : :Invalid function parameter was given:<2>\ncmd_ret:0");
        Assert.Contains("install failed[118, -22]", s);
        Assert.Contains("Security error", s);
        Assert.DoesNotContain("Push complete", s);
        Assert.Equal("TV'den cevap gelmedi", SamsungInstallOutput.Summary(" "));
        Assert.Equal("a | b | c", SamsungInstallOutput.Summary("x\na\nb\nc"));
    }

    [Fact]
    public void TizenGates()
    {
        Assert.True(SamsungInstaller.IsTooOld("2.4"));
        Assert.True(SamsungInstaller.IsTooOld("2.3.1"));
        foreach (var v in new[] { "3.0", "4.0", "4.0.0", "5.0", "6.5", "9.0", "" }) Assert.False(SamsungInstaller.IsTooOld(v));
        foreach (var v in new[] { "3.0", "4.0", "4.0.0" }) Assert.True(SamsungInstaller.NeedsDeviceProfile(v));
        foreach (var v in new[] { "5.0", "6.5", "9.0", "", "2.4" }) Assert.False(SamsungInstaller.NeedsDeviceProfile(v));
    }
}

/// <summary>Kurtarma testleri için sahte sdb.</summary>
sealed class FakeSdb(params string[] installOutputs) : ISamsungSdb
{
    public int Installs;
    public readonly List<string> Commands = [];
    public Func<string, string> Shell = _ => "";
    public Exception? UninstallError;
    public Exception? ConnectError;
    public int Connects;

    public Task ConnectAsync(CancellationToken ct)
    {
        Connects++;
        return ConnectError is null ? Task.CompletedTask : Task.FromException(ConnectError);
    }

    public Task<IReadOnlyDictionary<string, string>> CapabilitiesAsync(CancellationToken ct) =>
        Task.FromResult<IReadOnlyDictionary<string, string>>(new Dictionary<string, string> { ["platform_version"] = "6.5" });

    public Task<string> ShellAsync(string command, CancellationToken ct)
    {
        Commands.Add(command);
        if (UninstallError is not null && command.Contains("vd_appuninstall")) return Task.FromException<string>(UninstallError);
        return Task.FromResult(Shell(command));
    }

    public Task PushAsync(string localPath, string remotePath, CancellationToken ct) => Task.CompletedTask;

    public Task<string> InstallAsync(string packagePath, string toolPath, CancellationToken ct) =>
        Task.FromResult(installOutputs[Math.Min(Installs++, installOutputs.Length - 1)]);

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

public class RecoveryTests
{
    const string OldCopy = "app_id[NinoTVApps.Nino] install failed[118, -12]\nreason: Check certificate error : :Package with the same id and different certificate has been already installed.:<-12>";
    const string Ok = "app_id[NinoTVApps.Nino] installing[100]\ncmd_ret:0";
    const string Mismatch = "app_id[NinoTVApps.Nino] install failed[118, -11], reason: Author certificate not match :";
    const string OldReg = "app_id[NinoTVApps.Nino] install failed[118, -22]\nreason: Security error";

    static Task Run(FakeSdb sdb, InstallLog? log = null) =>
        SamsungInstaller.InstallWithRecoveryAsync(sdb, "p.wgt", "/tmp", log ?? InstallLog.None, null, default);

    [Fact]
    public async Task OldCopyThenOk()
    {
        using var dir = new TempDir();
        var log = new InstallLog(Path.Combine(dir.Path, "l.log"));
        var sdb = new FakeSdb(OldCopy, Ok);
        await Run(sdb, log);
        Assert.Equal(2, sdb.Installs);
        Assert.Equal(["0 vd_appuninstall NinoTVApps", "0 vd_appuninstall NinoTVApps.Nino"], sdb.Commands);
        var logText = File.ReadAllText(log.Path!);
        Assert.Contains("same id and different certificate", logText);
        Assert.Contains("installing[100]", logText);
    }

    [Fact]
    public async Task OkOnce()
    {
        var sdb = new FakeSdb(Ok);
        await Run(sdb);
        Assert.Equal(1, sdb.Installs);
        Assert.Empty(sdb.Commands);
    }

    [Fact]
    public async Task MismatchTwice()
    {
        var sdb = new FakeSdb(Mismatch, Mismatch);
        var e = await Assert.ThrowsAsync<TvInstallException>(() => Run(sdb));
        Assert.Equal(TvInstallFailure.CertificateMismatch, e.Failure);
        Assert.Contains("Author certificate not match", e.Detail);
        Assert.Equal(2, sdb.Installs);
    }

    [Fact]
    public async Task OldRegistrationTwice()
    {
        var sdb = new FakeSdb(OldReg, OldReg);
        var e = await Assert.ThrowsAsync<TvInstallException>(() => Run(sdb));
        Assert.Equal(TvInstallFailure.PackageBlocked, e.Failure);
        Assert.Contains("118, -22", e.Detail);
        Assert.Equal(2, sdb.Commands.Count);
    }

    [Theory]
    [InlineData("install failed[118, -12] Check certificate error : :Certificate in signature is expired.:<-6>", TvInstallFailure.CertificateRejected)]
    [InlineData("install failed[118, -12] Check certificate error : :Certificate in signature is not valid yet.:<-7>", TvInstallFailure.TvClockWrong)]
    [InlineData("app_id[NinoTVApps.Nino] download failed[116]", TvInstallFailure.NotEnoughSpace)]
    [InlineData("connection reset by peer", TvInstallFailure.ConnectionLost)]
    public async Task NoUninstallForOthers(string output, TvInstallFailure expected)
    {
        var sdb = new FakeSdb(output);
        var e = await Assert.ThrowsAsync<TvInstallException>(() => Run(sdb));
        Assert.Equal(expected, e.Failure);
        Assert.Empty(sdb.Commands);
        Assert.Equal(1, sdb.Installs);
    }

    [Fact]
    public async Task UninstallErrorStillReinstalls()
    {
        using var dir = new TempDir();
        var log = new InstallLog(Path.Combine(dir.Path, "l.log"));
        var sdb = new FakeSdb(OldCopy, Ok) { UninstallError = new IOException("uninstall pipe broke") };
        await Run(sdb, log);
        Assert.Equal(2, sdb.Installs);
        var written = File.ReadAllText(log.Path!);
        Assert.Contains("uninstall pipe broke", written);
    }

    [Fact]
    public async Task ConnectRetriesThenUnreachable()
    {
        var fake = new FakeSdb(Ok) { ConnectError = new SocketException((int)SocketError.ConnectionRefused) };
        var installer = new SamsungInstaller(new HttpClient())
        {
            Connect = _ => fake,
            ConnectDelays = [TimeSpan.Zero, TimeSpan.FromMilliseconds(1), TimeSpan.FromMilliseconds(1)],
            DeviceInfo = (_, _) => Task.FromResult(new SamsungDeviceInfo(true, "192.168.1.50")),
        };
        var e = await Assert.ThrowsAsync<TvInstallException>(() => installer.InstallAsync(new SamsungInstallRequest
        {
            Host = "127.0.0.1", ProfilesRoot = "/nonexistent", PackagePath = "x.wgt", PackageVersion = "1.0",
        }));
        Assert.Equal(TvInstallFailure.Unreachable, e.Failure);
        Assert.Equal(3, fake.Connects);
        Assert.StartsWith("sdb 127.0.0.1:26101: ", e.Detail);
        Assert.Contains("TV'deki Host PC IP 192.168.1.50", e.Detail);
        var bad = await Assert.ThrowsAsync<TvInstallException>(() => installer.InstallAsync(new SamsungInstallRequest
        {
            Host = "tv.local", ProfilesRoot = "/x", PackagePath = "x.wgt",
        }));
        Assert.Equal("geçersiz TV adresi: tv.local", bad.Detail);
    }

    [Fact]
    public async Task SkipsWhenTvVersionIsCurrent()
    {
        var fake = new FakeSdb(Ok) { Shell = c => c == "0 vd_applist" ? "app_tizen_id = NinoTVApps.Nino\napp_version = 0.9.7\n" : "" };
        var installer = new SamsungInstaller(new HttpClient())
        {
            Connect = _ => fake,
            DeviceInfo = (_, _) => Task.FromResult(SamsungDeviceInfo.Unknown),
        };
        var r = await installer.InstallAsync(new SamsungInstallRequest
        {
            Host = "127.0.0.1", ProfilesRoot = "/x", PackagePath = "x.wgt", PackageVersion = "0.9.7",
        });
        Assert.Equal(new TvInstallResult("0.9.7", false), r);
        Assert.Equal(0, fake.Installs);
    }

    [Fact]
    public async Task NoSignInMeansLoginFailed()
    {
        using var dir = new TempDir();
        var fake = new FakeSdb(Ok) { Shell = c => c == "0 getduid" ? "ABCDEFGH1234\n" : "" };
        var installer = new SamsungInstaller(new HttpClient())
        {
            Connect = _ => fake,
            DeviceInfo = (_, _) => Task.FromResult(SamsungDeviceInfo.Unknown),
        };
        var e = await Assert.ThrowsAsync<TvInstallException>(() => installer.InstallAsync(new SamsungInstallRequest
        {
            Host = "127.0.0.1", ProfilesRoot = dir.Path, PackagePath = "x.wgt", PackageVersion = "1.0",
        }));
        Assert.Equal(TvInstallFailure.LoginFailed, e.Failure);
        Assert.Equal("giriş gerekiyor", e.Detail);
    }
}

public class CertificateFolderTests
{
    static byte[] MakeP12(DateTimeOffset start, DateTimeOffset end, string password, string issuer = "CN=Test")
    {
        using var key = RSA.Create(2048);
        var req = new CertificateRequest(issuer, key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var cert = req.CreateSelfSigned(start, end);
        using var pub = X509CertificateLoader.LoadCertificate(cert.RawData);
        return SamsungCertificates.BuildPkcs12(pub, key, password);
    }

    static SamsungCertificateFolder Make(string root, string duid, DateTimeOffset start, DateTimeOffset end, string? duidFile)
    {
        var f = SamsungCertificateFolder.ForDuid(root, duid);
        Directory.CreateDirectory(f.Path);
        var p12 = MakeP12(start, end, "pw");
        File.WriteAllBytes(f.AuthorPath, p12);
        File.WriteAllBytes(f.DistributorPath, p12);
        File.WriteAllText(Path.Combine(f.Path, "password.txt"), " pw \n");
        if (duidFile is not null) File.WriteAllText(Path.Combine(f.Path, "duid.txt"), duidFile);
        return f;
    }

    [Fact]
    public void ValidityAndOwnership()
    {
        using var dir = new TempDir();
        var now = DateTimeOffset.UtcNow;
        var f = Make(dir.Path, "AAAAAAAAAAAAA", now.AddMinutes(10), now.AddYears(1), "AAAAAAAAAAAAA");
        Assert.True(f.Exists);
        Assert.True(f.IsValid(now));
        Assert.False(f.IsValid(now.AddYears(2)));
        Assert.True(f.BelongsTo("AAAAAAAAAAAAA"));
        Assert.False(f.BelongsTo("BBBBBBBBBBBBB"));
        Assert.Contains("farklı bir TV'ye ait", f.Describe("BBBBBBBBBBBBB", now));
        Assert.StartsWith("geçerli", f.Describe("AAAAAAAAAAAAA", now));
        Assert.Contains("dağıtıcıyı veren Test", f.Describe("AAAAAAAAAAAAA", now));
    }

    [Fact]
    public void SetAsideMovesFolder()
    {
        using var dir = new TempDir();
        var now = DateTimeOffset.UtcNow;
        var f = Make(dir.Path, "DUID1234", now.AddDays(-1), now.AddYears(1), null);
        Assert.True(f.BelongsTo("ANY"));
        f.SetAside(now);
        Assert.False(Directory.Exists(f.Path));
        Assert.False(new SamsungCertificateFolder(f.Path).Exists);
        Assert.Single(Directory.GetDirectories(dir.Path, "DUID1234.rejected-*"));
    }

    [Fact]
    public void EmptyFolder()
    {
        using var dir = new TempDir();
        var f = new SamsungCertificateFolder(dir.Path);
        Assert.False(f.Exists);
        Assert.False(f.IsValid(DateTimeOffset.UtcNow));
        Assert.Equal("yok", f.Describe("X", DateTimeOffset.UtcNow));
        Assert.Equal("ab_c-d_", SamsungCertificateFolder.SafeName("ab/c-d."));
    }
}

public class CertificateRequestTests
{
    [Fact]
    public void DistributorSubjectAltName()
    {
        using var key = RSA.Create(2048);
        var pem = SamsungCertificates.DistributorRequest(key, "ABCDEF0123456789", "a@b.c");
        var loadOptions = CertificateRequestLoadOptions.UnsafeLoadCertificateExtensions;
        var req = CertificateRequest.LoadSigningRequestPem(pem, HashAlgorithmName.SHA256, loadOptions);
        Assert.Contains("CN=TizenSDK", req.SubjectName.Name);
        var san = req.CertificateExtensions.Single(e => e.Oid?.Value == "2.5.29.17");
        Assert.False(san.Critical);
        var seq = new AsnReader(san.RawData, AsnEncodingRules.DER).ReadSequence();
        var tag = new Asn1Tag(TagClass.ContextSpecific, 6);
        Assert.Equal("URN:tizen:packageid=", seq.ReadCharacterString(UniversalTagNumber.IA5String, tag));
        Assert.Equal("URN:tizen:deviceid=ABCDEF0123456789", seq.ReadCharacterString(UniversalTagNumber.IA5String, tag));
        Assert.False(seq.HasData);
        var author = CertificateRequest.LoadSigningRequestPem(SamsungCertificates.AuthorRequest(key), HashAlgorithmName.SHA256);
        Assert.Equal("CN=Nino", author.SubjectName.Name);
    }

    [Fact]
    public void ServerErrors()
    {
        const string expected = "code=AUTH_FAIL, message=Invalid access token";
        Assert.Equal(expected, SamsungCertificates.ServerError("{\"code\":\"AUTH_FAIL\",\"message\":\"Invalid access token\"}"));
        Assert.Equal("Service Unavailable", SamsungCertificates.ServerError(" Service Unavailable "));
        var e = Assert.Throws<TvInstallException>(() =>
            SamsungCertificates.ReadIssued(Encoding.UTF8.GetBytes("{\"message\":\"certificate service paused\"}"), "yazar"));
        Assert.Equal(TvInstallFailure.CertificateFailed, e.Failure);
        Assert.Contains("certificate service paused", e.Detail);
    }

    [Fact]
    public void EmbeddedCas()
    {
        var subjects = SamsungCertificates.EmbeddedCas().Select(c => c.GetNameInfo(X509NameType.SimpleName, false)).ToList();
        Assert.Equal(4, subjects.Count);
        Assert.Contains("Samsung VD Author CA", subjects);
        Assert.Contains("VD DEVELOPER Public CA Class", subjects);
    }
}

public class LoginTests
{
    const string Body = "code=%7B%22access_token%22%3A%22tok%22%2C%22userId%22%3A%22u1%22%2C%22inputEmailID%22%3A%22a%40b.c%22%2C%22token_type%22%3A%22bearer%22%7D&state=accountcheckdogeneratedstatetext";

    [Fact]
    public void ParsesCallback()
    {
        Assert.Equal(new SamsungAccount("tok", "u1", "a@b.c"), SamsungLogin.ParseCallback(Body));
        Assert.Null(SamsungLogin.ParseCallback(Body.Replace("accountcheckdogeneratedstatetext", "baska")));
        Assert.Null(SamsungLogin.ParseCallback("code=bozuk&state=accountcheckdogeneratedstatetext"));
        var reason = SamsungLogin.FailureReason("code=%7B%22access_token%22%3A%22gizli%22%7D&state=accountcheckdogeneratedstatetext&error=access_denied");
        Assert.Contains("error=access_denied", reason);
        Assert.Contains("code", reason);
        Assert.DoesNotContain("gizli", reason);
        Assert.Contains("redirect_uri=http%3A%2F%2Flocalhost%3A4794%2Fsignin%2Fcallback", SamsungLogin.SignInUrl());
    }

    static int FreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        var p = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return p;
    }

    static async Task<string> RequestAsync(int port, string raw)
    {
        using var c = new TcpClient();
        await c.ConnectAsync(IPAddress.Loopback, port);
        var s = c.GetStream();
        await s.WriteAsync(Encoding.UTF8.GetBytes(raw));
        using var r = new StreamReader(s);
        return await r.ReadToEndAsync();
    }

    [Fact]
    public async Task LiveListener()
    {
        var port = FreePort();
        var login = new SamsungLogin { Port = port, Timeout = TimeSpan.FromSeconds(20) };
        var opened = new TaskCompletionSource<string>();
        var run = login.RunAsync(u => opened.TrySetResult(u));
        Assert.Contains("signInGate", await opened.Task);
        Assert.StartsWith("HTTP/1.1 404", await RequestAsync(port, "GET /favicon.ico HTTP/1.1\r\nHost: x\r\n\r\n"));
        Assert.StartsWith("HTTP/1.1 400", await RequestAsync(port, "POST /signin/callback HTTP/1.1\r\nContent-Length: 6\r\n\r\nerror=x"));
        var ok = await RequestAsync(port, $"POST /signin/callback HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: {Body.Length}\r\n\r\n{Body}");
        Assert.StartsWith("HTTP/1.1 200", ok);
        Assert.Contains("Signed in", ok);
        Assert.Equal("u1", (await run).UserId);
    }

    [Fact]
    public async Task TimeoutMentionsReason()
    {
        var port = FreePort();
        var login = new SamsungLogin { Port = port, Timeout = TimeSpan.FromSeconds(2) };
        var opened = new TaskCompletionSource();
        var run = login.RunAsync(_ => opened.TrySetResult());
        await opened.Task;
        await RequestAsync(port, "POST /signin/callback HTTP/1.1\r\nContent-Length: 18\r\n\r\nerror=access_denied");
        var e = await Assert.ThrowsAsync<TvInstallException>(() => run);
        Assert.Equal(TvInstallFailure.LoginFailed, e.Failure);
        Assert.Contains("dakika içinde tamamlanmadı", e.Detail);
        Assert.Contains("error=access_denie", e.Detail);
    }
}
