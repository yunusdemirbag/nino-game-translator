// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using Nino.Core.Diagnostics;
using Nino.Core.Health;
using Nino.Core.Library;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.RemotePlay;
using TvKind = Nino.Core.Tv.TvBrand;

namespace Nino.Shell;

// Otomatik teşhis (otomatik-teshis.md): bekçi Nino.Core'da; burada denetleyicinin olayları iz adımına ve bekçi
// girdisine çevrilir, bildirim ölçüm kuyruğuna gider. Kapatma düğmesi yok (ölçümün parçası); sunucu telemetry.diag ile
// kural kural kapatır. Yalnız kod ve sayı; ad, adres, metin asla.
public sealed partial class NinoController
{
    DiagnosticsWatcher? _diag;
    DiagHeartbeat? _heartbeat;
    IDisposable? _diagTimer;
    IResourceProbe? _probe;
    long _dgFrames;
    DateTimeOffset _dgFpsSince;
    int _dgTicks;
    int _dgRetries;
    bool _dgPs5Dropped;
    string? _dgProto;
    double? _dgLuma;
    ulong _dgPrint;
    int _dgSamePrints;
    // İzleyici iş parçacığı (zamanlayıcı) ile arayüz arasında: yalnız Volatile/Interlocked.
    long _dgPingSentTicks;
    long _dgUiSeenTicks;
    int _dgPingOut;
    int _dgHangSent;
    int _dgStuck;

    /// <summary>Teşhis bekçisi (ölçüm kurulmadıysa null).</summary>
    [NotObserved]
    public DiagnosticsWatcher? Diagnostics => _diag;

    void OpenDiagnostics(ShellTelemetry telemetry, TelemetrySetup setup)
    {
        try
        {
            var clock = new ShellClock(_timers);
            var diag = new DiagnosticsWatcher(new DiagOptions
            {
                Clock = clock,
                State = DgHostState,
                Tv = DgTv,
                Game = () => GameIds.FromName(_game.Current?.Name),
                Versions = () => new Dictionary<string, string?>
                {
                    ["core"] = _services.AppVersion,
                    ["tvApp"] = _tvApp.Version,
                },
                Limits = new DiagDailyLimits(Path.Combine(setup.Folder, DiagDailyLimits.FileName)),
            });
            _diag = diag;
            diag.Reported += r =>
            {
                if (r.ToTelemetryEvent() is { } e) Record(e);
            };
            Action<string> onConfig = json => diag.ApplyRemoteConfigJson(json);
            telemetry.Client.RemoteConfigReceived += onConfig;
            _subscriptions.Add(new Unsubscribe(() => telemetry.Client.RemoteConfigReceived -= onConfig));

            _heartbeat = new DiagHeartbeat(Path.Combine(setup.Folder, DiagHeartbeat.FileName));
            if (_heartbeat.TakePrevious() is { } blocked) diag.PreviousRunHung(blocked);

            if (_services.NetworkWatch is { } network)
            {
                diag.NetworkChanged(NetCode(network.Read()));
                Action onNet = () => Post(() => _diag?.NetworkChanged(NetCode(network.Read())));
                network.Changed += onNet;
                _subscriptions.Add(new Unsubscribe(() => network.Changed -= onNet));
            }

            _probe = setup.ResourceProbe ?? new ProcessResourceProbe();
            var now = _timers.Now.UtcTicks;
            Volatile.Write(ref _dgUiSeenTicks, now);
            _dgFpsSince = _timers.Now;
            _diagTimer = _timers.Every(TimeSpan.FromSeconds(1), DgWatchdog);
        }
        catch (Exception e)
        {
            _logs.Error("Teşhis bekçisi kurulamadı", e);
            _diag = null;
        }
    }

    void CloseDiagnostics()
    {
        _diagTimer?.Dispose();
        _diagTimer = null;
        try { _diag?.FlushPending(); } catch (Exception) { }
        _heartbeat?.Stop();
    }

    /// <summary>Bilgisayar uykuya geçiyor (platform güç olayından çağırır; uyanış <see cref="SystemResumed"/>).</summary>
    public void SystemSuspending() => _diag?.SystemSleeping();

    static string NetCode(NetworkKind kind) => kind switch
    {
        NetworkKind.Wired => "ethernet",
        NetworkKind.Wifi => "wifi",
        NetworkKind.Other => "other",
        NetworkKind.Offline => "none",
        _ => "unknown",
    };

    // ---- Saniyelik izleyici (zamanlayıcı iş parçacığı) ----

