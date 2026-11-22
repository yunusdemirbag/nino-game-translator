// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Imaging;
using Nino.Core.Library;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Translation;

namespace Nino.Shell;

// Paketler, havuzlar ve oynanan oyun (§13).
public sealed partial class NinoController
{
    readonly GameSense _game = new();
    readonly ScreenCheckSchedule _screenSchedule = new();
    IReadOnlyList<PackInfo> _packRows = [];
    bool _gamePickerOpen;
    string? _publishedGame;
    DateTimeOffset? _sessionStartedAt;
    IDisposable? _gameAskTimer;
    IDisposable? _ps5GameTimer;
    CancellationTokenSource? _ps5GameCancel;
    CancellationTokenSource? _poolSyncCancel;
    IDisposable? _packTimer;
    long _packListVersion;
    long? _downloads;
    DateTimeOffset? _downloadsAsked;

    /// <summary>Yüklü paketler; aynı oyunun paketleri tek satır (asıl oyun kimliğine göre).</summary>
    public IReadOnlyList<PackInfo> Packs => _packRows;

    /// <summary>Şu anki oyun (önceliğe göre; bilinmiyorsa null). Tablodaki oyunlar okunur adıyla ("GTA 6").</summary>
    public string? PlayingGame => GameIds.ReadableName(_game.Current?.Name);

    /// <summary>"Hangi oyun?" kartı açık mı.</summary>
    public bool GamePickerOpen => _gamePickerOpen;

    /// <summary>Bu konsolda en son hangi oyunun seçildiği.</summary>
    public string? LastChosenGame => LastGames().GetValueOrDefault(ConsoleKey() ?? "");

    /// <summary>Çeviri havuzunun son bildiği toplam indirme sayısı (yoksa gösterge gizli).</summary>
    public long? Downloads => _downloads ?? _services.Pool?.Downloads;

    /// <summary>Havuz kuruluş kimliği.</summary>
    public string? PoolInstallId => _services.Pool?.InstallId;

    /// <summary>"Kararlı oyun": PS5'in bildirdiği, seçilen ya da çoğunluk paketi (yapay zekâya bağlam).</summary>
    string? StableGame => (_game.Ps5 ?? _game.User ?? _game.Pack)?.Name;

    /// <summary>Havuz öncelikli soruların oyunu (§13.3).</summary>
    string? PoolFirstGame
    {
        get
        {
            var pool = _services.Pool;
            var known = _game.Current?.Name;
            var scope = _services.Packs?.ScopeTitle;
            if (pool is null) return scope ?? known;
            if (known is not null && pool.IsPoolFirst(known)) return known;
            if (scope is not null && pool.IsPoolFirst(scope)) return scope;
            return scope ?? known;
        }
    }

    /// <summary>Havuz öncelikli canlı oyun (salon sahnesindeki TV fonu).</summary>
    public bool PoolFirstLive => _game.Current?.Name is not null && _services.Pool?.IsPoolFirst(PoolFirstGame) == true;

    /// <summary>Alt şeritteki çeviri kaynağı metni.</summary>
    public string TranslationSourceText =>
        PoolFirstLive ? _text.Get("status.translation.poolActive")
        : SettingsRules.SelectedEngine(_settings) == OnlineEngine.Free ? _text.Get("status.translation.free")
        : EngineDisplayName();

    // ---- Açılış (§13.1) ----

    void StartPacksAndPools()
    {
        if (_services.Packs is { } packs)
        {
            var version = _packListVersion;
            Background(async () =>
            {
                await Task.Run(packs.WarmUp).ConfigureAwait(false);
                var infos = packs.Infos;
                await OnUi();
                if (version == _packListVersion) SetPacks(infos);
                Refresh();
            });
        }
        if (_services.PackUpdater is not null)
        {
            Background(() => RefreshPacksFromServerAsync(force: true));
            _packTimer = _timers.Every(TimeSpan.FromDays(1), () => Post(() => Background(() => RefreshPacksFromServerAsync(false))));
        }
        _services.Pool?.SetLanguage(_settings.TargetLanguage);
        _services.Pool?.SetSharePool(_settings.SharePool);
        try { _services.LinePool?.SetEnabled(_settings.SharePool); } catch (Exception) { }
        _downloads = _services.Pool?.Downloads;
    }

