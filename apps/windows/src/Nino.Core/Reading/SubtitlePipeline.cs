// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Logging;
using Nino.Core.Translation;

namespace Nino.Core.Reading;

/// <summary>Altyazı hattının ayarları (hat kurulurken bir kez verilir).</summary>
public sealed class SubtitlePipelineOptions
{
    /// <summary>Okuma planı (varsayılanı "her zaman": her kare okunur).</summary>
    public ReadPlan Plan { get; init; } = ReadPlan.Always();

    /// <summary>Ekranda konuşan adı gösterilsin mi (<c>ShowSpeakerNames</c>).</summary>
    public bool ShowSpeakerNames { get; init; } = true; // ayarın varsayılanı

    /// <summary>Bozuk okuma bekletmesi (ms; 0–2000'e sıkıştırılır).</summary>
    public int MisreadWaitMs { get; init; } = 800;

    /// <summary>Yarım görünen temiz satır bekletmesi (ms; 0–2000'e sıkıştırılır).</summary>
    public int PartialWaitMs { get; init; } = 300;

    /// <summary>Paket araması yokken de bekletilsin mi ("paketsiz bekletme"; Windows'ta yazım denetimi varken açık).</summary>
    public bool HoldWithoutPack { get; init; }

    /// <summary>Paket araması (yoksa null).</summary>
    public ISubtitlePackLookup? Pack { get; init; }

    /// <summary>Ek "okuma bozuk mu" ölçüsü (Windows yazım denetimi); OCR iziyle "ya da" ile birleşir.</summary>
    public Func<string, bool>? ExtraMisread { get; init; }

    /// <summary>Okuma puanı (Windows yazım denetimi puanı); yoksa gürültü puanı.</summary>
    public Func<string, int>? ReadingScore { get; init; }

    /// <summary>Telefon/harita kancaları (yoksa null).</summary>
    public IPhoneLineHooks? Phone { get; init; }

    /// <summary>Görev şeridi çizgisi (karede y; Windows uygulaması vermez).</summary>
    public double? QuestLine { get; init; }

    /// <summary>Altyazı günlüğü (tek satırlık kayıtlar; kilit altında çağrılır, hızlı olmalı).</summary>
    public Action<string>? Log { get; init; }
}

/// <summary>TV'de gösterilen (kaynak, çeviri) çifti ve kökeni ("çift gösterildi" olayı).</summary>
public sealed record ShownPair(string Source, string Translation, ShownOrigin Origin, PackMatch? Pack);

/// <summary>
/// Altyazı okuma hattı: kareden altyazı satırını okur, süzer, sabitler, çeviriye gönderir (bekletme, sıra, geç sonuç,
/// paket) ve TV'ye çıkarır. Bir kareyi işlerken çağıranı bekletmez: okuma arka planda yapılır, çeviri beklenmez.
/// Olay işleyicileri hiçbir zaman hattın kilidi altında çağrılmaz.
/// </summary>
public sealed class SubtitlePipeline
{
    /// <summary>Geç sonuç sınırı (satır kalktıktan sonra).</summary>
    public const long LateLimitMs = 2500;

    /// <summary>Sırada bekleyebilecek satır.</summary>
    public const int QueueLimit = 2;

    /// <summary>Az önce çevrilenin yeniden okuması sayılma penceresi.</summary>
    public const long RepeatWindowMs = 4000;

    /// <summary>Hatırlanan çift sayısı.</summary>
    public const int RememberedPairs = 8;

    /// <summary>Ekranda duran satırın gösterim süresi.</summary>
    public const int OnScreenDurationMs = 15_000;

    /// <summary>Telefonun "az önce görüldü" sayılma süresi.</summary>
    public const long RecentPhoneMs = 5000;

    /// <summary>Kalkmış satırın geç gelen çevirisinin gösterim süresi.</summary>
    public static int RemovedDurationMs(string text) => (int)Math.Min(8000, 2000 + (long)text.Length * 60);

    sealed record FrameInfo(long ArrivedAt, long? OcrMs, double? Confidence);

    sealed class Request(long id, string source, Box? box, long session, FrameInfo frame)
    {
        public long Id { get; } = id;
        public string Source { get; } = source;
        public Box? Box { get; } = box;
        public long Session { get; } = session;
        public SpeakerSplit Speaker { get; } = SpeakerName.Split(source);
        public FrameInfo Frame { get; } = frame;
        public long? RemovedAt { get; set; }
        public bool Extended { get; set; }
        public bool Released { get; set; }
        public CancellationTokenSource? Cancel { get; set; }
    }

    sealed record Held(string Source, Box? Box, long Start, long MaxWait, int Score, FrameInfo Frame);

    sealed record Sent(string Source, int Score, long At);

    sealed record Pair(long Id, string Source, string? Translation);

    readonly ITextReader _reader;
    readonly ITranslator _translator;
    readonly ISubtitleOutput _output;
    readonly IMsClock _clock;
    readonly SubtitlePipelineOptions _options;
    readonly Stabilizer _stabilizer;
    readonly StaleLineFilter _staleLines = new();
    readonly object _lock = new();
    readonly int _misreadWait;
    readonly int _partialWait;

