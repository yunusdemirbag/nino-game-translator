# Denetleyici (Nino.Shell) — kısa API ve iş parçacığı kuralı

Yer: `apps/windows/src/Nino.Shell` (düz `net10.0`, Windows API yok). Windows (Nino.App, WPF) ve Linux (tarayıcı
paneli) aynı `NinoController`'ı kullanır. Davranış tarifi: `denetleyici.md`.

## İş parçacığı kuralı

- Denetleyicinin bütün durumu **tek bir mantıksal arayüz iş parçacığında** değişir. Kurucuya verilen
  `Action<Action> post` ("arayüze aktar") bu iş parçacığına iş gönderir:
  - **Windows:** WPF Dispatcher (tek `SynchronizationContext`): `post = a => dispatcher.BeginInvoke(a)`.
  - **Linux:** kendi tek iş parçacıklı seri kuyruğu: `post = a => queue.Enqueue(a)`.
  - **Testler:** `post = a => a()` (hemen).
- Ekranlar özellikleri okur ve eylemleri yalnız bu iş parçacığından çağırır.
- Platform hizmetlerinin olayları (kare, oturum durumu, TV sayısı, model ilerlemesi, kurulum olayları, Xbox jetonu,
  zamanlayıcı tikleri) **herhangi bir iş parçacığından** gelebilir; denetleyici hepsini `post` ile aktarır.
- Eşzamansız eylemlerde her `await`'ten sonra `await OnUi()` ile arayüz iş parçacığına dönülür; denetleyici
  `SynchronizationContext` yakalamaya güvenmez (Linux'ta yoktur).
- Kare işleyici kaynağın kendi iş parçacığında çalışır, hiçbir hatayı dışarı kaçırmaz, arayüz işlerini `post` eder.
- `PropertyChanged` yalnız arayüz iş parçacığında, değer gerçekten değişince verilir; bağlı özellikler de
  kendiliğinden bildirilir (her değişiklikten sonra bütün gözlenen özellikler karşılaştırılır). `Settings` ve
  `LastFrame` ayrıca bildirilir (`Settings` adıyla, `FrameArrived` olayıyla).

## Kurulum

```csharp
var controller = new NinoController(services, secrets, settingsStore, sleepGuard, TextCatalog.For(lang), post,
    new ShellOptions { Timers, Logs, Browser, Hotkeys, PsnWindow, LogicalProcessors });
```

- `IShellServices` (Platform/ShellServices.cs): ağ, cihaz ve dosya işleri. Varsayılan gövdeli üyeler doldurulmazsa
  özellik kapalıdır. Gerçek bağlantı için **`CoreShellServices`**'ten türetin; yalnız `Readers` zorunludur.
  `CoreShellServicesOptions.DataFolder` dışarıdan verilir (Windows: `NinoDataFolder.Prepare()` sonucu; Linux:
  kendi yolu). `KeepLegacyTurkish` (Windows false, Linux true) `FreeModelStore`'a geçer.
- Küçük platform arayüzleri (Platform/PlatformPorts.cs): `ISleepGuard` (`NoSleepGuard`), `IShellTimers`
  (`SystemShellTimers`), `IShellLogs` (`FileShellLogs`, `SilentShellLogs`), `ITextReaderFactory`, `IFirewall`,
  `IAppUpdater`, `IBrowser`, `IHotkeyHost`, `IPsnSignInWindow`.
- Kaynaklar (Platform/Sources.cs): `IVideoSource` (Nino.RemotePlay) + `IGameWindowSource`, `ICaptureCardSource`,
  `IXboxService`. Altyazı sunucusu: `ISubtitleServer` (`TvOutputServer` = `TvOutput` sarmalayıcısı; olaylar
  `TvCountChanged`, `TvModelReported`, `LocalEvent`, `AndroidTvHostFound` ve bağlantı başına `TvConnected`
  (`TvLinkConnected`) / `TvDropped` (`TvLinkDropped`, neden kodlu; bu ikisinin varsayılanı boş, sahte sunucular
  uygulamak zorunda değil) — `tv-baglanti.md` §13). TV bekçisi:
  `ITvWatch`. Ücretsiz model: `IFreeModel`.
- Telefon/harita: denetleyici `Nino.Core.Phone.PhoneOverlay`'i kendisi kurar (hat başına; tek geçişli okuyucu
  `ITextReaderFactory.CreateSinglePass`); ayrı hizmet gerekmez.

