// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using System.Text.Json.Nodes;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Linux.Core;
using Nino.Linux.Imaging;
using Nino.Linux.Ocr;
using Nino.Linux.Panel;
using Nino.Linux.Ports;
using Nino.RemotePlay;
using Nino.Shell;
using Nino.Translation.Online;
using CoreTvBrand = Nino.Core.Tv.TvBrand;
using TvRecord = Nino.Core.Tv.TvRecord;

namespace Nino.Linux.Engine;

/// <summary>
/// Panelin karşısındaki gerçek taraf: ortak denetleyici (<see cref="NinoController"/>). Panel çağrıları seri sıradan
/// gelir; bu sıra denetleyicinin "arayüz iş parçacığı"dır. Denetleyici hatalarını çoğu yerde özellik olarak tutar
/// (giriş, eşleme, TV hatası); burada panele 400 olarak döndürülür.
/// </summary>
public sealed class CoreBackend(NinoController controller, LinuxPlatform platform, bool ocrInstalled) : INinoBackend
{
    private readonly LinuxTools tools = new(platform);

    public string RedirectPrefix => PsnSignIn.RedirectPrefix;

    // ---- Durum ----

    public PanelState State()
    {
        var settings = controller.Settings; // kopya
        var tv = controller.Tv;
        var status = controller.SessionStatus;
        var app = controller.TvApp;
        return new PanelState
        {
            Version = platform.Version,
            Language = Hosting.Language.Code,
            Step = StepName(controller.Step),
            StepNumber = controller.StepNumber,
            StepCount = controller.StepCount,
            CanAdvance = controller.CanContinue,
            HasAccount = controller.HasAccount,
            PsnLoginUrl = PsnSignIn.SignInUrl(),
            RedirectPrefix = PsnSignIn.RedirectPrefix,
            Console = controller.HasConsole ? new PanelDevice(controller.ConsoleName ?? "PS5", ConsoleHost() ?? "") : null,
            Tv = tv is null ? null : new PanelTv(tv.Name, tv.Host, BrandName(tv.Brand)),
            TvApp = new PanelTvApp(AppKindName(app.Kind), app.Version, app.Error is { } error ? ErrorName(error) : null,
                app.SignInUrl, app.Reason),
            CanInstallTvApp = controller.CanInstallTvApp,
            BundledTvApp = platform.Services.LgPackageVersion,
            DevModeHoursLeft = controller.LgHoursLeft,
            ComputerAddress = app.ThisComputer ?? platform.Services.AddressNear(tv?.Host),
            ServerPort = controller.ServerPort,
            Model = new PanelModel(controller.ModelInstalled, controller.ModelDownloading, controller.ModelProgress, controller.ModelError),
            Running = controller.IsTranslating,
            Starting = controller.IsStarting,
            Paused = controller.IsPaused,
            Ps5 = new PanelPs5(controller.ConsoleStatusText, controller.ConsoleTone.ToString(), status.Phase.ToString(),
                status.Reason?.ToString(), status.Detail),
            TvStatus = new PanelTvStatus(controller.TvStatusText, controller.TvTone.ToString(), controller.ConnectedTvs),
            LastSource = controller.LastSource,
            LastTranslation = controller.LastTranslation,
            Translator = controller.TranslatorStatus.ToString(),
            OcrMissing = controller.OcrMissing || !ocrInstalled,
            NativeAvailable = LinuxPlatform.NativeAvailable,
            HasFrame = controller.LastFrame is not null,
            HasDeepLKey = controller.HasKey(Engine(settings)),
            OnlineEngine = controller.HasKey(Engine(settings)) ? Engine(settings).ToString() : null,
            Settings = new PanelSettings
            {
                Region = new PanelRegion(settings.Region.Top, settings.Region.Bottom, settings.Region.Left, settings.Region.Right),
                Style = StyleJson(settings.Style),
                SourceLanguage = settings.SourceLanguage,
                TargetLanguage = settings.TargetLanguage,
                OnlineTranslation = settings.OnlineTranslation,
            },
        };
    }

    private string? ConsoleHost() =>
        RemotePlayRecords.ConsoleFromJson(platform.Secrets.Get<JsonNode>(SecretKeys.Console))?.Host;