    long _session;
    long _sessionStart;
    bool _firstFrameLogged;
    bool _firstTextLogged;
    string? _lastGiantNote;
    StabilizerNote? _lastStabilizerNote;
    OcrReading _lastReading = OcrReading.Empty;
    long? _lastOcrMs;
    FrameInfo? _frame;
    string? _lastPretranslate;
    Box? _recentPhone;
    long _recentPhoneAt;

    Held? _held;
    Sent? _lastSent;
    long? _lastClearAt;
    long _lastRequestedId;
    long _lastShownId;
    Request? _running;
    readonly List<Request> _queue = [];
    long? _onScreenId;
    readonly List<Pair> _pairs = [];
    Task _pump = Task.CompletedTask;
    bool _pumpActive;

    (string Source, string Translation)? _lastPair;
    Box? _lastBox;
    ShownOrigin? _lastOrigin;
    SubtitleMetrics? _lastMetrics;
    UnavailableReason? _lastError;
    int _packHits;

    /// <summary>Hattı kurar.</summary>
    public SubtitlePipeline(ITextReader reader, ITranslator translator, ISubtitleOutput output,
        IMsClock? clock = null, SubtitlePipelineOptions? options = null)
    {
        _reader = reader;
        _translator = translator;
        _output = output;
        _clock = clock ?? SystemMsClock.Instance;
        _options = options ?? new SubtitlePipelineOptions();
        _misreadWait = Math.Clamp(_options.MisreadWaitMs, 0, 2000);
        _partialWait = Math.Clamp(_options.PartialWaitMs, 0, 2000);
        _stabilizer = new Stabilizer(_clock) { FastPath = translator.SupportsPretranslation };
        _sessionStart = _clock.NowMs;
    }

    /// <summary>Ölçüm hazır (TV'ye yeni bir satır gitti).</summary>
    public event Action<SubtitleMetrics>? MetricsReady;

    /// <summary>Bir çift TV'de gösterildi (oyun tanıma, son kaynak/çeviri, geçmiş).</summary>
    public event Action<ShownPair>? PairShown;

    /// <summary>Çeviri sonucu: (başarılı mı, çevirmen kullanılamıyorsa nedeni; başka hatada null).</summary>
    public event Action<bool, UnavailableReason?>? TranslationFinished;

    /// <summary>Satır pakette yok (ortak havuza öneri için; paket araması verilmemişse de).</summary>
    public event Action<string>? NotInPack;

    /// <summary>Son gösterilen çift.</summary>
    public (string Source, string Translation)? LastPair { get { lock (_lock) return _lastPair; } }

    /// <summary>Son gösterilen altyazının kutusu.</summary>
    public Box? LastBox { get { lock (_lock) return _lastBox; } }

    /// <summary>Son gösterilenin kökeni.</summary>
    public ShownOrigin? LastOrigin { get { lock (_lock) return _lastOrigin; } }

    /// <summary>Son ölçüm.</summary>
    public SubtitleMetrics? LastMetrics { get { lock (_lock) return _lastMetrics; } }

    /// <summary>Son çevirmen hatası (durum); başarılı çeviride silinir.</summary>
    public UnavailableReason? LastError { get { lock (_lock) return _lastError; } }

    /// <summary>Hattın şimdiye dek paketten aldığı satırların adedi.</summary>
    public int PackHits { get { lock (_lock) return _packHits; } }

    /// <summary>Son okuma (ek bölge ve ekranı çevir için değil; ölçüm ve tanı için).</summary>
    public OcrReading LastReading { get { lock (_lock) return _lastReading; } }

    internal bool LockHeldByCurrentThread => Monitor.IsEntered(_lock);

    void Log(string line) => _options.Log?.Invoke(line);

    int Score(string text) => _options.ReadingScore?.Invoke(text) ?? OcrJunk.Score(text);

    bool IsMisread(string text) => OcrJunk.IsMisread(text) || (_options.ExtraMisread?.Invoke(text) ?? false);

    bool Gating => _options.Pack is not null || _options.HoldWithoutPack;

    long WaitFor(string source)
    {
        if (!Gating) return 0;
        if (IsMisread(source)) return _misreadWait;
        return TextCompare.LooksComplete(source) ? 0 : _partialWait;
    }

    PackMatch? FindPack(string text)
    {
        var pack = _options.Pack;
        if (pack is null) return null;
        if (_held is { } h && TextCompare.IsPackFragment(text, h.Source)
            && TextCompare.AllLinesCovered(text, h.Source, IsMisread) && Score(text) <= h.Score) return null;
        var hit = pack.Find(text);
        if (hit is not null) return hit;
        var split = SpeakerName.Split(text);
        return split.HasName ? pack.Find(split.Sentence) : null;
    }

