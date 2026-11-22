// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Security.Cryptography;
using Nino.Core.Tv;

namespace Nino.Core.Tests.Tv;

/// <summary>Betikli sahte LG kabuğu.</summary>
sealed class FakeShell : ILgShell
{
    public readonly List<(string Command, string? Input)> Calls = [];
    public readonly Queue<string> Versions = new();
    public Func<string, ShellResult?>? Script;
    public TvException? Fail;

    public Task<ShellResult> RunAsync(string command, string? inputFile = null, TimeSpan? timeout = null, CancellationToken ct = default)
    {
        if (Fail is not null) throw Fail;
        Calls.Add((command, inputFile));
        if (Script?.Invoke(command) is { } scripted) return Task.FromResult(scripted);
        if (command.StartsWith("cat /media/developer/apps/", StringComparison.Ordinal))
        {
            var v = Versions.Count > 1 ? Versions.Dequeue() : Versions.Count == 1 ? Versions.Peek() : null;
            return Task.FromResult(v is null
                ? new ShellResult(1, "cat: No such file or directory")
                : new ShellResult(0, $"{{\"id\":\"com.ninotranslator.tv\",\"version\" : \"{v}\"}}"));
        }
        if (command.StartsWith("wc -c", StringComparison.Ordinal)) return Task.FromResult(new ShellResult(0, "10\n"));
        return Task.FromResult(new ShellResult(0, ""));
    }
}

public sealed class LgInstallTests : IDisposable
{
    readonly string package;