## Okunan durum (özetle)

Sihirbaz: `Step, StepNumber, StepCount, CanContinue, IsSetupComplete, ConsoleKind, IsXbox, ConsoleKindLocked,
CardGuideOpen, AccountLinkNeeded, HasAccount, HasConsole, ConsoleName, PairedMessage, PairError, PsnError, PsnBusy,
FoundConsoles, SearchingPs5, PairingPs5, XboxAvailable, HasXboxToken, XboxConsole, XboxConsoles, XboxCode, XboxError`.
TV: `Tv, TvPaired, FoundTvs, SearchingTvs, PairingTv, TvPairError, TvApp (TvAppStatus), LgHoursLeft, CanInstallTvApp,
ConnectedTvs, TvModel, TvStatusText, TvTone, NeedsTv`.
Çeviri: `IsTranslating, IsStarting, CanStart, IsPaused, SessionStatus, ConsoleStatusText, ConsoleTitle, ConsoleTone,
ShowsOnTv, ShowsOnComputer, CardPlayerVisible, MainAccountHint, WindowState, WindowAppName, GameArea, CardState,
PreferredCardId, TranslatorStatus, OnlineEnabled, OnlineProblem, OnlineProblemText, OcrMissing, GpuFellBack,
LastSource, LastTranslation, LastFrame, ActiveLanguage, MetricsLine, ServerPort, History, HotkeysActive, AdjustMode,
WaitingForHotkey`. Model: `HasFreeModel, ModelInstalled, ModelDownloading, ModelProgress, ModelError`.
Oyun/havuz: `PlayingGame, GamePickerOpen, LastChosenGame, Packs, PoolFirstLive, TranslationSourceText, Downloads,
PoolInstallId`. Diğer: `Firewall, UpdateVersion, Updating, UpdateProgress, UpdateError, CanSelfUpdate,
StreamBackground, ObsLocalAddress, ObsNetworkAddress, Settings`.

Olaylar: `PropertyChanged, ComputerOverlayEvent, StreamWindowEvent, ComputerOverlayCleared, StreamWindowCleared,
FrameArrived, SnapshotRequested, FreeAreaRequested, ComputerPopup, ProblemsChanged`.

## Eylemler (Linux panelinin kullandıkları kalın)

- Sihirbaz: **`Advance`**, **`Back`**, `GoToStep`, `SetConsoleKind`, `UseGameWindowHere`, `UseXboxWindow`,
  `OpenCardGuide/CancelCardGuide/FinishCardGuide`, `UseRemotePlayWindow`, `UseChosenWindow`, `NoTv`,
  `SetGameConsole`, `LinkAccount`, **`ResetEverything`**, `ResetFromTv`.
- PSN/PS5: `SignInToPsnAsync`, `OpenPsnSignInInBrowser`, **`CompletePsnSignInAsync(redirect)`**,
  `SetManualAccountId`, **`SearchPs5Async`**, **`PairPs5Async(host, code)`**, `ContinueAfterPairing`,
  `SaveLoginPasscode/RemoveLoginPasscode`. Xbox: `SignInToXboxAsync`, `FindXboxConsolesAsync`, `SelectXboxConsole`.
- TV: **`SearchTvsAsync`**, **`PairTvAsync`**, **`RecheckTvAppAsync`** (kur/yenile), `InstallLgWithPassphraseAsync`,
  `ReopenSamsungSignIn`.