    /// <summary>
    /// Bir kareyi işler (kare, altyazı bölgesinin karedeki kutusu, isteğe bağlı geliş anı). Okuma arka planda yapılır;
    /// dönen görev kare işlenince (çeviri beklenmeden) biter. Hata dışarı kaçmaz.
    /// </summary>
    public async Task ProcessFrameAsync(BgraFrame frame, Box area, long? arrivedAt = null)
    {
        var arrived = arrivedAt ?? _clock.NowMs;
        long session;
        lock (_lock)
        {
            session = _session;
            if (!_firstFrameLogged)
            {
                _firstFrameLogged = true;
                Log($"ilk kare geldi; oturum açılalı {_clock.NowMs - _sessionStart} ms oldu");
            }
        }
        var phone = _options.Phone;
        var searchPhone = SafeGet(() => phone?.SearchPhone ?? false);
        Box? recentPhone;
        lock (_lock) recentPhone = _recentPhone is { } p && _clock.NowMs - _recentPhoneAt <= RecentPhoneMs ? p : null;

        var work = await Task.Run(() => ReadAndFilter(frame, area, session, searchPhone, recentPhone)).ConfigureAwait(false);

        var deferred = new List<Action>();
        Request? toCancel = null;
        lock (_lock)
        {
            if (_session != session)
            {
                Log("sıfırlamadan önce başlamış okuma atıldı");
                return;
            }
            try { toCancel = AfterRead(work, arrived, deferred); }
            catch (Exception e) { Log("kare işlenirken hata: " + e.GetType().Name); }
        }
        foreach (var action in deferred)
        {
            try { action(); }
            catch (Exception e) { Log("olay işleyicisi hata verdi: " + e.GetType().Name); }
        }
        if (toCancel is not null) CancelRequest(toCancel);
    }

    static T SafeGet<T>(Func<T> get)
    {
        try { return get(); }
        catch { return default!; }
    }

    sealed record ReadWork(OcrReading Reading, byte[]? Signature, long? OcrMs, string? GiantNote, OcrReading? GiantBlock,
        Box Area);

    ReadWork ReadAndFilter(BgraFrame frame, Box area, long session, bool searchPhone, Box? recentPhone)
    {
        byte[]? signature = null;
        OcrReading reading;
        long? ocrMs = null;
        BgraFrame region;
        Box? maskBox = null;
        var phoneFound = false;
        try
        {
            region = frame.CropRegion(area);
            if (searchPhone && _options.Phone is { } hooks)
            {
                var found = SafeGet(() => hooks.LocatePhone(frame));
                phoneFound = found is not null;
                if (found is { } f)
                    lock (_lock)
                        if (_session == session)
                        {
                            _recentPhone = f;
                            _recentPhoneAt = _clock.NowMs;
                        }
                if ((found ?? recentPhone) is { } phoneBox)
                {
                    maskBox = phoneBox with { Bottom = Math.Max(phoneBox.Bottom, Math.Min(phoneBox.Bottom + 0.15, 0.84)) };
                    region = region.MaskBlack(maskBox.Value, area);
                }
            }
            signature = RegionSignature.Of(region);
            PlanDecision decision;
            lock (_lock) decision = _options.Plan.Next(signature);
            if (decision.Reuse)
            {
                lock (_lock)
                {
                    reading = _lastReading;
                    ocrMs = _lastOcrMs;
                }
            }
            else
            {
                var start = _clock.NowMs;
                reading = _reader.ReadLines(region, decision.Deep);
                ocrMs = _clock.NowMs - start;
                lock (_lock)
                {
                    if (_session == session)
                    {
                        _options.Plan.Record(reading.Text);
                        _lastReading = reading;
                        _lastOcrMs = ocrMs;
                    }
                }
            }
        }
        catch
        {
            return new ReadWork(OcrReading.Empty, signature, null, null, null, area);
        }

        try
        {
            if (_options.Phone is { } hooks && (searchPhone || maskBox is not null))
            {
                var r = reading;
                var context = new PhoneLineContext(r, region, area, maskBox, phoneFound);
                reading = SafeGet(() => hooks.FilterLines(context)) ?? r;
            }
            if (_options.QuestLine is { } quest) reading = LineLayout.RemoveBelowQuestLine(reading, area, quest);
            bool sameSession;
            lock (_lock) sameSession = _session == session;
            if (sameSession) reading = _staleLines.Apply(reading, _clock.NowMs);
            reading = LineLayout.RemoveGiantLines(reading, area, out var dropped);
            var giantNote = dropped.Count > 0 ? string.Join(" / ", dropped) : null;
            if (searchPhone) reading = LineLayout.KeepCentered(reading, area);
            reading = ButtonHints.Remove(reading);
            reading = Directions.Remove(reading);
            reading = OcrJunk.Clean(reading);
            reading = LineLayout.RemoveEdgeToEdge(reading);
            reading = LineLayout.MergeRows(reading);
            reading = LineLayout.SelectSubtitleBlock(reading, area);
            if (SafeGet(() => _options.Phone?.MapOpen ?? false)) reading = OcrReading.Empty;
            OcrReading? giantBlock = null;
            if (LineLayout.IsGiantBlock(reading, area))
            {
                giantBlock = reading;
                reading = OcrReading.Empty;
            }
            return new ReadWork(reading, signature, ocrMs, giantNote, giantBlock, area);
        }
        catch
        {
            return new ReadWork(OcrReading.Empty, signature, ocrMs, null, null, area);
        }
    }

