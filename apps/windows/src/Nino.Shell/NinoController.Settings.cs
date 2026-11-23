// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Shell;

// Ayar yazıcısı (§7), çevrimiçi anahtarlar (§11.5), model indirme (§9), yayın penceresi zemini (§14).
public sealed partial class NinoController
{
    bool _modelDownloading;
    double _modelProgress;
    string? _modelError;
    bool _usingFreeGemini;

    // ---- Ayarlar değişince (§7) ----

    /// <summary>
    /// Yeni ayarı uygular (ekran ayarın tamamını verir). Kurallar sırasıyla uygulanır; değer değişmediyse hiçbir şey olmaz.
    /// </summary>
    public void UpdateSettings(AppSettings next)
    {
        var previous = _settings;
        var wasOnTv = ShowsOnTv;
        var wasOnComputer = ShowsOnComputer;
        next = next.Clone();
        if (!SettingsRules.ApplyWriteRules(previous, next, _cpus)) return;
        _settings = next;
        _settingsStore.Save(next);
        SendStyle();

        var outputChanged = previous.Output != next.Output || wasOnTv != ShowsOnTv || wasOnComputer != ShowsOnComputer;
        var videoChanged = previous.VideoSource != next.VideoSource;
        var frameChanged = previous.FrameSource != next.FrameSource;
        var restart = false;
        if (outputChanged) OnOutputChanged();
        if (previous.Output != next.Output && !videoChanged && next.VideoSource == VideoSource.Card && _translating) restart = true;
        if (videoChanged)
        {
            OnOutputChanged();
            if (_translating) restart = true;
        }
        if (TargetLanguages.Code(previous.TargetLanguage) != TargetLanguages.Code(next.TargetLanguage))
        {
            _services.Pool?.SetLanguage(next.TargetLanguage);
            OnPackLanguageChanged(next.TargetLanguage);
        }
        var rebuild = false;
        if (previous.GamePacks != next.GamePacks && _pipeline is not null) rebuild = true;
        if (previous.ShowSpeakerNames != next.ShowSpeakerNames && _pipeline is not null) rebuild = true;
        if ((previous.MisreadWaitMs != next.MisreadWaitMs || previous.PartialWaitMs != next.PartialWaitMs) && _pipeline is not null)
            rebuild = true;
        if (previous.SharePool != next.SharePool)
        {
            try { _services.LinePool?.SetEnabled(next.SharePool); } catch (Exception) { }
            _services.Pool?.SetSharePool(next.SharePool);
            if (_pipeline is not null) rebuild = true;
        }
        if (previous.TranslationDevice != next.TranslationDevice)
        {
            _gpuFellBack = false;
            _services.FreeModel.SetDevice(next.TranslationDevice);
        }
        if (previous.CpuTranslationThreads != next.CpuTranslationThreads)
            _services.FreeModel.SetCpuThreads(next.CpuTranslationThreads);
        UpdateExtraAreas();

        if (_translating && (frameChanged
            || (next.FrameSource == FrameSource.RemotePlayWindow && previous.RemotePlayApp != next.RemotePlayApp)
            || (next.FrameSource == FrameSource.ChosenWindow && previous.CaptureWindow != next.CaptureWindow)
            || (IsXbox && previous.XboxLegacyFrameRate != next.XboxLegacyFrameRate)
            || (IsXbox && previous.XboxStreamQuality != next.XboxStreamQuality)))
            restart = true;

        var translationChanged = previous.OnlineTranslation != next.OnlineTranslation
            || previous.OnlineEngine != next.OnlineEngine || previous.GeminiModel != next.GeminiModel
            || previous.OpenAiModel != next.OpenAiModel || previous.ClaudeModel != next.ClaudeModel
            || previous.LocalAiBaseUrl != next.LocalAiBaseUrl || previous.LocalAiModel != next.LocalAiModel
            || previous.TranslationDevice != next.TranslationDevice
            || previous.CpuTranslationThreads != next.CpuTranslationThreads;
        var languageChanged = previous.SourceLanguage != next.SourceLanguage || previous.TargetLanguage != next.TargetLanguage;
        if (translationChanged || languageChanged) RefreshTranslatorStatus();
        if (_translating && (translationChanged || languageChanged
            || previous.FastSubtitleDetection != next.FastSubtitleDetection))
            rebuild = true;

        if (restart) Background(RestartAsync);
        else if (rebuild && _translating) BuildPipeline();
        Raise(nameof(Settings));
        Refresh();
    }

    /// <summary>Altyazı penceresinin yerini kaydeder (bozuk değer kaydedilmez).</summary>
    public void SaveOverlayPlacement(double left, double top, double width)
    {
        if (OverlayLayout.ToSave(left, top, width) is not { } placement) return;
        ChangeSettings(s => s.Overlay = placement);
    }

    // ---- Model (§9) ----

