// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Core.Diagnostics.Guards;

namespace Nino.Core.Diagnostics;

/// <summary>
/// Otomatik teşhis bekçisi (otomatik-teshis.md). Uygulama olayları tipli yöntemlerle bildirir, saniyede bir
/// <see cref="Tick"/> çağırır; bekçi iz tutar, kuralları (her biri ayrı küçük bekçi) değerlendirir, susturma, öncelik
/// ve sınırları uygular, tetiklenen sorunu <see cref="Reported"/> ile verir. Kendi zamanlayıcısı yoktur. Her yöntem
/// her iş parçacığından çağrılabilir (içeride kilit); <see cref="Reported"/> kilit dışında, çağıranın iş parçacığında
/// verilir.
/// </summary>
/// <remarks>
/// Genel kurallar: bilgisayar uyurken ve uyandıktan sonraki 2 dk, uygulama arka plandayken ve öne geldikten sonraki
/// 2 dk, kullanıcı çeviriyi durdurduktan sonraki 2 dk ve açılışın ilk 60 sn'si susar. Ağ tamamen gittiğinde yalnız ağ
/// kuralları (<see cref="DiagRules.IsNetworkRule"/>) çalışır. Bir kural tetiklenince 5 dk'lık bir grup açılır; o sürede
/// tetiklenenlerden yalnız önceliği en yüksek olan gönderilir (en yüksek öncelikli <c>app.hang</c> hemen gider),
/// öbürleri iz adımı (<c>diag.&lt;kural&gt;</c>) olarak kalır. Aynı kural bir oturumda en çok bir kez tetiklenir;
/// günlük sınırlar <see cref="DiagDailyLimits"/>'te.
/// </remarks>
public sealed class DiagnosticsWatcher
{
    /// <summary>Susturan bir olaydan sonra susma süresi.</summary>
    public static readonly TimeSpan QuietAfter = TimeSpan.FromMinutes(2);

    /// <summary>Açılıştan sonra susma süresi.</summary>
    public static readonly TimeSpan LaunchQuiet = TimeSpan.FromSeconds(60);

    /// <summary>Tek kök penceresi.</summary>
    public static readonly TimeSpan GroupWindow = TimeSpan.FromMinutes(5);

    /// <summary>Son bildirimlerden tutulan.</summary>
    public const int RecentCount = 10;

    readonly object _gate = new();
    readonly DiagOptions _options;
    readonly DiagDailyLimits _limits;
    readonly DiagGuard[] _guards;
    readonly HashSet<string> _firedInSession = new(StringComparer.Ordinal);
    readonly List<DiagReport> _outbox = [];
    readonly List<DiagReport> _recent = [];
    DiagConfig _remote = DiagConfig.Default;
    DiagConfig _config = DiagConfig.Default;
    Group? _group;
    double _lastTrailFps = -1;

    sealed class Group(DateTimeOffset end)
    {
        public DateTimeOffset End { get; } = end;
        public List<DiagReport> Candidates { get; } = [];
        public bool Sent { get; set; }
    }

    /// <param name="options">Saat, durum kaynakları, sınır sayımı.</param>
    public DiagnosticsWatcher(DiagOptions? options = null)
    {
        _options = options ?? new DiagOptions();
        _limits = _options.Limits ?? new DiagDailyLimits(null);
        AppStart = Now;
        _guards =
        [
            new Ps5NoReturnGuard(this), new TvFlappingGuard(this), new OcrSilentGuard(this), new OcrStalledGuard(this),
            new TrSlowGuard(this), new TrErrorsGuard(this), new AppHangGuard(this), new AppResourcesGuard(this),
            new PackDownloadGuard(this),
        ];
        ApplyConfig(DiagConfig.Default);
    }

    /// <summary>Bir sorun bildirildi (kilit dışında).</summary>
    public event Action<DiagReport>? Reported;

    /// <summary>Son bildirimler (en yenisi sonda; yalnız kodlar). sağlık sayfası açıklamayı koddan kurar.</summary>
    public IReadOnlyList<DiagReport> Recent
    {
        get { lock (_gate) return [.. _recent]; }
    }

    /// <summary>Geçerli ayar.</summary>
    public DiagConfig Config
    {
        get { lock (_gate) return _config; }
    }

    /// <summary>Tampondaki iz (testler ve inceleme için).</summary>
    public IReadOnlyList<DiagStep> TrailSteps
    {
        get { lock (_gate) return Trail.Steps(Now); }
    }

    // ---- Ayar ----

