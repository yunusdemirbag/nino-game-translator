// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Settings;
using Nino.Core.Support;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell;

// Güvenlik duvarı önerisi (§16), uygulama güncellemesi (§17), sorun bekçisi ve cihaz bilgisi.
public sealed partial class NinoController
{
    FirewallHint _firewall;
    bool _ruleSeen;
    bool _firewallChecking;
    DateTimeOffset? _ps5ProblemSince;
    DateTimeOffset? _tvWaitSince;

    string? _updateVersion;
    bool _updating;
    double _updateProgress;
    string? _updateError;
    bool _pendingUpdate;
    int _abortedAutoDownloads;
    IDisposable? _updateTimer;
    AutoUpdateAttempts? _attempts;

    readonly ProblemWatcher? _problems;

    /// <summary>Güvenlik duvarı önerisi.</summary>
    public FirewallHint Firewall => _firewall;

    static readonly TimeSpan Ps5FirewallAfter = TimeSpan.FromSeconds(20);
    static readonly TimeSpan TvFirewallAfter = TimeSpan.FromSeconds(60);

    void UpdateFirewallClocks()
    {
        var now = _timers.Now;
        var ps5Problem = !IsXbox && _translating && OnStreamPath && _status.Phase != SourcePhase.Streaming
            && !(_status.Reason is { } r && SessionRules.ExcludesFirewallHint(r));
        if (ps5Problem) _ps5ProblemSince ??= now;
        else _ps5ProblemSince = null;
        var tvWait = _translating && ShowsOnTv && TvPaired && _tvCount == 0;
        if (tvWait) _tvWaitSince ??= now;
        else _tvWaitSince = null;
    }

    /// <summary>Bağlantıları denetler (ana ekran birkaç saniyede bir çağırır).</summary>
    public async Task CheckConnectionsAsync()
    {
        UpdateFirewallClocks();
        if (!_translating || _services.Firewall is not { } fw) return;
        if (_ps5ProblemSince is null && _tvWaitSince is null)
        {
            if (_firewall != FirewallHint.Working && _firewall != FirewallHint.Allowed) _firewall = FirewallHint.None;
            Refresh();
            return;
        }
        var now = _timers.Now;
        var due = (_ps5ProblemSince is { } p && now - p >= Ps5FirewallAfter) || (_tvWaitSince is { } t && now - t >= TvFirewallAfter);
        if (!due || _firewall != FirewallHint.None || _ruleSeen || _firewallChecking) return;
        _firewallChecking = true;
        var session = _sourceGen;
        try
        {
            var hint = await FindFirewallProblemAsync(fw).ConfigureAwait(false);
            await OnUi();
            if (!_translating || session != _sourceGen) return;
            if (hint == FirewallHint.None) _ruleSeen = true;
            else _firewall = hint;
        }
        finally
        {
            _firewallChecking = false;
            Refresh();
        }
    }

    static async Task<FirewallHint> FindFirewallProblemAsync(IFirewall fw)
    {
        bool rule;
        try { rule = await fw.HasPrivateRuleAsync().ConfigureAwait(false); }
        catch (Exception) { rule = false; }
        if (!rule) return FirewallHint.Suggest;
        bool publicNet;
        try { publicNet = await fw.IsOnPublicNetworkAsync().ConfigureAwait(false); }
        catch (Exception) { publicNet = false; }
        return publicNet ? FirewallHint.PublicNetwork : FirewallHint.None;
    }

    async Task CheckFirewallAfterPairingAsync()
    {
        if (_services.Firewall is not { } fw) return;
        var hint = await FindFirewallProblemAsync(fw).ConfigureAwait(false);
        await OnUi();
        if (_firewall != FirewallHint.Working) _firewall = hint;
        Refresh();
    }

    /// <summary>"İzin ver": yönetici izniyle kuralı ekler.</summary>
    public async Task<bool> AllowFirewallAsync()
    {
        if (_services.Firewall is not { } fw || _firewall == FirewallHint.Working) return false;
        _firewall = FirewallHint.Working;
        Refresh();
        bool added;
        try { added = await fw.AddRuleAsync().ConfigureAwait(false); }
        catch (Exception) { added = false; }
        await OnUi();
        _firewall = added ? FirewallHint.Allowed : FirewallHint.Failed;
        if (added)
        {
            _ruleSeen = true;
            if (_translating)
            {
                try { _source?.ReconnectNow(); } catch (Exception) { }
                try { _watch?.ReconnectNow(); } catch (Exception) { }
            }
        }
        Refresh();
        return added;
    }