    /// <summary>
    /// Ana iş parçacığı yanıt veriyor mu: her saniye arayüze bir yoklama gönderilir; dönmeden eşik (5 sn) geçerse askı
    /// bildirilir. Damga 10 sn'de bir yazılır (önceki çalışmanın askıda bitip bitmediği). Teşhisin geri kalanı arayüzde.
    /// </summary>
    void DgWatchdog()
    {
        if (_diag is not { } diag) return;
        var now = _timers.Now;
        if (Volatile.Read(ref _dgPingOut) == 1)
        {
            var blocked = (now - new DateTimeOffset(Volatile.Read(ref _dgPingSentTicks), TimeSpan.Zero)).TotalSeconds;
            // Eşik geçtikçe her saniye bildirilir: bekçi açılış susturmasını ve "oturumda bir kez"i kendisi uygular.
            if (blocked >= diag.Config[DiagLimitKeys.HangSec] && Volatile.Read(ref _dgHangSent) == 0)
            {
                diag.UiBlocked(blocked);
                var since = new DateTimeOffset(Volatile.Read(ref _dgPingSentTicks), TimeSpan.Zero);
                if (diag.Recent.Any(r => r.Rule == DiagRules.AppHang && r.At >= since))
                {
                    Volatile.Write(ref _dgHangSent, 1);
                    // Damga hemen: süreç şimdi öldürülürse bir sonraki açılış aynı askıyı yeniden bildirmesin.
                    _heartbeat?.Beat(now, new DateTimeOffset(Volatile.Read(ref _dgUiSeenTicks), TimeSpan.Zero), reported: true);
                }
            }
        }
        else
        {
            Volatile.Write(ref _dgPingSentTicks, now.UtcTicks);
            Volatile.Write(ref _dgPingOut, 1);
            _post(() =>
            {
                Volatile.Write(ref _dgUiSeenTicks, _timers.Now.UtcTicks);
                Volatile.Write(ref _dgHangSent, 0);
                Volatile.Write(ref _dgPingOut, 0);
                DgTick();
            });
        }
        if (now.Second % 10 == 0)
            _heartbeat?.Beat(now, new DateTimeOffset(Volatile.Read(ref _dgUiSeenTicks), TimeSpan.Zero),
                Volatile.Read(ref _dgHangSent) == 1);
    }

    /// <summary>Arayüzde, saniyede bir: süreye bağlı kurallar; 5 sn'de bir kare hızı, 10 sn'de bir kaynak ve kare özeti.</summary>
    void DgTick()
    {
        if (_diag is not { } diag || _closing) return;
        _dgTicks++;
        if (_dgTicks % 5 == 0 && _sessionActive)
        {
            var now = _timers.Now;
            var seconds = (now - _dgFpsSince).TotalSeconds;
            var frames = Interlocked.Exchange(ref _dgFrames, 0);
            _dgFpsSince = now;
            if (seconds > 0) diag.FrameRate(frames / seconds);
        }
        if (_dgTicks % 10 == 0)
        {
            try
            {
                if (_probe?.Read() is { } r) diag.Resources(r.MemMB, r.CpuPercent);
            }
            catch (Exception) { }
            DgSampleFrame();
        }
        diag.Tick();
    }

    void DgSampleFrame()
    {
        if (_lastFrame is not { } frame || !_sessionActive)
        {
            _dgLuma = null;
            _dgSamePrints = 0;
            return;
        }
        var (luma, print) = DiagFrameStats.Sample(frame);
        _dgSamePrints = print == _dgPrint ? _dgSamePrints + 1 : 0;
        _dgPrint = print;
        _dgLuma = luma;
    }

    DiagHostState DgHostState() => new()
    {
        TvCount = _tvCount,
        Proto = _dgProto,
        FrameLuma = _dgLuma is { } l ? Math.Round(l) : null,
        // 30 sn (üç örnek) boyunca parmak izi değişmediyse kareler donuk.
        FrameSame = _dgLuma is null ? null : _dgSamePrints >= 3,
        RegionManual = _settings.Region != new Region(),
        Provider = ProviderName(),
    };

    DiagTv? DgTv()
    {
        var brand = _tv?.Brand switch
        {
            TvKind.AndroidTv => "androidtv",
            TvKind.Samsung => "samsung",
            TvKind.Lg => "lg",
            _ => null,
        };
        return brand is null && _tvModel is null ? null : new DiagTv(brand, _tvModel, _tvApp.Version);
    }

    // ---- Denetleyicinin olaylarından ----

    void DgSessionStarted()
    {
        _dgRetries = 0;
        _dgPs5Dropped = false;
        Interlocked.Exchange(ref _dgFrames, 0);
        _dgFpsSince = _timers.Now;
        _diag?.SessionStarted();
    }

    void DgSessionEnded() => _diag?.SessionStopped();

    /// <summary>
    /// Kare iş parçacığından (kare başına): son kare zamanı her zaman, kare hızı sayacı yalnız okuma duraklatılmamışken
    /// (duraklatma "yazı okunmuyor" sayılmasın; her kaynak türünde: kart, pencere, PS5, Xbox).
    /// </summary>
    void DgFrame(bool paused)
    {
        if (!paused) Interlocked.Increment(ref _dgFrames);
        _diag?.FrameSeen();
    }

