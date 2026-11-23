// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell;

// Çeviri yaşam döngüsü (tarif §10): başlat, durdur, oturum durumu, altyazı yeri, uyku bekçisi, TV bekçisi.
public sealed partial class NinoController
{
    bool _translating;
    bool _starting;
    bool _paused;
    IVideoSource? _source;
    long _sourceGen;
    SourceStatus _status = SourceStatus.Down(DisconnectReason.Stopped);
    WindowCaptureState _windowState = WindowCaptureState.Stopped;
    string? _windowApp;
    PixelRect? _gameArea;
    CardStatus _card = new(CardCaptureState.Stopped);
    ITvWatch? _watch;
    bool _sleepActive;
    bool _sessionActive;
    bool _xboxNameRefreshed;
    int _tvCount;
    string? _tvModel;

    // ---- Olaylar (ekranlara) ----

    /// <summary>Masaüstündeki altyazı penceresine giden olay (yalnız bilgisayarda gösterilirken).</summary>
    public event Action<LocalSubtitleEvent>? ComputerOverlayEvent;

    /// <summary>Yayıncı penceresine giden olay (her zaman).</summary>
    public event Action<LocalSubtitleEvent>? StreamWindowEvent;

    /// <summary>Bilgisayar penceresi hemen boşaltılsın.</summary>
    public event Action? ComputerOverlayCleared;

    /// <summary>Yayıncı penceresi hemen boşaltılsın.</summary>
    public event Action? StreamWindowCleared;

    // ---- Okunan durum ----

    /// <summary>Çeviri sürüyor mu.</summary>
    public bool IsTranslating => _translating;

    /// <summary>Çeviri başlatılıyor mu.</summary>
    public bool IsStarting => _starting;

    /// <summary>Çeviri duraklatılmış mı (Num 0).</summary>
    public bool IsPaused => _paused;

    /// <summary>Oturumun durumu.</summary>
    public SourceStatus SessionStatus => _status;

    /// <summary>Oyunun penceresi durumu.</summary>
    public WindowCaptureState WindowState => _windowState;

    /// <summary>Okunan uygulamanın adı.</summary>
    public string? WindowAppName => _windowApp;

    /// <summary>Oyun alanının ekrandaki yeri.</summary>
    public PixelRect? GameArea => _gameArea;

    /// <summary>HDMI yakalama kartı durumu.</summary>
    public CardStatus CardState => _card;

    /// <summary>Tercih edilen yakalama aygıtı.</summary>
    public string? PreferredCardId => _secrets.Get<string>(SecretKeys.CaptureCardId);

    /// <summary>Bağlı TV sayısı.</summary>
    public int ConnectedTvs => _tvCount;

    /// <summary>TV uygulamasının bildirdiği model.</summary>
    public string? TvModel => _tvModel;

    /// <summary>Altyazı sunucusunun portu (açılmadıysa 0).</summary>
    public int ServerPort => _server.Port;

    /// <summary>Oyunun penceresi kullanılıyor mu.</summary>
    public bool UsesGameWindow => _settings.VideoSource == VideoSource.Window;

    /// <summary>Oyunun penceresi (PS5) kullanılıyor mu.</summary>
    public bool UsesPs5GameWindow => UsesGameWindow && _settings.GameConsole == GameConsole.Ps5;

    /// <summary>Oyunun penceresi (Xbox) kullanılıyor mu.</summary>
    public bool UsesXboxGameWindow => UsesGameWindow && _settings.GameConsole == GameConsole.Xbox;

    /// <summary>HDMI yakalama kartı kullanılıyor mu.</summary>
    public bool UsesCaptureCard => _settings.VideoSource == VideoSource.Card;

    /// <summary>Görüntü PS5 yolundan (PS5 / Xbox yayını / Remote Play penceresi / seçilen pencere) mi.</summary>
    public bool OnStreamPath => _settings.VideoSource == VideoSource.Ps5;

    /// <summary>Altyazı TV'de gösteriliyor mu.</summary>
    public bool ShowsOnTv => (!UsesGameWindow || UsesXboxGameWindow) && _settings.Output is SubtitleOutput.Tv or SubtitleOutput.Both;