    // Kilit altında: okumanın sonrası (§6 adım 13). Kilit dışında iptal edilecek isteği döndürür.
    Request? AfterRead(ReadWork work, long arrived, List<Action> deferred)
    {
        var now = _clock.NowMs;
        if (work.GiantNote is { } note && note != _lastGiantNote)
        {
            _lastGiantNote = note;
            Log($"dev yazı atlandı: {LogQuote.Of(note)}");
        }
        if (work.GiantBlock is { } block && block.Text != _lastGiantNote)
        {
            _lastGiantNote = block.Text;
            Log($"dev blok atlandı: {LogQuote.Of(block.Text)} ({block.Lines.Count} satır)");
        }
        var reading = work.Reading;
        var text = reading.Text;
        if (!_firstTextLogged && !reading.IsEmpty)
        {
            _firstTextLogged = true;
            Log($"ilk yazı okundu; oturum açılalı {now - _sessionStart} ms oldu: {LogQuote.Of(text)}");
        }
        _frame = new FrameInfo(arrived, work.OcrMs, reading.Confidence);

        var reaction = _stabilizer.Feed(text, work.Signature, reading.Box);
        if (_stabilizer.LastNote is { } sNote && sNote != _lastStabilizerNote)
        {
            _lastStabilizerNote = sNote;
            Log(sNote.Kind == StabilizerNoteKind.BadReread
                ? $"kötü yeniden okuma yok sayıldı: {LogQuote.Of(sNote.Reading)}"
                : $"çöp okuma kararlaşmadan ekrandan gitti, yollanmadı: {LogQuote.Of(sNote.Reading)}");
        }
        Box? box = reading.Box is { } rb ? LineLayout.CenterOnScreen(rb.PlaceIn(work.Area)) : null;

        if (reaction.Action == StabilizerAction.None && _translator.SupportsPretranslation)
        {
            var trimmed = text.Trim();
            if (trimmed.Length >= 6 && trimmed != _lastPretranslate)
            {
                _lastPretranslate = trimmed;
                var split = SpeakerName.Split(trimmed);
                var pre = split.HasName ? split.Sentence : trimmed;
                deferred.Add(() => _ = PretranslateQuietly(pre));
            }
        }

        Action? first = null;
        if (_held is not null) reaction = HeldBranches(reaction, text, box, now, deferred, ref first);

        switch (reaction.Action)
        {
            case StabilizerAction.Clear:
                _lastClearAt = now;
                OnScreenGone(now);
                _output.ClearSubtitle();
                Log("satır kalktı, ekran temizlendi");
                break;
            case StabilizerAction.Translate:
                TranslateOrHold(reaction.Text ?? text, box, null, now, deferred);
                break;
            case StabilizerAction.Restore:
                OnScreenGone(now);
                Restore(reaction.Text ?? text, box, now, deferred);
                break;
        }
        if (first is not null) deferred.Insert(0, first);
        return ReleaseCheck(now);
    }

    async Task PretranslateQuietly(string text)
    {
        try { await _translator.PretranslateAsync(text).ConfigureAwait(false); }
        catch { }
    }

    StabilizerReaction HeldBranches(StabilizerReaction reaction, string text, Box? box, long now, List<Action> deferred,
        ref Action? first)
    {
        var held = _held!;
        switch (reaction.Action)
        {
            case StabilizerAction.Translate:
            {
                var source = reaction.Text ?? text;
                var wait = Math.Max(held.MaxWait, WaitFor(source));
                if (FindPack(source) is not null)
                {
                    _held = null;
                    Log($"bekleyen atıldı, yerine paket satırı: {LogQuote.Of(held.Source)}");
                    return reaction;
                }
                if (TextCompare.AddsMeaningMarker(source, held.Source)
                    && TextKey.Similar(TextKey.Of(source), TextKey.Of(held.Source)))
                {
                    var merged = TextCompare.KeepMissingLines(source, held.Source, IsMisread);
                    _held = held with { Source = merged, Box = box ?? held.Box, MaxWait = wait, Score = Score(source) };
                    OnScreenGone(now);
                    if (now - held.Start >= wait) ReleaseHeld(now, deferred);
                    return StabilizerReaction.Nothing;
                }
                if ((TextCompare.IsRereadOf(source, held.Source, IsMisread)
                        || TextCompare.IsRereadOf(held.Source, source, IsMisread)) && now - held.Start < wait)
                {
                    if (Score(source) > held.Score)
                    {
                        var merged = TextCompare.KeepMissingLines(source, held.Source, IsMisread);
                        _held = held with { Source = merged, Box = box ?? held.Box, MaxWait = wait, Score = Score(merged) };
                    }
                    OnScreenGone(now);
                    return StabilizerReaction.Nothing;
                }
                if (IsMisread(held.Source))
                {
                    _held = null;
                    Log($"bozuk bekleyen atıldı, başka satır geldi: {LogQuote.Of(held.Source)}");
                    return reaction;
                }
                if (IsMisread(source) && now - held.Start < held.MaxWait) return StabilizerReaction.Nothing;
                _held = null;
                first = EnqueueHeldFirst(held, now, deferred);
                return reaction;
            }
            case StabilizerAction.Clear:
            case StabilizerAction.Restore:
                _held = null;
                if (!IsMisread(held.Source)) first = EnqueueHeldFirst(held, now, deferred);
                else Log($"bozuk bekleyen atıldı, beklerken kalktı: {LogQuote.Of(held.Source)}");
                return reaction;
            default:
            {
                var trimmed = text.Trim();
                if (trimmed.Length >= 3 && FindPack(trimmed) is { } pack)
                {
                    _held = null;
                    var request = NewRequest(trimmed, box ?? held.Box, held.Frame);
                    _onScreenId = request.Id;
                    ShowFromPack(request, pack, deferred);
                    return reaction;
                }
                if (trimmed.Length >= 3 && TextCompare.Related(trimmed, held.Source) && Score(trimmed) > held.Score)
                {
                    var merged = TextCompare.KeepMissingLines(trimmed, held.Source, IsMisread);
                    _held = held with { Source = merged, Box = box ?? held.Box, Score = Score(merged) };
                }
                if (_held is { } h && now - h.Start >= h.MaxWait) ReleaseHeld(now, deferred);
                return reaction;
            }
        }
    }