    /// <summary>Ayarlar ekranının güvenlik duvarı bilgisi (hizmet yoksa null).</summary>
    public async Task<FirewallInfo?> FirewallInfoAsync()
    {
        if (_services.Firewall is not { } fw) return null;
        bool rule, publicNet;
        try { rule = await fw.HasPrivateRuleAsync().ConfigureAwait(false); } catch (Exception) { rule = false; }
        try { publicNet = await fw.IsOnPublicNetworkAsync().ConfigureAwait(false); } catch (Exception) { publicNet = false; }
        await OnUi();
        return new FirewallInfo(rule, publicNet);
    }

    // ---- Güncelleme (§17) ----

    /// <summary>Bulunan yeni sürüm.</summary>
    public string? UpdateVersion => _updateVersion;

    /// <summary>Güncelleniyor mu.</summary>
    public bool Updating => _updating;

    /// <summary>Güncelleme ilerlemesi (0–1).</summary>
    public double UpdateProgress => _updateProgress;

    /// <summary>Güncelleme hatası.</summary>
    public string? UpdateError => _updateError;

    /// <summary>Kendini güncelleyebilir mi.</summary>
    public bool CanSelfUpdate => _services.Updater?.CanSelfUpdate ?? false;

    AutoUpdateAttempts Attempts => _attempts ??= new AutoUpdateAttempts(_services.AutoUpdateCounterPath);

    bool CanAutoInstall() => _updateVersion is { } v && CanSelfUpdate && !Attempts.Exhausted(v) && _abortedAutoDownloads < 3;

