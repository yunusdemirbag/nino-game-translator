// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Library;
using Nino.Core.Link;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Translation;
using Nino.Translation.Local;
using Nino.Translation.Online;
using Nino.TvInstall;
using Nino.TvInstall.Android;
using Nino.TvInstall.Samsung;
using RpLog = Nino.RemotePlay.RemotePlayLog;

namespace Nino.Shell.Platform;

/// <summary>
/// <see cref="CoreShellServices"/>'in kurulumu. Veri klasörü DIŞARIDAN verilir (denetleyici ve bu sınıf veri klasörünü
/// kendisi bulmaz): Windows açılışı <c>NinoDataFolder.Prepare()</c> sonucunu, Linux kendi yolunu (<c>NINO_DATA</c>) verir.
/// </summary>
public sealed record CoreShellServicesOptions
{
    /// <summary>Veri klasörü (<c>%LOCALAPPDATA%\Nino</c> ya da Linux'un klasörü).</summary>
    public required string DataFolder { get; init; }

    /// <summary>Şifreli depo (Samsung istemci adı burada saklanır).</summary>
    public required ISecretStore Secrets { get; init; }

    /// <summary>Paylaşılan HTTP istemcisi.</summary>
    public required HttpClient Http { get; init; }

    /// <summary>Nino'nun sürümü.</summary>
    public string AppVersion { get; init; } = "0.0.0";

    /// <summary>Paketle gelen TV uygulamalarının klasörü (exe'nin yanındaki <c>tv-app</c>); yoksa null.</summary>
    public string? TvAppFolder { get; init; }

    /// <summary>
    /// Eski ONNX Türkçe modelini (<c>models/en-tr</c>) silme ve kuruluysa onu kullan (<see cref="FreeModelStore"/>).
    /// Windows: false; Linux sunucusu: true (Python/CTranslate2 olmadan çalışır).
    /// </summary>
    public bool KeepLegacyTurkish { get; init; }

    /// <summary>Ücretsiz model hiç olmasın (ör. yalnız çevrimiçi çeviri).</summary>
    public bool NoFreeModel { get; init; }

    /// <summary>
    /// ONNX ücretsiz motorunu ayrı süreçte açan işlev (model klasörü, hedef belirteci); null ise bu süreçte açılır.
    /// Windows: Nino'nun kendi exe'si işçi kipinde (yerel bir hata uygulamayı kapatmasın).
    /// </summary>
    public Func<string, string?, IWorkerProcess>? OnnxWorker { get; init; }

    /// <summary>Remote Play günlüğü (yerel köprü satırları dahil).</summary>
    public RpLog RemotePlayLog { get; init; } = RpLog.Silent();

    /// <summary>Remote Play yerel köprüsü.</summary>
    public Nino.RemotePlay.Bridge.IRemotePlayBridge? Bridge { get; init; }

    /// <summary>Gönderici kimliği (<c>/nino/info</c>).</summary>
    public SenderIdentity? Identity { get; init; }

    /// <summary>Çeviri havuzu ve satır havuzu sunucusu (null: havuz yok).</summary>
    public Uri? PoolEndpoint { get; init; }

    /// <summary>Paket sunucusu (null: paket güncelleyici yok).</summary>
    public Uri? PackServer { get; init; }

    /// <summary>Tarayıcıda açma (Samsung oturumu).</summary>
    public Action<string>? OpenBrowser { get; init; }

    /// <summary>
    /// NVIDIA sürücüsü var mı (Windows: <c>%WINDIR%\System32\nvcuda.dll</c>). Verilirse ücretsiz modelin GPU seçeneği
    /// için CUDA çalışma zamanı deposu (<c>cuda-12.8</c>) kurulur; null ise (Linux) GPU yok, CPU'da kalınır.
    /// </summary>
    public Func<bool>? CudaDriverPresent { get; init; }

    /// <summary>Hata günlüğü (CUDA indirme hatası gibi arka plan hataları); null ise yazılmaz.</summary>
    public Action<string, Exception?>? ErrorLog { get; init; }
}

