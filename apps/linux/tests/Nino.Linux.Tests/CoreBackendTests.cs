// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Text;
using Nino.Linux.Core;
using Nino.Linux.Engine;
using Nino.Linux.Hosting;
using Nino.Linux.Panel;
using Nino.Linux.Ports;
using Nino.Shell;
using Nino.Shell.Platform;

namespace Nino.Linux.Tests;

/// <summary>Panel bağlayıcısı gerçek denetleyiciyle (ağ işi yapmadan).</summary>
public sealed class CoreBackendTests : IDisposable
{
    private readonly TempFolder temp = new();
    private readonly LinuxPlatform platform;
    private readonly NinoController controller;
    private readonly CoreBackend backend;

    public CoreBackendTests()
    {
        platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0");
        controller = new NinoController(platform.Services, platform.Secrets, platform.Settings, new NoSleepGuard(),
            TextCatalog.For("tr"), action => action(), new ShellOptions { Logs = new LinuxShellLogs(platform) });
        backend = new CoreBackend(controller, platform, ocrInstalled: false);
    }

    public void Dispose()
    {
        backend.ShutdownAsync().Wait(TimeSpan.FromSeconds(5));
        platform.Dispose();
        temp.Dispose();
    }

    [Fact]
    public void IlkDurumKarsilama()
    {
        var state = backend.State();
        Assert.Equal("Welcome", state.Step);
        Assert.Equal(1, state.StepNumber);
        Assert.Equal(8, state.StepCount);
        Assert.True(state.CanAdvance);
        Assert.False(state.HasAccount);
        Assert.Null(state.Console);
        Assert.Null(state.Tv);
        Assert.True(state.OcrMissing);
        Assert.StartsWith("https://", state.PsnLoginUrl);
        Assert.Equal("https://remoteplay.dl.playstation.net/remoteplay/redirect", state.RedirectPrefix);
        Assert.Equal(46, (int)state.Settings.Style["fontSize"]!);
        Assert.Equal("Cover", (string?)state.Settings.Style["placement"]);
        Assert.Null(state.OnlineEngine);
    }

    [Fact]
    public async Task KurulumBitmisseAnaEkran()
    {
        platform.Secrets.Set(SecretKeys.SetupComplete, true);
        platform.Secrets.Set(SecretKeys.AccountId, Nino.RemotePlay.RemotePlayRecords.AccountIdToJson([1, 2, 3, 4, 5, 6, 7, 8]));
        platform.Secrets.Set(SecretKeys.Console, Nino.RemotePlay.RemotePlayRecords.ConsoleToJson(
            new Nino.RemotePlay.Ps5Console("192.168.0.20", "PS5-123", new byte[16], new byte[16])));
        var reopened = new NinoController(platform.Services, platform.Secrets, platform.Settings, new NoSleepGuard(),
            TextCatalog.For("tr"), action => action());
        await using (reopened)
        {
            var state = new CoreBackend(reopened, platform, false).State();
            Assert.Equal("Done", state.Step);
            Assert.True(state.HasAccount);
            Assert.Equal(new PanelDevice("PS5-123", "192.168.0.20"), state.Console);
        }
    }

    [Fact]
    public async Task AyarlarBolgeVeGorunumKaydedilir()
    {
        await backend.ChangeSettingsAsync(new PanelRegion(0.5, 0.9, 0.1, 0.9),
            new JsonObject { ["fontSize"] = 58, ["autoSize"] = false, ["background"] = 30, ["placement"] = "Below", ["bold"] = true },
            onlineTranslation: true, showSpeakerNames: false);
        var saved = platform.Settings.Load();
        Assert.Equal(new Region(0.5, 0.9, 0.1, 0.9), saved.Region);
        Assert.Equal(58, saved.Style.FontSize);
        Assert.False(saved.Style.AutoSize);
        Assert.Equal(60, saved.Style.Background);            // İngilizcenin üstüne binerken en az %60
        Assert.Equal(SubtitlePlacement.Cover, saved.Style.Placement); // panel yeri değiştirmez (Mac gibi)
        Assert.False(saved.Style.Bold);
        Assert.True(saved.OnlineTranslation);
        Assert.False(saved.ShowSpeakerNames);
        var state = backend.State();
        Assert.False((bool)state.Settings.Style["autoSize"]!);
        Assert.Equal(60, (int)state.Settings.Style["minBackground"]!);
        Assert.False(state.Settings.ShowSpeakerNames);
        Assert.StartsWith("https://", state.Guides.Setup);
        await backend.ChangeSettingsAsync(null, new JsonObject { ["fontSize"] = 200 }, null);
        Assert.Equal(CoreBackend.MaxFontSize, platform.Settings.Load().Style.FontSize);
    }

    [Fact]
    public async Task KayitliAnahtarMotoruVeSilme()
    {
        platform.Secrets.Set(SecretKeys.DeepLKey, "abc:fx");
        Assert.Equal("DeepL", backend.State().OnlineEngine);
        Assert.True(backend.State().HasDeepLKey);
        await backend.RemoveOnlineKeyAsync();
        Assert.Null(backend.State().OnlineEngine);
        Assert.False(platform.Secrets.Contains(SecretKeys.DeepLKey));
    }

