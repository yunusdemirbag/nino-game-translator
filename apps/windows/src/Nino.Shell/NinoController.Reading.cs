// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Imaging;
using Nino.Core.Library;
using Nino.Core.Link;
using Nino.Core.Phone;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.RemotePlay;
using Nino.Shell.Platform;
using ReadingScreenItem = Nino.Core.Reading.ScreenItem;

namespace Nino.Shell;

// Kare işleyici (§10.7), okuma hattı ve çevirmen zinciri (§11), ek bölgeler ve telefon (§12).
public sealed partial class NinoController
{
    readonly FrameGate _gate;
    readonly Nino.Core.Reading.IMsClock _msClock;
    readonly SubtitleHistory _history = new();
    readonly PoolContextLines _poolContext = new();
    SubtitlePipeline? _pipeline;
    TranslatorChain? _chain;
    ITextReader? _reader;
    ITextReader? _readerForExtras;
    ExtraAreaTracker? _extra;
    PhoneOverlay? _overlay;
    bool _phoneFailed;
    bool _phoneQueued;
    BgraFrame? _lastFrame;
    string? _activeLanguage;
    bool _ocrMissing;
    string _metricsLine = "";
    string? _lastSource;
    string? _lastTranslation;
    Box? _lastSubtitleBox;
    TranslatorStatus _translatorStatus;
    bool _freeCreateFailed;
    bool _gpuFellBack;
    OnlineFailure? _onlineProblem;
    IOnlineEngineStatus? _onlineStatus;
    Action<OnlineFailure?>? _onlineHandler;
    long _pipelineGen;

    /// <summary>Son kare (ek bölge, serbest alan, ayar ekranı önizlemesi). Değişimi ayrıca bildirilmez; <see cref="FrameArrived"/>.</summary>
    [NotObserved]
    public BgraFrame? LastFrame => _lastFrame;

    /// <summary>Son kare değişti (arayüz iş parçacığında).</summary>
    public event Action? FrameArrived;

    /// <summary>"Anlık görüntü istendi" (Num 8): ayar ekranı oyunun şu anki görüntüsünü yeniden alsın.</summary>
    public event Action? SnapshotRequested;

    /// <summary>Etkin dil (çeviri sürerken kaynak dil).</summary>
    public string? ActiveLanguage => _activeLanguage;

    /// <summary>OCR eksik mi (okuyucu yok ya da dilin OCR paketi yok).</summary>
    public bool OcrMissing => _ocrMissing;

    /// <summary>Ölçüm satırı; ilk satır gelene kadar boş.</summary>
    public string MetricsLine => _metricsLine;

    /// <summary>Son gösterilen İngilizce kaynak.</summary>
    public string? LastSource => _lastSource;

    /// <summary>Son çeviri.</summary>
    public string? LastTranslation => _lastTranslation;

    /// <summary>Çevirmen durumu.</summary>
    public TranslatorStatus TranslatorStatus => _translatorStatus;

    /// <summary>"GPU kullanılamadı, CPU'ya geçildi" uyarısı.</summary>
    public bool GpuFellBack => _gpuFellBack;

    /// <summary>Çevrimiçi motorun şu anki sorunu (ana ekran uyarısı).</summary>
    public OnlineFailure? OnlineProblem => _onlineProblem;

    /// <summary>Çevrimiçi sorunun açıklaması (Ayarlar ve ana ekran aynı metni kullanır).</summary>
    public string? OnlineProblemText => _onlineProblem is { } f ? OnlineFailureDescription(f) : null;

    /// <summary>Geçmiş.</summary>
    public IReadOnlyList<HistoryEntry> History => _historyView;

    IReadOnlyList<HistoryEntry> _historyView = [];

    /// <summary>
    /// Ana hesap ipucu (GitHub #231): çeviri sürüyor, Xbox değil, PS5 yolu, henüz hiç çeviri gelmedi.
    /// </summary>
    public bool MainAccountHint =>
        _translating && !IsXbox && OnStreamPath && _settings.FrameSource == FrameSource.Ps5 && _lastTranslation is null;

    bool PacksEnabled => _settings.GamePacks && TargetLanguages.Code(_settings.SourceLanguage) == "en"
        && TargetLanguages.Code(_settings.TargetLanguage) == "tr" && _services.Packs is not null;