/// <summary>
/// Hizmetlerin platformdan bağımsız gerçek bağlantısı: PS5 (Nino.RemotePlay), TV (Nino.Core.Tv, Nino.TvInstall),
/// altyazı sunucusu (<see cref="TvOutput"/>), çevirmenler (<see cref="NinoTranslatorFactory"/>), paketler ve havuzlar.
/// Platform yalnız <see cref="Readers"/>'ı ve isteğe bağlı üyeleri (pencere/kart kaynakları, güvenlik duvarı,
/// güncelleyici, Xbox) doldurur. Windows (Nino.App) ve Linux bundan türetir.
/// </summary>
public abstract class CoreShellServices : IShellServices, IDisposable
{
    readonly CoreShellServicesOptions _o;
    readonly NinoTranslatorFactory _factory;
    readonly StoreFreeModel _model;
    readonly Nino.RemotePlay.Bridge.IRemotePlayBridge _bridge;
    readonly TvDiscovery _discovery;

    /// <summary>Kurar.</summary>
    protected CoreShellServices(CoreShellServicesOptions options)
    {
        _o = options;
        _bridge = options.Bridge ?? Nino.RemotePlay.Bridge.NativeBridge.Shared;
        _discovery = new TvDiscovery(options.Http);
        var downloader = new ModelDownloader(options.Http);
        FreeModelStore? store = options.NoFreeModel ? null
            : new FreeModelStore(Path.Combine(options.DataFolder, "models"), downloader, keepLegacyTurkish: options.KeepLegacyTurkish);
        var cuda = store is not null && options.CudaDriverPresent is { } driver
            ? new CudaRuntimeStore(Path.Combine(options.DataFolder, CudaCatalog.Folder), downloader, driver)
            : null;
        _model = new StoreFreeModel(store, cuda, options.ErrorLog);
        _factory = new NinoTranslatorFactory(new TranslatorFactoryOptions
        {
            CacheFolder = Path.Combine(options.DataFolder, "translations"),
            // Kullanıcı terim sözlükleri (glossary\*.json) genel sözlüğün üstüne ad sırasıyla eklenir.
            Glossary = new GlossaryFolder(Path.Combine(options.DataFolder, "glossary")),
            Http = options.Http,
            Free = store is null ? null : new FreeEngineOptions
            {
                Store = store, Cuda = cuda, GpuFellBack = _model.OnGpuFellBack,
                OnnxWorker = options.OnnxWorker,
                Log = line => options.ErrorLog?.Invoke(line, null),
            },
            FreeEngineFailed = _ => _model.OnEngineFailed(),
        });
        _model.Factory = _factory;
        Packs = new PackLibrary(Path.Combine(options.DataFolder, "packs"));
        if (options.PoolEndpoint is { } endpoint)
        {
            Pool = new TranslationPool(new TranslationPoolOptions(Path.Combine(options.DataFolder, "pool-translations"),
                endpoint, options.AppVersion, options.Http), SettingsRules.FallbackTargetLanguage, sharePool: true);
            LinePool = new LineQueue(new LineQueueOptions(Path.Combine(options.DataFolder, "pool"), endpoint,
                options.AppVersion, options.Http));
        }
        if (options.PackServer is { } packServer)
            PackUpdater = new PackUpdater(Path.Combine(options.DataFolder, "packs"),
                Path.Combine(options.DataFolder, "packs-remote.json"), packServer, options.Http);
    }

    /// <summary>Veri klasörü.</summary>
    protected string DataFolder => _o.DataFolder;

    // ---- PS5 ----

    /// <inheritdoc />
    public virtual Task<IReadOnlyList<FoundPs5>> FindPs5Async(string? host, CancellationToken cancellationToken = default) =>
        new Ps5Finder(_bridge).SearchAsync(host, cancel: cancellationToken);

