// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Shell;

// Tek seferlik işler (§12.1, §12.2, §12.4): deneme altyazısı, duraklat, anlık görüntü, ek bölge, serbest alan,
// ekranı çevir, kısayollar.
public sealed partial class NinoController
{
    bool _regionBusy;
    bool _freeAreaBusy;
    CancellationTokenSource? _screenCancel;
    DateTimeOffset? _screenShownUntil;
    bool _adjustMode;
    bool _waitingForHotkey;
    bool _hotkeysHeld;
    string? _heldHotkeys;

    /// <summary>Bilgisayar penceresinde gösterilecek kısa ileti (ek bölge sonucu).</summary>
    public event Action<PopupText>? ComputerPopup;

    /// <summary>Ayarlama modu (pencere taşınıyor/genişletiliyor).</summary>
    public bool AdjustMode
    {
        get => _adjustMode;
        set
        {
            _adjustMode = value && ShowsOnComputer;
            Refresh();
        }
    }

    /// <summary>Ayarlar yeni kısayol bekliyor mu (genel kısayollar bırakılır).</summary>
    public bool WaitingForHotkey
    {
        get => _waitingForHotkey;
        set
        {
            _waitingForHotkey = value;
            Refresh();
        }
    }

    /// <summary>Genel kısayollar şu an tutulmalı mı.</summary>
    public bool HotkeysActive => _translating && !_waitingForHotkey;

    void UpdateHotkeys()
    {
        if (_hotkeys is null) return;
        var want = HotkeysActive && !_closing;
        var table = Hotkeys.Resolve(_settings.Hotkeys);
        var signature = string.Join(";", table.Select(b => $"{b.Action}/{b.Slot}/{b.Key.Modifiers}/{b.Key.VirtualKey}"));
        if (want && (!_hotkeysHeld || signature != _heldHotkeys))
        {
            _hotkeys.Hold(table);
            _hotkeysHeld = true;
            _heldHotkeys = signature;
        }
        else if (!want && _hotkeysHeld)
        {
            _hotkeys.Release();
            _hotkeysHeld = false;
            _heldHotkeys = null;
        }
    }

    /// <summary>Kısayol eylemi (Num 1–3, 5, 7, 8, 9, 0).</summary>
    public async Task<OneShotResult?> RunHotkeyAsync(HotkeyAction action)
    {
        switch (action)
        {
            case HotkeyAction.ExtraRegion1: return await TranslateExtraRegionAsync(1).ConfigureAwait(false);
            case HotkeyAction.ExtraRegion2: return await TranslateExtraRegionAsync(2).ConfigureAwait(false);
            case HotkeyAction.ExtraRegion3: return await TranslateExtraRegionAsync(3).ConfigureAwait(false);
            case HotkeyAction.PauseSubtitles: TogglePause(); return null;
            case HotkeyAction.Snapshot: RequestSnapshot(); return null;
            case HotkeyAction.Screen: return await TranslateScreenAsync().ConfigureAwait(false);
            case HotkeyAction.ClickThrough: ToggleClickThrough(); return null;
            case HotkeyAction.FreeArea: FreeAreaRequested?.Invoke(); return null;
            default: return null;
        }
    }

    /// <summary>Serbest seçim penceresi açılsın (Num 5; pencere alanı seçip <see cref="TranslateFreeAreaAsync"/>'i çağırır).</summary>
    public event Action? FreeAreaRequested;

    /// <summary>Num 7: tıklama geçirgenliğini tersine çevirir (kaydedilir).</summary>
    public void ToggleClickThrough() => ChangeSettings(s => s.OverlayClickThrough = !s.OverlayClickThrough);

    /// <summary>Num 8: anlık görüntü istendi.</summary>
    public void RequestSnapshot() => SnapshotRequested?.Invoke();

    // ---- Deneme altyazısı ----