    async Task RefreshPacksFromServerAsync(bool force, TimeSpan? maxAge = null)
    {
        if (_services.PackUpdater is not { } updater) return;
        try
        {
            var result = await updater.RefreshAsync(force, maxAge).ConfigureAwait(false);
            await OnUi();
            if (!result.Skipped) DgPackResult(!result.ListFailed, null);
            if (!result.Changed) return;
            _logs.Subtitle("paketler güncellendi: " + string.Join(", ", result.Downloaded.Concat(result.Removed.Select(r => "-" + r))));
            ReloadPacks();
        }
        catch (Exception e) when (e is HttpRequestException or IOException or TaskCanceledException or UnauthorizedAccessException)
        {
            await OnUi();
            DgPackResult(false, e is HttpRequestException { StatusCode: { } code } ? (int)code : null,
                e is HttpRequestException { StatusCode: null } ? "offline" : null);
        }
    }

    /// <summary>"Paketleri yeniden yükle" (Ayarlar).</summary>
    public void ReloadPacks()
    {
        if (_services.Packs is not { } packs) return;
        _packListVersion++;
        packs.Reload();
        SetPacks(packs.Infos);
        if (_pipeline is not null) BuildPipeline();
        Refresh();
    }

    void SetPacks(IReadOnlyList<PackInfo> infos)
    {
        _packRows = GameIds.DistinctPacks(infos);
    }

    // ---- Oturum başı ve sonu ----

    void StartGameDetection()
    {
        _game.NewSession();
        _sessionStartedAt = _timers.Now;
        _screenSchedule.Restart(_timers.Now);
        _gamePickerOpen = false;
        PublishGame();
        _gameAskTimer?.Dispose();
        _gameAskTimer = _timers.Every(TimeSpan.FromSeconds(15), () => Post(CheckGameAsk));
    }

    void StopGameDetection()
    {
        _gameAskTimer?.Dispose();
        _gameAskTimer = null;
        _gamePickerOpen = false;
        _sessionStartedAt = null;
    }

    void CheckGameAsk()
    {
        if (!_translating || _sessionStartedAt is not { } start) return;
        if (_settings.SharePool && _game.ShouldAsk(_settings.AskGame, _timers.Now - start))
        {
            _game.MarkAsked();
            _gamePickerOpen = true;
        }
    }

    // ---- PS5 oyun sorusu ----

    void StartPs5GamePoll()
    {
        if (_ps5GameTimer is not null || _services.LinePool is null || _console is null) return;
        _ps5GameCancel = new CancellationTokenSource();
        var token = _ps5GameCancel.Token;
        void Ask() => Background(async () =>
        {
            if (_console?.Host is not { Length: > 0 } host) return;
            Nino.RemotePlay.FoundPs5? found;
            try { found = await _services.RunningGameAsync(host, token).ConfigureAwait(false); }
            catch (Exception) { return; }
            await OnUi();
            if (token.IsCancellationRequested) return;
            var game = RunningGame.WithName(found?.RunningAppName, found?.RunningAppTitleId);
            if (game != _game.Ps5)
            {
                _logs.Subtitle($"PS5'te çalışan oyun: {game?.Name ?? "?"} ({game?.Id ?? "?"})");
                _game.SetPs5(game);
                PublishGame();
            }
            Refresh();
        });
        Ask();
        _ps5GameTimer = _timers.Every(TimeSpan.FromMinutes(2), () => Post(Ask));
    }

    void StopPs5GamePoll()
    {
        _ps5GameTimer?.Dispose();
        _ps5GameTimer = null;
        _ps5GameCancel?.Cancel();
        _ps5GameCancel = null;
        if (_game.Ps5 is not null)
        {
            _game.SetPs5(null);
            PublishGame();
        }
    }

    // ---- Seç / değiştir / sorma ----

    /// <summary>Oyunu seçer.</summary>
    public void ChooseGame(string? name)
    {
        var clean = RunningGame.CleanName(name);
        if (clean is null) return;
        _game.SetUser(clean);
        if (ConsoleKey() is { } key)
        {
            var map = new Dictionary<string, string>(LastGames()) { [key] = clean };
            _secrets.Set(SecretKeys.LastGames, map);
        }
        _gamePickerOpen = false;
        PublishGame();
        Refresh();
    }

    /// <summary>"Değiştir": kart açılır.</summary>
    public void ChangeGame()
    {
        _game.MarkAsked();
        _gamePickerOpen = true;
        Refresh();
    }

    /// <summary>"Sorma": kart kapanır.</summary>
    public void DismissGamePicker()
    {
        _game.MarkAsked();
        _gamePickerOpen = false;
        Refresh();
    }

