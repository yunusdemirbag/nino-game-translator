// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Imaging;
using Nino.Core.Library;
using Nino.Core.Link;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Text;
using Nino.Core.Translation;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Shell.Platform;
using Nino.Translation.Online;
using Nino.TvInstall;
using Nino.TvInstall.Samsung;

namespace Nino.Shell.Tests;

/// <summary>Elle ilerletilen saat ve zamanlayıcılar.</summary>
sealed class ManualTimers : IShellTimers
{
    readonly List<Entry> _entries = [];
    sealed class Entry
    {
        public DateTimeOffset Due;
        public TimeSpan? Period;
        public required Action Tick;
        public bool Cancelled;
    }

    sealed class Handle(Entry e) : IDisposable
    {
        public void Dispose() => e.Cancelled = true;
    }

    public DateTimeOffset Now { get; private set; } = new(2026, 11, 22, 12, 0, 0, TimeSpan.Zero);

    public IDisposable Every(TimeSpan period, Action tick)
    {
        var e = new Entry { Due = Now + period, Period = period, Tick = tick };
        lock (_entries) _entries.Add(e);
        return new Handle(e);
    }

    public IDisposable After(TimeSpan due, Action tick)
    {
        var e = new Entry { Due = Now + due, Tick = tick };
        lock (_entries) _entries.Add(e);
        return new Handle(e);
    }

    public int Active(TimeSpan period)
    {
        lock (_entries) return _entries.Count(e => !e.Cancelled && e.Period == period);
    }

    public void Advance(TimeSpan span)
    {
        var end = Now + span;
        while (true)
        {
            Entry? next;
            lock (_entries)
                next = _entries.Where(e => !e.Cancelled && e.Due <= end).OrderBy(e => e.Due).FirstOrDefault();
            if (next is null) break;
            Now = next.Due > Now ? next.Due : Now;
            if (next.Period is { } p) next.Due += p;
            else next.Cancelled = true;
            next.Tick();
        }
        Now = end;
    }
}

sealed class RecordingLogs : SilentShellLogs
{
    public readonly List<string> RemotePlayLines = [];
    public readonly List<string> SubtitleLines = [];
    public readonly List<string> Errors = [];
    public override string? RemotePlayLogPath => "/logs/remoteplay.log";
    public override void RemotePlay(string line) { lock (RemotePlayLines) RemotePlayLines.Add(line); }
    public override void Subtitle(string line) { lock (SubtitleLines) SubtitleLines.Add(line); }
    public override void Error(string message, Exception? error = null) { lock (Errors) Errors.Add(message + " " + error); }
}

sealed class FakeSleep : ISleepGuard
{
    public bool Active;
    public bool DisplayOn;
    public void Begin(bool keepDisplayOn)
    {
        Active = true;
        DisplayOn = keepDisplayOn;
    }

    public void End()
    {
        Active = false;
        DisplayOn = false;
    }
}

sealed class FakeBrowser : IBrowser
{
    public readonly List<string> Opened = [];
    public void Open(string url) => Opened.Add(url);
}

/// <summary>Altyazı sunucusu: olayları kaydeder, yerel özetini verir.</summary>
sealed class FakeServer : ISubtitleServer
{
    public readonly List<TvEvent> Events = [];
    public int StartCount;
    public bool FailStart;
    public event Action<int>? TvCountChanged;
    public event Action<string>? TvModelReported;
    public event Action<LocalSubtitleEvent>? LocalEvent;
    public event Action<string>? AndroidTvHostFound { add { } remove { } }
    public event Action<TvLinkConnected>? TvConnected;
    public event Action<TvLinkDropped>? TvDropped;
    public bool IsRunning { get; private set; }
    public int Port { get; private set; }
    public int TvCount { get; private set; }
    public bool SendToTv { get; set; } = true;
    public int AndroidConnects;

    public Task<int> StartAsync(CancellationToken cancellationToken = default)
    {
        StartCount++;
        if (FailStart) throw new InvalidOperationException("port");
        IsRunning = true;
        Port = 8787;
        return Task.FromResult(Port);
    }

    public void Send(TvEvent e)
    {
        lock (Events) Events.Add(e);
        if (TvWire.Local(e) is { } local) LocalEvent?.Invoke(local);
    }