    /// <summary>Altyazı bilgisayarda gösteriliyor mu.</summary>
    public bool ShowsOnComputer => UsesPs5GameWindow || _settings.Output is SubtitleOutput.Computer or SubtitleOutput.Both;

    /// <summary>"TV bağla" düğmesi: TV'de gösteriliyor ama TV eşleşmemiş.</summary>
    public bool NeedsTv => ShowsOnTv && !TvPaired;

    /// <summary>Kart oynatıcısı görünür mü.</summary>
    public bool CardPlayerVisible => _translating && UsesCaptureCard && ShowsOnComputer;

    bool SourceReady
    {
        get
        {
            if (UsesGameWindow || UsesCaptureCard) return true;
            if (IsXbox) return _xboxToken is not null && _xboxConsole is not null;
            return _settings.FrameSource switch
            {
                FrameSource.RemotePlayWindow => true,
                FrameSource.ChosenWindow => _settings.CaptureWindow is { ProcessName.Length: > 0, Title.Length: > 0 },
                _ => _console is not null && _accountId is not null,
            };
        }
    }

    /// <summary>Çeviri başlatılabilir mi (§10.1).</summary>
    public bool CanStart => UsesPs5GameWindow || (SourceReady && (ShowsOnComputer || TvPaired));

    /// <summary>"Ekran da açık kalsın" (§10.3).</summary>
    internal bool KeepDisplayOn =>
        (!IsXbox && OnStreamPath && _settings.FrameSource != FrameSource.Ps5) || ShowsOnComputer;

    string RouteName() =>
        UsesGameWindow ? "oyun penceresi"
        : UsesCaptureCard ? "yakalama kartı"
        : IsXbox ? "Xbox"
        : _settings.FrameSource == FrameSource.RemotePlayWindow ? "Remote Play penceresi"
        : _settings.FrameSource == FrameSource.ChosenWindow ? "seçilen pencere"
        : "PS5";

    // ---- Başlat (§10.2) ----