    /// <summary>Uzak ayarı uygular (platform varsayılanları altta kalır).</summary>
    public void ApplyConfig(DiagConfig remote)
    {
        lock (_gate)
        {
            _remote = remote;
            var effective = remote;
            foreach (var (key, value) in _options.PlatformDefaults ?? new Dictionary<string, double>())
                if (DiagLimitKeys.All.FirstOrDefault(l => l.Key == key || l.Alias == key) is { } limit)
                    effective = effective.WithDefault(limit, value);
            _config = effective;
        }
    }

    /// <summary>Sunucu cevabındaki <c>telemetry.diag</c> bloğunu (varsa) uygular; yoksa geçerli ayar kalır.</summary>
    public void ApplyRemoteConfigJson(string? json)
    {
        if (DiagConfig.FromResponse(json) is { } config) ApplyConfig(config);
    }

    // ---- Girdiler ----

    /// <summary>Çeviri oturumu başladı.</summary>
    public void SessionStarted() => Input(() =>
    {
        SessionStart = Now;
        SessionRunning = true;
        Lines = 0;
        Fps = 0;
        _firedInSession.Clear();
        Signal("session.start");
    });

    /// <summary>Çeviri oturumu bitti (kullanıcı durdurdu ya da uygulama kapattı): bekçiler sıfırlanır, 2 dk susar.</summary>
    public void SessionStopped() => Input(() =>
    {
        SessionRunning = false;
        SessionStart = null;
        Ps5Up = false;
        LastQuiet = Now;
        Signal("session.stop");
    });

    /// <summary>PS5 (ya da Xbox) görüntüsü geldi / yeniden bağlandı.</summary>
    public void Ps5Connected() => Input(() =>
    {
        Ps5Up = true;
        Ps5Seen = true;
        LastFrameAt = Now;
        Signal("ps5.connect");
    });

    /// <summary>
    /// PS5 ile bağ kesildi. <paramref name="reason"/>: <c>network_lost</c>, <c>ps5_standby</c> (<c>standby</c>),
    /// <c>ps5_closed</c>, <c>kicked</c>, <c>stalled</c>; bilinmiyorsa null.
    /// </summary>
    public void Ps5Dropped(string? reason = null) => Input(() =>
    {
        Ps5Up = false;
        Ps5Seen = true;
        Signal("ps5.drop", reason: reason);
    });

    /// <summary>PS5'e yeniden bağlanma denemesi (kaçıncı).</summary>
    public void Ps5Retry(int attempt) => Input(() => Signal("ps5.retry", attempt));

    /// <summary>
    /// Kare hızı (birkaç saniyede bir; iz yalnız belirgin değişimde adım alır). Okuma duraklatıldıysa 0 verilir
    /// (duraklatma "yazı yok" sayılmasın).
    /// </summary>
    public void FrameRate(double fps) => Input(() =>
    {
        if (!double.IsFinite(fps) || fps < 0) return;
        Fps = fps;
        if (fps >= 1) LastFrameAt = Now;
        var changed = _lastTrailFps < 0 || (fps >= 1) != (_lastTrailFps >= 1)
            || Math.Abs(fps - _lastTrailFps) > Math.Max(5, _lastTrailFps * 0.3);
        if (changed)
        {
            _lastTrailFps = fps;
            Trail.Add(Now, "ps5.frame", Math.Round(fps));
        }
        Dispatch(new DiagSignal("ps5.frame", fps, null, Now));
    });

    /// <summary>Bir kare geldi (izsiz; kare başına çağrılabilir).</summary>
    public void FrameSeen()
    {
        lock (_gate) LastFrameAt = Now;
    }

    /// <summary>Görüntü çözücü hata verdi.</summary>
    public void DecoderFailed() => Input(() =>
    {
        DecoderFailedAt = Now;
        Signal("ps5.stream.decoder");
    });

    /// <summary>TV bağlandı.</summary>
    public void TvConnected() => Input(() => Signal("tv.connect"));

    /// <summary>
    /// Bağlıyken TV koptu. <paramref name="reason"/>: ölçümdeki <c>tv_drop.code</c> (<c>write_error</c>, <c>timeout</c>,
    /// <c>closed</c>, <c>resume</c>, <c>network_change</c>, <c>replaced</c>…). <paramref name="upSeconds"/>: bağlı kalma süresi.
    /// </summary>
    public void TvDropped(string? reason, double? upSeconds = null) =>
        Input(() => Signal("tv.drop", upSeconds is { } up && up >= 0 ? Math.Round(up) : null, reason));