    public IReadOnlyList<T> Of<T>() where T : TvEvent
    {
        lock (Events) return Events.OfType<T>().ToList();
    }

    public void SetTvCount(int n)
    {
        TvCount = n;
        TvCountChanged?.Invoke(n);
    }

    public void ReportModel(string m) => TvModelReported?.Invoke(m);

    /// <summary>Bağlantı olayı (sayıyı da bir artırır).</summary>
    public void LinkUp(long id, TvLinkKind kind, string address = "192.168.1.50", string? model = null, int tookMs = 0,
        string? appVersion = null)
    {
        TvConnected?.Invoke(new TvLinkConnected(id, kind, kind == TvLinkKind.Legacy ? 8787 : 47800, address, model, appVersion,
            TimeSpan.FromMilliseconds(tookMs)));
        SetTvCount(TvCount + 1);
    }

    /// <summary>Bitiş olayı (bağlıysa sayıyı bir azaltır).</summary>
    public void LinkDown(long id, TvLinkKind kind, TvLinkEndReason reason, bool wasConnected = true, string? detail = null,
        string address = "192.168.1.50")
    {
        TvDropped?.Invoke(new TvLinkDropped(id, kind, kind == TvLinkKind.Legacy ? 8787 : 47800, address, reason, wasConnected,
            TimeSpan.FromSeconds(1), null, null, detail));
        if (wasConnected) SetTvCount(Math.Max(0, TvCount - 1));
    }
    public string ServerAddress(string? localIp) => $"http://{localIp ?? "127.0.0.1"}:{(Port == 0 ? 8787 : Port)}";
    public string LaunchParameters(string? localIp) => "{\"server\":\"" + ServerAddress(localIp) + "\"}";
    public (string Local, string? Network) ObsAddresses(string? lanIp) =>
        ($"http://localhost:8787/obs", lanIp is null ? null : $"http://{lanIp}:8787/obs");
    public void ConnectAndroidTv(string? savedHost) => AndroidConnects++;
    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}

/// <summary>Yayın oturumu.</summary>
class FakeStream : IVideoSource
{
    public string Kind = "ps5";
    public bool Started;
    public bool Stopped;
    public int Reconnects;
    public Exception? StartError;
    public event Action<VideoFrame>? FrameArrived;
    public event Action<SourceStatus>? StatusChanged;
    public event Action<Ps5Console>? ConsoleMoved;

    public void Start()
    {
        if (StartError is not null) throw StartError;
        Started = true;
    }

    public void Stop() => Stopped = true;
    public void ReconnectNow() => Reconnects++;
    public void Dispose() { }
    public void Status(SourceStatus s) => StatusChanged?.Invoke(s);
    public void Move(Ps5Console c) => ConsoleMoved?.Invoke(c);

    public void Frame(BgraFrame f) => FrameArrived?.Invoke(new VideoFrame(f.Pixels, f.Width, f.Height, f.Stride));
}

sealed class FakeWindowSource : FakeStream, IGameWindowSource
{
    public GameConsole Console;
    public event Action<WindowCaptureState, string?>? WindowStateChanged;
    public event Action<PixelRect?>? GameAreaChanged;

    public void Window(WindowCaptureState state, string? app, PixelRect? area)
    {
        WindowStateChanged?.Invoke(state, app);
        GameAreaChanged?.Invoke(area);
        Status(state switch
        {
            WindowCaptureState.Capturing => SourceStatus.Streaming,
            WindowCaptureState.LookingForWindow => SourceStatus.Connecting,
            _ => SourceStatus.Down(DisconnectReason.Stopped),
        });
    }
}

sealed class FakeCardSource : FakeStream, ICaptureCardSource
{
    public bool ShowGame;
    public string? DeviceId;
    public int FullScreens;
    public event Action<CardStatus>? CardStatusChanged;
    public event Action<PixelRect?>? GameAreaChanged;
    public event Action? GameWindowClosed;
    public void ToggleFullScreen() => FullScreens++;

    public void Card(CardStatus status, PixelRect? area = null)
    {
        CardStatusChanged?.Invoke(status);
        if (area is not null) GameAreaChanged?.Invoke(area);
        Status(status.State switch
        {
            CardCaptureState.Capturing or CardCaptureState.BlackPicture => SourceStatus.Streaming,
            CardCaptureState.Stopped => SourceStatus.Down(DisconnectReason.Stopped),
            _ => SourceStatus.Connecting,
        });
    }