    public LgInstallTests()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-lg-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        package = Path.Combine(dir, "com.ninotranslator.tv_0.6.1_all.ipk");
        File.WriteAllBytes(package, new byte[10]);
    }

    public void Dispose() => Directory.Delete(Path.GetDirectoryName(package)!, true);

    static LgInstaller Fast(ILgShell shell) => new(shell)
    {
        InstallWait = TimeSpan.FromMilliseconds(200), VerifyAfterInstalled = TimeSpan.FromMilliseconds(200),
        VerifyAfterUnknown = TimeSpan.FromMilliseconds(200), VerifyEvery = TimeSpan.FromMilliseconds(1),
    };

    const string Remote = "/media/developer/temp/com.ninotranslator.tv_0.6.1_all.ipk";

    [Fact]
    public async Task InstallsAndVerifies()
    {
        var shell = new FakeShell();
        foreach (var v in new[] { "0.4.0", "0.4.0", "0.6.1" }) shell.Versions.Enqueue(v);
        await Fast(shell).InstallAsync(package, "0.6.1");
        var (upload, uploadInput) = shell.Calls[0];
        Assert.Contains($"cat > '{Remote}'", upload);
        Assert.Contains("rm -f /media/developer/temp/com.ninotranslator.tv_*.ipk", upload);
        Assert.Equal(package, uploadInput);
        Assert.Equal($"wc -c < '{Remote}'", shell.Calls[1].Command);
        var install = shell.Calls[2].Command;
        Assert.Contains("luna://com.webos.appInstallService/dev/install", install);
        Assert.Contains($"\"ipkUrl\":\"{Remote}\"", install);
        Assert.Equal($"rm -f '{Remote}'", shell.Calls[^1].Command);
        Assert.All(shell.Calls.Skip(1), c => Assert.Null(c.Input));
    }

    [Fact]
    public async Task FailedReplyStopsAndRemovesPackage()
    {
        var shell = new FakeShell
        {
            Script = c => c.Contains("luna-send-pub")
                ? new ShellResult(0, "{\"returnValue\":true}\n{\"details\":{\"state\":\"FAILED_IPK_INSTALL\",\"reason\":\"Invalid package\"},\"returnValue\":true}\n")
                : null,
        };
        var e = await Assert.ThrowsAsync<TvException>(() => Fast(shell).InstallAsync(package, "0.6.1"));
        Assert.Equal(TvError.InstallFailed, e.Error);
        Assert.Equal("Invalid package", e.Detail);
        Assert.Equal($"rm -f '{Remote}'", shell.Calls[^1].Command);
        Assert.DoesNotContain(shell.Calls, c => c.Command.StartsWith("cat /media/developer/apps/", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SpaceProblemsAreRecognised()
    {
        var shell = new FakeShell
        {
            Script = c => c.Contains("luna-send-pub")
                ? new ShellResult(0, "{\"details\":{\"state\":\"install failed\",\"reason\":\"Not enough space\"},\"returnValue\":true}")
                : null,
        };
        Assert.Equal(TvError.NotEnoughSpace, (await Assert.ThrowsAsync<TvException>(() => Fast(shell).InstallAsync(package, "0.6.1"))).Error);

        var upload = new FakeShell { Script = c => c.Contains("cat >") ? new ShellResult(1, "cat: write error: No space left on device") : null };
        var e = await Assert.ThrowsAsync<TvException>(() => Fast(upload).InstallAsync(package, "0.6.1"));
        Assert.Equal(TvError.NotEnoughSpace, e.Error);
        Assert.StartsWith("yükleme çıkış kodu 1: ", e.Detail);

        var disk = new FakeShell { Script = c => c.Contains("cat >") ? new ShellResult(1, "disk full") : null };
        await Assert.ThrowsAsync<TvException>(() => Fast(disk).InstallAsync(package, "0.6.1"));
        Assert.DoesNotContain(disk.Calls, c => c.Command.Contains("luna-send-pub"));
    }

    [Fact]
    public async Task InstalledReplyAndVersionSucceeds()
    {
        var shell = new FakeShell
        {
            Script = c => c.Contains("luna-send-pub") ? new ShellResult(0, "{\"details\":{\"state\":\"installed\"},\"returnValue\":true}") : null,
        };
        shell.Versions.Enqueue("0.6.1");
        await Fast(shell).InstallAsync(package, "0.6.1");
        Assert.Equal($"rm -f '{Remote}'", shell.Calls[^1].Command);
    }

    [Fact]
    public async Task VersionNeverAppears()
    {
        var shell = new FakeShell();
        shell.Versions.Enqueue("0.4.0");
        var e = await Assert.ThrowsAsync<TvException>(() => Fast(shell).InstallAsync(package, "0.6.1"));
        Assert.Equal(TvError.InstallFailed, e.Error);
        Assert.StartsWith("kurulumdan sonra TV 0.6.1 sürümünü göstermiyor; kurucunun çıkışı (0): ", e.Detail);
        Assert.DoesNotContain(shell.Calls.Skip(1), c => c.Command.StartsWith("rm -f '", StringComparison.Ordinal));
    }

    [Fact]
    public async Task WrongSizeStopsBeforeInstall()
    {
        var shell = new FakeShell { Script = c => c.StartsWith("wc -c", StringComparison.Ordinal) ? new ShellResult(0, "7") : null };
        var e = await Assert.ThrowsAsync<TvException>(() => Fast(shell).InstallAsync(package, "0.6.1"));
        Assert.Contains("7/10", e.Detail);
        Assert.DoesNotContain(shell.Calls, c => c.Command.Contains("luna-send-pub"));
    }

    [Fact]
    public async Task ShellErrorsPassThrough()
    {
        var shell = new FakeShell { Fail = new TvException(TvError.KeyRejected) };
        Assert.Equal(TvError.KeyRejected, (await Assert.ThrowsAsync<TvException>(() => new LgInstaller(shell).InstalledVersionAsync())).Error);
    }

    [Fact]
    public async Task VersionReading()
    {
        var shell = new FakeShell();
        Assert.Null(await new LgInstaller(shell).InstalledVersionAsync());
        shell.Versions.Enqueue("0.9.2");
        Assert.Equal("0.9.2", await new LgInstaller(shell).InstalledVersionAsync());
    }

    [Fact]
    public void InstallCommandShape()
    {
        var c = LgInstaller.InstallCommand(Remote, 180);
        Assert.Contains("while [ $i -lt 180 ]", c);
        Assert.Contains("sleep 210 </dev/null 2>/dev/null |", c);
        Assert.Contains("kill $L", c);
        Assert.DoesNotContain("-n 1", c);
        Assert.StartsWith("rm -f /media/developer/temp/nino-install.log; ", c);
    }

    [Fact]
    public void InstallReplies()
    {
        var unknown = "{\"returnValue\":true,\"subscribed\":true}\n{\"details\":{\"state\":\"installing\"},\"returnValue\":true}\n";
        Assert.Equal(LgInstallOutcome.Unknown, LgInstaller.ParseInstallReply(unknown).Outcome);
        Assert.Equal(LgInstallOutcome.Installed,
            LgInstaller.ParseInstallReply(unknown + "{\"details\":{\"state\":\"installed\"},\"returnValue\":true}").Outcome);
        Assert.Equal(LgInstallOutcome.Installed, LgInstaller.ParseInstallReply("{\"details\":{\"state\":\"SUCCESS\"}}").Outcome);
        Assert.Equal((LgInstallOutcome.Failed, "Installation failure (errorCode -5)"), LgInstaller.ParseInstallReply(
            unknown + "{\"details\":{\"state\":\"install failed\",\"reason\":\"Installation failure\",\"errorCode\":-5},\"returnValue\":true}"));
        Assert.Equal((LgInstallOutcome.Failed, "Denied method call (errorCode -1)"),
            LgInstaller.ParseInstallReply("{\"returnValue\":false,\"errorCode\":-1,\"errorText\":\"Denied method call\"}"));
        Assert.Equal(LgInstallOutcome.Installed,
            LgInstaller.ParseInstallReply("Error: busy\n{\"details\":\n{\"state\":\"installed\"}}\n").Outcome);
    }

    [Theory]
    [InlineData("No space left on device", true)]
    [InlineData("not enough free storage", true)]
    [InlineData("Insufficient space", true)]
    [InlineData("storage is full", true)]
    [InlineData("ENOSPC", true)]
    [InlineData("lack of storage", true)]
    [InlineData("Invalid package", false)]
    public void SpacePattern(string text, bool expected) => Assert.Equal(expected, LgInstaller.IsSpaceProblem(text));

    [Fact]
    public void ShortOutput()
    {
        Assert.Equal("abc", LgInstaller.Short("  abc \n"));
        var s = LgInstaller.Short(new string('x', 600));
        Assert.Equal(501, s.Length);
        Assert.EndsWith("…", s);
    }

    [Fact]
    public void DevSession()
    {
        Assert.Equal(999, LgDevSession.ParseRemainingHours("{\"result\":\"success\",\"errorCode\":\"200\",\"errorMsg\":\"999:58:40\"}"));
        Assert.Null(LgDevSession.ParseRemainingHours("{\"result\":\"fail\"}"));
        Assert.Equal("https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=ab12", LgDevSession.ResetUrl("ab12"));
        var now = DateTimeOffset.UnixEpoch.AddDays(100);
        Assert.True(LgDevSession.IsDue(null, now));
        Assert.False(LgDevSession.IsDue(now.AddHours(-19), now));
        Assert.True(LgDevSession.IsDue(now.AddHours(-21), now));
    }

    [Fact]
    public async Task SshShellErrors()
    {
        var closed = new SshLgShell("127.0.0.1", "irrelevant", port: 1);
        var key = await RsaPemAsync();
        Assert.Equal(TvError.Unreachable, (await Assert.ThrowsAsync<TvException>(() =>
            new SshLgShell("127.0.0.1", key, port: 1).RunAsync("echo"))).Error);
        Assert.Equal(TvError.KeyRejected, (await Assert.ThrowsAsync<TvException>(() => closed.RunAsync("echo"))).Error);
    }

    static Task<string> RsaPemAsync()
    {
        using var rsa = RSA.Create(2048);
        return Task.FromResult(rsa.ExportRSAPrivateKeyPem());
    }
}

public class LegacyPemTests
{
    static string? Openssl(params string[] args)
    {
        foreach (var tool in OpensslTool.Found)
        {
            var psi = new ProcessStartInfo(tool) { RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var a in args) psi.ArgumentList.Add(a);
            using var p = Process.Start(psi)!;
            var output = p.StandardOutput.ReadToEnd();
            p.StandardError.ReadToEnd();
            p.WaitForExit();
            if (p.ExitCode == 0) return output;
        }
        return null;
    }

    /// <summary>Eski PEM biçimli şifreli anahtar (OpenSSL 3'te -traditional gerekir).</summary>
    static string? Encrypted(string cipher)
    {
        var pem = Openssl("genrsa", "-traditional", cipher, "-passout", "pass:2FEEB2", "1024")
            ?? Openssl("genrsa", cipher, "-passout", "pass:2FEEB2", "1024");
        return pem is not null && LegacyPem.IsEncrypted(pem) ? pem : null;
    }

    [OpensslTheory]
    [InlineData("-aes128")]
    [InlineData("-des3")]
    public void DecryptsWithTheTvPassphrase(string cipher)
    {
        var pem = Encrypted(cipher);
        Assert.NotNull(pem);
        var plain = LegacyPem.Decrypt(pem, "2FEEB2");
        Assert.StartsWith("-----BEGIN RSA PRIVATE KEY-----\n", plain, StringComparison.Ordinal);
        Assert.EndsWith("-----END RSA PRIVATE KEY-----\n", plain, StringComparison.Ordinal);
        Assert.DoesNotContain("ENCRYPTED", plain, StringComparison.Ordinal);
        using var rsa = RSA.Create();
        rsa.ImportFromPem(plain);
        Assert.Equal(1024, rsa.KeySize);

        var path = Path.Combine(Path.GetTempPath(), "nino-pem-" + Guid.NewGuid().ToString("N"));
        File.WriteAllText(path, pem);
        try
        {
            var der = Openssl("rsa", "-in", path, "-passin", "pass:2FEEB2", "-traditional", "-outform", "PEM")
                ?? Openssl("rsa", "-in", path, "-passin", "pass:2FEEB2", "-outform", "PEM");
            if (der is not null && der.Contains("BEGIN RSA PRIVATE KEY"))
                Assert.Equal(Body(der), Body(plain));
        }
        finally
        {
            File.Delete(path);
        }

        Assert.Equal(TvError.WrongPassphrase, Assert.Throws<TvException>(() => LegacyPem.Decrypt(pem, "2FEEB3")).Error);
    }

    static byte[] Body(string pem) =>
        Convert.FromBase64String(string.Concat(pem.Split('\n').Where(l => l.Length > 0 && !l.StartsWith("-----", StringComparison.Ordinal))));

    [OpensslFact]
    public async Task UppercasePassphraseIsTried()
    {
        var pem = Encrypted("-aes128");
        Assert.NotNull(pem);
        Assert.StartsWith("-----BEGIN RSA PRIVATE KEY-----", await LgDevMode.UnlockAsync(pem.Replace("2FEEB2", "2FEEB2"), " 2feeb2 "));
    }

    [Fact]
    public void FormatChecks()
    {
        Assert.False(LegacyPem.IsEncrypted("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n"));
        Assert.Equal("PEM başlığı okunamadı", Assert.Throws<TvException>(() => LegacyPem.Decrypt("Proc-Type: 4,ENCRYPTED", "x")).Detail);
        var noEnd = "-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,00112233445566778899AABBCCDDEEFF\n\nAAAA\n";
        Assert.Equal("PEM sonu bulunamadı", Assert.Throws<TvException>(() => LegacyPem.Decrypt(noEnd, "x")).Detail);
        var odd = noEnd.Replace("AES-128-CBC", "BF-CBC") + "-----END RSA PRIVATE KEY-----\n";
        Assert.Equal("Desteklenmeyen şifre: BF-CBC", Assert.Throws<TvException>(() => LegacyPem.Decrypt(odd, "x")).Detail);
    }

    [Fact]
    public void DerShape()
    {
        Assert.True(LegacyPem.LooksLikeDer([0x30, 0x02, 0x01, 0x00]));
        Assert.False(LegacyPem.LooksLikeDer([0x30, 0x03, 0x01, 0x00]));
        Assert.False(LegacyPem.LooksLikeDer([0x31, 0x02, 0x01, 0x00]));
        var longForm = new byte[4 + 300];
        longForm[0] = 0x30; longForm[1] = 0x82; longForm[2] = 0x01; longForm[3] = 0x2C;
        Assert.True(LegacyPem.LooksLikeDer(longForm));
    }
}