- Model: **`StartModelDownload`**.
- Çeviri: **`StartAsync`**, **`Stop`**, `ToggleAsync`, **`TogglePause`**, `SystemResumed`, `ToggleCardFullScreen`,
  `SetPreferredCard`, **`SendTestSubtitleAsync`**, `TranslateExtraRegionAsync`, `TranslateFreeAreaAsync`,
  `TranslateScreenAsync`, `RunHotkeyAsync`, `RequestSnapshot`, `ToggleClickThrough`, `ClearHistory`.
- Ayarlar: **`UpdateSettings(AppSettings)`** (tarif §7 kuralları), `SaveOverlayPlacement`, `SetStreamBackground`.
- Anahtarlar: **`SaveDeepLKeyAsync`**, `CheckDeepLKeyAsync`, `SaveAiKeyAsync`, `CheckAiKeyAsync`,
  `TryLocalServerAsync`, **`RemoveKey`**, `HasKey`, `GetFreeGeminiKey`, `DescribeKeyCheck`.
- Oyun: `ChooseGame`, `ChangeGame`, `DismissGamePicker`, `GameSuggestions`, `ReloadPacks`, `RefreshDownloads`.
- Sistem: `CheckConnectionsAsync` (birkaç saniyede bir), `AllowFirewallAsync`, `FirewallInfoAsync`,
  `CheckForUpdateAsync`, `InstallUpdateAsync`, `DeviceInfoLines`, `DisposeAsync` (kapanış).

## Ekranlar için ekler (dalga 3: kurulum, ana ekran, paneller)

Ağ ya da disk okuyan her şey **yöntemdir** (gözlenen özellikler her yenilemede okunur, ağır iş özelliğe konmaz).

- **Kurulum** (`NinoController.SetupUi.cs`): `ThisComputerAddress()` (TV'ye dönük adres, Samsung "Host PC IP"; ağı
  okur), `IsRemotePlayAppMissing()` (ne PS Remote Play ne chiaki-ng kurulu; diske bakar), `NoteRemotePlay(line)`
  (remoteplay.log'a ekran notu), `RemotePlayLogPath`, `PsnWindowClosedText(problem)` (giriş penceresi yönlendirmesiz
  kapanınca gösterilecek metin; günlüğe de yazar). Ayrıca `HasLoginPasscode` (Setup.cs).
- **Ana ekran** (`NinoController.Home.cs`): `OnlineEngineName` (seçili çevrimiçi motorun ekrandaki adı),
  `HomeStyle` (salon / cam anahtar), `HomeSceneIsXbox` (ayardaki konsol Xbox ya da kurulumda Xbox seçildi),
  `SourceLanguage` (OCR paketi bunun için kurulur). Kaynak türü: `UsesGameWindow`, `UsesPs5GameWindow`,
  `UsesXboxGameWindow`, `UsesCaptureCard`, `CardPlayerVisible` (Session.cs); `UsingFreeGemini` (Settings.cs).
- **Paneller** (`NinoController.Panels.cs`): `DataFolder` (günlükler, paketler, sorun kaydı; yoksa null),
  `AppVersion`, `UserPacksFolder` (`…\packs`), `VisibleWindows()` (OBS projektörü / oyun penceresi seçimi; hata boş
  liste), `IsRemotePlayAppInstalled(app)`, `CanTranslateFrom(source)`, `Network` (sorun bekçisinin son okuduğu ağ türü),
  `ProblemRecords()` (dosyadan, eskiden yeniye), `HealthInput(network)` (`settings.section.systemHealth` denetimleri), `ProblemFindings
  (userText)` ("Nino'nun tespitleri"), `SendProblemReportAsync(userText, contact, includeLog, images)` (`settings.about.reportProblem`),
  `Assistant` (uygulama boyunca tek Nino'ya Sor sohbeti; `Changed` her iş parçacığından), `DeepLUsageAsync()` (bu ayki
  DeepL kullanımı), `CreateCardPreview()` (Ayarlar'daki canlı kart önizlemesi; çeviri sürerken/başlarken null, kaynağı
  çağıran başlatır ve bırakır). Ayrıca `Health` (`HealthRecorder`, tek paylaşılan sağlık kaydı), `Problems`
  (`ProblemWatcher`), `Text` (metin kataloğu).