    // "Önce bunu çevir": bekletilen temiz okuma, bu karenin tepkisinden önce sıraya girer.
    Action? EnqueueHeldFirst(Held held, long now, List<Action> deferred)
    {
        var mine = new List<Action>();
        Enqueue(held.Source, held.Box, held.Frame, now, mine, null);
        return mine.Count == 0 ? null : () => { foreach (var a in mine) a(); };
    }

    void ReleaseHeld(long now, List<Action> deferred)
    {
        var held = _held!;
        _held = null;
        Enqueue(held.Source, held.Box, held.Frame, now, deferred, null);
    }

    void OnScreenGone(long now)
    {
        if (_onScreenId is not { } id) return;
        if (_running is { } r && r.Id == id) r.RemovedAt ??= now;
        foreach (var q in _queue)
            if (q.Id == id) q.RemovedAt ??= now;
        _onScreenId = null;
    }

    void TranslateOrHold(string source, Box? box, FrameInfo? frame, long now, List<Action> deferred)
    {
        if (QueuedFullReadReturned(source, now)) return;
        if (!Gating)
        {
            OnScreenGone(now);
            Enqueue(source, box, frame, now, deferred, null);
            return;
        }
        var pack = FindPack(source);
        if (_lastSent is { } last
            && (pack is null || ((_lastClearAt is not { } clear || last.At > clear) && TextCompare.IsPackFragment(source, last.Source)))
            && now - last.At < RepeatWindowMs
            && TextCompare.AllLinesCovered(source, last.Source, IsMisread)
            && Score(source) <= last.Score)
        {
            _lastSent = last with { At = now };
            Log($"yeniden okuma yok sayıldı: {LogQuote.Of(source)}");
            return;
        }
        OnScreenGone(now);
        if (pack is not null)
        {
            Enqueue(source, box, frame, now, deferred, pack);
            return;
        }
        var wait = WaitFor(source);
        if (wait <= 0)
        {
            Enqueue(source, box, frame, now, deferred, null);
            return;
        }
        _held = new Held(source, box, now, wait, Score(source), frame ?? _frame ?? new FrameInfo(now, null, null));
        Log($"bekletiliyor (en çok {wait} ms): {LogQuote.Of(source)}");
    }

    Request NewRequest(string source, Box? box, FrameInfo? frame)
    {
        var id = ++_lastRequestedId;
        return new Request(id, source, box, _session, frame ?? _frame ?? new FrameInfo(_clock.NowMs, null, null));
    }

    void Enqueue(string source, Box? box, FrameInfo? frame, long now, List<Action> deferred, PackMatch? knownPack)
    {
        var request = NewRequest(source, box, frame);
        _onScreenId = request.Id;
        _lastSent = new Sent(source, Score(source), now);
        if ((knownPack ?? FindPack(source)) is { } pack)
        {
            ShowFromPack(request, pack, deferred);
            return;
        }
        if (_running is null)
        {
            Log($"#{request.Id} {LogQuote.Of(source)} çeviriye gitti");
            StartRunning(request);
        }
        else
        {
            var running = _running;
            Log($"#{request.Id} {LogQuote.Of(source)} sıraya girdi (süren #{running.Id})");
            for (var i = _queue.Count - 1; i >= 0; i--)
                if (TextCompare.ReplacesQueued(source, _queue[i].Source))
                {
                    Log($"#{_queue[i].Id} atıldı, yerini düzelmiş okuma #{request.Id} aldı");
                    _queue.RemoveAt(i);
                }
            _queue.Add(request);
            while (_queue.Count > QueueLimit)
            {
                Log($"#{_queue[0].Id} atıldı, sıra dolu");
                _queue.RemoveAt(0);
            }
            if (!running.Extended && !running.Released && running.Session == _session
                && TextCompare.IsExtension(source, running.Source))
            {
                Log($"#{running.Id} bırakıldı, uzamış okuma #{request.Id} geldi");
                running.Extended = true;
                deferred.Add(() => CancelRequest(running));
            }
        }
        deferred.Add(() => NotInPack?.Invoke(source));
    }