    /// <summary>Bu dil çifti için ücretsiz model var mı.</summary>
    public bool HasFreeModel => _services.FreeModel.Supports(TargetLanguages.Code(_settings.SourceLanguage),
        TargetLanguages.Code(_settings.TargetLanguage));

    /// <summary>Model kurulu mu (ücretsiz modeli olmayan dilde kurulu sayılır).</summary>
    public bool ModelInstalled => !HasFreeModel || _services.FreeModel.IsInstalled(
        TargetLanguages.Code(_settings.SourceLanguage), TargetLanguages.Code(_settings.TargetLanguage));

    /// <summary>Model iniyor mu.</summary>
    public bool ModelDownloading => _modelDownloading;

    /// <summary>İndirme ilerlemesi (0–1).</summary>
    public double ModelProgress => _modelProgress;

    /// <summary>İndirme hatası.</summary>
    public string? ModelError => _modelError;

    /// <summary>Model indirmesini başlatır (kuruluysa ya da sürüyorsa bir şey yapmaz).</summary>
    public void StartModelDownload()
    {
        if (ModelInstalled || _modelDownloading) return;
        _modelDownloading = true;
        _modelError = null;
        _modelProgress = 0;
        var src = TargetLanguages.Code(_settings.SourceLanguage);
        var tgt = TargetLanguages.Code(_settings.TargetLanguage);
        Background(async () =>
        {
            var progress = new Progress(p => Post(() => _modelProgress = Math.Clamp(p, 0, 1)));
            try
            {
                await _services.FreeModel.DownloadAsync(src, tgt, progress).ConfigureAwait(false);
                await OnUi();
                _modelProgress = 1;
            }
            catch (Exception e)
            {
                await OnUi();
                _modelError = e.Message;
                _logs.Error("Model indirilemedi", e);
            }
            _modelDownloading = false;
            RefreshTranslatorStatus();
            if (_translating && _translatorStatus == TranslatorStatus.Ready) BuildPipeline();
            Refresh();
        });
        Refresh();
    }

    sealed class Progress(Action<double> report) : IProgress<double>
    {
        public void Report(double value) => report(value);
    }

    // ---- Anahtarlar (§11.5) ----

    /// <summary>Motorun anahtarı kayıtlı mı (anahtarın kendisi hiçbir zaman dönmez).</summary>
    public bool HasKey(OnlineEngine engine) => TranslationChain.SecretKeyFor(engine) is { } name && _secrets.Contains(name);

    /// <summary>Çevrimiçi çeviri şu an etkin mi.</summary>
    public bool OnlineEnabled => OnlineEnabledNow;

    /// <summary>"Ücretsiz Gemini kullanılıyor" (sihirbazın Daha iyi çeviri adımı).</summary>
    public bool UsingFreeGemini => _usingFreeGemini;

    /// <summary>DeepL anahtarını dener; geçerli ya da kotası bitmişse kaydeder.</summary>
    public async Task<KeyCheckStatus> SaveDeepLKeyAsync(string key, CancellationToken cancellationToken = default)
    {
        var trimmed = key.Trim();
        var status = await _services.TryDeepLKeyAsync(trimmed, cancellationToken).ConfigureAwait(false);
        await OnUi();
        if (status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted) StoreKey(OnlineEngine.DeepL, trimmed);
        Refresh();
        return status;
    }

    /// <summary>Kayıtlı DeepL anahtarını dener; yoksa geçersiz.</summary>
    public async Task<KeyCheckStatus> CheckDeepLKeyAsync(CancellationToken cancellationToken = default)
    {
        if (_secrets.Get<string>(SecretKeys.DeepLKey) is not { Length: > 0 } key) return KeyCheckStatus.InvalidKey;
        var status = await _services.TryDeepLKeyAsync(key, cancellationToken).ConfigureAwait(false);
        await OnUi();
        return status;
    }

    static AiService ServiceOf(OnlineEngine engine) => engine switch
    {
        OnlineEngine.Gemini => AiService.Gemini,
        OnlineEngine.OpenAi => AiService.OpenAi,
        OnlineEngine.Claude => AiService.Claude,
        _ => AiService.Local,
    };

    /// <summary>Yapay zekâ anahtarını seçili modelle örnek satırla dener; geçerli, kota bitmiş ya da model reddi ise kaydeder.</summary>
    public async Task<KeyCheckStatus> SaveAiKeyAsync(OnlineEngine engine, string key, CancellationToken cancellationToken = default)
    {
        if (engine is OnlineEngine.Free or OnlineEngine.DeepL or OnlineEngine.Local) return KeyCheckStatus.InvalidKey;
        var trimmed = key.Trim();
        var service = ServiceOf(engine);
        var status = await _services.TryAiKeyAsync(service, TranslationChain.CloudModel(_settings, service), trimmed,
            TargetLanguages.Code(_settings.TargetLanguage), null, cancellationToken).ConfigureAwait(false);
        await OnUi();
        if (status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted or KeyCheckStatus.ModelRejected)
        {
            StoreKey(engine, trimmed);
            if (engine == OnlineEngine.Gemini) _usingFreeGemini = true;
        }
        Refresh();
        return status;
    }