    bool PoolTranslationsEnabled => _settings.SharePool && TargetLanguages.Code(_settings.SourceLanguage) == "en"
        && _services.Pool is not null;

    // ---- Kare işleyici (kare iş parçacığında; hata kaçmaz) ----

    void OnFrame(long gen, VideoFrame vf)
    {
        try
        {
            if (gen != Volatile.Read(ref _sourceGen)) return;
            DgFrame(Volatile.Read(ref _paused));
            var arrived = _msClock.NowMs;
            var frame = BgraFrame.CopyFrom(vf.Bgra, vf.Width, vf.Height, vf.Stride);
            _post(() =>
            {
                if (gen != _sourceGen) return;
                _lastFrame = frame;
                try { FrameArrived?.Invoke(); } catch (Exception) { }
                MaybeIdentifyGame(frame);
            });
            if (Volatile.Read(ref _paused)) return;
            var pipeline = Volatile.Read(ref _pipeline);
            if (pipeline is null) return;
            Volatile.Read(ref _extra)?.Offer(frame);

            if (Volatile.Read(ref _overlay) is { } overlay)
            {
                if (PhoneGame)
                {
                    if (!overlay.Installed && !_phoneFailed && !_phoneQueued)
                    {
                        _phoneQueued = true;
                        Post(SetUpPhoneReaders);
                    }
                    overlay.OnFrame(frame);
                }
                else if (overlay.Installed) Post(() => _overlay?.Remove());
            }

            var entry = _gate.TryEnter(arrived);
            if (entry.Outcome == GateOutcome.Busy) return;
            if (entry.Outcome == GateOutcome.Stuck)
            {
                _logs.Subtitle($"okuma {entry.ElapsedMs} ms geçtiği hâlde bitmedi; okuma hattı baştan kuruldu");
                DgOcrStuck(entry.ElapsedMs);
                Post(() => { if (_pipeline is not null) BuildPipeline(); });
                return;
            }
            var area = Box.FromRegion(_settings.Region);
            _lastFrameWork = RunFrameAsync(pipeline, frame, area, arrived, entry.Ticket);
        }
        catch (Exception e)
        {
            try { _logs.Error("Kare işlenemedi", e); } catch (Exception) { }
        }
    }

    Task _lastFrameWork = Task.CompletedTask;

    /// <summary>Son karenin okuması, süren çeviriler ve ek bölge turu bitene kadar bekler (testler).</summary>
    internal async Task WaitForReadingAsync()
    {
        try { await _lastFrameWork.ConfigureAwait(false); } catch (Exception) { }
        if (_pipeline is { } p) await p.WaitForTranslationsAsync().ConfigureAwait(false);
        if (_extra is { } x) await x.WaitIdleAsync().ConfigureAwait(false);
        await WhenIdleAsync().ConfigureAwait(false);
    }

    async Task RunFrameAsync(SubtitlePipeline pipeline, BgraFrame frame, Box area, long arrived, long ticket)
    {
        try
        {
            await pipeline.ProcessFrameAsync(frame, area, arrived).ConfigureAwait(false);
            DgOcrFinished(Math.Max(0, _msClock.NowMs - arrived));
        }
        catch (Exception e)
        {
            try { _logs.Error("Okuma hattı hata verdi", e); } catch (Exception) { }
            Post(() => RecordErrorCode("ocr.failed"));
        }
        finally { _gate.Exit(ticket); }
    }

    // ---- Hattı kur (§11.1) ----

    void ResetPipeline()
    {
        var old = _pipeline;
        _pipeline = null;
        _pipelineGen++;
        try { old?.Reset(); } catch (Exception) { }
        DetachOnline();
        ResetReaders();
        var overlay = _overlay;
        _overlay = null;
        try { overlay?.Remove(); } catch (Exception) { }
        (_reader as IDisposable)?.Dispose();
        _reader = null;
        _chain = null;
    }

    void ResetReaders()
    {
        try { _pipeline?.Reset(); } catch (Exception) { }
        var extra = _extra;
        _extra = null;
        if (extra is not null)
        {
            try { extra.Reset(); } catch (Exception) { }
            _server.Send(new RegionsCleared());
        }
        _phoneFailed = false;
        _phoneQueued = false;
        try { _overlay?.ResetReaders(); } catch (Exception) { }
    }

