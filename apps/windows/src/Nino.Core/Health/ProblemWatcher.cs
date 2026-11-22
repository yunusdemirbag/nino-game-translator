// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Support;

namespace Nino.Core.Health;

/// <summary>Sorun bekçisinin denetleyiciden sorduğu ve ona bildirdiği şeyler. Bütün üyeler arayüz iş parçacığında çağrılır.</summary>
public interface IProblemWatcherHost
{
    /// <summary>Çeviri sürüyor mu.</summary>
    bool IsTranslating { get; }

    /// <summary>Şu anda PS5'ten kare akıyorsa true.</summary>
    bool IsPictureArriving { get; }

    /// <summary>Altyazı TV'ye gidiyor mu.</summary>
    bool IsSendingToTv { get; }

    /// <summary>Bağlı TV uygulaması sayısı.</summary>
    int ConnectedTvs { get; }

    /// <summary>Otomatik bildirim ayarı (varsayılan açık).</summary>
    bool AutoReportEnabled { get; }

    /// <summary>Şu anki oyunun adı; bilinmiyorsa null.</summary>
    string? Game { get; }

    /// <summary>Muhtemel sebebin ekran dilindeki başlığı; yoksa null.</summary>
    string? CauseTitle(NetworkKind network);

    /// <summary>
    /// Otomatik bildirimin gövdesi: kuruluş kimliği, sürüm, çeviri dili, verilen metin, cihaz özeti. Kurulamıyorsa
    /// (sağlık klasörü yok) null.
    /// </summary>
    ReportBody? BuildAutoReport(string text);

    /// <summary>altyazi.log'a bir satır.</summary>
    void Log(string line);

    /// <summary>Sorun listesi değişti (ekranlar yenilensin).</summary>
    void ProblemsChanged();

    /// <summary>İşi arayüz iş parçacığına aktarır (arka plandan gelen ağ olayı ve zamanlayıcı sonu için).</summary>
    void Post(Action action);
}

/// <summary>
/// Çeviri sürerken PS5, ağ ve TV sorunlarını yakalar, sorun kaydına yazar ve (ayar açıksa) oturum başına bir otomatik
/// bildirim gönderir. Denetleyici kurar; çağrılar arayüz iş parçacığındandır.
/// </summary>
public sealed class ProblemWatcher : IDisposable
{
    /// <summary>PS5 kopunca "dakikalardır geri gelmiyor" sayılana kadar beklenen süre.</summary>
    public static readonly TimeSpan Ps5NotBack = TimeSpan.FromSeconds(180);

    /// <summary>TV sayısı 0'a düşünce "TV koptu" sayılana kadar beklenen süre (kısa kopmalar sayılmaz).</summary>
    public static readonly TimeSpan TvGone = TimeSpan.FromSeconds(20);

    public const string LogProblemPrefix = "sorun: ";
    public const string LogAutoSent = "kendiliğinden bildirim sunucuya ulaştı";
    public const string LogAutoFailed = "kendiliğinden bildirim ulaşmadı (günlük sınır dolmuş olabilir; ileride yeniden denenir)";

    readonly IProblemWatcherHost _host;
    readonly HealthRecorder _recorder;
    readonly ProblemLog _problems;
    readonly AutoReporter? _reporter;
    readonly INetworkWatch _network;
    readonly bool _watchNetworkEvents;
    readonly Func<TimeSpan, CancellationToken, Task> _delay;
    readonly TimeProvider _clock;

    CancellationTokenSource? _ps5Timer;
    CancellationTokenSource? _tvTimer;
    DateTimeOffset? _sessionStart;
    bool _reportedThisSession;
    int _lastTvCount;
    bool _started;
    bool _disposed;

