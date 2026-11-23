// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

// ============================================================================================================
// UYGULAMA DENETLEYİCİSİ — ekranların tek kaynağı (arayüzsüz; Windows WPF ve Linux paneli aynı nesneyi kullanır).
//
// İŞ PARÇACIĞI KURALI
//  * Denetleyicinin bütün durumu TEK bir mantıksal "arayüz iş parçacığında" değişir. Kurucuya verilen
//    "arayüze aktar" işlevi (post) bu iş parçacığına iş gönderir:
//      - Windows: WPF Dispatcher (tek SynchronizationContext) — post = a => dispatcher.BeginInvoke(a).
//      - Linux: kendi tek iş parçacıklı seri kuyruğu — post = a => queue.Enqueue(a).
//      - Testler: post = a => a() (hemen, eşzamanlı).
//  * Ekranlar bütün özellikleri ve eylemleri yalnız bu iş parçacığından çağırır.
//  * Platform hizmetlerinin olayları (kare, oturum durumu, TV sayısı, model ilerlemesi, havuz cevabı, Xbox jetonu,
//    zamanlayıcı tikleri…) hangi iş parçacığından gelirse gelsin denetleyici onları post ile aktarır.
//  * Eşzamansız eylemlerde her await'ten sonra "await OnUi()" ile arayüz iş parçacığına dönülür; denetleyici
//    SynchronizationContext yakalamaya güvenmez (Linux'ta yoktur).
//  * Kare işleyici kaynağın iş parçacığında çalışır; hiçbir hata dışarı kaçmaz; arayüz işleri post ile gider.
//  * PropertyChanged olayı yalnız arayüz iş parçacığında, değer gerçekten değişince ve bağlı özellikler için de
//    verilir (değerler her değişiklikten sonra karşılaştırılır).
// ============================================================================================================

using System.ComponentModel;
using System.Reflection;
using System.Runtime.CompilerServices;
using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Text;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell;

/// <summary>Denetleyicinin isteğe bağlı platform parçaları.</summary>
public sealed record ShellOptions
{
    /// <summary>Saat ve zamanlayıcılar.</summary>
    public IShellTimers? Timers { get; init; }

    /// <summary>Günlükler.</summary>
    public IShellLogs? Logs { get; init; }

    /// <summary>Tarayıcıda açma.</summary>
    public IBrowser? Browser { get; init; }

    /// <summary>Genel kısayollar.</summary>
    public IHotkeyHost? Hotkeys { get; init; }

    /// <summary>Uygulama içi PSN giriş penceresi.</summary>
    public IPsnSignInWindow? PsnWindow { get; init; }

    /// <summary>Mantıksal işlemci sayısı (iş parçacığı seçenekleri).</summary>
    public int LogicalProcessors { get; init; } = Environment.ProcessorCount;

    /// <summary>Sağlık kaydedici (paylaşılan); yoksa kurulur.</summary>
    public HealthRecorder? Health { get; init; }

    /// <summary>Sorun bekçisinin bekleme işlevi (testler).</summary>
    public Func<TimeSpan, CancellationToken, Task>? ProblemDelay { get; init; }

    /// <summary>Ölçüm (olcum.md); null ise ölçüm yok. Kapatma ayarı yoktur.</summary>
    public TelemetrySetup? Telemetry { get; init; }
}

/// <summary>
/// Uygulama denetleyicisi. Bütün ekran durumu okunabilir özellikler + <see cref="PropertyChanged"/>, bütün işler
/// eylemlerdir. İş parçacığı kuralı dosya başında ve <c>docs/yeni/windows/denetleyici-api.md</c>'de.
/// </summary>
public sealed partial class NinoController : INotifyPropertyChanged, IAsyncDisposable
{
    readonly IShellServices _services;
    readonly ISecretStore _secrets;
    readonly ISettingsStore _settingsStore;
    readonly ISleepGuard _sleep;
    readonly ITextSource _text;
    readonly Action<Action> _post;
    readonly IShellTimers _timers;
    readonly IShellLogs _logs;
    readonly IBrowser _browser;
    readonly IHotkeyHost? _hotkeys;
    readonly IPsnSignInWindow? _psnWindow;
    readonly int _cpus;
    readonly ISubtitleServer _server;
    readonly HealthRecorder _health;
    readonly List<Task> _background = [];
    readonly List<IDisposable> _subscriptions = [];