    void StartRunning(Request request)
    {
        _running = request;
        request.Cancel = new CancellationTokenSource();
        if (_pumpActive) return;
        _pumpActive = true;
        _pump = Task.Run(PumpAsync);
    }

    static void CancelRequest(Request request)
    {
        lock (request)
        {
            try { request.Cancel?.Cancel(); }
            catch (ObjectDisposedException) { }
        }
    }

    async Task PumpAsync()
    {
        while (true)
        {
            Request? request;
            lock (_lock)
            {
                request = _running;
                if (request is null)
                {
                    _pumpActive = false;
                    return;
                }
            }
            CancellationToken token;
            lock (request) token = request.Cancel?.Token ?? CancellationToken.None;
            try { await TranslateRequestAsync(request, token).ConfigureAwait(false); }
            catch { }
            lock (request)
            {
                request.Cancel?.Dispose();
                request.Cancel = null;
            }
            lock (_lock)
            {
                var now = _clock.NowMs;
                for (var i = _queue.Count - 1; i >= 0; i--)
                {
                    var q = _queue[i];
                    if (q.Session != _session)
                    {
                        Log($"#{q.Id} atıldı, oturum bitti");
                        _queue.RemoveAt(i);
                    }
                    else if (q.RemovedAt is { } removed && now - removed > LateLimitMs)
                    {
                        Log($"#{q.Id} atıldı, çevrilmeden kalktı ({now - removed} ms önce)");
                        _queue.RemoveAt(i);
                    }
                }
                if (_queue.Count == 0)
                {
                    _running = null;
                    _pumpActive = false;
                    return;
                }
                var next = _queue[0];
                _queue.RemoveAt(0);
                _running = next;
                next.Cancel = new CancellationTokenSource();
            }
        }
    }

    /// <summary>Süren ve sıradaki bütün çeviriler bitene kadar bekler.</summary>
    public async Task WaitForTranslationsAsync(CancellationToken cancellation = default)
    {
        while (true)
        {
            Task pump;
            lock (_lock)
            {
                pump = _pump;
                if (!_pumpActive && pump.IsCompleted) return;
            }
            await pump.WaitAsync(cancellation).ConfigureAwait(false);
        }
    }

    bool Stale(Request request) => request.Session != _session || request.Extended || request.Released;

    async Task TranslateRequestAsync(Request request, CancellationToken token)
    {
        var toTranslator = request.Speaker.HasName ? request.Speaker.Sentence : request.Source;
        var start = _clock.NowMs;
        TranslationResult result;
        string origin;
        try
        {
            using var probe = TranslationProbe.Begin();
            result = await _translator.TranslateAsync(toTranslator, token).ConfigureAwait(false);
            origin = probe.Probe.Label();
        }
        catch (Exception e)
        {
            UnavailableReason? status;
            lock (_lock)
            {
                if (Stale(request)) return;
                var onScreen = _onScreenId == request.Id;
                status = (e as TranslatorUnavailableException)?.Reason;
                Log($"#{request.Id} hata ({_clock.NowMs - start} ms): {status?.ToString() ?? e.GetType().Name}"
                    + (onScreen ? "; ekranda kaldıkça yeniden denenecek" : ""));
                _lastError = status;
                if (onScreen)
                {
                    _stabilizer.ForgetSent();
                    if (_lastSent?.Source == request.Source) _lastSent = null;
                }
            }
            Invoke(() => TranslationFinished?.Invoke(false, status));
            return;
        }
        lock (_lock)
        {
            if (request.Session != _session || request.Released)
            {
                Log($"#{request.Id} {origin} {_clock.NowMs - start} ms: atıldı ("
                    + (request.Released ? "bırakıldı" : "oturum bitti") + ")");
                return;
            }
            _lastError = null;
        }
        Invoke(() => TranslationFinished?.Invoke(true, null));

        SubtitleMetrics metrics;
        ShownPair shown;
        lock (_lock)
        {
            var end = _clock.NowMs;
            if (request.Session != _session || request.Released)
            {
                Log($"#{request.Id} {origin} {end - start} ms: atıldı ("
                    + (request.Released ? "bırakıldı" : "oturum bitti") + ")");
                return;
            }
            var sentence = result.Text;
            var translation = SpeakerName.Present(result.Text, request.Source, _options.ShowSpeakerNames);
            if (FindPack(request.Source) is { } late)
            {
                translation = SpeakerName.Present(late.Translation, request.Source, _options.ShowSpeakerNames);
                sentence = late.Translation;
            }
            var send = Stabilizer.ShouldSend(toTranslator, sentence);
            Remember(request.Id, request.Source, send ? translation : null);
            if (request.Id <= _lastShownId || !send || request.Extended)
            {
                var why = !send ? "zaten hedef dilde" : request.Extended ? "uzamış okuma geldi" : $"daha yeni satır #{_lastShownId} gösterildi";
                Log($"#{request.Id} {origin} {end - start} ms: atıldı ({why})");
                return;
            }
            var onScreen = _onScreenId == request.Id;
            if (!onScreen && request.RemovedAt is { } removed && end - removed > LateLimitMs)
            {
                Log($"#{request.Id} {origin} {end - start} ms: geç kaldı, satır {end - removed} ms önce kalkmıştı; gösterilmedi");
                return;
            }
            Log($"#{request.Id} {origin} {end - start} ms: gösterildi" + (onScreen ? "" : " (satır kalkmıştı)"));
            _lastShownId = request.Id;
            var replace = CorrectsShown(request.Source);
            _output.ShowSubtitle(new SubtitleShow(translation, onScreen ? OnScreenDurationMs : RemovedDurationMs(translation),
                request.Box, Replace: replace));
            _lastPair = (request.Source, translation);
            _lastBox = request.Box;
            _lastOrigin = ShownOrigin.Engine;
            metrics = SubtitleMetrics.Build(request.Frame.ArrivedAt, request.Frame.OcrMs, start, end, end,
                request.Frame.Confidence, ShownOrigin.Engine);
            _lastMetrics = metrics;
            shown = new ShownPair(request.Source, translation, ShownOrigin.Engine, null);
        }
        Invoke(() => MetricsReady?.Invoke(metrics));
        Invoke(() => PairShown?.Invoke(shown));
    }