    void BuildPipeline()
    {
        ResetPipeline();
        _gate.Reset();
        var lang = _settings.SourceLanguage;
        _activeLanguage = lang;
        var reader = _services.Readers.Create(lang);
        _ocrMissing = reader is null || !_services.Readers.HasLanguagePack(lang);
        if (reader is null) return;
        _reader = reader;
        _readerForExtras = reader;
        var chain = BuildChain();
        _chain = chain;
        RefreshTranslatorStatus();
        var gen = _pipelineGen;
        var overlay = new PhoneOverlay(new ServerOutput(_server), _msClock);
        _overlay = overlay;
        var quality = _services.Readers.QualityFor(lang);
        var options = new SubtitlePipelineOptions
        {
            Plan = ReadPlan.ForApp(_settings.FastSubtitleDetection),
            ShowSpeakerNames = _settings.ShowSpeakerNames,
            MisreadWaitMs = SettingsRules.ClampWait(_settings.MisreadWaitMs),
            PartialWaitMs = SettingsRules.ClampWait(_settings.PartialWaitMs),
            Pack = HasLookup ? new LookupAdapter(this) : null,
            ExtraMisread = quality?.IsMisread,
            ReadingScore = quality?.Score,
            HoldWithoutPack = quality is not null,
            Phone = overlay.CreateLineHooks(() => PhoneGame),
            Log = line => _logs.Subtitle(line),
        };
        var pipeline = new SubtitlePipeline(reader, chain.Translator, new ServerOutput(_server, NewTvShows()), _msClock, options);
        pipeline.MetricsReady += m => Post(() => { if (gen == _pipelineGen) OnMetrics(m); });
        pipeline.PairShown += p => Post(() => { if (gen == _pipelineGen) OnPairShown(p); });
        pipeline.TranslationFinished += (ok, reason) => Post(() => { if (gen == _pipelineGen) OnTranslationFinished(ok, reason); });
        pipeline.NotInPack += line => Post(() => { if (gen == _pipelineGen) SuggestToPool(line); });
        _pipeline = pipeline;
        AttachOnline(chain);
        UpdateExtraAreas();
        RestartPoolSync(force: true);
    }

    bool HasLookup => PacksEnabled || (TargetLanguages.Code(_settings.SourceLanguage) == "en" && _services.Pool is not null);

    TranslatorChain BuildChain()
    {
        var pool = _services.Pool;
        PoolFirstOptions? poolFirst = pool is null ? null
            : new PoolFirstOptions(pool, TargetLanguages.Code(_settings.SourceLanguage) == "en", () => PoolFirstGame,
                line => _poolContext.Before(line), line => _logs.Subtitle(line));
        return TranslationChain.Build(_settings, name => _secrets.Get<string>(name), new GuardedFactory(this),
            () => StableGame, poolFirst);
    }

    void AttachOnline(TranslatorChain chain)
    {
        DetachOnline();
        if (chain.OnlineStatus is not { } status) return;
        _onlineStatus = status;
        _onlineHandler = f => Post(() =>
        {
            _onlineProblem = f;
            TmOnlineFailure(f);
        });
        status.FailureChanged += _onlineHandler;
        _onlineProblem = status.LastFailure;
    }

    void DetachOnline()
    {
        if (_onlineStatus is { } s && _onlineHandler is { } h) s.FailureChanged -= h;
        _onlineStatus = null;
        _onlineHandler = null;
        _onlineProblem = null;
    }

    /// <summary>Ücretsiz çevirmenin oluşturulmasını koruyan fabrika (§11.2 madde 4).</summary>
    sealed class GuardedFactory(NinoController owner) : ITranslatorFactory
    {
        public ITranslator CreateFree(string target)
        {
            try
            {
                return owner._services.Translators.CreateFree(target);
            }
            catch (Exception e)
            {
                owner._logs.RemotePlay("Ücretsiz çeviri motoru kurulamadı: " + e.Message);
                owner._freeCreateFailed = true;
                return new UnavailableTranslator(UnavailableReason.EngineFailed);
            }
        }