    /// <summary>Güncellemeyi denetler (açılışta, sonra 3 saatte bir).</summary>
    public async Task CheckForUpdateAsync()
    {
        if (_services.Updater is not { } updater) return;
        _updateTimer ??= _timers.Every(TimeSpan.FromHours(3), () => Post(() => Background(CheckForUpdateAsync)));
        string? version;
        try { version = await updater.FindNewerAsync().ConfigureAwait(false); }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or InvalidOperationException)
        {
            _updateCheckFailed = true;
            return;
        }
        await OnUi();
        _updateVersion = version;
        Refresh();
        if (_closing || version is null || !CanAutoInstall()) return;
        if (_translating) _pendingUpdate = true;
        else await InstallUpdateAsync(automatic: true).ConfigureAwait(false);
    }

    /// <summary>Güncellemeyi kur ("Güncelle" düğmesi ya da kendiliğinden).</summary>
    public async Task InstallUpdateAsync(bool automatic = false)
    {
        if (_services.Updater is not { } updater || _updating || (automatic && _closing)) return;
        if (!updater.CanSelfUpdate)
        {
            _browser.Open(updater.DownloadPage);
            return;
        }
        _pendingUpdate = false;
        _updating = true;
        _updateError = null;
        _updateProgress = 0;
        if (_translating) Stop();
        Refresh();
        var version = _updateVersion ?? "";
        var reachedInstall = false;
        try
        {
            await updater.DownloadAndInstallAsync(new Progress(p => Post(() => _updateProgress = p)), () =>
            {
                reachedInstall = true;
                if (!Attempts.Record(version) && automatic)
                    throw new IOException(_text.Get("update.error.counterNotSaved"));
                // Kurulum uygulamayı kapatıp yeniden açar: bu çıkış çökme sayılmasın.
                _telemetry?.Exiting();
            }).ConfigureAwait(false);
            await OnUi();
        }
        catch (Exception e)
        {
            await OnUi();
            if (reachedInstall) _telemetry?.ExitCancelled(_services.AppVersion);
            RecordErrorCode("app.update.failed");
            _updateError = _text.Format("update.error.failed", e.Message);
            if (automatic && !reachedInstall) _abortedAutoDownloads++;
        }
        finally
        {
            _updating = false;
            Refresh();
        }
    }

    // ---- Sorun bekçisi ----

    ProblemWatcher? CreateProblemWatcher(Func<TimeSpan, CancellationToken, Task>? delay)
    {
        try
        {
            var folder = _services.HealthFolder;
            var log = ProblemLog.InFolder(folder);
            var reporter = folder is null ? null : AutoReporter.InFolder(folder, (b, ct) => _services.SendReportAsync(b, ct));
            var network = _services.NetworkWatch ?? new FixedNetwork();
            var watcher = new ProblemWatcher(new ProblemHost(this), _health, log, reporter, network, folder is not null, delay);
            watcher.Start();
            return watcher;
        }
        catch (Exception e)
        {
            _logs.Error("Sorun bekçisi kurulamadı", e);
            return null;
        }
    }

    sealed class FixedNetwork : INetworkWatch
    {
        public NetworkKind Read() => NetworkKind.Unknown;

        public event Action? Changed { add { } remove { } }
    }

    sealed class ProblemHost(NinoController owner) : IProblemWatcherHost
    {
        public bool IsTranslating => owner._translating;

        public bool IsPictureArriving => owner._status.Phase == SourcePhase.Streaming;

        public bool IsSendingToTv => owner.ShowsOnTv;

        public int ConnectedTvs => owner._tvCount;

        public bool AutoReportEnabled => owner._settings.AutoReport;

        public string? Game => owner.PlayingGame;

        public string? CauseTitle(NetworkKind network) => HealthCauses.FirstTitle(owner._health.Snapshot(), network, owner._text);

        public ReportBody? BuildAutoReport(string text)
        {
            if (owner._services.HealthFolder is not { } folder) return null;
            var install = InstallIdFile.ReadOrCreateReportId(Path.Combine(folder, InstallIdFile.ReportFileName),
                owner._services.Pool?.InstallId);
            return new ReportBody
            {
                Install = install,
                App = owner._services.AppVersion,
                Language = owner._settings.TargetLanguage,
                Text = text,
                Device = DeviceInfo.Summary(owner.DeviceInfoLines()),
                Kind = ReportBody.AutoKind,
            };
        }

        public void Log(string line) => owner._logs.Subtitle(line);

        public void ProblemsChanged() => owner.Post(() => owner.ProblemsChanged?.Invoke());

        public void Post(Action action) => owner.Post(action);
    }

    /// <summary>Sorun listesi değişti.</summary>
    public event Action? ProblemsChanged;

    /// <summary>Sorun bekçisi (Sağlık sayfası ve sorun bildirme kullanır).</summary>
    [NotObserved]
    public ProblemWatcher? Problems => _problems;

    // ---- Cihaz bilgisi ----

    /// <summary>Cihaz bilgisi satırları (<c>app, device, system, tv, console, status</c>).</summary>
    public IReadOnlyList<DeviceInfoLine> DeviceInfoLines()
    {
        var (device, system) = _services.DeviceAndSystem;
        var tv = DeviceLines.Tv(_tv?.Brand, _tvModel, _tvApp.Version, _secrets.Get<string>(SecretKeys.TvAppVersion), _tvCount > 0);
        var route = UsesCaptureCard ? ConsoleRoute.CaptureCard
            : UsesGameWindow ? ConsoleRoute.GameWindow
            : IsXbox ? ConsoleRoute.XboxStream
            : _settings.FrameSource == FrameSource.RemotePlayWindow ? ConsoleRoute.RemotePlayWindow
            : _settings.FrameSource == FrameSource.ChosenWindow ? ConsoleRoute.ChosenWindow
            : ConsoleRoute.Ps5RemotePlay;
        var console = DeviceLines.Console(route, _settings.GameConsole, _xboxConsole?.Model, _settings.RemotePlayApp);
        var last = _health.Snapshot().LastReason;
        var game = PlayingGame;
        var status = UsesGameWindow ? DeviceLines.StatusForWindow(_translating, _windowState.ToString(), last, game)
            : UsesCaptureCard ? DeviceLines.StatusForCard(_translating, _card.State.ToString(), last, game)
            : DeviceLines.StatusForStream(_translating, IsXbox ? "Xbox" : "PS5", _status.Phase switch
            {
                SourcePhase.Streaming => "Streaming",
                SourcePhase.Connecting => "Connecting",
                _ => "Disconnected",
            }, _status.Reason is { } why && why != DisconnectReason.Stopped ? why.ToString() : null, _status.Detail, last, game);
        return DeviceLines.Lines(_services.AppVersion, device, system, tv, console, status);
    }
}