    AppSettings _settings;
    bool _closing;

    /// <summary>Denetleyiciyi kurar (açılış sırası tarif §5).</summary>
    /// <param name="services">Hizmetler.</param>
    /// <param name="secrets">Şifreli depo.</param>
    /// <param name="settings">Ayar deposu.</param>
    /// <param name="sleep">Uyku bekçisi.</param>
    /// <param name="text">Metin kataloğu (o anki arayüz dili).</param>
    /// <param name="post">Arayüze aktarma işlevi.</param>
    /// <param name="options">İsteğe bağlı platform parçaları.</param>
    public NinoController(IShellServices services, ISecretStore secrets, ISettingsStore settings, ISleepGuard sleep,
        ITextSource text, Action<Action> post, ShellOptions? options = null)
    {
        options ??= new ShellOptions();
        _services = services;
        _secrets = new CachingSecretStore(secrets);
        _settingsStore = settings;
        _sleep = sleep;
        _text = text;
        _post = post;
        _timers = options.Timers ?? new SystemShellTimers();
        _logs = options.Logs ?? new SilentShellLogs();
        _browser = options.Browser ?? new NoBrowser();
        _hotkeys = options.Hotkeys;
        _psnWindow = options.PsnWindow;
        _cpus = Math.Max(1, options.LogicalProcessors);
        _health = options.Health ?? new HealthRecorder();
        _gate = new FrameGate();
        _msClock = new TimerMsClock(_timers);

        // 1. Xbox hizmetinin jeton olayı.
        if (services.Xbox is { } xbox)
        {
            Action<string> onToken = t => Post(() => OnXboxTokenRefreshed(t));
            xbox.TokenRefreshed += onToken;
            _subscriptions.Add(new Unsubscribe(() => xbox.TokenRefreshed -= onToken));
        }

        // 2. Depodan okunanlar.
        LoadStoredState();

        // 3–6. Ayarlar ve açılış düzeltmeleri.
        _settings = settings.Load();
        var fixedUp = SettingsRules.ApplyStartupFixes(_settings, _cpus);
        services.FreeModel.SetCpuThreads(_settings.CpuTranslationThreads);
        services.FreeModel.SetDevice(_settings.TranslationDevice);
        if (fixedUp) _settingsStore.Save(_settings);

        // 7. İlk adım.
        _step = FirstStep();

        // 8. Altyazı sunucusu nesnesi (açılmaz).
        _server = services.CreateSubtitleServer(line => _logs.Subtitle(line));
        Action<int> onCount = n => Post(() => OnTvCountChanged(n));
        Action<string> onModel = m => Post(() => _tvModel = m);
        Action<Nino.Core.Link.LocalSubtitleEvent> onLocal = OnServerLocalEvent;
        Action<string> onAndroid = host => Post(() =>
        {
            if (_tv is { Brand: TvBrand.AndroidTv } tv && tv.Host != host) SaveTv(tv with { Host = host });
        });
        Action<Nino.Core.Link.TvLinkConnected> onLinkUp = e => Post(() =>
        {
            NoteTvLinkUp(e);
            TmTvConnected(e);
        });
        Action<Nino.Core.Link.TvLinkDropped> onLinkDown = e => Post(() =>
        {
            NoteTvLinkDown(e);
            TmTvDropped(e);
        });
        _server.TvConnected += onLinkUp;
        _server.TvDropped += onLinkDown;
        _server.AndroidTvHostFound += onAndroid;
        _server.TvCountChanged += onCount;
        _server.TvModelReported += onModel;
        _server.LocalEvent += onLocal;
        _subscriptions.Add(new Unsubscribe(() =>
        {
            _server.TvCountChanged -= onCount;
            _server.TvModelReported -= onModel;
            _server.LocalEvent -= onLocal;
            _server.AndroidTvHostFound -= onAndroid;
            _server.TvConnected -= onLinkUp;
            _server.TvDropped -= onLinkDown;
        }));
        _server.SendToTv = ShowsOnTv;

        // 9. Paketler ve havuzlar.
        StartPacksAndPools();

        // 10. Ücretsiz modelin olayları.
        Action onFailed = () => Post(OnFreeEngineFailed);
        Action onGpu = () => Post(() => _gpuFellBack = true);
        services.FreeModel.EngineFailedOnce += onFailed;
        services.FreeModel.GpuFellBack += onGpu;
        _subscriptions.Add(new Unsubscribe(() =>
        {
            services.FreeModel.EngineFailedOnce -= onFailed;
            services.FreeModel.GpuFellBack -= onGpu;
        }));

        // 11. Geçmiş.
        if (services.HistoryPath is { } historyPath)
        {
            try { _history.Load(historyPath); } catch (Exception e) { _logs.Error("Geçmiş okunamadı", e); }
        }

        // 12. Sorun bekçisi.
        _problems = CreateProblemWatcher(options.ProblemDelay);

        // 13. Ölçüm: önceki çalışma çöktüyse crash, sonra launch; havuzun uzak ayarı telemetry bloğunu da taşır.
        OpenTelemetry(options.Telemetry);

        RefreshTranslatorStatus();
        Snapshot(raise: false);
    }