        public ITranslator CreateDeepL(string apiKey, string target, ITranslator? fallback) =>
            owner._services.Translators.CreateDeepL(apiKey, target, fallback);

        public ITranslator CreateAi(AiService service, string model, string apiKey, string target, LocalServer? local,
            ITranslator? fallback, Func<string?> gameName) =>
            owner._services.Translators.CreateAi(service, model, apiKey, target, local, fallback, gameName);
    }

    void OnMetrics(SubtitleMetrics m)
    {
        TmMetrics(m);
        if (m.Origin != ShownOrigin.Pack)
            _health.LineShown(m.TranslationMs is { } t ? TimeSpan.FromMilliseconds(t) : null);
        else _health.LineShown(null);
        _metricsLine = string.Join(" · ", m.Parts().Select(p => p.Kind switch
        {
            MetricPartKind.Ocr => _text.Format("reading.metrics.ocr", p.Value),
            MetricPartKind.FromPack => _text.Get("reading.metrics.fromPack"),
            MetricPartKind.Translation => _text.Format("reading.metrics.translation", p.Value),
            MetricPartKind.Latency => _text.Format("reading.metrics.delay", p.Value),
            _ => null,
        }).Where(s => s is not null));
    }

    void OnPairShown(ShownPair pair)
    {
        TmLineShown();
        if (pair.Origin == ShownOrigin.Pack && pair.Pack?.PackId is { } packId)
        {
            if (_game.NotePackLine(packId, pair.Pack.PackName))
            {
                _gamePickerOpen = false;
                PublishGame();
            }
        }
        _lastSource = pair.Source;
        _lastTranslation = pair.Translation;
        _lastSubtitleBox = _pipeline?.LastBox ?? _lastSubtitleBox;
        _poolContext.Add(pair.Source);
        if (_history.Add(pair.Source, pair.Translation, pair.Origin == ShownOrigin.Pack ? HistoryOrigin.Pack : HistoryOrigin.Engine))
        {
            _historyView = _history.Entries;
            SaveHistoryInBackground();
        }
    }

    Task _historyWrite = Task.CompletedTask;

    void SaveHistoryInBackground()
    {
        if (_services.HistoryPath is not { } path) return;
        var snapshot = _history;
        lock (_history)
        {
            _historyWrite = _historyWrite.ContinueWith(_ =>
            {
                try { snapshot.Save(path); } catch (Exception) { }
            }, TaskScheduler.Default);
        }
    }

    /// <summary>Geçmişi temizler (liste ve dosya).</summary>
    public void ClearHistory()
    {
        _history.Clear();
        _historyView = [];
        SaveHistoryInBackground();
        Refresh();
    }

    void OnTranslationFinished(bool ok, UnavailableReason? reason)
    {
        DgTranslationFinished(ok);
        if (!ok && reason is { } r)
            _translatorStatus = r switch
            {
                UnavailableReason.Unsupported => TranslatorStatus.Unsupported,
                UnavailableReason.DownloadRequired => TranslatorStatus.DownloadRequired,
                UnavailableReason.EngineFailed => TranslatorStatus.EngineFailed,
                _ => _translatorStatus,
            };
        else if (ok) RefreshTranslatorStatus();
    }

    // ---- Çevirmen durumu (§11.4) ----

    void RefreshTranslatorStatus()
    {
        var src = TargetLanguages.Code(_settings.SourceLanguage);
        var tgt = TargetLanguages.Code(_settings.TargetLanguage);
        var model = _services.FreeModel;
        _translatorStatus = OnlineEnabledNow ? TranslatorStatus.Ready
            : !model.Supports(src, tgt) ? TranslatorStatus.Unsupported
            : !model.IsInstalled(src, tgt) ? TranslatorStatus.DownloadRequired
            : model.EngineFailed || _freeCreateFailed ? TranslatorStatus.EngineFailed
            : TranslatorStatus.Ready;
    }

    void OnFreeEngineFailed()
    {
        RefreshTranslatorStatus();
    }

    bool OnlineEnabledNow => TranslationChain.OnlineEnabled(_settings, name => _secrets.Get<string>(name));

    // ---- Paket araması ve havuza öneri (§13.2) ----