    void DgSourceStatus(SourceStatus old, SourceStatus status)
    {
        if (_diag is not { } diag) return;
        switch (status.Phase)
        {
            case SourcePhase.Streaming:
                _dgPs5Dropped = false;
                _dgRetries = 0;
                diag.Ps5Connected();
                break;
            case SourcePhase.Connecting when _dgPs5Dropped:
                diag.Ps5Retry(++_dgRetries);
                break;
            case SourcePhase.Disconnected when status.Reason is { } reason && reason != DisconnectReason.Stopped:
                if (old.Phase == SourcePhase.Streaming)
                {
                    _dgPs5Dropped = true;
                    diag.Ps5Dropped(Ps5Cause(reason));
                }
                else if (_dgPs5Dropped) diag.Note("ps5.retry.failed");
                break;
        }
    }

    /// <summary>Kopma sebebi → teşhis işareti (bilinmiyorsa null: sebep <c>timeout</c> olur).</summary>
    internal static string? Ps5Cause(DisconnectReason reason) => reason switch
    {
        DisconnectReason.Network => "network_lost",
        DisconnectReason.ConsoleAsleep => "ps5_standby",
        DisconnectReason.InUse => "kicked",
        DisconnectReason.Refused or DisconnectReason.Rejected => "ps5_closed",
        _ => null,
    };

    void DgTvConnected(Nino.Core.Link.TvLinkKind kind)
    {
        _dgProto = kind == Nino.Core.Link.TvLinkKind.Legacy ? "legacy" : "nino";
        _diag?.TvConnected();
    }

    void DgLine(SubtitleMetrics m) => _diag?.LineShown(m.TotalMs, m.Origin switch
    {
        ShownOrigin.Pack => "pack",
        ShownOrigin.Pool => "pool",
        _ => "provider",
    }, m.TranslationMs, m.OcrMs);

    /// <summary>
    /// Bir satırın çevirisi bitti. Çevrimiçi motor açıkken her satır bir istek sayılır; motorun hatası sürerken
    /// (yedekle çevrilse bile) hata sayılır. İstek başına HTTP durumu bilinmediği için durum hata türünden çıkarılır.
    /// </summary>
    void DgTranslationFinished(bool ok)
    {
        // Çevrilmek istenen bir satır, yazının okunduğu demektir (çeviri başarısız olsa da).
        _diag?.OcrText();
        if (_diag is not { } diag || _chain?.OnlineEnabled != true) return;
        if (ok && _onlineProblem is null)
        {
            diag.TranslationResult(true);
            return;
        }
        switch (_onlineProblem)
        {
            case OnlineFailure.QuotaExhausted: diag.TranslationResult(false, 429); break;
            case OnlineFailure.InvalidKey: diag.TranslationResult(false, 401); break;
            case OnlineFailure.Unreachable: diag.TranslationResult(false, null, timeout: true); break;
            default: diag.TranslationResult(false); break;
        }
    }

    /// <summary>
    /// Okuma süresi (kare iş parçacığından). Takıldığı için kapı tarafından zaten bildirilen okuma geç bitince ikinci
    /// kez takılma sayılmaz.
    /// </summary>
    void DgOcrFinished(long ms) =>
        _diag?.OcrFinished(ms, foundText: false, countStall: Interlocked.Exchange(ref _dgStuck, 0) == 0);

    /// <summary>Kapı okumayı takılmış saydı (kare iş parçacığından).</summary>
    void DgOcrStuck(long ms)
    {
        Volatile.Write(ref _dgStuck, 1);
        _diag?.OcrStalled(ms);
    }

    void DgPackResult(bool ok, int? http, string? kind = null) => _diag?.PackDownload("list", ok, http, kind);

    /// <summary>Saat: denetleyicinin zamanlayıcısı (testte elle ilerletilen).</summary>
    sealed class ShellClock(IShellTimers timers) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => timers.Now;
    }
}

/// <summary>Bellek ve işlemci ölçer (teşhis). Varsayılanı süreç bilgisinden okur; testler sahtesini verir.</summary>
public interface IResourceProbe
{
    /// <summary>Uygulamanın belleği (MB) ve işlemci kullanımı (bütün çekirdeklere göre %); okunamazsa null.</summary>
    (double MemMB, double CpuPercent)? Read();
}

/// <summary>Süreç bilgisinden (Windows ve Linux'ta aynı .NET API'si) bellek ve işlemci.</summary>
public sealed class ProcessResourceProbe : IResourceProbe
{
    TimeSpan _lastCpu;
    long _lastWall;

    /// <inheritdoc />
    public (double MemMB, double CpuPercent)? Read()
    {
        try
        {
            using var p = Process.GetCurrentProcess();
            var cpu = p.TotalProcessorTime;
            var wall = Stopwatch.GetTimestamp();
            double percent = 0;
            if (_lastWall != 0)
            {
                var elapsed = Stopwatch.GetElapsedTime(_lastWall, wall).TotalMilliseconds;
                if (elapsed > 0)
                    percent = (cpu - _lastCpu).TotalMilliseconds / elapsed / Environment.ProcessorCount * 100;
            }
            _lastCpu = cpu;
            _lastWall = wall;
            return (p.WorkingSet64 / (1024.0 * 1024.0), Math.Clamp(percent, 0, 100));
        }
        catch (Exception e) when (e is InvalidOperationException or PlatformNotSupportedException or NotSupportedException)
        {
            return null;
        }
    }
}
