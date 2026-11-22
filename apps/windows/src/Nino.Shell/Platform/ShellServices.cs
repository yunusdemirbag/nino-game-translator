// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Imaging;
using Nino.Core.Library;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Support;
using Nino.Core.Translation;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Translation.Online;
using Nino.TvInstall;
using Nino.TvInstall.Samsung;

namespace Nino.Shell.Platform;

/// <summary>
/// Ücretsiz yerel çeviri modeli (indirme, aygıt). Çevirmeni <see cref="IShellServices.Translators"/> kurar.
/// Olaylar herhangi bir iş parçacığından gelir.
/// </summary>
public interface IFreeModel
{
    /// <summary>Bu dil çifti için ücretsiz model var mı.</summary>
    bool Supports(string source, string target);

    /// <summary>Kurulu mu.</summary>
    bool IsInstalled(string source, string target);

    /// <summary>İndirir (ilerleme 0–1).</summary>
    Task DownloadAsync(string source, string target, IProgress<double> progress, CancellationToken cancellationToken = default);

    /// <summary>Aygıtı seçer (açık çevirmenler kapanır).</summary>
    void SetDevice(TranslationDevice device);

    /// <summary>CPU iş parçacığı sayısını seçer.</summary>
    void SetCpuThreads(int threads);

    /// <summary>Motor bu bilgisayarda açılamadı mı (kalıcı).</summary>
    bool EngineFailed { get; }

    /// <summary>Motor açılamadı (bir kez).</summary>
    event Action? EngineFailedOnce;

    /// <summary>GPU kullanılamadı, CPU'ya geçildi.</summary>
    event Action? GpuFellBack;
}

/// <summary>Ücretsiz modeli olmayan derleme.</summary>
public sealed class NoFreeModel : IFreeModel
{
    /// <inheritdoc />
    public bool Supports(string source, string target) => false;

    /// <inheritdoc />
    public bool IsInstalled(string source, string target) => false;

    /// <inheritdoc />
    public Task DownloadAsync(string source, string target, IProgress<double> progress, CancellationToken cancellationToken = default) =>
        Task.CompletedTask;

    /// <inheritdoc />
    public void SetDevice(TranslationDevice device) { }

    /// <inheritdoc />
    public void SetCpuThreads(int threads) { }

    /// <inheritdoc />
    public bool EngineFailed => false;

    /// <inheritdoc />
    public event Action? EngineFailedOnce { add { } remove { } }

    /// <inheritdoc />
    public event Action? GpuFellBack { add { } remove { } }
}

/// <summary>TV bekçisi (TV uygulamasını açık tutar).</summary>
public interface ITvWatch
{
    /// <summary>Başlatır.</summary>
    void Start();

    /// <summary>Durdurur.</summary>
    void Stop();

    /// <summary>Hemen yeniden bağlanır.</summary>
    void ReconnectNow();
}

/// <summary>Bekçinin kurulumu.</summary>
/// <param name="Tv">TV.</param>
/// <param name="Key">Kayıtlı jeton.</param>
/// <param name="LaunchParameters">Açılış parametreleri (her denemede okunur).</param>
/// <param name="TvAppConnected">TV uygulaması şu an bağlı mı (Samsung'da bağlıyken TV'ye dokunulmaz).</param>
/// <param name="Moved">TV yeni adreste (herhangi bir iş parçacığından).</param>
/// <param name="KeyChanged">TV yeni jeton verdi (herhangi bir iş parçacığından).</param>
/// <param name="Interval">Aralık (5 sn).</param>
public sealed record TvWatchRequest(TvRecord Tv, string Key, Func<string> LaunchParameters, Func<bool> TvAppConnected,
    Action<TvRecord> Moved, Action<string> KeyChanged, TimeSpan Interval);

/// <summary>Samsung ön denetimi: TV'nin 8001 bilgisi ve TV'ye giden yolun bu bilgisayardaki adresi.</summary>
public sealed record SamsungPrecheck(SamsungDeviceInfo Info, string? ThisComputer)
{
    /// <summary>İkisi de bilinmiyor.</summary>
    public static SamsungPrecheck Unknown { get; } = new(SamsungDeviceInfo.Unknown, null);
}

/// <summary>Samsung/Android kurulumunun olayları (herhangi bir iş parçacığından).</summary>
/// <param name="SignInWaiting">Samsung oturumu bekleniyor (adres).</param>
/// <param name="ApprovalWaiting">TV ekranında onay bekleniyor.</param>
/// <param name="Progress">İlerleme (adım adı: <c>reading</c>, <c>signin</c>, <c>certificate</c>, <c>signing</c>,
/// <c>installing</c>, <c>uninstalling</c>).</param>
public sealed record TvInstallEvents(Action<string> SignInWaiting, Action ApprovalWaiting, Action<string> Progress);

/// <summary>
/// Denetleyicinin dış dünyadan istediği her şey (ağ, cihazlar, dosyalar). Varsayılan gövdeli üyeler (V)
/// doldurulmayabilir; özellik o derlemede kapalı sayılır. Bütün olaylar herhangi bir iş parçacığından gelebilir.
/// Gerçek bağlantı için <see cref="CoreShellServices"/>'ten türetilir.
/// </summary>
public interface IShellServices
{
    // ---- PS5 ve PSN ----