    /// <inheritdoc />
    public virtual async Task<byte[]> AccountIdFromRedirectAsync(string redirectUrl, CancellationToken cancellationToken = default)
    {
        using var client = new PsnAccountClient();
        return await client.AccountIdAsync(redirectUrl, cancellationToken).ConfigureAwait(false);
    }

    /// <inheritdoc />
    public virtual Task<Ps5Console> RegisterPs5Async(string host, byte[] accountId, uint pin, CancellationToken cancellationToken = default) =>
        new Ps5Pairing(_bridge, _o.RemotePlayLog).PairAsync(host, pin, accountId, cancellationToken);

    /// <inheritdoc />
    public virtual IVideoSource CreatePs5Source(Ps5Console console, byte[] accountId, string? loginPasscode) =>
        new Ps5Source(new Ps5SourceOptions
        {
            Console = console,
            AccountId = accountId,
            LoginPasscode = loginPasscode,
            Bridge = _bridge,
            Log = _o.RemotePlayLog,
        });

    /// <inheritdoc />
    public virtual Task<FoundPs5?> RunningGameAsync(string host, CancellationToken cancellationToken = default) =>
        new Ps5Finder(_bridge).RunningGameAsync(host, cancellationToken);

    // ---- TV ----

    /// <inheritdoc />
    public virtual ISubtitleServer CreateSubtitleServer(Action<string> subtitleLog) =>
        new TvOutputServer(new TvOutput(new TvOutputOptions { Log = subtitleLog, Identity = _o.Identity ?? new SenderIdentity() }));

    /// <inheritdoc />
    public virtual string? AddressNear(string? tvHost) => LocalNetwork.AddressNear(tvHost);

    /// <inheritdoc />
    public virtual Task<IReadOnlyList<FoundTv>> FindTvsAsync(CancellationToken cancellationToken = default) =>
        _discovery.FindAllAsync(cancellationToken);

    TvConnect Connect(TvBrand brand, string? savedKey)
    {
        if (brand != TvBrand.Samsung) return TvRemoteFactory.For(brand);
        var (name, store) = SamsungRemote.ChooseClientName(_o.Secrets.Get<string>(SecretKeys.SamsungClientName),
            !string.IsNullOrEmpty(savedKey));
        if (store) _o.Secrets.Set(SecretKeys.SamsungClientName, name);
        return TvRemoteFactory.For(brand, name);
    }

    /// <inheritdoc />
    public virtual Task<PairResult> PairTvAsync(TvRecord tv, string? savedKey, string launchParameters,
        CancellationToken cancellationToken = default) =>
        TvPairing.PairAsync(tv, savedKey, launchParameters, tv.Brand == TvBrand.AndroidTv ? null : Connect(tv.Brand, savedKey),
            cancellationToken);

    /// <inheritdoc />
    public virtual ITvWatch CreateTvWatch(TvWatchRequest request)
    {
        if (request.Tv.Brand == TvBrand.AndroidTv) return new IdleWatch();
        var keeper = new TvKeeper(new TvKeeperOptions
        {
            Tv = request.Tv,
            Key = request.Key,
            LaunchParameters = request.LaunchParameters,
            TvAppConnected = request.TvAppConnected,
            KeyChanged = request.KeyChanged,
            Moved = request.Moved,
            Connect = Connect(request.Tv.Brand, request.Key),
            Find = TvRemoteFactory.Finder(_discovery),
            Interval = request.Interval,
        });
        return new KeeperWatch(keeper);
    }

    sealed class IdleWatch : ITvWatch
    {
        public void Start() { }
        public void Stop() { }
        public void ReconnectNow() { }
    }

    sealed class KeeperWatch(TvKeeper keeper) : ITvWatch
    {
        public void Start() => keeper.Start();
        public void Stop() => _ = keeper.StopAsync();
        public void ReconnectNow() => _ = keeper.ReconnectAsync();
    }

    TvAppPackage? LgPackage => _o.TvAppFolder is { } f ? TvAppPackages.FindLg(f) : null;

    /// <inheritdoc />
    public virtual string? LgPackageVersion => LgPackage?.Version;