    /// <summary>Deneme altyazısı (çeviri yokken sunucuyu da açar; açılamazsa yalnız bilgisayar penceresine gider).</summary>
    public async Task SendTestSubtitleAsync(CancellationToken cancellationToken = default)
    {
        if (!_translating)
        {
            try { await _server.StartAsync(cancellationToken).ConfigureAwait(false); }
            catch (Exception e) { _logs.Subtitle("altyazı sunucusu açılamadı: " + e.Message); }
            await OnUi();
        }
        SendStyle();
        var bottom = _settings.Region.Bottom;
        var box = _lastSubtitleBox ?? new Box(0.3, bottom - 0.1, 0.7, bottom - 0.03);
        _server.Send(new SubtitleShown(_text.Get("status.testSubtitle"), 8000, box));
        Refresh();
    }

    // ---- Duraklat (Num 0) ----

    /// <summary>Altyazı çevirisini duraklatır ya da sürdürür (yalnız çeviri sürerken).</summary>
    public void TogglePause()
    {
        if (!_translating) return;
        _paused = !_paused;
        if (_paused)
        {
            ResetReaders();
            _server.Send(new SubtitleCleared());
        }
        else UpdateExtraAreas();
        _server.Send(new SubtitleShown(_text.Get(_paused ? "status.pause.paused" : "status.pause.resumed"), 1800));
        Refresh();
    }

    // ---- Ek bölge (Num 1–3) ----

    (Region? Region, ResultTarget Target) ExtraSlot(int slot) => slot switch
    {
        1 => (_settings.ExtraRegion1, _settings.ExtraTarget1),
        2 => (_settings.ExtraRegion2, _settings.ExtraTarget2),
        _ => (_settings.ExtraRegion3, _settings.ExtraTarget3),
    };

    /// <summary>Ek bölgeyi bir kez okur ve çevirir.</summary>
    public async Task<OneShotResult> TranslateExtraRegionAsync(int slot, CancellationToken cancellationToken = default)
    {
        var (region, target) = ExtraSlot(slot);
        if (region is null) return OneShotResult.NotConfigured;
        if (!_translating || _readerForExtras is null || _chain is null || _lastFrame is not { } frame) return OneShotResult.NotRunning;
        if (_regionBusy) return OneShotResult.Busy;
        _regionBusy = true;
        var reader = _readerForExtras;
        var translator = _chain.Translator;
        var box = Box.FromRegion(region);
        try
        {
            var result = await Task.Run(() => RegionTranslation.TranslateAsync(frame, box, reader, translator, cancellationToken),
                cancellationToken).ConfigureAwait(false);
            await OnUi();
            var id = $"area{slot}";
            if (result is null)
            {
                var noText = _text.Get("status.area.noText");
                if (target != ResultTarget.Computer) _server.Send(new SubtitleShown(noText, 2500, box));
                if (target != ResultTarget.Tv) ComputerPopup?.Invoke(new PopupText(noText, 2500));
                return OneShotResult.NoText;
            }
            if (target != ResultTarget.Computer)
                _server.Send(new SubtitleShown(result.Translation, result.DurationMs, result.Box, result.Structured));
            _lastSource = result.Source;
            _lastTranslation = result.Translation;
            if (target != ResultTarget.Tv) ComputerPopup?.Invoke(new PopupText(result.Translation, result.DurationMs));
            return OneShotResult.Shown;
        }
        catch (TranslatorUnavailableException e)
        {
            await OnUi();
            OnTranslationFinished(false, e.Reason);
            return OneShotResult.NoTranslator;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("Ek bölge çevrilemedi", e);
            return OneShotResult.Failed;
        }
        finally
        {
            _regionBusy = false;
            Refresh();
        }
    }

    // ---- Serbest seçim (Num 5) ----