    // ---------------------------------------------------------------------------------------------------------
    // Bildirim düzeni
    // ---------------------------------------------------------------------------------------------------------

    /// <inheritdoc />
    public event PropertyChangedEventHandler? PropertyChanged;

    static readonly PropertyInfo[] Observed = typeof(NinoController)
        .GetProperties(BindingFlags.Public | BindingFlags.Instance)
        .Where(p => p.GetIndexParameters().Length == 0 && p.GetCustomAttribute<NotObservedAttribute>() is null)
        .ToArray();

    readonly Dictionary<string, object?> _snapshot = [];
    bool _refreshing;
    bool _dirty;

    [AttributeUsage(AttributeTargets.Property)]
    sealed class NotObservedAttribute : Attribute;

    /// <summary>Değişen bütün özellikleri bildirir (değer aynıysa bildirim yok).</summary>
    void Refresh()
    {
        if (_refreshing)
        {
            _dirty = true;
            return;
        }
        _refreshing = true;
        try
        {
            do
            {
                _dirty = false;
                Snapshot(raise: true);
            } while (_dirty);
        }
        finally
        {
            _refreshing = false;
        }
        UpdateHotkeys();
    }

    void Snapshot(bool raise)
    {
        List<string>? changed = null;
        foreach (var p in Observed)
        {
            object? value;
            try { value = p.GetValue(this); } catch (Exception) { value = null; }
            if (_snapshot.TryGetValue(p.Name, out var old) && Equals(old, value)) continue;
            _snapshot[p.Name] = value;
            (changed ??= []).Add(p.Name);
        }
        if (!raise || changed is null) return;
        foreach (var name in changed) Raise(name);
    }