    /// <inheritdoc />
    public virtual Task<bool> LgDevModeOpenAsync(string host, CancellationToken cancellationToken = default) =>
        LgDevMode.IsOpenAsync(host, cancellationToken);

    /// <inheritdoc />
    public virtual Task<string> LgFetchKeyAsync(string host, string passphrase, CancellationToken cancellationToken = default) =>
        LgDevMode.FetchKeyAsync(host, passphrase, _o.Http, cancellationToken);

    /// <inheritdoc />
    public virtual Task<string?> LgInstalledVersionAsync(string host, string devKey, CancellationToken cancellationToken = default) =>
        new LgInstaller(new SshLgShell(host, devKey)).InstalledVersionAsync(cancellationToken);

    /// <inheritdoc />
    public virtual Task LgInstallAsync(string host, string devKey, CancellationToken cancellationToken = default) =>
        LgPackage is { } p
            ? new LgInstaller(new SshLgShell(host, devKey)).InstallAsync(p.Path, p.Version, cancellationToken)
            : throw new TvException(TvError.InstallFailed, "paket yok");

    /// <inheritdoc />
    public virtual Task<int?> LgRenewDevModeAsync(string host, string devKey, CancellationToken cancellationToken = default) =>
        LgDevSession.RenewAsync(new SshLgShell(host, devKey), _o.Http, cancellationToken);

    /// <inheritdoc />
    public virtual TvAppPackage? PackageFor(TvBrand brand) => _o.TvAppFolder is not { } f ? null : brand switch
    {
        TvBrand.Samsung => TvAppPackages.FindSamsung(f),
        TvBrand.AndroidTv => TvAppPackages.FindAndroid(f),
        _ => null,
    };

    /// <inheritdoc />
    public virtual Task<bool> SamsungDevModeOpenAsync(string host, CancellationToken cancellationToken = default) =>
        SamsungDeviceInfo.IsInstallPortOpenAsync(host, cancellationToken);

    /// <inheritdoc />
    public virtual async Task<SamsungPrecheck> SamsungPrecheckAsync(string host, CancellationToken cancellationToken = default)
    {
        var info = await SamsungDeviceInfo.FetchAsync(_o.Http, host, cancellationToken).ConfigureAwait(false);
        return new SamsungPrecheck(info, AddressNear(host));
    }

    InstallLog TvInstallLog => new(Path.Combine(_o.DataFolder, Nino.Core.Logging.LogNames.TvInstall));

    /// <inheritdoc />
    public virtual async Task<TvInstallResult> SamsungInstallAsync(string host, TvInstallEvents events,
        CancellationToken cancellationToken = default)
    {
        if (PackageFor(TvBrand.Samsung) is not { } package) throw new TvException(TvError.InstallFailed, "paket yok");
        var login = new SamsungLogin();
        try
        {
            return await new SamsungInstaller(_o.Http).InstallAsync(new SamsungInstallRequest
            {
                Host = host,
                ProfilesRoot = Path.Combine(_o.DataFolder, "samsung"),
                PackagePath = package.Path,
                PackageVersion = package.Version,
                Log = TvInstallLog,
                OnProgress = events.Progress,
                SignInAsync = ct => login.RunAsync(url => events.SignInWaiting(url), ct),
            }, cancellationToken).ConfigureAwait(false);
        }
        catch (TvInstallException e)
        {
            throw new TvException(Map(e.Failure), e.Detail, e);
        }
    }