    /// <summary>Panel sayfasının adım adları (sayfa sözleşmesi; çekirdeğin adlarından ikisi farklı).</summary>
    internal static string StepName(SetupStep step) => step switch
    {
        SetupStep.PsnSignIn => "PsnLogin",
        SetupStep.Model => "Translation",
        _ => step.ToString(),
    };

    internal static string BrandName(CoreTvBrand brand) => brand.ToString();

    internal static string AppKindName(TvAppKind kind) => kind switch
    {
        TvAppKind.Installing => "Working",
        TvAppKind.PassphraseNeeded => "NeedsPassphrase",
        TvAppKind.SamsungSignIn => "SignIn",
        TvAppKind.ConfirmOnTv => "ApproveOnTv",
        _ => kind.ToString(),
    };

    internal static string ErrorName(Nino.Core.Tv.TvError error) =>
        error == Nino.Core.Tv.TvError.KeyServerClosed ? "KeyServerOff" : error.ToString();

    /// <summary>Panelin tek anahtar alanının motoru: Claude seçiliyse Claude, değilse DeepL.</summary>
    private static OnlineEngine Engine(AppSettings settings) =>
        settings.OnlineEngine == OnlineEngine.Claude ? OnlineEngine.Claude : OnlineEngine.DeepL;

    private static readonly JsonSerializerOptions StyleOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() },
    };

    internal static JsonObject StyleJson(SubtitleStyle style) =>
        JsonSerializer.SerializeToNode(style, StyleOptions) as JsonObject ?? new JsonObject();

    // ---- Sihirbaz ----

    public Task AdvanceAsync()
    {
        controller.Advance();
        return Task.CompletedTask;
    }

    public Task BackAsync()
    {
        controller.Back();
        return Task.CompletedTask;
    }

    public async Task SignInAsync(Uri redirect)
    {
        if (!await controller.CompletePsnSignInAsync(redirect.AbsoluteUri))
            throw new PanelProblem(controller.PsnError ?? Words.InvalidSignIn);
    }

    public async Task<IReadOnlyList<PanelConsole>> FindConsolesAsync()
    {
        await controller.SearchPs5Async();
        return [.. controller.FoundConsoles.Select(found => new PanelConsole(found.Name, found.Host, found.Awake))];
    }

    public async Task RegisterConsoleAsync(string host, string pin)
    {
        if (!await controller.PairPs5Async(host, pin))
            throw new PanelProblem(controller.PairError ?? (Words.Turkish ? "PS5 eşlenemedi." : "Couldn't link the PS5."));
    }

    public async Task<IReadOnlyList<PanelTv>> FindTvsAsync()
    {
        await controller.SearchTvsAsync();
        return [.. controller.FoundTvs.Select(found => new PanelTv(found.Name, found.Host, BrandName(found.Brand)))];
    }

    public async Task PairTvAsync(PanelTv tv)
    {
        if (string.IsNullOrWhiteSpace(tv.Host)) throw new PanelProblem(Words.Turkish ? "TV için bir IP yazın." : "Type an IP for the TV.");
        var brand = Enum.TryParse<CoreTvBrand>(tv.Brand, ignoreCase: true, out var parsed) ? parsed : CoreTvBrand.Lg;
        var name = string.IsNullOrWhiteSpace(tv.Name) ? $"{brand} TV" : tv.Name;
        if (!await controller.PairTvAsync(new TvRecord(name, tv.Host, brand)))
            throw new PanelProblem(controller.TvPairError ?? (Words.Turkish ? "TV eşlemeyi kabul etmedi ya da yanıtsız kaldı." : "The TV refused or ignored the pairing."));
    }

    public Task InstallTvAppAsync(string passphrase) => controller.InstallLgWithPassphraseAsync(passphrase.Trim());

    public Task RefreshTvAppAsync() => controller.RecheckTvAppAsync();

    public Task DownloadModelAsync()
    {
        controller.StartModelDownload();
        return Task.CompletedTask;
    }

    public Task SendTestSubtitleAsync() => controller.SendTestSubtitleAsync();

    public Task ResetAsync()
    {
        controller.ResetEverything();
        return Task.CompletedTask;
    }

    // ---- Çeviri ----

    public async Task StartAsync()
    {
        if (!controller.CanStart) throw new PanelProblem(Words.Turkish ? "Önce kurulumu bitirin (PS5 ve TV)." : "Finish setup first (PS5 and TV).");
        try
        {
            await controller.StartAsync();
        }
        catch (Exception error) when (error is not PanelProblem)
        {
            throw new PanelProblem(error.Message);
        }
    }

    public Task StopAsync()
    {
        controller.Stop();
        return Task.CompletedTask;
    }

    public Task TogglePauseAsync()
    {
        controller.TogglePause();
        return Task.CompletedTask;
    }

    public Task ChangeSettingsAsync(PanelRegion? region, JsonObject? style, bool? onlineTranslation)
    {
        var next = controller.Settings;
        if (region is not null)
        {
            next.Region = new Region(region.Top, region.Bottom, region.Left, region.Right);
            next.AreaPreset = RegionPresets.Detect(next.Region);
        }
        if (style is not null) ApplyStyle(next.Style, style);
        if (onlineTranslation is { } online) next.OnlineTranslation = online;
        controller.UpdateSettings(next);
        return Task.CompletedTask;
    }

    /// <summary>Panel yalnız yazı boyunu ve yeri değiştirir; öbür alanlar olduğu gibi kalır.</summary>
    internal static void ApplyStyle(SubtitleStyle target, JsonObject style)
    {
        if (style["fontSize"] is JsonValue size && size.TryGetValue<int>(out var fontSize) && fontSize is >= 20 and <= 120)
            target.FontSize = fontSize;
        if (style["placement"] is JsonValue place && place.TryGetValue<string>(out var text)
            && Enum.TryParse<SubtitlePlacement>(text, ignoreCase: true, out var placement))
            target.Placement = placement;
    }

    public async Task<KeyCheck> SaveOnlineKeyAsync(string key)
    {
        if (string.IsNullOrWhiteSpace(key)) throw new PanelProblem(Words.Turkish ? "Anahtarı yapıştırın." : "Paste the key.");
        var engine = OnlineKeys.EngineFor(key);
        var result = engine == OnlineEngine.Claude
            ? await controller.SaveAiKeyAsync(engine, key.Trim())
            : await controller.SaveDeepLKeyAsync(key.Trim());
        if (controller.HasKey(engine) && controller.Settings is { } settings && settings.OnlineEngine != engine)
        {
            settings.OnlineEngine = engine;
            controller.UpdateSettings(settings);
        }
        return new KeyCheck(CheckName(result));
    }

    internal static string CheckName(KeyCheckStatus status) => status switch
    {
        KeyCheckStatus.Valid => "Valid",
        KeyCheckStatus.InvalidKey => "Invalid",
        KeyCheckStatus.QuotaExhausted => "QuotaExceeded",
        KeyCheckStatus.ModelRejected => "Invalid",
        _ => "Unreachable",
    };

    public Task RemoveOnlineKeyAsync()
    {
        controller.RemoveKey(Engine(controller.Settings));
        return Task.CompletedTask;
    }

    // ---- Tanı ----

    public BgraPicture? LatestFrame => controller.LastFrame is { } frame ? Pictures.From(frame) : null;

    public Task<RegionProbe> ProbeRegionAsync(BgraPicture frame) => Task.Run(() => tools.Probe(frame, deep: true));

    public async Task<SampleTranslation> TranslateSampleAsync(string text)
    {
        try
        {
            return await tools.TranslateSampleAsync(text);
        }
        catch (TranslatorUnavailableException error)
        {
            throw new PanelProblem(error.Message);
        }
    }

    private Task? shutdown;

    /// <summary>
    /// Denetleyiciyi kapatır. Seri sıradan çağrılır ama orada beklenmez: kapanışın <c>await</c> sonrası işleri de aynı
    /// sıraya döndüğünden, bekleme sunucu tarafında (sıranın dışında) yapılır.
    /// </summary>
    public Task ShutdownAsync() => shutdown ??= controller.DisposeAsync().AsTask();

    public void Dispose() => _ = ShutdownAsync();
}