    public void CloseWindow() => GameWindowClosed?.Invoke();
}

sealed class FakeWatch(TvWatchRequest request) : ITvWatch
{
    public TvWatchRequest Request = request;
    public bool Running;
    public int Starts;
    public int Reconnects;
    public void Start() { Running = true; Starts++; }
    public void Stop() => Running = false;
    public void ReconnectNow() => Reconnects++;
}

/// <summary>"TR: " önekiyle yankılayan çevirmen.</summary>
sealed class EchoTranslator(string name = "echo") : ITranslator
{
    public string EngineName => name;
    public bool SupportsPretranslation => false;
    public bool SupportsBatch => false;
    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
        Task.FromResult(TranslationResult.FromEngine("TR: " + text));
    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;
    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
        this.TranslateOneByOneAsync(texts, cancellationToken);
}

/// <summary>Ücretsiz model: yalnız en→tr.</summary>
sealed class FakeModel : IFreeModel
{
    public bool Installed;
    public bool Failed;
    public int Downloads;
    public TaskCompletionSource? Gate;
    public Exception? DownloadError;
    public TranslationDevice Device;
    public int Threads;
    public event Action? EngineFailedOnce;
    public event Action? GpuFellBack;

    public bool Supports(string source, string target) => source == "en" && target == "tr";
    public bool IsInstalled(string source, string target) => Supports(source, target) && Installed;

    public async Task DownloadAsync(string source, string target, IProgress<double> progress, CancellationToken cancellationToken = default)
    {
        Downloads++;
        progress.Report(0.5);
        if (Gate is not null) await Gate.Task;
        if (DownloadError is not null) throw DownloadError;
        Installed = true;
    }

    public void SetDevice(TranslationDevice device) => Device = device;
    public void SetCpuThreads(int threads) => Threads = threads;
    public bool EngineFailed => Failed;

    public void Fail()
    {
        Failed = true;
        EngineFailedOnce?.Invoke();
    }

    public void FallBackToCpu() => GpuFellBack?.Invoke();
}

sealed class FakeFactory(FakeModel model) : ITranslatorFactory
{
    public Exception? CreateError;
    public readonly List<(string Key, ITranslator? Fallback)> DeepL = [];
    public readonly List<(AiService Service, string Model, string Key, LocalServer? Local)> Ai = [];

    public ITranslator CreateFree(string target)
    {
        if (CreateError is not null) throw CreateError;
        if (!model.Supports("en", target)) return new UnavailableTranslator(UnavailableReason.Unsupported);
        if (!model.Installed) return new UnavailableTranslator(UnavailableReason.DownloadRequired);
        if (model.Failed) return new UnavailableTranslator(UnavailableReason.EngineFailed);
        return new EchoTranslator("free");
    }

    public ITranslator CreateDeepL(string apiKey, string target, ITranslator? fallback)
    {
        DeepL.Add((apiKey, fallback));
        return new EchoTranslator("deepl");
    }

    public ITranslator CreateAi(AiService service, string model1, string apiKey, string target, LocalServer? local,
        ITranslator? fallback, Func<string?> gameName)
    {
        Ai.Add((service, model1, apiKey, local));
        return new EchoTranslator("ai");
    }
}

/// <summary>Sabit metin okuyan okuyucu.</summary>
sealed class FakeReader(Func<string> text) : ITextReader
{
    public string ReadText(BgraFrame image) => text();

    public OcrReading ReadLines(BgraFrame image, bool deep)
    {
        var t = text();
        return t.Length == 0 ? OcrReading.Empty : new OcrReading([new OcrLine(t, new Box(0.2, 0.4, 0.8, 0.6), 0.95)]);
    }
}

sealed class FakeReaders : ITextReaderFactory
{
    public string Text = "";
    public bool None;
    public bool Pack = true;
    public readonly List<string> Languages = [];
    public ITextReader? Create(string language)
    {
        lock (Languages) Languages.Add(language);
        return None ? null : new FakeReader(() => Text);
    }

    public bool HasLanguagePack(string language) => Pack;

    /// <summary>Küçük JPEG kodlayıcısı (buzlu zemin, oyun tanıma); null: kodlayıcı yok.</summary>
    public Func<BgraFrame, int, int, byte[]?>? Jpeg;