    /// <summary>Çeviri oturumunu açar. Hata çağırana fırlatılır (geride oturum kalmaz).</summary>
    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_translating || _starting || !CanStart || _closing) return;

        IGameWindowSource? window = null;
        ICaptureCardSource? card = null;
        if (UsesGameWindow)
        {
            window = _services.CreateGameWindowSource(_settings.GameConsole);
            if (window is null) return;
        }
        else if (UsesCaptureCard)
        {
            card = _services.CreateCaptureCardSource(ShowsOnComputer, PreferredCardId);
            if (card is null) return;
        }
        else if (!IsXbox && _settings.FrameSource == FrameSource.Ps5 && (_console is null || _accountId is null)) return;

        _starting = true;
        Refresh();
        try
        {
            var tvBrand = _tv?.Brand.ToString() ?? "yok";
            _logs.RemotePlay($"Çeviri hazırlanıyor; altyazının gideceği yer: {_settings.Output}, TV: {tvBrand}");
            RefreshTranslatorStatus();
            try { await _server.StartAsync(cancellationToken).ConfigureAwait(false); }
            catch (Exception e) { _logs.Subtitle("altyazı sunucusu açılamadı: " + e.Message); }
            await OnUi();
            SendStyle();
            _paused = false;
            _metricsLine = "";
            BuildPipeline();
            _logs.Subtitle($"oturum başladı: {_settings.SourceLanguage}→{_settings.TargetLanguage}, motor: "
                + $"{(_chain?.OnlineEnabled == true ? _settings.OnlineEngine.ToString() : "ücretsiz")}, paketler: "
                + $"{(PacksEnabled ? "açık" : "kapalı")}, görüntü: {RouteName()}, ağ: {_problems?.Network.Wire() ?? "unknown"}");
            _health.SessionStarted();
            _problems?.SessionStarted();
            _sessionActive = true;
            TmSessionStarted();

            var gen = ++_sourceGen;
            IVideoSource source;
            if (window is not null)
            {
                window.WindowStateChanged += (state, app) => Post(() => { if (gen == _sourceGen) OnWindowState(state, app); });
                window.GameAreaChanged += area => Post(() => { if (gen == _sourceGen) _gameArea = area; });
                source = window;
                _logs.RemotePlay("Çeviri başladı; oyun penceresi okunuyor (" + _settings.GameConsole + ")");
            }
            else if (card is not null)
            {
                card.CardStatusChanged += status => Post(() => { if (gen == _sourceGen) OnCardStatus(status); });
                card.GameAreaChanged += area => Post(() => { if (gen == _sourceGen) _gameArea = area; });
                card.GameWindowClosed += () => Post(() => { if (gen == _sourceGen) Stop(); });
                source = card;
                _logs.RemotePlay("Çeviri başladı; yakalama kartı okunuyor");
            }
            else if (IsXbox)
            {
                if (_services.Xbox is not { } xbox) throw new InvalidOperationException(_text.Get("wizard.xbox.error.unavailable"));
                source = xbox.CreateStream(_xboxConsole!, _xboxToken!, _settings.XboxLegacyFrameRate,
                    _settings.XboxStreamQuality);
                _xboxNameRefreshed = false;
                _logs.RemotePlay("Çeviri başladı; Xbox yayını: " + _xboxConsole!.Name);
            }
            else if (_settings.FrameSource == FrameSource.RemotePlayWindow)
            {
                source = _services.CreateRemotePlayWindowSource(_settings.RemotePlayApp);
                _logs.RemotePlay("Çeviri açıldı; görüntü Remote Play penceresinden alınıyor (" + _settings.RemotePlayApp + ")");
            }
            else if (_settings.FrameSource == FrameSource.ChosenWindow)
            {
                source = _services.CreateChosenWindowSource(_settings.CaptureWindow!);
                _logs.RemotePlay("Çeviri başladı; seçilen pencere okunuyor: " + _settings.CaptureWindow!.Title);
            }
            else
            {
                source = _services.CreatePs5Source(_console!, _accountId!, _secrets.Get<string>(SecretKeys.LoginPasscode));
                _logs.RemotePlay($"Çeviri başladı; PS5: {_console!.Name} ({_console.Host})");
            }
            source.StatusChanged += s => Post(() => { if (gen == _sourceGen) OnSourceStatus(s); });
            source.ConsoleMoved += c => Post(() => { if (gen == _sourceGen) SaveConsole(c); });
            source.FrameArrived += f => OnFrame(gen, f);
            _source = source;
            _status = SourceStatus.Connecting;
            source.Start();

            EnsureTvWatch();
            StartGameDetection();

            _sleep.Begin(KeepDisplayOn);
            _sleepActive = true;
            _translating = true;
            _translationFailing = false;
            _server.Send(new TranslationStarted());
            UpdateFirewallClocks();
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.RemotePlay($"Çeviri başlatılamadı: {e.GetType().Name}: {e.Message}");
            if (_source is null)
            {
                try { window?.Dispose(); } catch (Exception) { }
                try { card?.Dispose(); } catch (Exception) { }
            }
            Stop();
            throw;
        }
        finally
        {
            _starting = false;
            Refresh();
        }
    }

    /// <summary>Başlat ya da durdur (aç/kapat düğmesi). Başlatma hatası günlüğe yazılır, yutulur.</summary>
    public async Task ToggleAsync()
    {
        if (_translating) Stop();
        else
        {
            try { await StartAsync().ConfigureAwait(false); }
            catch (Exception) { }
            await OnUi();
        }
    }

    // ---- Durdur (§10.5) ----

    /// <summary>Çeviri oturumunu kapatır.</summary>
    public void Stop()
    {
        TmTvWatchStopped();
        var source = _source;
        _source = null;
        _sourceGen++;
        if (source is not null)
        {
            try { source.Stop(); } catch (Exception e) { _logs.Error("Kaynak durdurulamadı", e); }
            try { source.Dispose(); } catch (Exception) { }
        }
        StopPs5GamePoll();
        StopGameDetection();
        StopPoolSync();
        try { _services.Pool?.Save(); } catch (Exception) { }
        StopTvWatch();

        if (_sessionActive)
        {
            _sessionActive = false;
            TmSessionEnded();
            _health.SessionEnded();
            _problems?.SessionEnded();
            var network = _problems?.Network ?? NetworkKind.Unknown;
            _logs.Subtitle(HealthSummary.LogPrefix + string.Join(" · ", HealthSummary.Lines(_health.Snapshot(), network)));
            _logs.Subtitle("oturum bitti");
        }
        ResetPipeline();
        _gate.Reset();
        _readerForExtras = null;
        _screenCancel?.Cancel();
        _screenCancel = null;
        if (_screenShownUntil is not null)
        {
            _server.Send(new ScreenCleared());
            _screenShownUntil = null;
        }
        _paused = false;
        _activeLanguage = null;
        _onlineProblem = null;
        if (_sleepActive)
        {
            _sleep.End();
            _sleepActive = false;
        }
        var was = _translating;
        _translating = false;
        if (was) _server.Send(new TranslationStopped());
        if (_pendingUpdate && !_closing && CanAutoInstall()) Background(() => InstallUpdateAsync(automatic: true));

        _status = SourceStatus.Down(DisconnectReason.Stopped);
        _windowState = WindowCaptureState.Stopped;
        _windowApp = null;
        _card = new CardStatus(CardCaptureState.Stopped);
        _gameArea = null;
        UpdateFirewallClocks();
        _ruleSeen = false;
        if (_firewall != FirewallHint.Working) _firewall = FirewallHint.None;
        ComputerOverlayCleared?.Invoke();
        StreamWindowCleared?.Invoke();
        Refresh();
    }

    async Task RestartAsync()
    {
        if (!_translating) return;
        Stop();
        try { await StartAsync().ConfigureAwait(false); }
        catch (Exception e) { _logs.RemotePlay("Çeviri yeniden başlatılamadı: " + e.Message); }
        await OnUi();
    }

    /// <summary>Bilgisayar uykudan uyandı: oturuma ve bekçiye "yeniden bağlan".</summary>
    public void SystemResumed()
    {
        _diag?.SystemWoke();
        try { _source?.ReconnectNow(); } catch (Exception e) { _logs.Error("Yeniden bağlanılamadı", e); }
        try { _watch?.ReconnectNow(); } catch (Exception) { }
    }

    /// <summary>Kart oynatıcısını tam ekrana alır ya da çıkarır.</summary>
    public void ToggleCardFullScreen()
    {
        if (_source is ICaptureCardSource card) card.ToggleFullScreen();
    }

    /// <summary>Tercih edilen yakalama aygıtını kaydeder (boşsa silinir).</summary>
    public void SetPreferredCard(string? deviceId)
    {
        if (string.IsNullOrWhiteSpace(deviceId)) _secrets.Remove(SecretKeys.CaptureCardId);
        else _secrets.Set(SecretKeys.CaptureCardId, deviceId.Trim());
        Refresh();
    }

    // ---- Oturum durumu (§10.6) ----

    void OnSourceStatus(SourceStatus status)
    {
        var old = _status;
        if (OnStreamPath && old.Phase != status.Phase)
        {
            TmSourceStatus(old, status);
            var title = IsXbox ? "Xbox" : _settings.FrameSource == FrameSource.ChosenWindow ? "seçilen pencere" : "PS5";
            _logs.Subtitle(title + ": " + status.Phase switch
            {
                SourcePhase.Connecting => "bağlanıyor",
                SourcePhase.Streaming => "bağlandı",
                _ => "bağlantı yok",
            });
            switch (status.Phase)
            {
                case SourcePhase.Connecting:
                    _health.Connecting();
                    break;
                case SourcePhase.Streaming:
                    _health.PictureArrived();
                    _problems?.Ps5Back();
                    break;
                default:
                    if (status.Reason is { } r && r != DisconnectReason.Stopped)
                    {
                        _health.Disconnected(r.ToString());
                        _problems?.Ps5Dropped(r.ToString(), old.Phase == SourcePhase.Streaming);
                    }
                    break;
            }
        }
        _status = status;
        UpdateFirewallClocks();
        if (!IsXbox)
        {
            if (status.Phase == SourcePhase.Streaming) StartPs5GamePoll();
            else StopPs5GamePoll();
        }
        else if (status.Phase == SourcePhase.Streaming && !_xboxNameRefreshed)
        {
            _xboxNameRefreshed = true;
            Background(RefreshXboxNameAsync);
        }
        if (status.Phase == SourcePhase.Disconnected && status.Reason != DisconnectReason.Stopped)
        {
            ResetReaders();
            _server.Send(new SubtitleCleared());
        }
    }

    async Task RefreshXboxNameAsync()
    {
        if (_services.Xbox is not { } xbox || _xboxToken is not { } token) return;
        try
        {
            var list = await xbox.FindConsolesAsync(token).ConfigureAwait(false);
            await OnUi();
            FixXboxName(list);
            Refresh();
        }
        catch (Exception) { }
    }

    void OnWindowState(WindowCaptureState state, string? app)
    {
        if (state == _windowState && app == _windowApp) return;
        _windowState = state;
        _windowApp = app;
        _logs.Subtitle("oyun penceresi: " + state switch
        {
            WindowCaptureState.Capturing => $"okunuyor ({app})",
            WindowCaptureState.LookingForWindow => "bulunamadı",
            _ => "durdu",
        });
    }

    void OnCardStatus(CardStatus status)
    {
        if (status == _card) return;
        _card = status;
        if (status.State == CardCaptureState.NeedsPermission) RecordErrorCode("app.capture.denied");
        _logs.Subtitle("yakalama kartı: " + status.State switch
        {
            CardCaptureState.NeedsPermission => "kamera izni yok",
            CardCaptureState.NoCard => "bulunamadı",
            CardCaptureState.BlackPicture => $"görüntü siyah ({status.DeviceName})",
            CardCaptureState.Capturing => $"okunuyor ({status.DeviceName})",
            _ => "durdu",
        });
    }

    // ---- Altyazı yeri (§10.3) ----

    void OnOutputChanged()
    {
        _server.SendToTv = ShowsOnTv;
        if (!ShowsOnComputer)
        {
            _adjustMode = false;
            ComputerOverlayCleared?.Invoke();
        }
        UpdateFirewallClocks();
        if (!_translating) return;
        _sleep.Begin(KeepDisplayOn);
        _sleepActive = true;
        if (ShowsOnTv) EnsureTvWatch();
        else StopTvWatch();
    }

    // ---- TV bekçisi (§10.4) ----

    void EnsureTvWatch()
    {
        if (_watch is not null || !ShowsOnTv || !TvPaired || _tv is not { } tv) return;
        var key = _secrets.Get<string>(SecretKeys.TvKey) ?? "";
        var watch = _services.CreateTvWatch(new TvWatchRequest(tv, key,
            () => _server.LaunchParameters(_services.AddressNear(_tv?.Host)),
            () => _server.TvCount > 0,
            moved => Post(() => OnTvMoved(moved)),
            newKey => Post(() => SaveTvKey(newKey)),
            TimeSpan.FromSeconds(5)));
        _watch = watch;
        TmTvWatchStarted();
        watch.Start();
        if (tv.Brand == TvBrand.AndroidTv) _server.ConnectAndroidTv(tv.Host.Length > 0 ? tv.Host : null);
        Background(RecheckTvAppAsync);
    }

    void StopTvWatch()
    {
        TmTvWatchStopped();
        var watch = _watch;
        _watch = null;
        try { watch?.Stop(); } catch (Exception) { }
        if (watch is not null && _tv?.Brand == TvBrand.AndroidTv) _server.DisconnectAndroidTv();
    }

    void SaveTvKey(string key)
    {
        var stored = TvRecord.KeyToStore(_secrets.Get<string>(SecretKeys.TvKey), key);
        _secrets.Set(SecretKeys.TvKey, stored);
    }

    void OnTvMoved(TvRecord moved)
    {
        if (_tv is null) return;
        SaveTv(moved);
    }

    void OnTvCountChanged(int count)
    {
        _tvCount = count;
        UpdateFirewallClocks();
        _problems?.TvCountChanged(count);
    }

    // ---- Sunucunun yerel olayları (§14) ----

    void OnServerLocalEvent(LocalSubtitleEvent e) => Post(() =>
    {
        StreamWindowEvent?.Invoke(e);
        if (ShowsOnComputer) ComputerOverlayEvent?.Invoke(e);
    });

    void SendStyle()
    {
        try { _server.Send(new StyleChanged(TvStyle.From(_settings.Style))); }
        catch (Exception e) { _logs.Error("Biçem gönderilemedi", e); }
    }
}