    /// <summary>Verilen karedeki alanı bir kez okur; TV'ye (hedef bilgisayar değilse) gider, sonuç her durumda döner.</summary>
    public async Task<FreeAreaResult> TranslateFreeAreaAsync(BgraFrame frame, Box area, CancellationToken cancellationToken = default)
    {
        if (!_translating || _readerForExtras is null || _chain is null) return new(OneShotResult.NotRunning);
        if (_freeAreaBusy) return new(OneShotResult.Busy);
        _freeAreaBusy = true;
        var reader = _readerForExtras;
        var translator = _chain.Translator;
        var target = _settings.FreeAreaTarget;
        try
        {
            var result = await Task.Run(() => RegionTranslation.TranslateAsync(frame, area, reader, translator, cancellationToken),
                cancellationToken).ConfigureAwait(false);
            await OnUi();
            if (result is null)
            {
                if (target != ResultTarget.Computer) _server.Send(new SubtitleShown(_text.Get("status.area.noText"), 2500, area));
                return new(OneShotResult.NoText);
            }
            if (target != ResultTarget.Computer)
                _server.Send(new SubtitleShown(result.Translation, result.DurationMs, result.Box, result.Structured));
            _lastSource = result.Source;
            _lastTranslation = result.Translation;
            return new(OneShotResult.Shown, result.Source, result.Translation, result.DurationMs);
        }
        catch (TranslatorUnavailableException e)
        {
            await OnUi();
            OnTranslationFinished(false, e.Reason);
            return new(OneShotResult.NoTranslator);
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("Serbest seçim çevrilemedi", e);
            return new(OneShotResult.Failed);
        }
        finally
        {
            _freeAreaBusy = false;
            Refresh();
        }
    }

    // ---- Tam ekran çevirisi (Num 9) ----

    /// <summary>Ekrandaki bütün yazıları çevirir; sürerken ya da TV'de duruyorken basılırsa temizler.</summary>
    public async Task<OneShotResult> TranslateScreenAsync(CancellationToken cancellationToken = default)
    {
        if (!_translating || _readerForExtras is null || _chain is null) return OneShotResult.NotRunning;
        if (_lastFrame is not { } frame)
        {
            _server.Send(new SubtitleShown(_text.Get("status.screenTranslate.noFrame"), 4000));
            return OneShotResult.NotRunning;
        }
        if (_screenCancel is not null)
        {
            _screenCancel.Cancel();
            _screenCancel = null;
            _server.Send(new ScreenCleared());
            _screenShownUntil = null;
            return OneShotResult.Cleared;
        }
        if (_screenShownUntil is { } until && until > _timers.Now)
        {
            _server.Send(new ScreenCleared());
            _screenShownUntil = null;
            return OneShotResult.Cleared;
        }

        var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _screenCancel = cts;
        var reader = _readerForExtras;
        var translator = _chain.Translator;
        _server.Send(new SubtitleShown(_text.Get("status.screenTranslate.working"), 2500));
        try
        {
            var groups = await Task.Run(() => ScreenTranslation.Group(ScreenTranslation.Read(frame, reader)), cts.Token)
                .ConfigureAwait(false);
            var shownLength = 0;
            var items = await ScreenTranslation.TranslateAsync(groups, translator, partial =>
            {
                shownLength = partial.Sum(i => i.Text.Length);
                var duration = ScreenTranslation.DurationMs(shownLength);
                _server.Send(new ScreenShown(partial.Select(ToLink).ToList(), duration));
                _post(() => _screenShownUntil = _timers.Now.AddMilliseconds(duration));
            }, cts.Token).ConfigureAwait(false);
            await OnUi();
            if (cts.IsCancellationRequested) return OneShotResult.Cleared;
            _server.Send(new SubtitleCleared());
            if (items.Count == 0)
            {
                _server.Send(new SubtitleShown(_text.Get("status.screenTranslate.noText"), 2500));
                return OneShotResult.NoText;
            }
            _screenShownUntil = _timers.Now.AddMilliseconds(ScreenTranslation.DurationMs(items.Sum(i => i.Text.Length)));
            return OneShotResult.Shown;
        }
        catch (OperationCanceledException)
        {
            await OnUi();
            return OneShotResult.Cleared;
        }
        catch (TranslatorUnavailableException e)
        {
            await OnUi();
            OnTranslationFinished(false, e.Reason);
            ScreenFailed(ScreenReason(e.Reason));
            return OneShotResult.NoTranslator;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.RemotePlay("Ekran çevrilemedi: " + e.Message);
            ScreenFailed(ScreenReason(null));
            return OneShotResult.Failed;
        }
        finally
        {
            if (_screenCancel == cts) _screenCancel = null;
            cts.Dispose();
            Refresh();
        }
    }