    /// <inheritdoc />
    public virtual async Task<bool> TvAwakeAsync(TvRecord tv, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(tv.Host)) return false;
        using var any = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        any.CancelAfter(TimeSpan.FromSeconds(2));
        async Task<bool> Probe(int port)
        {
            try
            {
                using var client = new System.Net.Sockets.TcpClient();
                await client.ConnectAsync(tv.Host.Trim(), port, any.Token).ConfigureAwait(false);
                return true;
            }
            catch (Exception) { return false; }
        }
        var probes = UpdateRules.WakePorts(tv.Brand).Select(Probe).ToList();
        while (probes.Count > 0)
        {
            var done = await Task.WhenAny(probes).ConfigureAwait(false);
            probes.Remove(done);
            if (await done.ConfigureAwait(false))
            {
                await any.CancelAsync().ConfigureAwait(false);
                return true;
            }
        }
        return false;
    }

    /// <inheritdoc />
    public virtual Task<bool> AndroidAdbOpenAsync(string host, CancellationToken cancellationToken = default) =>
        AndroidTvAppInstaller.IsReachableAsync(host, ct: cancellationToken);

    /// <inheritdoc />
    public virtual Task<IReadOnlyList<string>> AndroidScanAsync(CancellationToken cancellationToken = default) =>
        AndroidTvAppInstaller.ScanAsync(cancellationToken);

    /// <inheritdoc />
    public virtual async Task<TvInstallResult> AndroidInstallAsync(string host, TvInstallEvents events,
        CancellationToken cancellationToken = default)
    {
        if (PackageFor(TvBrand.AndroidTv) is not { } package) throw new TvException(TvError.InstallFailed, "paket yok");
        try
        {
            return await new AndroidTvAppInstaller().InstallAsync(host, package.Path, package.Version,
                Path.Combine(_o.DataFolder, "adb"), events.ApprovalWaiting, cancellationToken).ConfigureAwait(false);
        }
        catch (TvInstallException e)
        {
            throw new TvException(Map(e.Failure), e.Detail, e);
        }
    }

    static TvError Map(TvInstallFailure f) => f switch
    {
        TvInstallFailure.Unreachable => TvError.Unreachable,
        TvInstallFailure.LoginFailed => TvError.LoginFailed,
        TvInstallFailure.CertificateFailed => TvError.CertificateFailed,
        TvInstallFailure.TooOld => TvError.TooOld,
        TvInstallFailure.NotEnoughSpace => TvError.NotEnoughSpace,
        TvInstallFailure.CertificateMismatch => TvError.CertificateMismatch,
        TvInstallFailure.CertificateRejected => TvError.CertificateRejected,
        TvInstallFailure.TvClockWrong => TvError.TvClockWrong,
        TvInstallFailure.PackageBlocked => TvError.PackageBlocked,
        TvInstallFailure.ConnectionLost => TvError.ConnectionLost,
        TvInstallFailure.NotApproved => TvError.NotApproved,
        _ => TvError.InstallFailed,
    };

    // ---- Yazı tanıma (platform) ----

    /// <inheritdoc />
    public abstract ITextReaderFactory Readers { get; }

    // ---- Çeviri ----

    /// <inheritdoc />
    public IFreeModel FreeModel => _model;

    /// <inheritdoc />
    public ITranslatorFactory Translators => _factory;

    /// <inheritdoc />
    public virtual async Task<KeyCheckStatus> TryDeepLKeyAsync(string key, CancellationToken cancellationToken = default) =>
        (await DeepLTranslator.CheckUsageAsync(key, _o.Http, cancellationToken).ConfigureAwait(false)).Status;

    /// <inheritdoc />
    public virtual async Task<KeyCheckStatus> TryAiKeyAsync(AiService service, string model, string key, string target,
        LocalServer? local, CancellationToken cancellationToken = default) =>
        (await AiKeyCheck.RunAsync(service, model, key, target, _o.Http, local, cancellationToken).ConfigureAwait(false)).Status;

    // ---- Paketler, havuz, geçmiş, sağlık ----

    /// <inheritdoc />
    public PackLibrary? Packs { get; }

    /// <inheritdoc />
    public LineQueue? LinePool { get; }

    /// <inheritdoc />
    public TranslationPool? Pool { get; }

    /// <inheritdoc />
    public PackUpdater? PackUpdater { get; }

    /// <inheritdoc />
    public virtual string? HistoryPath => Path.Combine(_o.DataFolder, SubtitleHistory.FileName);

    /// <inheritdoc />
    public virtual string? HealthFolder => _o.DataFolder;

    /// <inheritdoc />
    public virtual string? AutoUpdateCounterPath => Path.Combine(_o.DataFolder, AutoUpdateAttempts.FileName);

    /// <inheritdoc />
    public string AppVersion => _o.AppVersion;

    /// <inheritdoc />
    public virtual Nino.Core.Telemetry.ITelemetrySender? TelemetrySender => _o.PoolEndpoint is { } root
        ? new Nino.Core.Telemetry.HttpTelemetrySender(_o.Http, Nino.Core.Library.PoolEndpoint.Combine(root, "v1/events"))
        : null;

    readonly Lazy<Nino.Core.Health.SystemNetworkWatch> _network = new(() => new Nino.Core.Health.SystemNetworkWatch());

    /// <inheritdoc />
    public virtual Nino.Core.Health.INetworkWatch? NetworkWatch => _network.Value;

    /// <inheritdoc />
    public virtual Task<Nino.Core.Support.ReportResult> SendReportAsync(Nino.Core.Support.ReportBody body,
        CancellationToken cancellationToken = default) =>
        new Nino.Core.Support.ReportClient(_o.Http, _o.PoolEndpoint).SendAsync(body, cancellationToken);

    /// <inheritdoc />
    public virtual void Dispose()
    {
        _factory.Dispose();
        if (_network.IsValueCreated) _network.Value.Dispose();
    }

    /// <summary>Ücretsiz model: <see cref="FreeModelStore"/> + <see cref="NinoTranslatorFactory"/> aygıt ayarı.</summary>
    sealed class StoreFreeModel(FreeModelStore? store, CudaRuntimeStore? cuda, Action<string, Exception?>? errorLog) : IFreeModel
    {
        TranslationDevice _device;
        int _threads = 2;
        volatile bool _failed;

        public NinoTranslatorFactory? Factory { get; set; }

        public bool Supports(string source, string target) => store is not null && TargetLanguages.FreeModelSupports(source, target);

        public bool IsInstalled(string source, string target) => Supports(source, target) && store!.IsInstalled(target);

        public Task DownloadAsync(string source, string target, IProgress<double> progress, CancellationToken cancellationToken = default) =>
            store is null ? Task.CompletedTask : store.DownloadAsync(target, progress, cancellationToken);

        public void SetDevice(TranslationDevice device)
        {
            _device = device;
            if (device == TranslationDevice.Gpu) StartCudaDownload();
            Factory?.ConfigureFreeEngine(_device == TranslationDevice.Gpu, _threads);
        }

        /// <summary>
        /// GPU seçilince (çeviri tarifi §8.5): NVIDIA sürücüsü varsa CUDA çalışma zamanı arka planda iner (yoksa ~565 MB
        /// boşa inerdi; CPU'da kalınır). Hata günlüğe yazılır; sonraki seçimde yeniden denenir.
        /// </summary>
        void StartCudaDownload()
        {
            if (cuda is null) return;
            try
            {
                if (!cuda.DriverPresent || cuda.IsInstalled) return;
                cuda.EnsureStarted().ContinueWith(t =>
                {
                    if (t.Exception is { } e) errorLog?.Invoke("CUDA çalışma zamanının indirilmesi başarısız oldu", e.GetBaseException());
                }, TaskContinuationOptions.OnlyOnFaulted);
            }
            catch (Exception e)
            {
                errorLog?.Invoke("CUDA çalışma zamanının indirilmesi başarısız oldu", e);
            }
        }

        public void SetCpuThreads(int threads)
        {
            _threads = threads;
            Factory?.ConfigureFreeEngine(_device == TranslationDevice.Gpu, _threads);
        }

        public bool EngineFailed => _failed;

        public event Action? EngineFailedOnce;

        public event Action? GpuFellBack;

        public void OnEngineFailed()
        {
            if (_failed) return;
            _failed = true;
            EngineFailedOnce?.Invoke();
        }

        public void OnGpuFellBack() => GpuFellBack?.Invoke();
    }
}
