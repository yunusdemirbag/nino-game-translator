// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Data;

namespace Nino.Core.Tests.Data;

public class SmallDataTests : IDisposable
{
    readonly TempFolder _tmp = new();

    public void Dispose() => _tmp.Dispose();

    [Theory]
    [InlineData("0.1.0", "0.1.0-beta.9", 1)]
    [InlineData("0.1.0-beta.10", "0.1.0-beta.9", 1)]
    [InlineData("v4.0.1", "4.0.0", 1)]
    [InlineData("1.0.0-rc", "1.0.0-beta", 1)]
    [InlineData("1.0.0-beta.2", "1.0.0-beta", 1)]
    [InlineData("1.0", "1.0.0", 0)]
    [InlineData("1.0.0-1", "1.0.0-a", -1)]
    [InlineData("1.2.3+abc", "1.2.3", 0)]
    [InlineData(" v10.0.0 ", "9.9.9", 1)]
    public void SurumKarsilastirma(string a, string b, int sign)
    {
        Assert.Equal(sign, Math.Sign(AppVersion.Compare(a, b)));
        Assert.Equal(-sign, Math.Sign(AppVersion.Compare(b, a)));
    }

    [Fact]
    public void BilgiSurumu()
    {
        Assert.Equal("4.0.6", AppVersion.FromInformational("4.0.6+abc123"));
        Assert.Equal("0.0.0", AppVersion.FromInformational(null));
    }

    [Fact]
    public void DenemeSayaci()
    {
        var path = _tmp.File("auto-update-tried.txt");
        var a = new AutoUpdateAttempts(path);
        Assert.Equal(0, a.Count("1.2.3"));
        Assert.True(a.Record("1.2.3"));
        Assert.Equal(1, a.Count("1.2.3"));
        a.Record("1.2.3");
        Assert.True(a.Exhausted("1.2.3"));
        Assert.Equal("1.2.3\n2\n", File.ReadAllText(path));
        Assert.Equal(0, a.Count("1.2.4"));
        a.Record("1.2.4");
        Assert.Equal(0, new AutoUpdateAttempts(path).Count("1.2.3"));
        File.WriteAllText(path, "1.2.3");
        var old = new AutoUpdateAttempts(path);
        Assert.Equal(1, old.Count("1.2.3"));
        Assert.False(old.Exhausted("1.2.3"));
    }

    [Fact]
    public void DenemeSayaciYazilamazsaBellekSurer()
    {
        var blocker = _tmp.File("dosya");
        File.WriteAllText(blocker, "");
        var a = new AutoUpdateAttempts(Path.Combine(blocker, "x.txt"));
        Assert.False(a.Record("1.0.0"));
        Assert.Equal(1, a.Count("1.0.0"));
        var memory = new AutoUpdateAttempts(null);
        Assert.True(memory.Record("1.0.0"));
        Assert.Equal(1, memory.Count("1.0.0"));
    }

    [Theory]
    [InlineData("{\"ok\":true,\"downloads\":3439}", 3439L)]
    [InlineData("{\"downloads\":3439.0}", 3439L)]
    [InlineData("{\"ok\":true}", null)]
    [InlineData("{\"downloads\":0}", null)]
    [InlineData("bozuk", null)]
    [InlineData("{\"downloads\":\"3439\"}", null)]
    [InlineData("{\"downloads\":-5}", null)]
    [InlineData("{\"downloads\":12.5}", null)]
    [InlineData("{\"downloads\":1e30}", null)]
    [InlineData("[3439]", null)]
    [InlineData("", null)]
    public void IndirmeSayisiAyristirma(string json, long? expected) =>
        Assert.Equal(expected, DownloadCounter.Parse(json));

    [Fact]
    public void IndirmeSayaciDosyasi()
    {
        var path = _tmp.File("pool-translations", "downloads.txt");
        var c = new DownloadCounter(path);
        Assert.Null(c.Value);
        Assert.True(c.Update("{\"downloads\":3502}"));
        Assert.Equal("3502", File.ReadAllText(path));
        Assert.False(c.Update("{\"downloads\":3502}"));
        Assert.False(c.Update("bozuk"));
        Assert.Equal(3502, new DownloadCounter(path).Value);
        File.WriteAllText(path, "12a");
        Assert.Null(new DownloadCounter(path).Value);
        Assert.Equal("3.439", DownloadCounter.Format(3439, new CultureInfo("tr-TR")));
        Assert.Equal("3,439", DownloadCounter.Format(3439, new CultureInfo("en-US")));
        Assert.Equal("999", DownloadCounter.Format(999, new CultureInfo("tr-TR")));
    }

    [Fact]
    public void KurulumKimlikleri()
    {
        var pool = _tmp.File("install");
        var id = InstallIdFile.ReadOrCreateGuid(pool);
        Assert.Equal(id, InstallIdFile.ReadOrCreateGuid(pool));
        File.WriteAllText(pool, " 8D0F5C9E-3B1A-4C2D-9E8F-7A6B5C4D3E2F ");
        Assert.Equal("8d0f5c9e-3b1a-4c2d-9e8f-7a6b5c4d3e2f", InstallIdFile.ReadOrCreateGuid(pool));

        var report = _tmp.File(InstallIdFile.ReportFileName);
        Assert.Equal("pool-install-id", InstallIdFile.ReadOrCreateReportId(report, "pool-install-id"));
        var made = InstallIdFile.ReadOrCreateReportId(report, null);
        Assert.Equal(32, made.Length);
        Assert.Equal(made, InstallIdFile.ReadOrCreateReportId(report, "short"));
    }

    [Fact]
    public void CihazBilgisi()
    {
        Assert.Equal("ACER N22C5", DeviceInfo.ComputerModel("ACER", "N22C5"));
        Assert.Equal("ASUS Vivobook 16", DeviceInfo.ComputerModel("ASUS", "ASUS Vivobook 16"));
        Assert.Equal("Gigabyte Technology Co., Ltd.", DeviceInfo.ComputerModel("Gigabyte Technology Co., Ltd.", "To Be Filled By O.E.M."));
        Assert.Equal("Windows PC", DeviceInfo.ComputerModel("Default string", "Not Specified"));
        Assert.Equal("Windows PC", DeviceInfo.ComputerModel(null, null));
        Assert.Equal("Windows 11 (22631)", DeviceInfo.WindowsName(10, 0, 22631));
        Assert.Equal("Windows 10 (19044)", DeviceInfo.WindowsName(10, 0, 19044));
        Assert.Equal("Windows 6.1 (7601)", DeviceInfo.WindowsName(6, 1, 7601));

        var lines = DeviceInfo.Lines(("app", "4.1.2"), ("device", "ACER N22C5"), ("system", "Windows 11 (22631)"),
            ("tv", "Sony Bravia | 2.4\r\nhazır"), ("console", "Xbox · bulut"), ("status", "  "));
        Assert.Equal(5, lines.Count);
        Assert.Equal("app: 4.1.2 | device: ACER N22C5 | system: Windows 11 (22631) | tv: Sony Bravia / 2.4 hazır | console: Xbox · bulut",
            DeviceInfo.Summary(lines));
        Assert.Equal(600, DeviceInfo.Summary([new DeviceInfoLine("app", new string('x', 700))]).Length);
        Assert.Null(DeviceInfo.ForRequest("   "));
    }
}