    /// <summary>Ağ türü değişti: <c>wifi</c>, <c>ethernet</c>, <c>cellular</c>, <c>other</c>, <c>none</c> (ağ yok), <c>unknown</c>.</summary>
    public void NetworkChanged(string kind) => Input(() =>
    {
        if (!DiagPayload.IsShort(kind) || kind == Net) return;
        var was = Net;
        Net = kind;
        if (kind == "none") Signal("net.down");
        else if (was == "none") Signal("net.up");
        else if (was != "unknown") Signal("net.change");
    });

    /// <summary>
    /// Bir yazı tanıma isteği bitti (süre ms). Yavaşsa iz adımı alır; eşikten (10 sn) uzunsa takılma sayılır
    /// (<paramref name="countStall"/> false ise sayılmaz: aynı okuma zaten <see cref="OcrStalled"/> ile bildirildiyse).
    /// </summary>
    public void OcrFinished(long ms, bool foundText, bool countStall = true) => Input(() =>
    {
        if (ms < 0) return;
        OcrMs = ms;
        if (ms >= 1000) Trail.Add(Now, "ocr.slow", ms, TimeSpan.FromSeconds(10));
        if (countStall && ms >= Limit(DiagLimitKeys.OcrStallSec) * 1000) Signal("ocr.stall", ms);
        if (foundText) Signal("ocr.text");
    });

    /// <summary>Yazı tanıma isteği süresi içinde dönmedi (takıldı; <paramref name="ms"/> geçen süre).</summary>
    public void OcrStalled(long ms) => Input(() =>
    {
        OcrMs = Math.Max(0, ms);
        Signal("ocr.stall", Math.Max(0, ms));
    });

    /// <summary>Yazı okundu (bir satır).</summary>
    public void OcrText() => Input(() => Signal("ocr.text"));

    /// <summary>Yazı tanıma boş döndü (izde kısaltılır).</summary>
    public void OcrEmpty() => Input(() => Signal("ocr.empty"));

    /// <summary>
    /// Bir satır ekrana geldi: toplam gecikme (<c>tr.total</c>), kaynağı (<c>pack</c>, <c>pool</c>, <c>provider</c>,
    /// <c>cache</c>), çeviri ve yazı tanıma süreleri.
    /// </summary>
    public void LineShown(long? totalMs, string origin, long? translationMs = null, long? ocrMs = null) => Input(() =>
    {
        Lines++;
        if (ocrMs is { } o && o >= 0) OcrMs = o;
        Dispatch(new DiagSignal("line", totalMs, origin, Now) { Extra = translationMs, Extra2 = ocrMs });
    });

    /// <summary>
    /// Bir çeviri isteğinin sonucu. Hatada <paramref name="http"/> durum kodu (biliniyorsa; ağ yoksa 0),
    /// <paramref name="timeout"/> zaman aşımı.
    /// </summary>
    public void TranslationResult(bool ok, int? http = null, bool timeout = false) => Input(() =>
    {
        if (ok) Signal("tr.ok");
        else Signal("tr.error", http, timeout ? "timeout" : null);
    });

    /// <summary>
    /// Oyun paketi (ya da paket listesi) indirme sonucu. <paramref name="key"/> yalnız bellekte eşleştirme içindir,
    /// gönderilmez. <paramref name="kind"/>: <c>offline</c>, <c>corrupt</c>, <c>storage_full</c> (yoksa HTTP'den).
    /// </summary>
    public void PackDownload(string key, bool ok, int? http = null, string? kind = null, long? sizeKB = null) => Input(() =>
    {
        if (!ok) Trail.Add(Now, "pack.fail", http);
        Dispatch(new DiagSignal(ok ? "pack.ok" : "pack.fail", http, kind, Now) { Key = key, Extra = sizeKB });
    });

    /// <summary>Bellek (MB) ve işlemci (%) örneği; birkaç saniyede bir. <paramref name="thermal"/> biliniyorsa.</summary>
    public void Resources(double memMB, double cpuPercent, string? thermal = null) => Input(() =>
    {
        if (double.IsFinite(memMB) && memMB >= 0) MemMB = Math.Round(memMB);
        if (double.IsFinite(cpuPercent) && cpuPercent >= 0) Cpu = Math.Round(cpuPercent);
        if (thermal is not null && DiagPayload.IsShort(thermal)) Thermal = thermal;
        Dispatch(new DiagSignal("resources", MemMB, Thermal, Now) { Extra = (long?)Cpu });
    });