    public byte[]? SmallJpeg(BgraFrame frame, int maxWidth, int quality) => Jpeg?.Invoke(frame, maxWidth, quality);
}

/// <summary>Sahte dünya: PS5 192.168.1.253 "PS5-789" uyanık, TV "LG TV" 192.168.1.153, LG parolası ABC123.</summary>
sealed class FakeServices : IShellServices
{
    public string? RegionCode { get; set; } = "US";
    public string? AccountName { get; set; } = "yunus.demir";
    public readonly FakeModel Model = new();
    public readonly FakeFactory Factory;
    public readonly FakeReaders ReaderFactory = new();
    public readonly FakeServer Server = new();
    public readonly List<FakeStream> Ps5Sessions = [];
    public readonly List<FakeWindowSource> WindowSources = [];
    public readonly List<FakeCardSource> CardSources = [];
    public readonly List<FakeStream> RemotePlayWindowSources = [];
    public readonly List<RemotePlayApp> RemotePlayApps = [];
    public readonly List<FakeStream> ChosenSources = [];
    public readonly List<FakeWatch> Watches = [];
    public readonly List<string?> Passcodes = [];
    public Exception? Ps5Error;
    public Exception? RegisterError;
    public Exception? SignInError;
    public bool RemotePlayInstalled = true;
    public int TvCalls;
    public int Pairs;
    public string PairKey = "tv-key";
    public bool PairLaunched = true;
    public FoundTv FoundTv = new("LG TV", "192.168.1.153", TvBrand.Lg);

    // LG
    public string? LgPackage = "0.6.1";
    public bool LgDevOpen;
    public string? LgOnTv = "0.6.1";
    public int LgInstalls;
    public TvError? LgKeyError;
    public bool LgKeyRejected;
    public int Renewals;

    // Samsung / Android
    public TvAppPackage? SamsungPackage;
    public TvAppPackage? AndroidPackage;
    public SamsungPrecheck Precheck = SamsungPrecheck.Unknown;
    public bool SamsungGate = true;
    public Func<TvInstallEvents, TvInstallResult>? SamsungInstall;
    public int SamsungInstalls;
    public bool AdbOpen;

    // Güncelleme denetimi
    public IAppUpdater? UpdaterService;
    public IAppUpdater? Updater => UpdaterService;
    public bool TvOn;
    public int TvAwakeCalls;

    // Sorun bildirimi
    public string? HealthDir;
    public string? HealthFolder => HealthDir;
    public readonly List<Nino.Core.Support.ReportBody> Reports = [];
    public Nino.Core.Support.ReportStatus ReportAnswer = Nino.Core.Support.ReportStatus.Sent;

    public Task<Nino.Core.Support.ReportResult> SendReportAsync(Nino.Core.Support.ReportBody body,
        CancellationToken cancellationToken = default)
    {
        Reports.Add(body);
        return Task.FromResult(new Nino.Core.Support.ReportResult(ReportAnswer));
    }

    public Task<bool> TvAwakeAsync(TvRecord tv, CancellationToken cancellationToken = default)
    {
        TvAwakeCalls++;
        return Task.FromResult(TvOn);
    }
    public List<string> AdbScan = [];
    public Func<string, TvInstallEvents, TvInstallResult>? AndroidInstall;

    // Çeviri anahtarları
    public KeyCheckStatus DeepLAnswer = KeyCheckStatus.Valid;
    public KeyCheckStatus AiAnswer = KeyCheckStatus.Valid;
    public readonly List<string> DeepLTried = [];
    public readonly List<(AiService Service, string Model, string Key, LocalServer? Local)> AiTried = [];

    public IFirewall? FirewallService;
    public TranslationPool? PoolService;
    public PackLibrary? PackService;
    public IXboxService? XboxService;

    public FakeServices() => Factory = new FakeFactory(Model);