    /// <summary>Ağdaki PS5'ler (adres verilirse yalnız o).</summary>
    Task<IReadOnlyList<FoundPs5>> FindPs5Async(string? host, CancellationToken cancellationToken = default);

    /// <summary>Giriş yönlendirmesinden 8 baytlık hesap kimliği (hata: <see cref="PsnSignInException"/>).</summary>
    Task<byte[]> AccountIdFromRedirectAsync(string redirectUrl, CancellationToken cancellationToken = default);

    /// <summary>PS5'e kayıt (hata: <see cref="PairingException"/>).</summary>
    Task<Ps5Console> RegisterPs5Async(string host, byte[] accountId, uint pin, CancellationToken cancellationToken = default);

    /// <summary>PS5 yayın oturumu.</summary>
    IVideoSource CreatePs5Source(Ps5Console console, byte[] accountId, string? loginPasscode);

    /// <summary>(V) PS5'te çalışan oyun (yalnız bu adrese keşif sorusu).</summary>
    Task<FoundPs5?> RunningGameAsync(string host, CancellationToken cancellationToken = default) =>
        Task.FromResult<FoundPs5?>(null);

    // ---- Xbox ----

    /// <summary>(V) Xbox hizmeti; yoksa Xbox yayını bu sürümde yok.</summary>
    IXboxService? Xbox => null;

    // ---- Pencere ve kart ----

    /// <summary>(V) Oyunun penceresi kaynağı.</summary>
    IGameWindowSource? CreateGameWindowSource(GameConsole console) => null;

    /// <summary>(V) HDMI yakalama kartı kaynağı.</summary>
    ICaptureCardSource? CreateCaptureCardSource(bool showGameHere, string? preferredDeviceId) => null;

    /// <summary>(V) Remote Play penceresi kaynağı.</summary>
    IVideoSource CreateRemotePlayWindowSource(RemotePlayApp app) =>
        throw new NotSupportedException("Remote Play penceresi bu derlemede okunamıyor.");

    /// <summary>(V) Kullanıcının seçtiği pencerenin kaynağı.</summary>
    IVideoSource CreateChosenWindowSource(CaptureWindowChoice window) =>
        throw new NotSupportedException("Bu derleme kullanıcının seçtiği pencereyi okuyamaz.");

    /// <summary>(V) Seçilebilecek görünür pencereler.</summary>
    IReadOnlyList<VisibleWindow> VisibleWindows() => [];

    /// <summary>(V) Seçilen Remote Play uygulaması kurulu mu.</summary>
    bool IsRemotePlayAppInstalled(RemotePlayApp app) => true;

    // ---- TV ----

    /// <summary>Altyazı sunucusunu kurar (açmaz).</summary>
    ISubtitleServer CreateSubtitleServer(Action<string> subtitleLog);

    /// <summary>TV'ye yakın bu bilgisayar adresi (TV bilinmiyorsa Wi-Fi/Ethernet).</summary>
    string? AddressNear(string? tvHost) => null;

    /// <summary>TV ara (LG + Samsung).</summary>
    Task<IReadOnlyList<FoundTv>> FindTvsAsync(CancellationToken cancellationToken = default);

    /// <summary>Eşleş ve TV uygulamasını açmayı dene. Android TV'de (boş jeton, açıldı).</summary>
    Task<PairResult> PairTvAsync(TvRecord tv, string? savedKey, string launchParameters, CancellationToken cancellationToken = default);

    /// <summary>TV bekçisi.</summary>
    ITvWatch CreateTvWatch(TvWatchRequest request);

    /// <summary>(V) Paketle gelen LG uygulamasının sürümü.</summary>
    string? LgPackageVersion => null;

    /// <summary>(V) LG geliştirici modu açık mı.</summary>
    Task<bool> LgDevModeOpenAsync(string host, CancellationToken cancellationToken = default) => Task.FromResult(false);

    /// <summary>(V) TV parolasıyla geliştirici anahtarı (hata: <see cref="TvException"/>).</summary>
    Task<string> LgFetchKeyAsync(string host, string passphrase, CancellationToken cancellationToken = default) =>
        throw new TvException(TvError.KeyServerClosed);

    /// <summary>(V) TV'de kurulu sürüm (hata: <see cref="TvException"/>; anahtar reddi <see cref="TvError.KeyRejected"/>).</summary>
    Task<string?> LgInstalledVersionAsync(string host, string devKey, CancellationToken cancellationToken = default) =>
        Task.FromResult<string?>(null);

    /// <summary>(V) Kur.</summary>
    Task LgInstallAsync(string host, string devKey, CancellationToken cancellationToken = default) =>
        throw new TvException(TvError.InstallFailed);

    /// <summary>(V) Geliştirici modu süresini baştan başlatır; kalan saat ya da bilinmiyor.</summary>
    Task<int?> LgRenewDevModeAsync(string host, string devKey, CancellationToken cancellationToken = default) =>
        Task.FromResult<int?>(null);

