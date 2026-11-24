// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell;

// Ana ekranın okuduğu küçük ek durumlar (ana-ekran.md §3.3, §3.4; Mac'in ana ekranıyla eşit alt şerit ve öneri).
public sealed partial class NinoController
{
    UpdateCheckState _updateCheck;
    volatile bool _updateCheckFailed;
    HashSet<string>? _dismissedKeyGames;

    /// <summary>Seçili çevrimiçi motorun ekrandaki adı ("DeepL", "Gemini", "Yerel model" …; ana ekran kart 8 başlığı).</summary>
    public string OnlineEngineName => EngineDisplayName();

    /// <summary>Ana ekran biçimi (salon ya da cam anahtar).</summary>
    public HomeStyle HomeStyle => _settings.HomeStyle;

    /// <summary>Salon sahnesi Xbox'lı mı: ayarlardaki oyun konsolu Xbox ya da kurulumda Xbox seçildi.</summary>
    public bool HomeSceneIsXbox => _settings.GameConsole == GameConsole.Xbox || IsXbox;

    /// <summary>Oyunun dili (ayarlardaki kaynak dil kodu; yazı tanıma paketi bunun için kurulur).</summary>
    public string SourceLanguage => _settings.SourceLanguage;

    // ---- Fiş balonu ----

    /// <summary>Fiş balonunun metin anahtarı (<see cref="PlugHintText"/>); balon yoksa null.</summary>
    /// <param name="plugged">Sahnede fiş takılı görünüyor.</param>
    public string? PlugHintKey(bool plugged) =>
        PlugHintText.Key(_translating || _starting, plugged, CanStart,
            HomeSceneIsXbox || (UsesCaptureCard && ShowsOnTv && !TvPaired));

    // ---- Alt şerit ----

    /// <summary>Kaynağın (PS5, pencere, kart) alt şeritteki kısa etiketi (uzun metin <see cref="ConsoleStatusText"/>, ipucunda).</summary>
    public string ConsoleShortStatusText
    {
        get
        {
            var streaming = _translating && _status.Phase == SourcePhase.Streaming;
            var connecting = _translating && _status.Phase == SourcePhase.Connecting;
            if (UsesGameWindow)
            {
                if (_windowState == WindowCaptureState.Capturing) return GameWindowText();
                return _text.Get(_windowState == WindowCaptureState.LookingForWindow || _translating
                    ? "home.short.searching" : "home.short.waiting");
            }
            if (UsesCaptureCard)
            {
                return _card.State switch
                {
                    CardCaptureState.NeedsPermission => _text.Get("home.short.permission"),
                    CardCaptureState.NoCard => _text.Get("home.short.noCard"),
                    CardCaptureState.InUse => _text.Get("home.short.cardInUse"),
                    CardCaptureState.BlackPicture => _text.Get("home.short.darkScreen"),
                    CardCaptureState.Capturing => CardText(),
                    _ => _text.Get("home.short.waiting"),
                };
            }
            if (streaming) return _text.Get("status.common.connected");
            if (connecting) return _text.Get("status.common.connecting");
            if (IsXbox)
            {
                if (!_translating)
                    return _text.Get(_xboxConsole is null ? "status.common.notConnected" : "home.short.paired");
                return _text.Get("status.common.reconnecting");
            }
            switch (_settings.FrameSource)
            {
                case FrameSource.RemotePlayWindow:
                    if (!_services.IsRemotePlayAppInstalled(_settings.RemotePlayApp)) return _text.Get("home.short.appMissing");
                    return _text.Get(_translating ? "home.short.searching" : "home.short.waiting");
                case FrameSource.ChosenWindow:
                    if (_settings.CaptureWindow is not { ProcessName.Length: > 0, Title.Length: > 0 })
                        return ChosenWindowText();
                    return _text.Get(_translating ? "home.short.searching" : "home.short.waiting");
            }
            if (!_translating)
                return _text.Get(_console is null ? "status.common.notConnected" : "home.short.paired");
            return HomeShortStatus.DropKey(_status.Reason) is { } key ? _text.Get(key) : _text.Get("status.common.reconnecting");
        }
    }

    /// <summary>Alt şeridin sağındaki "Çeviri …" bağlantısının değeri (<see cref="TranslationLinkRule"/>).</summary>
    public string TranslationLinkValue =>
        TranslationLinkRule.Value(PlayingGame, PoolFirstLive, _settings.TargetLanguage,
            SettingsRules.SelectedEngine(_settings) == OnlineEngine.Free ? null : EngineDisplayName(), _text);

    /// <summary>Son güncelleme denetimi (alt şeridin ortası).</summary>
    public UpdateCheckState UpdateCheck => _updateCheck;

    /// <summary>Eşli TV'deki Nino da güncel mi ("Her şey güncel").</summary>
    public bool TvAppUpToDate => ShowsOnTv && TvPaired && _tvApp.Kind == TvAppKind.UpToDate;

    /// <summary>Alt şeridin ortası.</summary>
    public UpdateCenterState UpdateCenter =>
        UpdateCenterState.Choose(_updating, _updateVersion, _updateCheck, TvAppUpToDate);

    /// <summary>
    /// Ana ekrandan güncelleme denetimi (açılışta ve yenile düğmesiyle): denetlerken "Bakılıyor…", sonra yeni sürüm yoksa
    /// "Güncel", bakılamadıysa yine "Güncellemelere bak". Güncelleyici yoksa hiçbir şey yapmaz.
    /// </summary>
    public async Task CheckForUpdateFromHomeAsync()
    {
        if (_services.Updater is null || _updateCheck == UpdateCheckState.Checking) return;
        _updateCheck = UpdateCheckState.Checking;
        _updateCheckFailed = false;
        Refresh();
        try { await CheckForUpdateAsync(); }
        catch (Exception) { _updateCheckFailed = true; }
        await OnUi();
        _updateCheck = _updateCheckFailed ? UpdateCheckState.Failed : UpdateCheckState.UpToDate;
        Refresh();
    }

    // ---- Anahtar önerisi ----

    /// <summary>"Bu oyun için çeviri anahtarı ekle" önerisinin oyunu (gösterilmeyecekse null).</summary>
    public string? KeySuggestionGame =>
        KeySuggestionRule.Game(IsSetupComplete, SettingsRules.SelectedEngine(_settings) != OnlineEngine.Free,
            _settings.SourceLanguage, PlayingGame, PoolFirstLive, _game.Pack is not null, _packRows, DismissedKeyGames());

    /// <summary>Öneri bu oyunda bir daha çıkmaz (kalıcı).</summary>
    public void DismissKeySuggestion()
    {
        if (PlayingGame is not { Length: > 0 } game) return;
        var set = DismissedKeyGames();
        if (set.Add(KeySuggestionRule.IdOf(game))) KeySuggestionRule.WriteDismissed(DataFolder, set);
        Refresh();
    }

    HashSet<string> DismissedKeyGames() => _dismissedKeyGames ??= KeySuggestionRule.ReadDismissed(DataFolder);
}