    /// <summary>Kartın önerileri.</summary>
    public IReadOnlyList<string> GameSuggestions(string? query) =>
        GamePicker.Suggestions(query, _packRows.Select(p => (p.Id, p.Title)), LastChosenGame);

    string? ConsoleKey() => _console is { } c ? (c.Name.Length > 0 ? c.Name : c.Host) : null;

    Dictionary<string, string> LastGames() =>
        _secrets.Get<Dictionary<string, string>>(SecretKeys.LastGames) ?? [];

    void PublishGame()
    {
        _services.Packs?.SelectGame(_game.PackSearchLimit);
        var current = _game.Current?.Name;
        if (current == _publishedGame) return;
        _publishedGame = current;
        if (_pipeline is not null) RestartPoolSync(force: true);
        if (current is not null && _services.PackUpdater is not null)
            Background(() => RefreshPacksFromServerAsync(false, PackUpdater.NewGameMaxAge));
    }

    // ---- Havuz eşitlemesi ----

    void RestartPoolSync(bool force)
    {
        StopPoolSync();
        if (_services.Pool is not { } pool || !PoolTranslationsEnabled) return;
        var cts = new CancellationTokenSource();
        _poolSyncCancel = cts;
        Func<string?> game = () => _services.Packs?.ScopeTitle ?? _game.Current?.Name;
        // Uzun süren döngü arka plan işleri listesine girmez (WhenIdleAsync onu beklemez).
        _ = Task.Run(async () =>
        {
            try { await pool.RunSyncLoopAsync(game, cts.Token).ConfigureAwait(false); }
            catch (Exception e) when (e is not OperationCanceledException) { _logs.Error("Havuz eşitlemesi durdu", e); }
            catch (OperationCanceledException) { }
        });
    }

    void StopPoolSync()
    {
        _poolSyncCancel?.Cancel();
        _poolSyncCancel = null;
    }

    // ---- Ekrandan tanıma (§13.3) ----

    void MaybeIdentifyGame(BgraFrame frame)
    {
        var pool = _services.Pool;
        if (!_translating || pool is null || !_settings.SharePool || TargetLanguages.Code(_settings.SourceLanguage) != "en") return;
        if (_services.Packs?.ScopeTitle is not null && pool.IsPoolFirst(PoolFirstGame)) return;
        if (!pool.Enabled) return;
        var now = _timers.Now;
        if (!_screenSchedule.ShouldCheck(now, _game.Source)) return;
        var jpeg = _services.Readers.SmallJpeg(frame, 768, 60);
        if (jpeg is null) return;
        _screenSchedule.Begin(now);
        var before = _game.Screen?.Name;
        Background(async () =>
        {
            string? name = null;
            try { name = await pool.IdentifyAsync(jpeg).ConfigureAwait(false); }
            catch (Exception) { }
            await OnUi();
            _screenSchedule.Finish();
            if (!_translating) return;
            if (name is null)
            {
                _logs.Subtitle(before is null ? "oyun ekrandan tanınamadı" : $"ikinci bakışta da oyun belirlenemedi; {before} geçerli kalıyor");
            }
            else if (Same(before, name)) _logs.Subtitle("oyun doğrulandı: " + name);
            else
            {
                _logs.Subtitle(before is null ? "oyun ekrandan tanındı: " + name : $"oyun değişmiş: {before} → {name}");
                _game.SetScreen(name);
                _gamePickerOpen = false;
                PublishGame();
            }
            Refresh();
        });
    }

    // ---- İndirme sayısı ----

    /// <summary>İndirme sayısını yeniler (sunucu ayarı en sık 10 dakikada bir sorulur).</summary>
    public void RefreshDownloads()
    {
        if (_services.Pool is not { } pool) return;
        var now = _timers.Now;
        if (_downloadsAsked is { } asked && now - asked < TimeSpan.FromMinutes(10)) return;
        _downloadsAsked = now;
        Background(async () =>
        {
            try { await pool.RefreshConfigAsync().ConfigureAwait(false); }
            catch (Exception) { return; }
            await OnUi();
            if (pool.Downloads is { } d) _downloads = d;
            Refresh();
        });
    }

    void StopTimers()
    {
        _gameAskTimer?.Dispose();
        _ps5GameTimer?.Dispose();
        _packTimer?.Dispose();
        _updateTimer?.Dispose();
        _tvAppTimer?.Dispose();
        StopPoolSync();
    }
}