    /// <summary>(V) Markaya göre paketle gelen uygulama (Samsung <c>.wgt</c>, Android <c>.apk</c>).</summary>
    TvAppPackage? PackageFor(TvBrand brand) => null;

    /// <summary>(V) Samsung geliştirici modu (kurulum kapısı 26101) açık mı.</summary>
    Task<bool> SamsungDevModeOpenAsync(string host, CancellationToken cancellationToken = default) => Task.FromResult(false);

    /// <summary>(V) Samsung ön denetimi.</summary>
    Task<SamsungPrecheck> SamsungPrecheckAsync(string host, CancellationToken cancellationToken = default) =>
        Task.FromResult(SamsungPrecheck.Unknown);

    /// <summary>(V) Samsung'a kur (eksik/eskiyse). Hata: <see cref="TvException"/>.</summary>
    Task<TvInstallResult> SamsungInstallAsync(string host, TvInstallEvents events, CancellationToken cancellationToken = default) =>
        throw new TvException(TvError.Unreachable);

    /// <summary>(V) Android TV'de ADB açık mı.</summary>
    Task<bool> AndroidAdbOpenAsync(string host, CancellationToken cancellationToken = default) => Task.FromResult(false);

    /// <summary>(V) Ağda ADB'si açık cihazlar.</summary>
    Task<IReadOnlyList<string>> AndroidScanAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<string>>([]);

    /// <summary>(V) Android TV'ye kur. Hata: <see cref="TvException"/>.</summary>
    Task<TvInstallResult> AndroidInstallAsync(string host, TvInstallEvents events, CancellationToken cancellationToken = default) =>
        throw new TvException(TvError.Unreachable);

    // ---- Yazı tanıma ----

    /// <summary>Okuyucu fabrikası.</summary>
    ITextReaderFactory Readers { get; }

    // ---- Çeviri ----

    /// <summary>Ücretsiz model.</summary>
    IFreeModel FreeModel { get; }

    /// <summary>Çevirmen fabrikası (zinciri <see cref="TranslationChain.Build"/> kurar).</summary>
    ITranslatorFactory Translators { get; }

    /// <summary>(V) DeepL anahtarını dene.</summary>
    Task<KeyCheckStatus> TryDeepLKeyAsync(string key, CancellationToken cancellationToken = default) =>
        Task.FromResult(KeyCheckStatus.Unreachable);

    /// <summary>(V) Yapay zekâ (ya da yerel model) anahtarını örnek satırla dene.</summary>
    Task<KeyCheckStatus> TryAiKeyAsync(AiService service, string model, string key, string target, LocalServer? local,
        CancellationToken cancellationToken = default) => Task.FromResult(KeyCheckStatus.Unreachable);

    // ---- Paketler, havuz, geçmiş, sağlık, güncelleme ----

    /// <summary>(V) Oyun paketi kütüphanesi.</summary>
    PackLibrary? Packs => null;

    /// <summary>(V) Ortak satır havuzu (gönderim kuyruğu).</summary>
    LineQueue? LinePool => null;

    /// <summary>(V) Nino çeviri havuzu.</summary>
    TranslationPool? Pool => null;

    /// <summary>(V) Paket güncelleyicisi.</summary>
    PackUpdater? PackUpdater => null;

    /// <summary>(V) Geçmiş dosyasının yolu; yoksa diske yazılmaz.</summary>
    string? HistoryPath => null;

    /// <summary>(V) Sağlık klasörü; yoksa sorun dosyası, ağ izleme ve otomatik bildirim yok.</summary>
    string? HealthFolder => null;

    /// <summary>(V) Ağ türü okuyucu.</summary>
    INetworkWatch? NetworkWatch => null;

    /// <summary>(V) Sorun bildirimini gönder.</summary>
    Task<ReportResult> SendReportAsync(ReportBody body, CancellationToken cancellationToken = default) =>
        Task.FromResult(ReportResult.Failed);

    /// <summary>(V) Güncelleyici.</summary>
    IAppUpdater? Updater => null;

    /// <summary>(V) Kendiliğinden kurulum sayaç dosyası (<c>auto-update-tried.txt</c>); null: yalnız bellek.</summary>
    string? AutoUpdateCounterPath => null;

    /// <summary>(V) Güvenlik duvarı.</summary>
    IFirewall? Firewall => null;

    /// <summary>(V) Nino'nun sürümü.</summary>
    string AppVersion => "0.0.0";

    /// <summary>(V) Ölçüm göndericisi (havuzla aynı kök adresin <c>/v1/events</c>'i); yoksa ölçüm gönderilmez.</summary>
    Nino.Core.Telemetry.ITelemetrySender? TelemetrySender => null;

    /// <summary>(V) Bilgisayarın modeli ve işletim sistemi (cihaz bilgisi).</summary>
    (string Device, string System) DeviceAndSystem => (DeviceInfo.FallbackModel, Environment.OSVersion.VersionString);
}