## Platform bağlantıları (birleştirme)

- `CoreShellServicesOptions` ekleri: `CudaDriverPresent` (Windows `System32\nvcuda.dll` denetimi; verilirse ücretsiz
  modele `cuda-12.8` CUDA deposu bağlanır, GPU seçilince indirme arka planda başlar; null = GPU yok, Linux),
  `ErrorLog` (arka plan hataları, ör. CUDA indirme). Kullanıcı sözlük klasörü `glossary\*.json` (veri klasöründe)
  çevirmen fabrikasına kendiliğinden bağlanır.
- Remote Play günlüğü tek sınıftır: `Nino.RemotePlay.RemotePlayLog` (Nino.Core'daki eşi kaldırıldı). Uygulama **tek
  örnek** açar ve aynısını `CoreShellServicesOptions.RemotePlayLog`'a ve `IShellLogs`'a verir (`FileShellLogs` da bu
  sınıfı alır; `FilePath` gösterilen yoldur). Açılışta `RemotePlayLogTap.Attach(log, controller.Health, logs.Subtitle)`
  bağlanır: her satır sağlık kaydına ve altyazı günlüğündeki duraklama notlarına (`PictureStallNotes`) gider.
- Otomatik teşhis (`Nino.Core.Diagnostics`, tarif NinoCore `otomatik-teshis.md`): ölçüm kurulunca `Diagnostics`
  (`DiagnosticsWatcher`) da kurulur; kapatma düğmesi yok, sunucu `telemetry.diag` ile kural kapatır/eşik değiştirir
  (`/v1/config` ve `/v1/events` cevabı, `TelemetryClient.RemoteConfigReceived` üstünden). Denetleyici 1 sn'lik bir
  zamanlayıcıyla ana iş parçacığını yoklar (askı), damgayı `telemetry/diag-alive.json`'a yazar, günlük sınır sayımı
  `telemetry/diag-limits.json`. Platformun yapacağı: güç olayında uykuya geçerken **`SystemSuspending()`**, uyanınca
  (zaten olan) `SystemResumed()`. `TelemetrySetup.ResourceProbe` isteğe bağlı (varsayılan süreç bilgisi; Linux'ta da
  çalışır). Bildirimler yalnız kod: `Diagnostics.Recent` son 10 bildirim (kural/sebep kodu); cümle gösterilecekse
  ekran koddan üretir.
- Olay `ProblemsChanged`: Windows'ta `settings.section.systemHealth` sayfası 2 sn'de bir kendini yenilediği için abone yok; Linux paneli
  kullanabilir.

## Saf hesaplar (Layout.cs)

`OverlayLayout` (altyazı penceresinin yeri, §14.1), `GameWindowRules` (oyun penceresi seçimi, 16:9 alan, §14.2),
`LivingRoomScene` (salon sahnesi ölçüleri, fiş dönüşü, kablo, §14.3), `StreamBackgroundColors`.
Panels/: `OverlayDrawing` (bilgisayardaki altyazı penceresi), `StreamWindowRules` (yayın penceresi: ölçek
max(0,2, yükseklik/1080), yan 24×ölçek, alt yükseklik×0,07, ek alan üstü 16×ölçek, kutulu satırda yazı soluklığı
1/0,6/0,45), `CardPreviewLook`, `FreeAreaMath`, `RegionPickerMath`, `HotkeyCapture`, `SettingsPanelRules`,
`HealthDetailsText`. Setup/: `SetupSidebar`, `TvPairText`, `CaptureGuideSteps` … HomeScreen.cs: ana ekran kuralları.