    void ScreenFailed(string reason)
    {
        _server.Send(new ScreenCleared());
        _screenShownUntil = null;
        _server.Send(new SubtitleShown(_text.Format("status.screenTranslate.failed", reason), 6000));
    }

    string ScreenReason(UnavailableReason? reason)
    {
        if (_onlineStatus is { LastFailure: { } failure }) return OnlineFailureDescription(failure);
        if (_onlineStatus is { LastLineHitMinuteLimit: true })
            return _text.Format("status.screenTranslate.reason.rateLimit", EngineDisplayName());
        return reason switch
        {
            UnavailableReason.DownloadRequired => _text.Get("status.screenTranslate.reason.notDownloaded"),
            UnavailableReason.EngineFailed => _text.Get("status.screenTranslate.reason.engineFailed"),
            _ => _text.Get("status.screenTranslate.reason.generic"),
        };
    }

    // ---- Çevrimiçi hata açıklaması (§19.3) ----

    string EngineDisplayName() => _settings.OnlineEngine switch
    {
        OnlineEngine.DeepL => OnlineFailureText.DeepLBrand,
        OnlineEngine.Gemini => OnlineFailureText.Brand(AiService.Gemini),
        OnlineEngine.OpenAi => OnlineFailureText.Brand(AiService.OpenAi),
        OnlineEngine.Claude => OnlineFailureText.Brand(AiService.Claude),
        OnlineEngine.Local => _text.Get("status.online.localModelName"),
        _ => _text.Get("status.translation.free"),
    };

    /// <summary>Çevrimiçi motorun hata türünün ekran metni.</summary>
    public string OnlineFailureDescription(OnlineFailure failure) => DescribeKeyStatus(OnlineFailureText.ToStatus(failure));

    string DescribeKeyStatus(KeyCheckStatus status)
    {
        if (_settings.OnlineEngine == OnlineEngine.Local && TranslationChain.LocalServerOf(_settings) is { } local)
        {
            return status switch
            {
                KeyCheckStatus.Valid => _text.Get("status.online.working"),
                KeyCheckStatus.InvalidKey => _text.Get("status.online.local.keyRejected"),
                KeyCheckStatus.QuotaExhausted => _text.Get("status.online.local.busy"),
                KeyCheckStatus.ModelRejected => local.Kind == LocalServerKind.LmStudio
                    ? _text.Format("status.online.local.lmStudioModelMissing", local.Model)
                    : _text.Format("status.online.local.modelMissing", local.Model),
                _ => local.Kind switch
                {
                    LocalServerKind.Ollama => _text.Format("status.online.local.ollamaDown", local.ShortAddress, local.Model),
                    LocalServerKind.LmStudio => _text.Format("status.online.local.lmStudioDown", local.ShortAddress),
                    _ => _text.Format("status.online.local.unreachable", local.ShortAddress),
                },
            };
        }
        var brand = EngineDisplayName();
        return status switch
        {
            KeyCheckStatus.Valid => _text.Get("status.online.working"),
            KeyCheckStatus.InvalidKey => _text.Format("status.online.invalidKey", brand),
            KeyCheckStatus.QuotaExhausted => _text.Format("status.online.quota", brand),
            KeyCheckStatus.ModelRejected => _text.Format("status.online.modelRejected", brand),
            _ => _text.Format("status.online.unreachable", brand),
        };
    }
}
