// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

// Güvenlik duvarı (§16) ve güncelleme (§17) örnekleri.
public sealed class FirewallUpdateTests
{
    static (World W, NinoController C, FakeFirewall F) Running(bool rule = false, bool isPublic = false)
    {
        var w = new World().WithPs5().WithTv();
        var f = new FakeFirewall { Rule = rule, Public = isPublic };
        w.Services.FirewallService = f;
        var c = w.Open();
        return (w, c, f);
    }

    [Fact]
    public async Task Ps5DropCountsAfterTwentySeconds()
    {
        var (w, c, _) = Running();
        await c.StartAsync();
        w.Services.Server.SetTvCount(1);
        var s = w.Services.Ps5Sessions[0];
        s.Status(SourceStatus.Down(DisconnectReason.Network));
        w.Timers.Advance(TimeSpan.FromSeconds(19));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c.Firewall);
        w.Timers.Advance(TimeSpan.FromSeconds(2));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.Suggest, c.Firewall);
    }

    [Fact]
    public async Task ConnectingThenStreamingClears()
    {
        var (w, c, _) = Running();
        await c.StartAsync();
        w.Services.Server.SetTvCount(1);
        w.Services.Ps5Sessions[0].Status(SourceStatus.Connecting);
        w.Timers.Advance(TimeSpan.FromSeconds(30));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.Suggest, c.Firewall);
        w.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c.Firewall);
    }

    [Fact]
    public async Task TvWaitSixtySeconds()
    {
        var (w, c, _) = Running();
        await c.StartAsync();
        w.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        w.Timers.Advance(TimeSpan.FromSeconds(50));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c.Firewall);
        w.Timers.Advance(TimeSpan.FromSeconds(11));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.Suggest, c.Firewall);

        var (w2, c2, f2) = Running(rule: true, isPublic: true);
        await c2.StartAsync();
        w2.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        w2.Timers.Advance(TimeSpan.FromSeconds(61));
        await c2.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.PublicNetwork, c2.Firewall);

        var (w3, c3, f3) = Running(rule: true);
        await c3.StartAsync();
        w3.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        w3.Timers.Advance(TimeSpan.FromSeconds(61));
        await c3.CheckConnectionsAsync();
        await c3.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c3.Firewall);
        Assert.Equal(1, f3.Scans);
    }

    [Fact]
    public async Task AsleepIsNotAFirewallProblem()
    {
        var (w, c, f) = Running();
        await c.StartAsync();
        w.Services.Server.SetTvCount(1);
        w.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.ConsoleAsleep));
        w.Timers.Advance(TimeSpan.FromSeconds(120));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c.Firewall);
        Assert.Equal(0, f.Scans);
    }

    [Fact]
    public async Task AllowReconnectsAndStays()
    {
        var (w, c, _) = Running();
        await c.StartAsync();
        w.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.Network));
        w.Timers.Advance(TimeSpan.FromSeconds(61));
        await c.CheckConnectionsAsync();
        Assert.True(await c.AllowFirewallAsync());
        Assert.Equal(FirewallHint.Allowed, c.Firewall);
        Assert.Equal(1, w.Services.Ps5Sessions[0].Reconnects);
        Assert.Equal(1, w.Services.Watches[0].Reconnects);
        w.Timers.Advance(TimeSpan.FromSeconds(120));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.Allowed, c.Firewall);
        c.Stop();
        Assert.Equal(FirewallHint.None, c.Firewall);
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c.Firewall);
    }

    [Fact]
    public async Task PairingFailureChecksFirewall()
    {
        var w = new World();
        var f = new FakeFirewall();
        w.Services.FirewallService = f;
        w.Secrets.Set(SecretKeys.AccountId, World.Account);
        var c = w.Open();
        w.Services.RegisterError = new PairingException(PairingOutcome.Failed, 0, null);
        await c.PairPs5Async("192.168.1.253", "12345678");
        Assert.Equal(FirewallHint.Suggest, c.Firewall);

        f.Rule = true;
        await c.PairPs5Async("192.168.1.253", "12345678");
        Assert.Equal(FirewallHint.None, c.Firewall);
        f.Public = true;
        await c.PairPs5Async("192.168.1.253", "12345678");
        Assert.Equal(FirewallHint.PublicNetwork, c.Firewall);

        f.Rule = false;
        f.Public = false;
        var scans = f.Scans;
        w.Services.RegisterError = new PairingException(PairingOutcome.WrongAccount, 0, null);
        await c.PairPs5Async("192.168.1.253", "12345678");
        w.Services.RegisterError = new PairingException(PairingOutcome.BadAddress, 0, null);
        await c.PairPs5Async("192.168.1.253", "12345678");
        Assert.Equal(scans, f.Scans);

        w.Services.RegisterError = new System.Net.Sockets.SocketException(10051);
        await c.PairPs5Async("192.168.1.253", "12345678");
        Assert.Equal(FirewallHint.Suggest, c.Firewall);
        Assert.Contains(new System.Net.Sockets.SocketException(10051).Message, c.PairError);

        Assert.True(await c.AllowFirewallAsync());
        Assert.Equal(FirewallHint.Allowed, c.Firewall);
        c.GoToStep(SetupStep.Tv);
        Assert.Equal(FirewallHint.None, c.Firewall);

        f.Allow = false;
        f.Rule = false;
        await c.PairPs5Async("192.168.1.253", "12345678");
        Assert.False(await c.AllowFirewallAsync());
        Assert.Equal(FirewallHint.Failed, c.Firewall);

        var w2 = new World();
        w2.Secrets.Set(SecretKeys.AccountId, World.Account);
        w2.Services.RegisterError = new PairingException(PairingOutcome.Failed, 0, null);
        var c2 = w2.Open();
        await c2.PairPs5Async("192.168.1.253", "12345678");
        Assert.Equal(FirewallHint.None, c2.Firewall);
        Assert.False(await c2.AllowFirewallAsync());
    }

    [Fact]
    public async Task ComputerOnlyNeverSuggestsForTv()
    {
        var w = new World(new AppSettings { Output = SubtitleOutput.Computer }).WithPs5().WithTv();
        w.Services.FirewallService = new FakeFirewall();
        var c = w.Open();
        await c.StartAsync();
        w.Services.Ps5Sessions[0].Status(SourceStatus.Streaming);
        w.Timers.Advance(TimeSpan.FromMinutes(5));
        await c.CheckConnectionsAsync();
        Assert.Equal(FirewallHint.None, c.Firewall);
    }

    sealed class FakeUpdater : IAppUpdater
    {
        public string? Newer = "9.9.9";
        public bool CanSelfUpdate { get; set; } = true;
        public string DownloadPage => "https://example.org/download";
        public int Installs;
        public Exception? DownloadError;
        public Task<string?> FindNewerAsync(CancellationToken cancellationToken = default) => Task.FromResult(Newer);

        public Task DownloadAndInstallAsync(IProgress<double> progress, Action beforeInstall, CancellationToken cancellationToken = default)
        {
            progress.Report(0.5);
            if (DownloadError is not null) throw DownloadError;
            beforeInstall();
            Installs++;
            return Task.CompletedTask;
        }
    }

    sealed class UpdateServices(FakeUpdater updater) : IShellServicesDecorator(new FakeServices())
    {
        public override IAppUpdater? Updater => updater;
    }

    [Fact]
    public async Task UpdateRules()
    {
        var updater = new FakeUpdater();
        var w = new World().WithPs5().WithTv();
        var services = new UpdateServices(updater);
        var c = new NinoController(services, w.Secrets, w.SettingsStore, w.Sleep, w.Text, a => a(),
            new ShellOptions { Timers = w.Timers, Browser = w.Browser });
        await c.CheckForUpdateAsync();
        Assert.Equal(1, updater.Installs);
        Assert.Equal("9.9.9", c.UpdateVersion);
        await c.CheckForUpdateAsync();
        Assert.Equal(2, updater.Installs);
        await c.CheckForUpdateAsync();
        Assert.Equal(2, updater.Installs);
        await c.InstallUpdateAsync();
        Assert.Equal(3, updater.Installs);

        // Çeviri sürerken bulunan güncelleme durunca kurulur.
        var updater2 = new FakeUpdater();
        var services2 = new UpdateServices(updater2);
        var c2 = new NinoController(services2, new MemorySecretStore(), new MemorySettingsStore(new AppSettings { VideoSource = VideoSource.Window, Output = SubtitleOutput.Computer }),
            new FakeSleep(), w.Text, a => a(), new ShellOptions { Timers = new ManualTimers() });
        await c2.StartAsync();
        await c2.CheckForUpdateAsync();
        Assert.Equal(0, updater2.Installs);
        c2.Stop();
        await c2.WhenIdleAsync();
        Assert.Equal(1, updater2.Installs);

        // İndirme hatası hak tüketmez; üç yarıda kalan indirmeden sonra kendiliğinden denenmez.
        var updater3 = new FakeUpdater { DownloadError = new HttpRequestException("ağ") };
        var c3 = new NinoController(new UpdateServices(updater3), new MemorySecretStore(), new MemorySettingsStore(),
            new FakeSleep(), w.Text, a => a(), new ShellOptions { Timers = new ManualTimers() });
        for (var i = 0; i < 3; i++) await c3.CheckForUpdateAsync();
        Assert.NotNull(c3.UpdateError);
        updater3.DownloadError = null;
        await c3.CheckForUpdateAsync();
        Assert.Equal(0, updater3.Installs);
        await c3.InstallUpdateAsync();
        Assert.Equal(1, updater3.Installs);

        // Zip kopyasında yalnız sayfa açılır.
        var updater4 = new FakeUpdater { CanSelfUpdate = false };
        var browser = new FakeBrowser();
        var c4 = new NinoController(new UpdateServices(updater4), new MemorySecretStore(), new MemorySettingsStore(),
            new FakeSleep(), w.Text, a => a(), new ShellOptions { Timers = new ManualTimers(), Browser = browser });
        await c4.InstallUpdateAsync();
        Assert.Equal(["https://example.org/download"], browser.Opened);
        Assert.Equal(0, updater4.Installs);
    }
}