    void Raise([CallerMemberName] string name = "")
    {
        try { PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name)); }
        catch (Exception e) { _logs.Error("Ekran yenilenirken hata", e); }
    }

    /// <summary>İşi arayüz iş parçacığına aktarır, sonra ekranları yeniler.</summary>
    void Post(Action action) => _post(() =>
    {
        try { action(); }
        catch (Exception e) { _logs.Error("Arayüz işi hata verdi", e); }
        Refresh();
    });

    /// <summary>"await OnUi()": arayüz iş parçacığına döner.</summary>
    UiAwaitable OnUi() => new(_post);

    /// <summary>Arka plan işi: hatası günlüğe yazılır; testler <see cref="WhenIdleAsync"/> ile bekler.</summary>
    void Background(Func<Task> work)
    {
        Task t;
        try { t = work(); }
        catch (Exception e)
        {
            _logs.Error("Arka plan işi başlatılamadı", e);
            return;
        }
        lock (_background) _background.Add(t);
        _ = t.ContinueWith(done =>
        {
            if (done.Exception is { } ex) _logs.Error("Arka plan işi hata verdi", ex.GetBaseException());
            lock (_background) _background.Remove(done);
        }, TaskScheduler.Default);
    }

    /// <summary>Süren bütün arka plan işleri bitene kadar bekler (testler ve kapanış için).</summary>
    public async Task WhenIdleAsync()
    {
        for (var i = 0; i < 100; i++)
        {
            Task[] pending;
            lock (_background) pending = _background.ToArray();
            if (pending.Length == 0) return;
            try { await Task.WhenAll(pending).ConfigureAwait(false); } catch (Exception) { }
        }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Ayarlar (okunur)
    // ---------------------------------------------------------------------------------------------------------

    /// <summary>Ayarların kopyası (değiştirip <see cref="UpdateSettings"/>'e verilir).</summary>
    [NotObserved]
    public AppSettings Settings => _settings.Clone();

    /// <summary>Metin kataloğu.</summary>
    [NotObserved]
    public ITextSource Text => _text;

    /// <summary>Sağlık kaydedici.</summary>
    [NotObserved]
    public HealthRecorder Health => _health;

    // ---------------------------------------------------------------------------------------------------------
    // Kapanış (§18)
    // ---------------------------------------------------------------------------------------------------------

    /// <summary>Kapanıyor mu.</summary>
    public bool IsClosing => _closing;

    /// <summary>Uygulama kapanırken: durdur, abonelikleri çöz, sunucuyu ve havuzları kapat.</summary>
    public async ValueTask DisposeAsync()
    {
        if (_closing) return;
        _closing = true;
        foreach (var s in _subscriptions) s.Dispose();
        _subscriptions.Clear();
        Stop();
        var telemetry = CloseTelemetryAsync();
        _problems?.Dispose();
        try { _services.Xbox?.Dispose(); } catch (Exception) { }
        try { await _server.DisposeAsync().ConfigureAwait(false); } catch (Exception) { }
        StopTimers();
        try { _services.LinePool?.Close(); } catch (Exception) { }
        try { _services.Pool?.Save(); } catch (Exception) { }
        _hotkeys?.Release();
        try { await telemetry.ConfigureAwait(false); } catch (Exception) { }
    }

    // ---------------------------------------------------------------------------------------------------------
    // Küçük yardımcılar
    // ---------------------------------------------------------------------------------------------------------

    sealed class Unsubscribe(Action undo) : IDisposable
    {
        Action? _undo = undo;

        public void Dispose()
        {
            var u = Interlocked.Exchange(ref _undo, null);
            u?.Invoke();
        }
    }

    /// <summary>Arayüze dönüş beklemesi: devamı her zaman post ile çalıştırır.</summary>
    internal readonly struct UiAwaitable(Action<Action> post) : INotifyCompletion
    {
        public UiAwaitable GetAwaiter() => this;

        public bool IsCompleted => false;

        public void OnCompleted(Action continuation) => post(continuation);

        public void GetResult() { }
    }

    sealed class TimerMsClock(IShellTimers timers) : Nino.Core.Reading.IMsClock
    {
        public long NowMs => timers.Now.ToUnixTimeMilliseconds();
    }

    string LogHint() => _text.Format("status.sendLogFile", _logs.RemotePlayLogPath ?? RemotePlayLog.FileName);
}