    /// <param name="host">Denetleyici.</param>
    /// <param name="recorder">Paylaşılan sağlık kaydedici.</param>
    /// <param name="problems">Sorun kaydı.</param>
    /// <param name="reporter">Otomatik bildirici; yoksa otomatik bildirim gitmez.</param>
    /// <param name="network">Ağ türü okuyucu.</param>
    /// <param name="watchNetworkEvents">Ağ olaylarına abone olunsun mu (yalnız sağlık klasörü varken).</param>
    /// <param name="delay">Bekleme işlevi (testler elle bitirir); yoksa <see cref="Task.Delay(TimeSpan, CancellationToken)"/>.</param>
    /// <param name="clock">Saat.</param>
    public ProblemWatcher(IProblemWatcherHost host, HealthRecorder recorder, ProblemLog problems,
        AutoReporter? reporter, INetworkWatch network, bool watchNetworkEvents,
        Func<TimeSpan, CancellationToken, Task>? delay = null, TimeProvider? clock = null)
    {
        _host = host;
        _recorder = recorder;
        _problems = problems;
        _reporter = reporter;
        _network = network;
        _watchNetworkEvents = watchNetworkEvents;
        _clock = clock ?? TimeProvider.System;
        _delay = delay ?? ((t, ct) => Task.Delay(t, _clock, ct));
    }

    /// <summary>Bilinen son ağ türü.</summary>
    public NetworkKind Network { get; private set; } = NetworkKind.Unknown;

    /// <summary>Bu oturumda otomatik bildirim yapıldı mı.</summary>
    public bool ReportedThisSession => _reportedThisSession;

    /// <summary>Açılışta: ağ türü okunur, ağ olaylarına abone olunur, bekleyen otomatik bildirim gönderilir.</summary>
    public void Start()
    {
        if (_started || _disposed) return;
        _started = true;
        Network = SafeRead();
        if (_watchNetworkEvents) _network.Changed += OnNetworkEvent;
        if (_reporter is { HasPending: true } reporter)
            _ = Task.Run(async () =>
            {
                try { await reporter.SendPendingAsync().ConfigureAwait(false); }
                catch { }
            });
    }

    /// <summary>Oturum başladı.</summary>
    public void SessionStarted()
    {
        _reportedThisSession = false;
        _sessionStart = _clock.GetUtcNow();
        _lastTvCount = _host.ConnectedTvs;
    }

    /// <summary>Oturum bitti: zamanlayıcılar iptal; sorun olduysa otomatik bildirim.</summary>
    public void SessionEnded()
    {
        Cancel(ref _ps5Timer);
        Cancel(ref _tvTimer);
        if (_sessionStart is { } start)
        {
            var snap = _recorder.Snapshot();
            if (_problems.Since(start).Count > 0 || HealthVerdicts.Picture(snap) == HealthLevel.Problem
                || HealthVerdicts.Speed(snap) == HealthLevel.Problem)
                AutoReport();
        }
        _sessionStart = null;
    }

    /// <summary>PS5'le bağlantı kesildi.</summary>
    /// <param name="reason">Kopma nedeninin adı (yoksa ya da <c>Stopped</c> ise kullanıcının durdurması: yok sayılır).</param>
    /// <param name="wasStreaming">Kopmadan önce görüntü geliyor muydu.</param>
    public void Ps5Dropped(string? reason, bool wasStreaming)
    {
        if (_disposed || !_host.IsTranslating || string.IsNullOrEmpty(reason) || reason == "Stopped") return;
        if (wasStreaming) Record(ProblemKind.Ps5Dropped, reason);
        if (_ps5Timer is not null) return;
        var cts = new CancellationTokenSource();
        _ps5Timer = cts;
        Schedule(Ps5NotBack, cts, () =>
        {
            if (ReferenceEquals(_ps5Timer, cts)) _ps5Timer = null;
            if (!_host.IsTranslating || _host.IsPictureArriving) return;
            Record(ProblemKind.Ps5Unreachable, _recorder.Snapshot().LastReason);
            AutoReport();
        });
    }

    /// <summary>PS5 görüntüsü geri geldi.</summary>
    public void Ps5Back() => Cancel(ref _ps5Timer);