    public Task<IReadOnlyList<FoundPs5>> FindPs5Async(string? host, CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<FoundPs5>>([new FoundPs5("192.168.1.253", "PS5-789", true)]);

    public Task<byte[]> AccountIdFromRedirectAsync(string redirectUrl, CancellationToken cancellationToken = default) =>
        SignInError is not null ? Task.FromException<byte[]>(SignInError) : Task.FromResult(Enumerable.Repeat((byte)1, 8).ToArray());

    public Task<Ps5Console> RegisterPs5Async(string host, byte[] accountId, uint pin, CancellationToken cancellationToken = default) =>
        RegisterError is not null ? Task.FromException<Ps5Console>(RegisterError)
            : Task.FromResult(new Ps5Console(host, "PS5-789", Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray()));

    public IVideoSource CreatePs5Source(Ps5Console console, byte[] accountId, string? loginPasscode)
    {
        if (Ps5Error is not null) throw Ps5Error;
        Passcodes.Add(loginPasscode);
        var s = new FakeStream();
        Ps5Sessions.Add(s);
        return s;
    }

    public IXboxService? Xbox => XboxService;

    public IGameWindowSource? CreateGameWindowSource(GameConsole console)
    {
        var s = new FakeWindowSource { Console = console, Kind = "window" };
        WindowSources.Add(s);
        return s;
    }

    public ICaptureCardSource? CreateCaptureCardSource(bool showGameHere, string? preferredDeviceId)
    {
        var s = new FakeCardSource { ShowGame = showGameHere, DeviceId = preferredDeviceId, Kind = "card" };
        CardSources.Add(s);
        return s;
    }

    public IVideoSource CreateRemotePlayWindowSource(RemotePlayApp app)
    {
        RemotePlayApps.Add(app);
        var s = new FakeStream { Kind = "rpwindow" };
        RemotePlayWindowSources.Add(s);
        return s;
    }

    public IVideoSource CreateChosenWindowSource(CaptureWindowChoice window)
    {
        var s = new FakeStream { Kind = "chosen:" + window.ProcessName + "/" + window.Title };
        ChosenSources.Add(s);
        return s;
    }

    public bool IsRemotePlayAppInstalled(RemotePlayApp app) => RemotePlayInstalled;

    public ISubtitleServer CreateSubtitleServer(Action<string> subtitleLog) => Server;

    public string? AddressNear(string? tvHost) => "192.168.1.34";

    public Task<IReadOnlyList<FoundTv>> FindTvsAsync(CancellationToken cancellationToken = default)
    {
        TvCalls++;
        return Task.FromResult<IReadOnlyList<FoundTv>>([FoundTv]);
    }

    public Task<PairResult> PairTvAsync(TvRecord tv, string? savedKey, string launchParameters, CancellationToken cancellationToken = default)
    {
        TvCalls++;
        Pairs++;
        return Task.FromResult(new PairResult(PairKey, PairLaunched));
    }

    public ITvWatch CreateTvWatch(TvWatchRequest request)
    {
        TvCalls++;
        var w = new FakeWatch(request);
        Watches.Add(w);
        return w;
    }

    public string? LgPackageVersion => LgPackage;

    public Task<bool> LgDevModeOpenAsync(string host, CancellationToken cancellationToken = default)
    {
        TvCalls++;
        return Task.FromResult(LgDevOpen);
    }

    public Task<string> LgFetchKeyAsync(string host, string passphrase, CancellationToken cancellationToken = default)
    {
        TvCalls++;
        if (LgKeyError is { } e) throw new TvException(e);
        return passphrase == "ABC123" ? Task.FromResult("dev-key") : throw new TvException(TvError.WrongPassphrase);
    }

    public Task<string?> LgInstalledVersionAsync(string host, string devKey, CancellationToken cancellationToken = default)
    {
        TvCalls++;
        if (LgKeyRejected) throw new TvException(TvError.KeyRejected);
        return Task.FromResult(LgOnTv);
    }

    public Task LgInstallAsync(string host, string devKey, CancellationToken cancellationToken = default)
    {
        LgInstalls++;
        LgOnTv = LgPackage;
        return Task.CompletedTask;
    }

    public Task<int?> LgRenewDevModeAsync(string host, string devKey, CancellationToken cancellationToken = default)
    {
        Renewals++;
        return Task.FromResult<int?>(999);
    }

    public TvAppPackage? PackageFor(TvBrand brand) => brand switch
    {
        TvBrand.Samsung => SamsungPackage,
        TvBrand.AndroidTv => AndroidPackage,
        _ => null,
    };

    public Task<bool> SamsungDevModeOpenAsync(string host, CancellationToken cancellationToken = default) => Task.FromResult(SamsungGate);

    public Task<SamsungPrecheck> SamsungPrecheckAsync(string host, CancellationToken cancellationToken = default) => Task.FromResult(Precheck);

    public Task<TvInstallResult> SamsungInstallAsync(string host, TvInstallEvents events, CancellationToken cancellationToken = default)
    {
        SamsungInstalls++;
        try { return Task.FromResult(SamsungInstall!(events)); }
        catch (Exception e) { return Task.FromException<TvInstallResult>(e); }
    }

    public Task<bool> AndroidAdbOpenAsync(string host, CancellationToken cancellationToken = default) => Task.FromResult(AdbOpen);

    public Task<IReadOnlyList<string>> AndroidScanAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<string>>(AdbScan);

    public Task<TvInstallResult> AndroidInstallAsync(string host, TvInstallEvents events, CancellationToken cancellationToken = default) =>
        Task.FromResult(AndroidInstall!(host, events));

    public ITextReaderFactory Readers => ReaderFactory;
    public IFreeModel FreeModel => Model;
    public ITranslatorFactory Translators => Factory;

    public Task<KeyCheckStatus> TryDeepLKeyAsync(string key, CancellationToken cancellationToken = default)
    {
        DeepLTried.Add(key);
        return Task.FromResult(DeepLAnswer);
    }

    public Task<KeyCheckStatus> TryAiKeyAsync(AiService service, string model, string key, string target, LocalServer? local,
        CancellationToken cancellationToken = default)
    {
        AiTried.Add((service, model, key, local));
        return Task.FromResult(AiAnswer);
    }

    public IFirewall? Firewall => FirewallService;
    public TranslationPool? Pool => PoolService;
    public PackLibrary? Packs => PackService;
}

sealed class FakeFirewall : IFirewall
{
    public bool Rule;
    public bool Public;
    public bool Allow = true;
    public int Scans;
    public Task<bool> HasPrivateRuleAsync(CancellationToken cancellationToken = default)
    {
        Scans++;
        return Task.FromResult(Rule);
    }

