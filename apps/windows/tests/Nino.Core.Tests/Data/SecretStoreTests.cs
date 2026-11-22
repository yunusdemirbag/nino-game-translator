// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Security.Cryptography;
using System.Text;
using Nino.Core.Data;

namespace Nino.Core.Tests.Data;

public class SecretStoreTests : IDisposable
{
    readonly TempFolder _tmp = new();

    /// <summary>Sahte koruyucu: ek anahtarın özetini başa koyar; yanlış ek anahtarla çözülmez.</summary>
    sealed class FakeProtector : ISecretProtector
    {
        public byte[] Protect(byte[] plain, byte[] entropy) => [.. SHA256.HashData(entropy), .. plain];

        public byte[] Unprotect(byte[] data, byte[] entropy)
        {
            var tag = SHA256.HashData(entropy);
            if (data.Length < 32 || !data.AsSpan(0, 32).SequenceEqual(tag)) throw new CryptographicException("ek anahtar tutmadı");
            return data[32..];
        }
    }

    readonly FakeProtector _protector = new();

    string Path => _tmp.File(FileSecretStore.WindowsFileName);

    FileSecretStore Store() => new(Path, _protector);

    public void Dispose() => _tmp.Dispose();

    string Plain() => Encoding.UTF8.GetString(_protector.Unprotect(File.ReadAllBytes(Path), FileSecretStore.CurrentEntropy));

    [Fact]
    public void DosyaYoksaBos()
    {
        Assert.False(Store().TryGet<string>(SecretKeys.TvKey, out _));
        Assert.False(File.Exists(Path));
    }

    [Fact]
    public void KaydetOkuSilGidipGelir()
    {
        var s = Store();
        s.Set(SecretKeys.AccountId, new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 });
        s.Set(SecretKeys.ConsoleKind, StoredConsoleKind.Xbox);
        s.Set(SecretKeys.TvKey, "");
        Assert.Equal("{\"accountId\":\"AQIDBAUGBwg=\",\"consoleKind\":1,\"tvKey\":\"\"}", Plain());