    /// <summary>Sistemden gelen düşük bellek uyarısı (telefon/TV).</summary>
    public void MemoryWarning() => Input(() => Signal("mem.warning"));

    /// <summary>Ana iş parçacığı <paramref name="seconds"/> sn'dir yanıt vermiyor (izleyici iş parçacığından).</summary>
    public void UiBlocked(double seconds) => Input(() => Signal("ui.blocked", Math.Round(seconds, 1)));

    /// <summary>Önceki çalışma askıda kalarak bitti (açılışta; <see cref="DiagHeartbeat"/>).</summary>
    public void PreviousRunHung(double blockedSeconds) => Input(() => Signal("app.hung_before", Math.Round(blockedSeconds)));

    /// <summary>Bilgisayar uykuya geçiyor.</summary>
    public void SystemSleeping() => Input(() =>
    {
        Asleep = true;
        LastQuiet = Now;
        Signal("sys.sleep");
    });

    /// <summary>Bilgisayar uyandı.</summary>
    public void SystemWoke() => Input(() =>
    {
        Asleep = false;
        LastQuiet = Now;
        Signal("sys.wake");
    });

    /// <summary>Uygulama arka plana geçti (telefon/TV).</summary>
    public void AppBackground() => Input(() =>
    {
        InBackground = true;
        LastBackground = Now;
        Signal("app.background");
    });

    /// <summary>Uygulama öne geldi.</summary>
    public void AppForeground() => Input(() =>
    {
        InBackground = false;
        LastBackground = Now;
        Signal("app.foreground");
    });

    /// <summary>Başka bir iz adımı (ör. ölçümdeki hata kodu). Kod kurala uymuyorsa atlanır.</summary>
    public void Note(string code, double? number = null) => Input(() => Trail.Add(Now, code, number, TimeSpan.FromSeconds(5)));

    /// <summary>Süreye bağlı kuralları değerlendirir ve bekleyen grubu süresi dolunca gönderir (saniyede bir).</summary>
    public void Tick() => Input(() =>
    {
        // Saniyelik tik arasında saat birden ileri atladıysa bilgisayar uyumuş demektir. Linux gibi uykuyu ancak
        // uyandıktan sonra (geriye dönük) bildirebilen platformlarda bile kurallar uyku boşluğunu sorun saymasın.
        var now = Now;
        if (_lastTick is { } last && now - last > SleepGap)
        {
            LastQuiet = now;
            Signal("sys.wake", Math.Round((now - last).TotalSeconds));
        }
        _lastTick = now;
        foreach (var g in _guards) g.OnTick();
        if (_group is { } group && Now >= group.End) CloseGroup();
    });

    /// <summary>Bekleyen grubu hemen gönderir (kapanışta).</summary>
    public void FlushPending() => Input(() =>
    {
        if (_group is not null) CloseGroup();
    });

    // ---- Bekçilerin kullandıkları ----

    internal DateTimeOffset Now => _options.Clock.GetUtcNow();

    /// <summary>İki tik arası bundan uzunsa uyku sayılır.</summary>
    internal static readonly TimeSpan SleepGap = TimeSpan.FromSeconds(30);

    DateTimeOffset? _lastTick;

    internal DateTimeOffset AppStart { get; }

    internal DiagTrail Trail { get; } = new();

    internal bool SessionRunning { get; private set; }

    internal DateTimeOffset? SessionStart { get; private set; }

    internal bool Ps5Up { get; private set; }

    internal bool Ps5Seen { get; private set; }

    internal DateTimeOffset? LastFrameAt { get; set; }

    internal DateTimeOffset? DecoderFailedAt { get; private set; }

    internal double Fps { get; private set; }

    internal string Net { get; private set; } = "unknown";

    internal bool NetDown => Net == "none";

    internal long Lines { get; private set; }

    internal long? OcrMs { get; private set; }

    internal double? MemMB { get; private set; }

    internal double? Cpu { get; private set; }

    internal string? Thermal { get; private set; }

    internal bool Asleep { get; private set; }

    internal bool InBackground { get; private set; }

    internal DateTimeOffset? LastQuiet { get; private set; }

    internal DateTimeOffset? LastBackground { get; private set; }

    internal double Limit(DiagLimit limit) => _config[limit];

    internal DiagHostState Host()
    {
        try { return _options.State?.Invoke() ?? new DiagHostState(); }
        catch (Exception) { return new DiagHostState(); }
    }