    public Task<bool> AddRuleAsync(CancellationToken cancellationToken = default)
    {
        if (Allow) Rule = true;
        return Task.FromResult(Allow);
    }

    public Task<bool> IsOnPublicNetworkAsync(CancellationToken cancellationToken = default) => Task.FromResult(Public);
}

/// <summary>Bir denetleyici kurulumu: depo, ayarlar, hizmetler ve yeniden açılış.</summary>
sealed class World
{
    public readonly MemorySecretStore Secrets = new();
    public readonly MemorySettingsStore SettingsStore;
    public readonly FakeServices Services = new();
    public readonly FakeSleep Sleep = new();
    public readonly ManualTimers Timers = new();
    public readonly RecordingLogs Logs = new();
    public readonly FakeBrowser Browser = new();
    public ITextSource Text = TextCatalog.For("en");

    public World(AppSettings? settings = null) => SettingsStore = new MemorySettingsStore(settings);

    public NinoController Open() => new(Services, Secrets, SettingsStore, Sleep, Text, a => a(), new ShellOptions
    {
        Timers = Timers,
        Logs = Logs,
        Browser = Browser,
        LogicalProcessors = 8,
        ProblemDelay = (_, ct) => Task.Delay(Timeout.Infinite, ct),
    });

    public static byte[] Account => Enumerable.Repeat((byte)1, 8).ToArray();

    public static StoredConsole Ps5 => new()
    {
        Host = "192.168.1.253",
        Name = "PS5-789",
        RegistKey = Enumerable.Repeat((byte)0x31, 16).ToArray(),
        Morning = Enumerable.Repeat((byte)2, 16).ToArray(),
    };

    public World WithPs5()
    {
        Secrets.Set(SecretKeys.AccountId, Account);
        Secrets.Set(SecretKeys.Console, Ps5);
        return this;
    }

    public World WithTv(StoredTvBrand brand = StoredTvBrand.Lg, string key = "tv-key", string host = "192.168.1.153",
        string name = "LG TV")
    {
        Secrets.Set(SecretKeys.Tv, new StoredTv { Name = name, Host = host, Brand = brand });
        Secrets.Set(SecretKeys.TvKey, key);
        return this;
    }

    public AppSettings Saved => SettingsStore.Load();

    public static BgraFrame Frame() => BgraFrame.Filled(64, 36, 0);
}
