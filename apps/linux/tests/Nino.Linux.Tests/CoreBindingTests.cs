// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Linux.Core;
using Nino.Linux.Hosting;
using Nino.Linux.Imaging;

namespace Nino.Linux.Tests;

/// <summary>Eski Linux sunucusunun veri dosyaları çekirdeğin depolarıyla açılıyor mu.</summary>
public sealed class LegacyDataTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    [Fact]
    public void EskiSecureJsonOkunurYazilincaYalnizSahibi()
    {
        File.WriteAllText(temp.File("secure.json"),
            """{"accountId":"AQIDBAUGBwg=","tv":{"Name":"Salon","Host":"192.168.0.110","Brand":2},"tvKey":"","setupComplete":true}""");
        var store = FileSecretStore.ForLinux(temp.Path);
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, store.Get<byte[]>(SecretKeys.AccountId));
        Assert.True(store.Get<bool>(SecretKeys.SetupComplete));
        Assert.Equal(StoredTvBrand.AndroidTv, store.Get<StoredTv>(SecretKeys.Tv)!.Brand);
        store.Set(SecretKeys.DeepLKey, "k");
        if (!OperatingSystem.IsWindows())
            Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(temp.File("secure.json")));
        Assert.Equal("k", FileSecretStore.ForLinux(temp.Path).Get<string>(SecretKeys.DeepLKey));
    }

    [Fact]
    public void EskiSettingsJsonOkunur()
    {
        // Eski sunucu ayarları varsayılan JSON ile yazardı: PascalCase, sayılar sayı olarak.
        File.WriteAllText(temp.File("settings.json"),
            """{"Region":{"Top":0.5,"Bottom":0.9,"Left":0.1,"Right":0.9},"Style":{"FontSize":58,"Placement":2},"SourceLanguage":"en","TargetLanguage":"tr","OnlineTranslation":true}""");
        var settings = new JsonFileSettingsStore(temp.File("settings.json"), () => "tr").Load();
        Assert.Equal(new Region(0.5, 0.9, 0.1, 0.9), settings.Region);
        Assert.Equal(58, settings.Style.FontSize);
        Assert.Equal(SubtitlePlacement.Below, settings.Style.Placement);
        Assert.True(settings.OnlineTranslation);
    }

    [Fact]
    public void EskiClaudeAnahtariTasinir()
    {
        File.WriteAllText(temp.File("secure.json"), """{"deepLKey":" sk-ant-api03-abc "}""");
        using var platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0");
        platform.MoveLegacyOnlineKey();
        Assert.Null(platform.Secrets.Get<string>(SecretKeys.DeepLKey));
        Assert.Equal("sk-ant-api03-abc", platform.Secrets.Get<string>(SecretKeys.ClaudeKey));
        Assert.Equal(OnlineEngine.Claude, platform.Settings.Load().OnlineEngine);
        Assert.Equal("Claude", OnlineKeys.SavedEngine(platform.Secrets, platform.Settings.Load()));
    }

    [Fact]
    public void DeepLAnahtariYerindeKalir()
    {
        File.WriteAllText(temp.File("secure.json"), """{"deepLKey":"abc:fx"}""");
        using var platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0");
        platform.MoveLegacyOnlineKey();
        Assert.Equal("abc:fx", platform.Secrets.Get<string>(SecretKeys.DeepLKey));
        Assert.Equal("DeepL", OnlineKeys.SavedEngine(platform.Secrets, platform.Settings.Load()));
    }

    [Fact]
    public void EskiOnnxTurkceModeliKullanilir()
    {
        var legacy = Path.Combine(temp.Path, "models", "en-tr");
        Directory.CreateDirectory(legacy);
        foreach (var name in new[] { "encoder_model_int8.onnx", "decoder_model_merged_int8.onnx", "source.spm", "vocab.json" })
            File.WriteAllText(Path.Combine(legacy, name), "x");
        using var platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0");
        Assert.True(new LinuxTools(platform).ModelInstalled);
        Assert.True(Directory.Exists(legacy));
    }

    [Fact]
    public void PsGunluguDosyayaBilgiDisiPanele()
    {
        var journal = new Journal();
        using (var platform = LinuxPlatform.Open(new DataFolder(temp.Path), journal, "0.1.0"))
        {
            platform.RemotePlayLog.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Info, "bağlandı");
            platform.RemotePlayLog.Chiaki(Nino.RemotePlay.Bridge.BridgeLogLevel.Error, "koptu");
            platform.RemotePlayLog.Flush(TimeSpan.FromSeconds(5));
        }
        var file = File.ReadAllText(temp.File("remoteplay.log"));
        Assert.Contains("bağlandı", file);
        Assert.Contains("koptu", file);
        var panel = journal.Recent();
        Assert.Contains(panel, line => line.Contains("[ps5]") && line.Contains("koptu"));
        Assert.DoesNotContain(panel, line => line.Contains("bağlandı"));
    }
}