    [Fact]
    public async Task EksikGirdilerPanelSorunu()
    {
        await Assert.ThrowsAsync<PanelProblem>(() => backend.SaveOnlineKeyAsync("  "));
        await Assert.ThrowsAsync<PanelProblem>(() => backend.PairTvAsync(new PanelTv("", " ", "Lg")));
        await Assert.ThrowsAsync<PanelProblem>(() => backend.RegisterConsoleAsync("192.168.0.20", "12"));
        await Assert.ThrowsAsync<PanelProblem>(() => backend.StartAsync());
        Assert.Null(backend.LatestFrame);
    }

    [Theory]
    [InlineData(SetupStep.Welcome, "Welcome")]
    [InlineData(SetupStep.PsnSignIn, "PsnLogin")]
    [InlineData(SetupStep.Console, "Console")]
    [InlineData(SetupStep.Model, "Translation")]
    [InlineData(SetupStep.BetterTranslation, "BetterTranslation")]
    [InlineData(SetupStep.Done, "Done")]
    public void AdimAdlariSayfaSozlesmesi(SetupStep step, string name) => Assert.Equal(name, CoreBackend.StepName(step));

    [Theory]
    [InlineData(TvAppKind.Installing, "Working")]
    [InlineData(TvAppKind.PassphraseNeeded, "NeedsPassphrase")]
    [InlineData(TvAppKind.SamsungSignIn, "SignIn")]
    [InlineData(TvAppKind.ConfirmOnTv, "ApproveOnTv")]
    [InlineData(TvAppKind.UpToDate, "UpToDate")]
    public void TvUygulamasiDurumAdlari(TvAppKind kind, string name) => Assert.Equal(name, CoreBackend.AppKindName(kind));

    [Fact]
    public void AnahtarDenemesiAdlari()
    {
        Assert.Equal("Valid", CoreBackend.CheckName(Nino.Translation.Online.KeyCheckStatus.Valid));
        Assert.Equal("Invalid", CoreBackend.CheckName(Nino.Translation.Online.KeyCheckStatus.InvalidKey));
        Assert.Equal("QuotaExceeded", CoreBackend.CheckName(Nino.Translation.Online.KeyCheckStatus.QuotaExhausted));
        Assert.Equal("Unreachable", CoreBackend.CheckName(Nino.Translation.Online.KeyCheckStatus.Unreachable));
        Assert.Equal("KeyServerOff", CoreBackend.ErrorName(Nino.Core.Tv.TvError.KeyServerClosed));
    }
}

/// <summary>Sunucudaki gibi: denetleyici gerçek seri sırada.</summary>
public sealed class SerialControllerTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    [Fact]
    public async Task DurumAyarVeKapanisSeriSiradaTakilmaz()
    {
        using var platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0");
        using var serial = new SerialWorker();
        var controller = await serial.Invoke(() => new NinoController(platform.Services, platform.Secrets, platform.Settings,
            new NoSleepGuard(), TextCatalog.For("tr"), serial.Enqueue, new ShellOptions { Logs = new LinuxShellLogs(platform) }));
        var backend = new CoreBackend(controller, platform, ocrInstalled: false);

        Assert.Equal("Welcome", (await serial.Invoke(backend.State)).Step);
        await serial.Invoke(() => backend.ChangeSettingsAsync(null, new JsonObject { ["fontSize"] = 72 }, null));
        Assert.Equal(72, (int)(await serial.Invoke(backend.State)).Settings.Style["fontSize"]!);

        var clock = System.Diagnostics.Stopwatch.StartNew();
        await serial.Invoke(backend.ShutdownAsync).WaitAsync(TimeSpan.FromSeconds(10));
        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(2), $"kapanış {clock.ElapsedMilliseconds} ms sürdü");
    }
}

/// <summary>
/// Eski Linux sunucusunun kendi koduyla (FileAppStore, FileSettingsStore) yazılmış veri dosyaları yeni sunucuda
/// açılır: kurulum bitmiş görünür, PS5/TV/bölge/görünüm ve çevrimiçi anahtar korunur.
/// </summary>
public sealed class OldVolumeTests : IDisposable
{
    private readonly TempFolder temp = new();

    public void Dispose() => temp.Dispose();

    [Fact]
    public async Task EskiBirimOlduguGibiAcilir()
    {
        foreach (var file in Directory.GetFiles(Path.Combine(AppContext.BaseDirectory, "Fixtures", "old-linux")))
            File.Copy(file, Path.Combine(temp.Path, Path.GetFileName(file)));
        using var platform = LinuxPlatform.Open(new DataFolder(temp.Path), new Journal(), "0.1.0");
        platform.MoveLegacyOnlineKey();
        var controller = new NinoController(platform.Services, platform.Secrets, platform.Settings, new NoSleepGuard(),
            TextCatalog.For("tr"), action => action());
        var backend = new CoreBackend(controller, platform, ocrInstalled: false);
        try
        {
            var state = backend.State();
            Assert.Equal("Done", state.Step);
            Assert.True(state.HasAccount);
            Assert.Equal(new PanelDevice("PS5-123", "192.168.0.20"), state.Console);
            Assert.Equal(new PanelTv("Salon TV", "192.168.0.110", "AndroidTv"), state.Tv);
            Assert.Equal(new PanelRegion(0.55, 0.95, 0.1, 0.9), state.Settings.Region);
            Assert.Equal(58, (int)state.Settings.Style["fontSize"]!);
            Assert.Equal("Below", (string?)state.Settings.Style["placement"]);
            Assert.True(state.Settings.OnlineTranslation);
            Assert.Equal("Claude", state.OnlineEngine);
            Assert.True(controller.CanStart);
        }
        finally
        {
            await backend.ShutdownAsync();
        }
    }
}