        var again = Store();
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, again.Get<byte[]>(SecretKeys.AccountId));
        Assert.Equal(StoredConsoleKind.Xbox, again.Get<StoredConsoleKind>(SecretKeys.ConsoleKind));
        Assert.True(again.TryGet<string>(SecretKeys.TvKey, out var empty) && empty == "");
        again.Remove(SecretKeys.TvKey);
        Assert.False(again.Contains(SecretKeys.TvKey));
        Assert.False(File.Exists($"{Path}.tmp"));
    }

    [Fact]
    public void KayitBicimleriBirebir()
    {
        var s = Store();
        s.Set(SecretKeys.Tv, new StoredTv { Name = "LG", Host = "192.168.0.110", Brand = StoredTvBrand.AndroidTv });
        s.Set(SecretKeys.DevSessionRenewed(" 192.168.0.5 "), new DateTimeOffset(2026, 11, 22, 10, 0, 0, TimeSpan.Zero));
        Assert.Equal("{\"tv\":{\"Name\":\"LG\",\"Host\":\"192.168.0.110\",\"Brand\":2},\"devSessionRenewed.192.168.0.5\":\"2026-11-22T10:00:00\\u002B00:00\"}", Plain()); // varsayılan JSON yazımı + kaçışlı
        Assert.Equal(StoredTvBrand.AndroidTv, Store().Get<StoredTv>(SecretKeys.Tv)!.Brand);
    }

    [Fact]
    public void EskiKonsolKaydiOkunur()
    {
        var s = Store();
        s.Set("console", System.Text.Json.Nodes.JsonNode.Parse(
            "{\"Host\":\"192.168.0.5\",\"Name\":\"PS5-123\",\"RegistKey\":\"AAECAwQFBgcICQoLDA0ODw==\",\"Morning\":\"AAECAwQFBgcICQoLDA0ODw==\",\"WakeCredential\":null}"));
        var c = Store().Get<StoredConsole>(SecretKeys.Console)!;
        Assert.Equal("PS5-123", c.Name);
        Assert.Equal(16, c.RegistKey.Length);
    }

    [Fact]
    public void TipiTutmayanDegerYokSayilir()
    {
        var s = Store();
        s.Set(SecretKeys.SetupComplete, "evet");
        Assert.False(s.TryGet<bool>(SecretKeys.SetupComplete, out _));
    }

    [Fact]
    public void SilmeAnahtarYoksaDosyaYazmaz()
    {
        Store().Remove("yok");
        Assert.False(File.Exists(Path));
    }

    [Fact]
    public void EskiEkAnahtarlaKorunanDosyaBirKezYenidenYazilir()
    {
        File.WriteAllBytes(Path, _protector.Protect(Encoding.UTF8.GetBytes("{\"tvKey\":\"abc\"}"), LegacyNames.SecretsEntropy));
        Assert.Equal("abc", Store().Get<string>(SecretKeys.TvKey));
        Assert.Equal("{\"tvKey\":\"abc\"}", Plain());
    }

    [Fact]
    public void EskiAnahtarlaNesneDegilseYenidenYazilmaz()
    {
        var blob = _protector.Protect(Encoding.UTF8.GetBytes("[1]"), LegacyNames.SecretsEntropy);
        File.WriteAllBytes(Path, blob);
        Assert.False(Store().Contains("x"));
        Assert.Equal(blob, File.ReadAllBytes(Path));
    }

    [Fact]
    public void CozulemeyenDosyaKayittanOnceKenaraAlinir()
    {
        File.WriteAllBytes(Path, [1, 2, 3]);
        var clock = new FakeClock(new DateTimeOffset(2026, 11, 22, 10, 0, 0, TimeSpan.Zero));
        var s = new FileSecretStore(Path, _protector, clock: clock);
        Assert.False(s.Contains(SecretKeys.TvKey));
        Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(Path)); // okumak dokunmaz
        s.Set(SecretKeys.TvKey, "yeni");
        var aside = Directory.GetFiles(_tmp.Path, "secure.dat.bozuk-*");
        Assert.Single(aside);
        Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(aside[0]));
        Assert.Equal("{\"tvKey\":\"yeni\"}", Plain());
    }

    [Fact]
    public void BozukJsonDaKenaraAlinir()
    {
        File.WriteAllBytes(Path, _protector.Protect(Encoding.UTF8.GetBytes("{bozuk"), FileSecretStore.CurrentEntropy));
        var s = Store();
        s.Set("a", 1);
        Assert.Single(Directory.GetFiles(_tmp.Path, "secure.dat.bozuk-*"));
    }

    [Fact]
    public void LinuxDuzDosyaYalnizSahibi()
    {
        var s = FileSecretStore.ForLinux(_tmp.Path);
        s.Set(SecretKeys.DeepLKey, "k");
        var path = _tmp.File("secure.json");
        Assert.Equal("{\"deepLKey\":\"k\"}", File.ReadAllText(path));
        if (!OperatingSystem.IsWindows())
            Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(path));
        Assert.Equal("k", FileSecretStore.ForLinux(_tmp.Path).Get<string>(SecretKeys.DeepLKey));
    }

    [Fact]
    public void GirisSifresiVeZemin()
    {
        Assert.Null(SecretKeys.NormalizePasscode("12a4"));
        Assert.Equal("4321", SecretKeys.NormalizePasscode(" 4321 "));
        Assert.Null(SecretKeys.NormalizePasscode("123"));
        Assert.Equal(StreamBackground.Magenta, SecretKeys.ParseStreamBackground("MAGENTA"));
        Assert.Equal(StreamBackground.Green, SecretKeys.ParseStreamBackground("mor"));
        Assert.Equal("black", StreamBackground.Black.ToStoredName());
    }

    [Fact]
    public void SifirlamaListeleri()
    {
        var s = new MemorySecretStore();
        foreach (var k in new[] { SecretKeys.AccountId, SecretKeys.Tv, SecretKeys.DeepLKey, SecretKeys.LastGames, SecretKeys.LoginPasscode })
            s.Set(k, "x");
        s.RemoveAll(SecretKeys.ResetEverything);
        Assert.False(s.Contains(SecretKeys.AccountId));
        Assert.False(s.Contains(SecretKeys.LoginPasscode));
        Assert.True(s.Contains(SecretKeys.DeepLKey));
        Assert.True(s.Contains(SecretKeys.LastGames));
    }
}