    /// <summary>Bağlı TV sayısı değişti.</summary>
    public void TvCountChanged(int count)
    {
        var previous = _lastTvCount;
        _lastTvCount = count;
        if (_disposed) return;
        if (count > 0)
        {
            Cancel(ref _tvTimer);
            return;
        }
        if (previous <= 0 || !_host.IsTranslating || !_host.IsSendingToTv || _tvTimer is not null) return;
        var cts = new CancellationTokenSource();
        _tvTimer = cts;
        Schedule(TvGone, cts, () =>
        {
            if (ReferenceEquals(_tvTimer, cts)) _tvTimer = null;
            if (!_host.IsTranslating || _host.ConnectedTvs != 0) return;
            _recorder.TvDropped();
            Record(ProblemKind.TvDropped, null);
        });
    }

    /// <summary>Ağ türü değişti (arayüz iş parçacığında).</summary>
    public void NetworkChanged(NetworkKind kind)
    {
        var previous = Network;
        Network = kind;
        if (_disposed) return;
        if (kind == NetworkKind.Offline && previous != NetworkKind.Offline && _host.IsTranslating)
        {
            _recorder.NetworkLost();
            Record(ProblemKind.NetworkLost, null);
        }
    }

    /// <summary>
    /// "Nino'nun tespitleri" metni: muhtemel sebep, son 3 günün sorunları ve sağlık özeti (sorun bildirme de kullanır).
    /// </summary>
    public string Findings(bool automatic, string? userText) =>
        ReportText.Build(automatic, userText, _host.CauseTitle(Network), _problems.All,
            HealthSummary.Lines(_recorder.Snapshot(), Network), _clock.GetUtcNow(), _clock.LocalTimeZone);

    void Record(ProblemKind kind, string? reason)
    {
        var snap = _recorder.Snapshot();
        var record = new ProblemRecord
        {
            Date = _clock.GetUtcNow().ToUniversalTime(),
            Kind = kind,
            Reason = string.IsNullOrEmpty(reason) ? null : reason,
            StreamedMinutes = snap.HasData ? Math.Round(snap.StreamedMinutes, 1) : null,
            LossPerMinute = snap.LossPerMinute is { } loss ? Math.Round(loss, 1) : null,
            StallsPerMinute = snap.StallsPerMinute is { } stalls ? Math.Round(stalls, 2) : null,
            Network = Network.Wire(),
            Game = string.IsNullOrWhiteSpace(_host.Game) ? null : _host.Game.Trim(),
        };
        _problems.Add(record);
        _host.Log(LogProblemPrefix + record.SupportLine(_clock.LocalTimeZone));
        _host.ProblemsChanged();
    }

    void AutoReport()
    {
        if (!_host.AutoReportEnabled || _reportedThisSession) return;
        _reportedThisSession = true;
        if (_reporter is null) return;
        if (_host.BuildAutoReport(Findings(automatic: true, userText: null)) is not { } body) return;
        Task<bool> sending;
        try { sending = _reporter.SendAsync(body); }
        catch { sending = Task.FromResult(false); }
        _ = sending.ContinueWith(t =>
        {
            var ok = t.IsCompletedSuccessfully && t.Result;
            _host.Post(() => _host.Log(ok ? LogAutoSent : LogAutoFailed));
        }, TaskScheduler.Default);
    }

    void Schedule(TimeSpan wait, CancellationTokenSource cts, Action then)
    {
        var token = cts.Token;
        _ = RunAsync();

        async Task RunAsync()
        {
            try { await _delay(wait, token).ConfigureAwait(false); }
            catch { return; }
            if (token.IsCancellationRequested) return;
            _host.Post(() =>
            {
                if (!token.IsCancellationRequested && !_disposed) then();
            });
        }
    }

    void OnNetworkEvent()
    {
        var kind = SafeRead();
        _host.Post(() => NetworkChanged(kind));
    }

    NetworkKind SafeRead()
    {
        try { return _network.Read(); }
        catch { return NetworkKind.Unknown; }
    }

    static void Cancel(ref CancellationTokenSource? timer)
    {
        var t = timer;
        timer = null;
        if (t is null) return;
        try { t.Cancel(); }
        catch (ObjectDisposedException) { }
        t.Dispose();
    }

    /// <summary>Zamanlayıcılar iptal, ağ aboneliği çözülür.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Cancel(ref _ps5Timer);
        Cancel(ref _tvTimer);
        if (_watchNetworkEvents && _started) _network.Changed -= OnNetworkEvent;
    }
}