    /// <summary>Kayıtlı yapay zekâ anahtarını dener; yoksa geçersiz.</summary>
    public async Task<KeyCheckStatus> CheckAiKeyAsync(OnlineEngine engine, CancellationToken cancellationToken = default)
    {
        if (TranslationChain.StoredKey(n => _secrets.Get<string>(n), engine) is not { } key) return KeyCheckStatus.InvalidKey;
        var service = ServiceOf(engine);
        var status = await _services.TryAiKeyAsync(service, TranslationChain.CloudModel(_settings, service), key,
            TargetLanguages.Code(_settings.TargetLanguage), null, cancellationToken).ConfigureAwait(false);
        await OnUi();
        return status;
    }

    /// <summary>
    /// Yerel model sunucusunu dener. Yazılan anahtar varsa o (kabul edilirse kaydedilir), yoksa kayıtlı ya da boş.
    /// </summary>
    public async Task<KeyCheckStatus> TryLocalServerAsync(string? typedKey = null, CancellationToken cancellationToken = default)
    {
        if (TranslationChain.LocalServerOf(_settings) is not { } local) return KeyCheckStatus.Unreachable;
        var typed = typedKey?.Trim();
        var key = typed is { Length: > 0 } ? typed : _secrets.Get<string>(SecretKeys.LocalAIKey) ?? "";
        var status = await _services.TryAiKeyAsync(AiService.Local, local.Model, key,
            TargetLanguages.Code(_settings.TargetLanguage), local, cancellationToken).ConfigureAwait(false);
        await OnUi();
        if (typed is { Length: > 0 } && status is KeyCheckStatus.Valid or KeyCheckStatus.QuotaExhausted or KeyCheckStatus.ModelRejected)
            StoreKey(OnlineEngine.Local, typed);
        Refresh();
        return status;
    }

    /// <summary>Çevrimiçi hata türünün açıklaması (Ayarlar'daki deneme sonucu).</summary>
    public string DescribeKeyCheck(KeyCheckStatus status) => DescribeKeyStatus(status);

    /// <summary>Anahtarı kaldırır.</summary>
    public void RemoveKey(OnlineEngine engine)
    {
        if (TranslationChain.SecretKeyFor(engine) is not { } name) return;
        _secrets.Remove(name);
        if (engine == OnlineEngine.Gemini) _usingFreeGemini = false;
        if (engine == OnlineEngine.Local)
        {
            if (_settings.OnlineEngine == OnlineEngine.Local && _translating) BuildPipeline();
        }
        else if (_settings.OnlineEngine == engine)
        {
            ChangeSettings(s => s.OnlineEngine = OnlineEngine.Free);
        }
        RefreshTranslatorStatus();
        if (_translating) BuildPipeline();
        Refresh();
    }

    void StoreKey(OnlineEngine engine, string key)
    {
        if (TranslationChain.SecretKeyFor(engine) is not { } name) return;
        _secrets.Set(name, key);
        if (_settings.OnlineEngine == engine && _settings.OnlineTranslation)
        {
            if (_translating) BuildPipeline();
        }
        else ChangeSettings(s =>
        {
            s.OnlineEngine = engine;
            s.OnlineTranslation = true;
        });
        RefreshTranslatorStatus();
    }

    /// <summary>"Ücretsiz anahtar al": Gemini motor olur (anahtar gelene dek ücretsiz çeviri sürer); sayfa tarayıcıda açılır.</summary>
    public void GetFreeGeminiKey()
    {
        ChangeSettings(s =>
        {
            s.OnlineEngine = OnlineEngine.Gemini;
            s.OnlineTranslation = true;
        });
        _browser.Open(OnlineFailureText.KeyPage(AiService.Gemini));
        Refresh();
    }

    // ---- Yayıncı penceresi ----

    /// <summary>Yayıncı penceresinin zemini.</summary>
    public StreamBackground StreamBackground => SecretKeys.ParseStreamBackground(_secrets.Get<string>(SecretKeys.StreamBackground));

    /// <summary>Zemini kaydeder.</summary>
    public void SetStreamBackground(StreamBackground background)
    {
        _secrets.Set(SecretKeys.StreamBackground, background.ToStoredName());
        Refresh();
    }

    /// <summary>OBS ağ adresi (bilgisayarın ağ adresi varsa).</summary>
    [NotObserved]
    public string? ObsNetworkAddress => _server.ObsAddresses(_services.AddressNear(null)).Network;

    /// <summary>OBS yerel adresi.</summary>
    public string ObsLocalAddress => _server.ObsAddresses(null).Local;
}