public sealed class TelemetryContextTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    [Fact]
    public void LinuxBaglami()
    {
        File.WriteAllText(temp.File("os-release"), "NAME=\"Ubuntu\"\nPRETTY_NAME=\"Ubuntu 24.04.1 LTS\"\n");
        Assert.StartsWith("Ubuntu 24.04.1 LTS · ", LinuxPlatform.OsName(temp.File("os-release")));
        using (var platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0"))
        {
            var setup = platform.TelemetrySetup();
            Assert.Equal("linux", setup.Platform);
            Assert.Equal(platform.InstallId, setup.Install);
            Assert.Equal(Path.Combine(temp.Path, "telemetry"), setup.Folder);
            Assert.NotNull(setup.Sender);
        }
        var context = LinuxPlatform.Context("0.1.0");
        Assert.Equal("linux", context.Platform);
        Assert.Equal("linux", (string?)context.ToJson()["platform"]);
    }
}

public sealed class CoreRulesTests
{
    [Fact]
    public void BuyutmeBilineerVeBoyut()
    {
        var picture = BgraPicture.Packed([0, 0, 0, 255, 200, 200, 200, 255], 2, 1);
        var big = new CoreOcrRules().Enlarge(picture, 2);
        Assert.Equal((4, 2), (big.Width, big.Height));
        Assert.InRange(big.Pixels[4], 1, 199); // ara piksel karışım: en yakın komşu değil
    }

    [Fact]
    public void AyriYaziKuraliCekirdektenGelir()
    {
        var rules = new CoreOcrRules();
        Assert.True(rules.IsSeparateText(300, 20, 1000));
        Assert.False(rules.IsSeparateText(30, 20, 1000));
        Assert.True(rules.WordLikeness("Meet me by the old pier tonight.") > rules.WordLikeness("~wq xz|| ,,"));
    }
}

public sealed class TvPackageNameTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    [Fact]
    public void WebTvPaketAdlariOkunur()
    {
        // apps/tv-web/tools/package.py'nin ürettiği adlar (tv-web dalında denendi).
        File.WriteAllText(temp.File("com.ninotranslator.tv_4.0.3_all.ipk"), "");
        File.WriteAllText(temp.File("nino-samsung_4.0.3.wgt"), "");
        File.WriteAllText(temp.File("nino-androidtv_4.0.3.apk"), "");
        Assert.Equal("4.0.3", Nino.TvInstall.TvAppPackages.FindLg(temp.Path)?.Version);
        Assert.Equal("4.0.3", Nino.TvInstall.TvAppPackages.FindSamsung(temp.Path)?.Version);
        Assert.Equal("4.0.3", Nino.TvInstall.TvAppPackages.FindAndroid(temp.Path)?.Version);
    }
}

public sealed class SubtitleBlockTests
{
    [Fact]
    public void KutularBolgeyeBirKezYerlesir()
    {
        // GTA 6 telefon menüsü (gta6-telefon-koyu-rydeme): eski sunucu "Book Ryde ($82)" seçiyordu.
        var area = Nino.Core.Imaging.Box.FromRegion(new Region());
        // Kutular gerçek Tesseract okumasından (bölgeye göre).
        var reading = new Nino.Core.Reading.OcrReading([
            new Nino.Core.Reading.OcrLine("Book Ryde ($82)", new Nino.Core.Imaging.Box(0.6460, 0.1266, 0.7522, 0.2005)),
            new Nino.Core.Reading.OcrLine("Choose Ryde", new Nino.Core.Imaging.Box(0.6460, 0.2670, 0.7312, 0.3372)),
            new Nino.Core.Reading.OcrLine("Change Destination", new Nino.Core.Imaging.Box(0.6633, 0.4095, 0.7926, 0.4797)),
        ]);
        Assert.Equal("Book Ryde ($82)", LinuxTools.SubtitleOf(reading, area).Text);
    }
}
