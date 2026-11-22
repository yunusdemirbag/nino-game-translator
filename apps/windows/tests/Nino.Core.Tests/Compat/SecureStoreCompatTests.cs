// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Nino.Core.Data;
using Nino.Core.Tests.Data;
using Nino.RemotePlay;
using static Nino.Core.Tests.Compat.CompatFixtures;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// <c>secure.dat</c>'ın şifresiz içeriği. Fikstür: eski uygulamanın kendi deposuyla (DPAPI yerine şeffaf koruyucu)
/// uygulamanın yazdığı tiplerle ve sırayla yazdığı JSON. Bütün anahtar değerleri sahtedir.
/// </summary>
public class SecureStoreCompatTests
{
    static readonly byte[] RegistKey = Encoding.ASCII.GetBytes("1a2b3c4d\0\0\0\0\0\0\0\0");
    static readonly byte[] Morning = Enumerable.Range(0x10, 16).Select(i => (byte)i).ToArray();
    static readonly DateTimeOffset Renewed = new(2026, 11, 22, 10, 0, 0, TimeSpan.Zero);

    static FileSecretStore Store(string path) => new(path, new PlainSecretProtector());

    /// <summary>Yeni uygulamanın yazdığı değerler, eski fikstürdeki sırayla (denetleyicideki ifadelerle aynı tipler).</summary>
    static void WriteLikeApp(ISecretStore s)
    {
        s.Set(SecretKeys.ConsoleKind, StoredConsoleKind.Xbox);
        s.Set(SecretKeys.AccountId, new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 });
        s.Set(SecretKeys.Console, RemotePlayRecords.ConsoleToJson(new Ps5Console("192.0.2.5", "PS5-123", RegistKey, Morning)));
        s.Set(SecretKeys.ConsoleKindLocked, true);
        s.Set(SecretKeys.XboxToken, "fake-xbox-token");
        s.Set(SecretKeys.XboxConsole, new StoredXboxConsole { Id = "FAKE0123", Name = "Salon Xbox", Model = "XboxSeriesX", StreamingEnabled = true });
        s.Set(SecretKeys.Tv, new StoredTv { Name = "Samsung QE65 \"Salon\"", Host = "192.0.2.110", Brand = StoredTvBrand.Samsung });
        s.Set(SecretKeys.TvKey, "fake-tv-key-ğ");
        s.Set(SecretKeys.TvDevKey, "fake-dev-key");
        s.Set(SecretKeys.TvAppVersion, "0.9.40");
        s.Set(SecretKeys.DevSessionRenewed(" 192.0.2.110 "), Renewed);
        s.Set(SecretKeys.LastGames, new Dictionary<string, string> { ["PS5-123"] = "GTA 6", ["PS5-Oda"] = "Ghost of Yōtei" });
        s.Set(SecretKeys.CaptureCardId, "\\\\?\\usb#vid_fake&pid_0001#0#{65e8773d}\\global");
        s.Set(SecretKeys.StreamBackground, StreamBackground.Magenta.ToStoredName());
        s.Set(SecretKeys.SetupComplete, true);
        s.Set(SecretKeys.LoginPasscode, "0420");
        s.Set(SecretKeys.DeepLKey, "fake-deepl:fx");
        s.Set(SecretKeys.GeminiKey, "fake-gemini");
        s.Set(SecretKeys.OpenAIKey, "fake-openai");
        s.Set(SecretKeys.ClaudeKey, "fake-claude");
        s.Set(SecretKeys.LocalAIKey, "fake-local");
        s.Set(SecretKeys.SamsungClientName, "Nino");
    }

    [Fact]
    public void NewWriterProducesOldBytes()
    {
        using var temp = new TempFolder();
        var path = temp.File(FileSecretStore.WindowsFileName);
        WriteLikeApp(Store(path));
        Export(path, "secure.dat");
        SameBytes(OldBytes("secure", "secure-plain.json"), File.ReadAllBytes(path), "secure.dat içeriği");
    }

    [Fact]
    public void OldFileReadsWithAppTypes()
    {
        using var temp = new TempFolder();
        var path = temp.File(FileSecretStore.WindowsFileName);
        File.Copy(Old("secure", "secure-plain.json"), path);
        var s = Store(path);

        Assert.True(s.TryGet<StoredConsoleKind>(SecretKeys.ConsoleKind, out var kind));
        Assert.Equal(StoredConsoleKind.Xbox, kind);
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, s.Get<byte[]>(SecretKeys.AccountId));
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, RemotePlayRecords.AccountIdFromJson(s.Get<JsonNode>(SecretKeys.AccountId)));
        var console = RemotePlayRecords.ConsoleFromJson(s.Get<JsonNode>(SecretKeys.Console))!;
        Assert.Equal("192.0.2.5", console.Host);
        Assert.Equal("PS5-123", console.Name);
        Assert.Equal(RegistKey, console.RegistKey);
        Assert.Equal(Morning, console.Morning);
        Assert.Equal(0x1a2b3c4dUL, console.WakeCredential);
        var stored = s.Get<StoredConsole>(SecretKeys.Console)!;
        Assert.Equal(0x1a2b3c4dUL, stored.WakeCredential);
        Assert.True(s.Get<bool>(SecretKeys.ConsoleKindLocked));
        Assert.Equal("fake-xbox-token", s.Get<string>(SecretKeys.XboxToken));
        Assert.Equal(new StoredXboxConsole { Id = "FAKE0123", Name = "Salon Xbox", Model = "XboxSeriesX", StreamingEnabled = true },
            s.Get<StoredXboxConsole>(SecretKeys.XboxConsole));
        Assert.Equal(new StoredTv { Name = "Samsung QE65 \"Salon\"", Host = "192.0.2.110", Brand = StoredTvBrand.Samsung }, s.Get<StoredTv>(SecretKeys.Tv));
        Assert.Equal("fake-tv-key-ğ", s.Get<string>(SecretKeys.TvKey));
        Assert.Equal("fake-dev-key", s.Get<string>(SecretKeys.TvDevKey));
        Assert.Equal("0.9.40", s.Get<string>(SecretKeys.TvAppVersion));
        Assert.True(s.TryGet<DateTimeOffset>(SecretKeys.DevSessionRenewed("192.0.2.110"), out var renewed));
        Assert.Equal(Renewed, renewed);
        Assert.Equal(TimeSpan.Zero, renewed.Offset);
        Assert.Equal(new Dictionary<string, string> { ["PS5-123"] = "GTA 6", ["PS5-Oda"] = "Ghost of Yōtei" },
            s.Get<Dictionary<string, string>>(SecretKeys.LastGames));
        Assert.Equal("\\\\?\\usb#vid_fake&pid_0001#0#{65e8773d}\\global", s.Get<string>(SecretKeys.CaptureCardId));
        Assert.Equal(StreamBackground.Magenta, SecretKeys.ParseStreamBackground(s.Get<string>(SecretKeys.StreamBackground)));
        Assert.True(s.Get<bool>(SecretKeys.SetupComplete));
        Assert.Equal("0420", SecretKeys.NormalizePasscode(s.Get<string>(SecretKeys.LoginPasscode)));
        Assert.Equal("fake-deepl:fx", s.Get<string>(SecretKeys.DeepLKey));
        Assert.Equal("fake-gemini", s.Get<string>(SecretKeys.GeminiKey));
        Assert.Equal("fake-openai", s.Get<string>(SecretKeys.OpenAIKey));
        Assert.Equal("fake-claude", s.Get<string>(SecretKeys.ClaudeKey));
        Assert.Equal("fake-local", s.Get<string>(SecretKeys.LocalAIKey));
        Assert.Equal("Nino", s.Get<string>(SecretKeys.SamsungClientName));
        // Dosya okunurken yeniden yazılmadı.
        SameBytes(OldBytes("secure", "secure-plain.json"), File.ReadAllBytes(path), "okuma dosyayı değiştirmez");
    }

    [Fact]
    public void OneChangeKeepsEveryOtherByte()
    {
        using var temp = new TempFolder();
        var path = temp.File(FileSecretStore.WindowsFileName);
        File.Copy(Old("secure", "secure-plain.json"), path);
        var s = Store(path);
        s.Set(SecretKeys.TvAppVersion, "0.9.41");
        var expected = OldText("secure", "secure-plain.json").Replace("\"tvAppVersion\":\"0.9.40\"", "\"tvAppVersion\":\"0.9.41\"");
        SameText(expected, File.ReadAllText(path), "tek değişiklik");

        s.Remove(SecretKeys.LoginPasscode);
        Assert.DoesNotContain("loginPasscode", File.ReadAllText(path));
        Assert.Contains("\"setupComplete\":true,\"deepLKey\"", File.ReadAllText(path));
    }

    [Fact]
    public void OldReaderSeesNewFileValues()
    {
        // Yeni kodun yazdığı dosyayı eski kodun deposu okudu (deneme programı); değerler aynı.
        using var doc = JsonDocument.Parse(File.ReadAllText(New("oldread.json")));
        var s = doc.RootElement.GetProperty("secure");
        Assert.Equal("0102030405060708", s.GetProperty("accountId").GetString());
        var c = s.GetProperty("console");
        Assert.Equal("192.0.2.5", c.GetProperty("Host").GetString());
        Assert.Equal(Convert.ToHexString(RegistKey), c.GetProperty("RegistKey").GetString());
        Assert.Equal(Convert.ToHexString(Morning), c.GetProperty("Morning").GetString());
        Assert.Equal(0x1a2b3c4dUL, c.GetProperty("WakeCredential").GetUInt64());
        Assert.Equal("Xbox", s.GetProperty("consoleKind").GetString());
        Assert.True(s.GetProperty("consoleKindLocked").GetBoolean());
        Assert.Equal("Samsung", s.GetProperty("tv").GetProperty("Brand").GetString());
        Assert.Equal("Samsung QE65 \"Salon\"", s.GetProperty("tv").GetProperty("Name").GetString());
        Assert.True(s.GetProperty("xboxConsole").GetProperty("StreamingEnabled").GetBoolean());
        Assert.Equal("fake-tv-key-ğ", s.GetProperty("tvKey").GetString());
        Assert.Equal(Renewed.ToString("O"), s.GetProperty("devSessionRenewed").GetString());
        Assert.Equal("Ghost of Yōtei", s.GetProperty("lastGames").GetProperty("PS5-Oda").GetString());
        Assert.Equal("magenta", s.GetProperty("streamBackground").GetString());
        Assert.True(s.GetProperty("setupComplete").GetBoolean());
        Assert.Equal("0420", s.GetProperty("loginPasscode").GetString());
        Assert.Equal("fake-local", s.GetProperty("localAIKey").GetString());
        Assert.Equal("Nino", s.GetProperty("samsungClientName").GetString());

        // Ve okunan dosya, bugünkü yazıcının çıktısıyla aynı.
        using var temp = new TempFolder();
        var path = temp.File(FileSecretStore.WindowsFileName);
        WriteLikeApp(Store(path));
        SameBytes(File.ReadAllBytes(New("secure.dat")), File.ReadAllBytes(path), "eski koda okutulan dosya");
    }
}