    LookupState CurrentLookup => new(_settings.SourceLanguage, _settings.TargetLanguage, _settings.GamePacks,
        _settings.SharePool, _services.Pool?.IsPoolFirst(PoolFirstGame) == true);

    sealed class LookupAdapter(NinoController owner) : ISubtitlePackLookup
    {
        readonly SubtitleLookup _lookup = new(owner._services.Packs, owner._services.Pool);

        public PackMatch? Find(string text)
        {
            var state = owner.CurrentLookup;
            if (!state.PacksEnabled && !state.PoolFirst && !state.SharePool) return null;
            if (_lookup.Find(text, state) is not { } found) return null;
            string? packId = null, packName = null;
            if (found.FromPack && owner._services.Packs?.TakeDistinctiveHit() is { } hit)
            {
                packId = hit.Id;
                packName = hit.Title;
            }
            return new PackMatch(found.Text, packId, packName ?? owner._services.Packs?.ScopeTitle);
        }
    }

    void SuggestToPool(string line)
    {
        if (TargetLanguages.Code(_settings.SourceLanguage) != "en") return;
        var lookup = new SubtitleLookup(_services.Packs, _services.Pool);
        if (!lookup.ShouldSuggest(line, CurrentLookup)) return;
        try { _services.LinePool?.Add(line, _services.Packs?.ScopeGameId ?? StableGame); } catch (Exception) { }
        if (_services.Pool is not { } pool) return;
        if (!(PoolTranslationsEnabled || CurrentLookup.PoolFirst)) return;
        var context = _poolContext.Add(line);
        var pipeline = _pipeline;
        var game = PoolFirstGame;
        Background(async () =>
        {
            var better = await pool.AskAsync(line, context, game).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(better)) return;
            await OnUi();
            if (pipeline == _pipeline) pipeline?.OnBetterTranslation(line, better);
        });
    }

    // ---- Ek bölgeler (§12.2) ----

    void UpdateExtraAreas()
    {
        var areas = WatchedArea.FromSettings(_settings);
        var want = _pipeline is not null && !_paused && areas.Count > 0;
        if (!want)
        {
            var old = _extra;
            _extra = null;
            if (old is not null)
            {
                try { old.Reset(); } catch (Exception) { }
                _server.Send(new RegionsCleared());
            }
            return;
        }
        if (_extra is null)
        {
            var reader = _services.Readers.Create(_settings.SourceLanguage);
            if (reader is null) return;
            var chain = BuildChain();
            _extra = new ExtraAreaTracker(reader, chain.Translator, new ServerOutput(_server), _msClock,
                PacksEnabled ? new LookupAdapter(this) : null, line => _logs.Subtitle(line));
        }
        _extra.Areas = areas;
    }

    // ---- Telefon ve harita (§12.3) ----

    bool PhoneGame
    {
        get
        {
            var pool = _services.Pool;
            if (pool is null) return false;
            return Nino.Core.Phone.PhoneGame.IsPhoneGame(_paused, TargetLanguages.Code(_settings.SourceLanguage),
                pool.IsPoolFirst(PoolFirstGame), _game.Source,
                Nino.Core.Phone.PhoneGame.PoolFirstAllows(pool.PoolFirst, _settings.TargetLanguage));
        }
    }

    void SetUpPhoneReaders()
    {
        _phoneQueued = false;
        if (_overlay is not { Installed: false } overlay || _phoneFailed || _pipeline is null) return;
        var lang = _settings.SourceLanguage;
        var phoneOcr = _services.Readers.CreateSinglePass(lang);
        var mapOcr = phoneOcr is null ? null : _services.Readers.CreateSinglePass(lang);
        if (phoneOcr is null || mapOcr is null)
        {
            _phoneFailed = true;
            return;
        }
        var chain = _chain ?? BuildChain();
        var target = TargetLanguages.Code(_settings.TargetLanguage);
        var fallback = new ScriptGuardTranslator(new PerCallFallback(this, chain), target);
        var pool = _services.Pool;
        var gen = _pipelineGen;
        var services = new OverlayServices
        {
            Clock = _msClock,
            Pool = pool is null ? null : AskPoolManyAsync,
            Fallback = fallback,
            Ready = pool is null ? null : text => pool.Lookup(text),
            Glossary = target == "tr",
            TargetLanguage = target,
            Gta6Seen = () => Post(() => { if (gen == _pipelineGen) OnGta6Seen(); }),
            Log = line => _logs.Subtitle(line),
        };
        try { overlay.Install(services, phoneOcr, mapOcr); }
        catch (Exception e)
        {
            _logs.Error("Telefon okuyucusu kurulamadı", e);
            _phoneFailed = true;
        }
    }

    /// <summary>Yedek çevirmen her çeviride seçilir: havuz öncelikli oyunda ücretsiz yerel, değilse kullanıcının motoru.</summary>
    sealed class PerCallFallback(NinoController owner, TranslatorChain chain) : ITranslator
    {
        ITranslator Now => owner._services.Pool?.IsPoolFirst(owner.PoolFirstGame) == true ? chain.Free : chain.Base;
        public string EngineName => Now.EngineName;
        public bool SupportsPretranslation => false;
        public bool SupportsBatch => Now.SupportsBatch;
        public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
            Now.TranslateAsync(text, cancellationToken);
        public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
            Now.TranslateBatchAsync(texts, cancellationToken);
    }

    async Task<IReadOnlyList<string?>> AskPoolManyAsync(IReadOnlyList<string> lines, IReadOnlyList<string> context,
        CancellationToken ct)
    {
        var pool = _services.Pool;
        var game = PoolFirstGame;
        if (pool is null || !(_settings.SharePool || pool.IsPoolFirst(game))) return new string?[lines.Count];
        return await pool.AskManyAsync(lines, context, game, null, ct).ConfigureAwait(false);
    }

    void OnGta6Seen()
    {
        if (!Nino.Core.Phone.PhoneGame.NoteGta6(_game, _translating, line => _logs.Subtitle(line))) return;
        _gamePickerOpen = false;
        PublishGame();
        RestartPoolSync(force: true);
    }

    // ---- Çıkış uyarlayıcısı ----

    internal static Nino.Core.Link.ScreenItem ToLink(ReadingScreenItem i) => new(i.Box, i.Text)
    {
        Line = i.LineHeight,
        Plain = i.Plain,
        Italic = i.Italic,
        Fill = i.Fill,
        Ink = i.Ink,
        Angle = i.Angle,
        Alpha = i.Alpha,
        Side = i.Side,
        Backdrop = i.Backdrop,
        Card = i.Card,
    };

    /// <summary>
    /// Altyazının TV'ye giden ek alanları (konuşan adı, konum, buzlu zemin): ayarı ve son kareyi o an okur. Buzlu zemin
    /// JPEG'i okuyucu fabrikasının kodlayıcısıyla yapılır (yoksa gönderilmez).
    /// </summary>
    TvShowBuilder NewTvShows() => new(new TvShowOptions
    {
        ShowSpeakerNames = () => _settings.ShowSpeakerNames,
        Position = () => TvPosition.For(_settings.AreaPreset, _settings.Region),
        LastFrame = () => Volatile.Read(ref _lastFrame),
        EncodeJpeg = (frame, quality) => _services.Readers.SmallJpeg(frame, frame.Width, quality),
    });

    /// <summary>Okuma hattının çıkışını altyazı sunucusuna bağlar.</summary>
    sealed class ServerOutput(ISubtitleServer server, TvShowBuilder? shows = null) : ISubtitleOutput
    {
        public void ShowSubtitle(SubtitleShow show) =>
            server.Send(shows?.Build(show)
                ?? new SubtitleShown(show.Text, show.DurationMs, show.Box, show.Paragraphs, show.Replace, show.Source));

        public void ClearSubtitle() => server.Send(new SubtitleCleared());

        public void ShowScreen(IReadOnlyList<ReadingScreenItem> items, int durationMs, bool overlay) =>
            server.Send(new ScreenShown(items.Select(ToLink).ToList(), durationMs, overlay));

        public void ClearScreen() => server.Send(new ScreenCleared());

        public void ShowRegion(string id, string text, Box? box, double? lineHeight) =>
            server.Send(new RegionShown(id, text, box, lineHeight));

        public void ClearRegions() => server.Send(new RegionsCleared());
    }

    static bool Same(string? a, string? b) => GameIds.Same(a, b);
}