    /// <summary>
    /// <paramref name="at"/> anında genel susturma var mı: açılışın ilk 60 sn'si, uyku ve uyanmadan sonraki 2 dk,
    /// kullanıcının durdurmasından sonraki 2 dk, (istenirse) arka plan ve öne gelişten sonraki 2 dk.
    /// </summary>
    internal bool IsQuiet(DateTimeOffset at, bool background = true)
    {
        if (at - AppStart < LaunchQuiet) return true;
        if (Asleep) return true;
        if (Within(LastQuiet, at)) return true;
        return background && (InBackground || Within(LastBackground, at));
    }

    static bool Within(DateTimeOffset? when, DateTimeOffset at) => when is { } w && w <= at && at - w < QuietAfter;

    /// <summary>
    /// Bir kural tetiklendi: kapalıysa, bu oturumda zaten tetiklendiyse ya da ağ yokken ağ dışı bir kuralsa atlanır;
    /// değilse bildirim kurulur ve tek kök grubuna girer.
    /// </summary>
    internal void Fire(string rule, string? cause, DateTimeOffset at, IEnumerable<KeyValuePair<string, object?>> state)
    {
        if (_config.IsOff(rule) || _firedInSession.Contains(rule)) return;
        if (NetDown && !DiagRules.IsNetworkRule(rule)) return;
        _firedInSession.Add(rule);
        cause = DiagRules.CauseOrUnknown(rule, cause);
        var severity = DiagRules.Severity(rule);
        var host = Host();
        var all = new List<KeyValuePair<string, object?>>(state);
        void Common(string key, object? value)
        {
            if (value is not null && all.All(kv => kv.Key != key)) all.Add(new(key, value));
        }
        Common("ps5", Ps5Up ? "up" : Ps5Seen ? "down" : "none");
        Common("tv", host.TvCount is > 0 ? "up" : "down");
        Common("net", Net);
        if (SessionStart is { } start) Common("sessionMin", (long)Math.Max(0, (at - start).TotalMinutes));
        Common("lines", Lines);
        Common("fps", Math.Round(Fps));
        Common("memMB", MemMB);

        DiagTv? tv = null;
        string? game = null;
        IReadOnlyDictionary<string, string?>? versions = null;
        try { tv = _options.Tv?.Invoke(); } catch (Exception) { }
        try { game = _options.Game?.Invoke(); } catch (Exception) { }
        try { versions = _options.Versions?.Invoke(); } catch (Exception) { }

        var body = DiagPayload.Build(at, rule, cause, severity, all, Trail.ToJson(at), tv, game, versions);
        Trail.Add(at, "diag." + rule);
        if (body is null) return;
        var report = new DiagReport(rule, cause, severity, at, body);

        _group ??= new Group(at + GroupWindow);
        _group.Candidates.Add(report);
        if (rule == DiagRules.AppHang && !_group.Sent) Send(_group);
    }

    void CloseGroup()
    {
        var group = _group!;
        _group = null;
        if (!group.Sent) Send(group);
    }

    void Send(Group group)
    {
        foreach (var candidate in group.Candidates.OrderBy(c => DiagRules.Priority(c.Rule)).ThenBy(c => c.At))
        {
            if (!_limits.Allows(candidate.Rule, Now)) continue;
            _limits.Count(candidate.Rule, Now);
            group.Sent = true;
            _recent.Add(candidate);
            if (_recent.Count > RecentCount) _recent.RemoveAt(0);
            _outbox.Add(candidate);
            return;
        }
    }

    // ---- İç düzen ----

    void Signal(string code, double? number = null, string? reason = null)
    {
        var coalesce = code is "tr.ok" or "ocr.text" or "ocr.empty" or "ui.blocked" ? TimeSpan.FromSeconds(30) : (TimeSpan?)null;
        Trail.Add(Now, code, number, coalesce);
        Dispatch(new DiagSignal(code, number, reason, Now));
    }

    void Dispatch(DiagSignal signal)
    {
        foreach (var g in _guards) g.OnSignal(signal);
    }

    void Input(Action action)
    {
        DiagReport[] ready;
        lock (_gate)
        {
            try { action(); }
            catch (Exception) { }
            if (_outbox.Count == 0) return;
            ready = [.. _outbox];
            _outbox.Clear();
        }
        foreach (var r in ready)
        {
            try { Reported?.Invoke(r); }
            catch (Exception) { }
        }
    }
}

/// <summary>Bekçilere giden bir olay.</summary>
internal readonly record struct DiagSignal(string Code, double? Number, string? Reason, DateTimeOffset At)
{
    public string? Key { get; init; }

    public long? Extra { get; init; }

    public long? Extra2 { get; init; }
}
