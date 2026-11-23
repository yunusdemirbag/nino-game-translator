// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using Nino.Core.Support;
using Nino.Core.Tests.Data;

namespace Nino.Core.Tests.Support;

public sealed class LogRedactorTests
{
    [Theory]
    [InlineData("authorization: Bearer zyxw9876qrst5432", "authorization: Bearer [gizlendi]")]
    [InlineData("yanıt key=7f3e2a91bc04 geldi", "yanıt key=[gizlendi] geldi")]
    [InlineData("{\"api_key\":\"s3cr3tvalue\"}", "{\"api_key\":\"[gizlendi]\"}")]
    [InlineData("token: q1.w2.e3", "token: [gizlendi]")]
    [InlineData("giriş id_token=k9m8n7 bitti", "giriş id_token=[gizlendi] bitti")]
    [InlineData("auth_token: p0o9i8", "auth_token: [gizlendi]")]
    [InlineData("deepl_key=abc", "deepl_key=[gizlendi]")]
    [InlineData("basic QWxhZGRpbjpvcGVu", "basic [gizlendi]")]
    [InlineData("password = \"hunter2\"", "password = \"[gizlendi]\"")]
    [InlineData("x AIzaSyA1234567890abcdefghijklmnopq y", "x [gizlendi] y")]
    [InlineData("sk-proj-ABCDEF1234567890xyz", "[gizlendi]")]
    [InlineData("sk-ant-api03-ABCDEFGHIJ0123456789", "[gizlendi]")]
    [InlineData("ghp_ABCDEFGHIJ0123456789abcd", "[gizlendi]")]
    [InlineData("deepl 0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b:fx", "deepl [gizlendi]")]
    [InlineData("id 00112233445566778899aabbccddeeff00", "id [gizlendi]")]
    [InlineData("jwt eyJhbGciOiJIUzI1NiJ9eyJzdWIiOiIxMjM0NTY3ODkwIn0abc", "jwt [gizlendi]")]
    public void Redacts(string input, string expected) => Assert.Equal(expected, LogRedactor.Redact(input));

    [Theory]
    [InlineData("12:04:31 okundu \"Where is the key?\" → \"Anahtar nerede?\"")]
    [InlineData(@"C:\Users\nino\AppData\Local\Nino\models\opus-mt-en-tr\model.bin hazır")]
    [InlineData("System.IO.IOException: Nino.Core.Link.TvOutput.SendAsync")]
    [InlineData("2026-11-20T08:15:02.456Z PS5 10.0.0.9 akış başladı, 1280x720 30 fps")]
    [InlineData("hotkey=F9 alındı")]
    [InlineData("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")]
    public void Keeps(string input) => Assert.Equal(input, LogRedactor.Redact(input));
}

public sealed class LogCollectorTests
{
    [Fact]
    public void Collect_Example()
    {
        using var temp = new TempFolder();
        File.WriteAllText(temp.File("hata.log"), "eski\nkey=gizlideger123\n");
        var sb = new StringBuilder();
        for (var i = 0; i < 5000; i++) sb.Append("[2026-11-22 12:00:00.000] satır okundu ").Append(i).Append('\n');
        File.WriteAllText(temp.File("altyazi.log"), sb.ToString());
        var log = LogCollector.Collect(temp.Path, 2500)!;
        Assert.True(log.Length <= 2500, log.Length.ToString());
        Assert.DoesNotContain("gizlideger123", log);
        Assert.Contains("— hata.log —", log);
        Assert.Contains("— altyazi.log —", log);
        Assert.DoesNotContain("remoteplay.log", log);
        Assert.DoesNotContain("tvinstall.log", log);
        Assert.EndsWith("okundu 4999", log);
    }

    [Fact]
    public void Collect_FullSize_NoFiles()
    {
        using var temp = new TempFolder();
        Assert.Null(LogCollector.Collect(temp.Path));
        File.WriteAllText(temp.File("remoteplay.log"), string.Concat(Enumerable.Repeat("[chiaki info] satır\n", 5000)));
        File.WriteAllText(temp.File("tvinstall.log"), "[t] kuruldu\n");
        var log = LogCollector.Collect(temp.Path)!;
        Assert.StartsWith("— remoteplay.log —\n", log);
        Assert.EndsWith("— tvinstall.log —\n[t] kuruldu", log);
        Assert.True(log.Length <= 18_000 + 100);
    }

    [Fact]
    public void ReadTail_WhileOpenForWriting()
    {
        using var temp = new TempFolder();
        var path = temp.File("altyazi.log");
        using var writer = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
        var bytes = Encoding.UTF8.GetBytes(string.Concat(Enumerable.Range(0, 1000).Select(i => $"ğ satır {i}\n")));
        writer.Write(bytes);
        writer.Flush();
        var tail = LogCollector.ReadTail(path, 100)!;
        Assert.True(tail.Length <= 100);
        Assert.StartsWith("ğ satır", tail);
        Assert.EndsWith("ğ satır 999\n", tail);
    }

    [Fact]
    public void LastChars_DropsHalfLine()
    {
        var text = string.Join("\n", Enumerable.Range(0, 100).Select(i => $"satır {i:000}"));
        var tail = LogCollector.LastChars(text, 25);
        Assert.StartsWith("satır", tail);
        Assert.EndsWith("satır 099", tail);
        Assert.Equal("abc", LogCollector.LastChars("abc", 10));
        Assert.Equal("satır 099", LogCollector.LastChars(text, 9));
    }

    [Fact]
    public void LastLines()
    {
        Assert.Equal(["c", "d"], LogCollector.LastLines("a\nb\r\nc\nd\n", 2));
        Assert.Empty(LogCollector.LastLines(null, 3));
        using var temp = new TempFolder();
        Assert.Null(LogCollector.LastLinesOfFile(temp.File("yok.log"), 8));
    }
}