    void Invoke(Action action)
    {
        try { action(); }
        catch (Exception e) { Log("olay işleyicisi hata verdi: " + e.GetType().Name); }
    }

    bool CorrectsShown(string source) => _lastPair is { } p && TextCompare.IsCorrection(source, p.Source);

    void Remember(long id, string source, string? translation)
    {
        _pairs.RemoveAll(p => p.Source == source);
        _pairs.Add(new Pair(id, source, translation));
        while (_pairs.Count > RememberedPairs) _pairs.RemoveAt(0);
    }

    static bool HasTurkishLetter(string text) => text.IndexOfAny("ğışçöüĞİŞÇÖÜ".ToCharArray()) >= 0;

    void ShowFromPack(Request request, PackMatch pack, List<Action> deferred)
    {
        foreach (var q in _queue) Log($"#{q.Id} atıldı, sonraki satır #{request.Id} paketten");
        _queue.Clear();
        _packHits++;
        var translation = SpeakerName.Present(pack.Translation, request.Source, _options.ShowSpeakerNames);
        var show = !TextKey.Similar(TextKey.Of(request.Source), TextKey.Of(translation), Stabilizer.SameLanguageThreshold)
            || !HasTurkishLetter(request.Source);
        Remember(request.Id, request.Source, show ? translation : null);
        var originText = pack.PackName is { Length: > 0 } name ? "paket " + name : "paket";
        if (!show)
        {
            Log($"#{request.Id} {LogQuote.Of(request.Source)} {originText}: zaten hedef dilde, gösterilmedi");
            return;
        }
        Log($"#{request.Id} {LogQuote.Of(request.Source)} {originText}");
        _lastShownId = request.Id;
        var replace = CorrectsShown(request.Source);
        _output.ShowSubtitle(new SubtitleShow(translation, OnScreenDurationMs, request.Box, Replace: replace));
        _lastPair = (request.Source, translation);
        _lastBox = request.Box;
        _lastOrigin = ShownOrigin.Pack;
        var metrics = SubtitleMetrics.Build(request.Frame.ArrivedAt, request.Frame.OcrMs, null, null, _clock.NowMs,
            request.Frame.Confidence, ShownOrigin.Pack);
        _lastMetrics = metrics;
        var shown = new ShownPair(request.Source, translation, ShownOrigin.Pack, pack);
        deferred.Add(() => MetricsReady?.Invoke(metrics));
        deferred.Add(() => PairShown?.Invoke(shown));
    }

    void Restore(string source, Box? box, long now, List<Action> deferred)
    {
        if (QueuedFullReadReturned(source, now)) return;
        if (_lastSent is { } prev && (TextCompare.Related(source, prev.Source)
                || TextCompare.AllLinesCovered(source, prev.Source, IsMisread)))
        {
            var score = Score(source);
            _lastSent = score > prev.Score ? new Sent(source, score, now) : prev with { At = now };
            if (Gating && _pairs.LastOrDefault(p => p.Source == prev.Source) is { } full && prev.Source != source
                && TextCompare.AllLinesCovered(source, prev.Source, IsMisread) && score < prev.Score)
            {
                _onScreenId = full.Id;
                Log($"#{full.Id} geri geldi, yarım okumasıyla: {LogQuote.Of(source)}");
                if (full.Translation is { } t)
                {
                    _output.ShowSubtitle(new SubtitleShow(t, OnScreenDurationMs, box, Replace: true));
                    _lastPair = (full.Source, t);
                    _lastBox = box;
                }
                return;
            }
        }
        if (_pairs.LastOrDefault(p => p.Source == source) is { } pair)
        {
            _onScreenId = pair.Id;
            Log($"#{pair.Id} geri geldi: {LogQuote.Of(source)}");
            if (pair.Translation is not { } translation) return;
            var replace = CorrectsShown(source);
            _output.ShowSubtitle(new SubtitleShow(translation, OnScreenDurationMs, box, Replace: replace));
            _lastPair = (source, translation);
            _lastBox = box;
            return;
        }
        foreach (var r in _running is null ? _queue : _queue.Prepend(_running))
            if (r.Source == source && r.Session == _session && !r.Extended && !r.Released)
            {
                r.RemovedAt = null;
                _onScreenId = r.Id;
                return;
            }
        TranslateOrHold(source, box, null, now, deferred);
    }

