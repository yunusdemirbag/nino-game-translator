// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using Nino.TvInstall;

namespace Nino.TvInstall.Tests.Common;

public sealed class TempDir : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "nino-test-" + Guid.NewGuid().ToString("N"));
    public TempDir() => Directory.CreateDirectory(Path);
    public void Dispose()
    {
        try { Directory.Delete(Path, true); } catch (IOException) { }
    }
}

public class VersionTests
{
    [Theory]
    [InlineData("0.10.0", "0.9.9", true)]
    [InlineData("0.6.1", "0.6.1", false)]
    [InlineData("0.6.0", "0.6.1", false)]
    [InlineData("abc", "0.6.1", false)]
    [InlineData("0.7.0", null, false)]
    [InlineData("1", "0.1", false)]
    public void Strict(string? a, string? b, bool expected) => Assert.Equal(expected, TvVersions.IsNewerStrict(a, b));

    [Theory]
    [InlineData("0.10.0", "0.9.9", true)]
    [InlineData("0.7.0", "0.7.0", false)]
    [InlineData("0.7", "0.7.0", false)]
    [InlineData("5.0", "4.0", true)]
    [InlineData("5.0", "6.5", false)]
    public void Loose(string a, string b, bool expected) => Assert.Equal(expected, TvVersions.IsNewerLoose(a, b));
}

public class PackageTests
{
    [Fact]
    public void VersionsFromNames()
    {
        Assert.Equal("0.6.1", TvAppPackages.LgVersion("com.ninotranslator.tv_0.6.1_all.ipk"));
        Assert.Null(TvAppPackages.LgVersion("notes.txt"));
        Assert.Equal("0.7.0", TvAppPackages.SuffixVersion("nino-androidtv_0.7.0.apk"));
        Assert.Equal("0.7.0", TvAppPackages.SuffixVersion("nino-samsung_0.7.0.wgt"));
        Assert.Null(TvAppPackages.SuffixVersion("nino.apk"));
        Assert.Null(TvAppPackages.SuffixVersion("_0.7.apk"));
        Assert.Null(TvAppPackages.SuffixVersion("nino_.apk"));
    }

    [Fact]
    public void FindsFirstPackageAndSkipsUnreadable()
    {
        using var dir = new TempDir();
        File.WriteAllText(Path.Combine(dir.Path, "nino.apk"), "x");
        Assert.Null(TvAppPackages.FindAndroid(dir.Path));
        File.WriteAllText(Path.Combine(dir.Path, "nino-samsung_0.7.0.wgt"), "x");
        File.WriteAllText(Path.Combine(dir.Path, "com.ninotranslator.tv_0.6.1_all.ipk"), "x");
        Assert.Equal("0.7.0", TvAppPackages.FindSamsung(dir.Path)!.Version);
        Assert.Equal("0.6.1", TvAppPackages.FindLg(dir.Path)!.Version);
        Assert.Null(TvAppPackages.FindAndroid(Path.Combine(dir.Path, "yok")));
    }
}

public class InstallLogTests
{
    [Fact]
    public void DropsOldHalfOverOneMegabyte()
    {
        using var dir = new TempDir();
        var path = Path.Combine(dir.Path, "sub", "tvinstall.log");
        var log = new InstallLog(path);
        log.Write("ilk satır   ");
        Assert.Matches(@"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] ilk satır\n$", File.ReadAllText(path));
        File.AppendAllText(path, new string('x', 1_048_576 + 10) + "\n");
        log.Write("son satır");
        var content = File.ReadAllText(path);
        Assert.Contains("son satır", content);
        Assert.DoesNotContain("ilk satır", content);
        Assert.True(new FileInfo(path).Length < 1_048_576 + 1000);
    }

    [Fact]
    public void NoPathWritesNothing() => InstallLog.None.Write("x");
}

public class LanScanTests
{
    [Fact]
    public void PrivateAddresses()
    {
        foreach (var ip in new[] { "192.168.0.10", "172.20.1.1", "10.1.2.3" }) Assert.True(LanScan.IsPrivate(IPAddress.Parse(ip)));
        foreach (var ip in new[] { "8.8.8.8", "172.32.0.1" }) Assert.False(LanScan.IsPrivate(IPAddress.Parse(ip)));
    }

    [Fact]
    public void Targets()
    {
        var t = LanScan.Targets([IPAddress.Parse("192.168.1.40")]);
        Assert.Equal(253, t.Count);
        Assert.Contains(IPAddress.Parse("192.168.1.1"), t);
        Assert.Contains(IPAddress.Parse("192.168.1.254"), t);
        Assert.DoesNotContain(IPAddress.Parse("192.168.1.40"), t);
        var two = LanScan.Targets([IPAddress.Parse("10.0.0.5"), IPAddress.Parse("10.0.0.6")]);
        Assert.Equal(two.Count, two.Distinct().Count());
        Assert.Equal(252, two.Count);
        var android = LanScan.Targets([IPAddress.Parse("192.168.1.20")]);
        Assert.Equal(253, android.Count);
        Assert.DoesNotContain(IPAddress.Parse("192.168.1.20"), android);
    }

    [Fact]
    public async Task OpenHostsOnLoopback()
    {
        var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        try
        {
            var port = ((IPEndPoint)listener.LocalEndpoint).Port;
            var found = await LanScan.OpenHostsAsync([IPAddress.Loopback], port, TimeSpan.FromSeconds(1));
            Assert.Equal([IPAddress.Loopback], found);
            Assert.Equal(IPAddress.Loopback, LanScan.SourceAddressTowards(IPAddress.Loopback, 8001));
        }
        finally { listener.Stop(); }
    }
}