/// <summary>Bir hizmeti sarıp tek tek üyeleri değiştirmeye yarar.</summary>
class IShellServicesDecorator(IShellServices inner) : IShellServices
{
    public Task<IReadOnlyList<FoundPs5>> FindPs5Async(string? host, CancellationToken cancellationToken = default) => inner.FindPs5Async(host, cancellationToken);
    public Task<byte[]> AccountIdFromRedirectAsync(string redirectUrl, CancellationToken cancellationToken = default) => inner.AccountIdFromRedirectAsync(redirectUrl, cancellationToken);
    public Task<Ps5Console> RegisterPs5Async(string host, byte[] accountId, uint pin, CancellationToken cancellationToken = default) => inner.RegisterPs5Async(host, accountId, pin, cancellationToken);
    public IVideoSource CreatePs5Source(Ps5Console console, byte[] accountId, string? loginPasscode) => inner.CreatePs5Source(console, accountId, loginPasscode);
    public IGameWindowSource? CreateGameWindowSource(GameConsole console) => inner.CreateGameWindowSource(console);
    public ISubtitleServer CreateSubtitleServer(Action<string> subtitleLog) => inner.CreateSubtitleServer(subtitleLog);
    public Task<IReadOnlyList<Nino.Core.Tv.FoundTv>> FindTvsAsync(CancellationToken cancellationToken = default) => inner.FindTvsAsync(cancellationToken);
    public Task<Nino.Core.Tv.PairResult> PairTvAsync(Nino.Core.Tv.TvRecord tv, string? savedKey, string launchParameters, CancellationToken cancellationToken = default) => inner.PairTvAsync(tv, savedKey, launchParameters, cancellationToken);
    public ITvWatch CreateTvWatch(TvWatchRequest request) => inner.CreateTvWatch(request);
    public ITextReaderFactory Readers => inner.Readers;
    public IFreeModel FreeModel => inner.FreeModel;
    public Nino.Core.Translation.ITranslatorFactory Translators => inner.Translators;
    public virtual IAppUpdater? Updater => inner.Updater;
}