    bool QueuedFullReadReturned(string source, long now)
    {
        var index = _queue.FindLastIndex(q => q.Source == source);
        if (index < 0) return false;
        var full = _queue[index];
        if (full.RemovedAt is not { } removed || (_lastClearAt is { } clear && removed <= clear)) return false;
        for (var i = _queue.Count - 1; i > index; i--)
            if (TextCompare.IsExtension(source, _queue[i].Source))
            {
                Log($"#{_queue[i].Id} atıldı, tam okuma #{full.Id} geri geldi");
                _queue.RemoveAt(i);
            }
        OnScreenGone(now);
        full.RemovedAt = null;
        _onScreenId = full.Id;
        _lastSent = new Sent(source, Score(source), now);
        return true;
    }

    // Gösterilemeyecek süren çevirinin bırakılması (kilit altında); iptal edilecek isteği döndürür.
    Request? ReleaseCheck(long now)
    {
        if (_running is not { } r || r.Session != _session || r.Extended || r.Released || r.Cancel is null) return null;
        var passed = r.Id < _lastShownId;
        var expired = r.Id > _lastShownId && _onScreenId != r.Id && r.RemovedAt is { } removed && now - removed > LateLimitMs;
        if (!passed && !expired) return null;
        if (!passed && !_queue.Any(q => q.Session == _session && !q.Extended && !q.Released
                && !(q.RemovedAt is { } qr && now - qr > LateLimitMs))) return null;
        r.Released = true;
        if (_lastSent?.Source == r.Source) _lastSent = null;
        Log($"#{r.Id} bırakıldı: " + (passed ? "daha yeni satır gösterildi" : "süresi doldu ve yeni satır bekliyor"));
        return r;
    }

    /// <summary>
    /// Sunucunun çeviri havuzundan sonradan gelen daha iyi çeviri. Satır hâlâ ekrandaysa TV'de yerine konur; değilse
    /// yalnız hatırlanır (geri gelirse bu kullanılır).
    /// </summary>
    public void OnBetterTranslation(string source, string translation)
    {
        ShownPair? shown = null;
        lock (_lock)
        {
            if (string.IsNullOrWhiteSpace(translation)) return;
            var index = _pairs.FindLastIndex(p => p.Source == source);
            if (index < 0 || _pairs[index].Translation is null) return;
            var pair = _pairs[index];
            var presented = SpeakerName.Present(translation, source, _options.ShowSpeakerNames);
            if (string.Equals(presented, pair.Translation, StringComparison.Ordinal)) return;
            _pairs[index] = pair with { Translation = presented };
            if (_onScreenId != pair.Id || _lastShownId != pair.Id || _lastOrigin == ShownOrigin.Pack
                || _lastPair?.Source != source) return;
            Log($"#{pair.Id} havuzdan daha iyi çeviri yerine kondu");
            _output.ShowSubtitle(new SubtitleShow(presented, OnScreenDurationMs, _lastBox, Replace: true));
            _lastPair = (source, presented);
            _lastOrigin = ShownOrigin.Pool;
            shown = new ShownPair(source, presented, ShownOrigin.Pool, null);
        }
        if (shown is not null) Invoke(() => PairShown?.Invoke(shown));
    }

    /// <summary>
    /// Hattı sıfırlar (okuma durdu, hat yeniden kuruldu). Sıfırlamadan sonra biten eski okuma ve çeviriler hiçbir şey
    /// göstermez.
    /// </summary>
    public void Reset()
    {
        Request? running;
        lock (_lock)
        {
            Log($"hat sıfırlandı; bu hatta paketten {_packHits} satır geldi");
            _sessionStart = _clock.NowMs;
            _firstFrameLogged = false;
            _firstTextLogged = false;
            _lastStabilizerNote = null;
            _lastGiantNote = null;
            _session++;
            _onScreenId = null;
            _queue.Clear();
            _held = null;
            _lastSent = null;
            _lastClearAt = null;
            running = _running;
            _pairs.Clear();
            _lastReading = OcrReading.Empty;
            _lastOcrMs = null;
            _frame = null;
            _recentPhone = null;
            _staleLines.Reset();
            _options.Plan.Reset();
            if (_stabilizer.Reset().Action == StabilizerAction.Clear) _output.ClearSubtitle();
        }
        if (running is not null) CancelRequest(running);
    }
}
