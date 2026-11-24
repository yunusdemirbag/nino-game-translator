// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// GTA 6'nın köşe okuyucusu: 2 sn'de bir karenin tamamını kendi tanıyıcısıyla okur; sağ alttaki mesaj/uygulama
/// bildirimi kartını (<c>Donnie</c>, <c>BuckMe</c>), arama kartını, sol üst ipucu kutusunu ve sağ üst kısa bildirimi
/// çevirip yanlarına koyar. Harita yakında açıksa (<see cref="OverlayServices.Paused"/>) aranmaz, öğeler hemen kalkar;
/// telefon açıkken mesaj kartı kalkar ve telefonun içindeki yazı sayılmaz; menü ekranında üst köşeler kalkar. Çeviri
/// önce yerelde bilinenden (<see cref="Ready"/>), sonra havuz/çevirmenden gelir ve hafızada kalır. Gösterilen öğe harita
/// kartı gibi kalkar: art arda <see cref="MapReader.MissesToClear"/> okumada yoksa, ilk kaçırmadan beri
/// <see cref="MapReader.MissClearMs"/> geçtiyse ve oyunun kutusu görüntüde değiştiyse.
/// </summary>
public sealed class CornerReader
{
    /// <summary>İki tur arası en az süre.</summary>
    public const long ReadEveryMs = 2_000;

    /// <summary>Bu kadar dönmeyen okuma bırakılır, yenisi başlar.</summary>
    public const long StuckMs = 15_000;

    /// <summary>Menü ekranı görüldükten sonra açık sayılan süre (ikinci ıskaya dek).</summary>
    public const long MenuOpenMs = 5_000;

    /// <summary>Windows yazı tanımasının okuyabildiği en büyük kenar.</summary>
    public const int MaxSide = MapReader.MaxSide;

    /// <summary>Öğe türleri (TV listesindeki sıra).</summary>
    public enum Kind { Message, Call, TopLeft, TopRight }

    sealed class Held
    {
        public ScreenItem? Item;
        public Box Area;
        public byte[]? Signature;
        public int Misses;
        public long? FirstMissAt;
        public long Gen;
    }

    readonly OverlayServices _s;
    readonly IMsClock _clock;
    readonly object _lock = new();
    readonly Dictionary<Kind, Held> _held = new();
    readonly MessageCardWatcher _messages = new();
    readonly CallWatcher _calls = new();
    readonly StripWatcher _topLeft;
    readonly StripWatcher _notice;
    readonly Dictionary<GameCards.CallState, string> _callTexts = new();
    readonly HashSet<GameCards.CallState> _callAsking = [];
    long? _lastTour;
    int _busy;
    long _busySince;
    long _tourGen;
    long _session;
    long _menuSeenAt = long.MinValue / 2;
    int _menuMisses;

    /// <summary>Okuyucu.</summary>
    public CornerReader(OverlayServices services)
    {
        _s = services;
        _clock = services.Clock;
        Ready = services.Ready;
        Func<string, bool> isTarget = services.TargetLanguage == "tr" ? GameWords.HasTurkishLetters : _ => false;
        _topLeft = new StripWatcher(stable: true, isTarget);
        _notice = new StripWatcher(stable: false, isTarget);
        foreach (var k in Enum.GetValues<Kind>()) _held[k] = new Held();
    }

    /// <summary>Bilinen çeviri (güncellenebilir).</summary>
    public Func<string, string?>? Ready { get; set; }

    /// <summary>Son başlatılan arka plan okuması (testler bekler).</summary>
    public Task? Running { get; private set; }

    /// <summary>Son okumanın başlattığı çeviriler (testler bekler).</summary>
    public Task? Showing { get; private set; }

    /// <summary>Ekrandaki köşe öğeleri (kart, arama, sol üst, sağ üst sırasıyla).</summary>
    public IReadOnlyList<ScreenItem> Items
    {
        get
        {
            lock (_lock)
                return Enum.GetValues<Kind>().Select(k => _held[k].Item).OfType<ScreenItem>().ToArray();
        }
    }

    void Log(string line) => _s.Log?.Invoke(line);

    void Notify() => _s.Changed?.Invoke();

    /// <summary>Kare ver: 2 sn geçtiyse ve okuma sürmüyorsa arka planda okur; hemen döner.</summary>
    public void OfferFrame(BgraFrame frame)
    {
        var now = _clock.NowMs;
        lock (_lock)
        {
            if (_lastTour is { } t && now - t < ReadEveryMs) return;
            _lastTour = now;
        }
        if (_s.Paused?.Invoke() == true)
        {
            DropAll();
            return;
        }
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0)
        {
            var since = Interlocked.Read(ref _busySince);
            if (now - since < StuckMs) return;
            Log($"köşeler: okuma {now - since} ms'dir dönmedi; bırakıldı, yeniden okunuyor");
        }
        Interlocked.Exchange(ref _busySince, now);
        var gen = Interlocked.Increment(ref _tourGen);
        Running = Task.Run(() =>
        {
            try
            {
                if (_s.Ocr is not { } ocr) return;
                var region = frame;
                while (region.Width > MaxSide || region.Height > MaxSide) region = MapReader.Halve(region);
                var reading = OcrJunk.Clean(ocr.ReadLines(region, false));
                if (Interlocked.Read(ref _tourGen) != gen) return;
                Showing = Process(reading, frame);
            }
            catch (Exception e) { Log($"köşeler: okunamadı ({e.GetType().Name})"); }
            finally { if (Interlocked.Read(ref _tourGen) == gen) Volatile.Write(ref _busy, 0); }
        });
    }

    /// <summary>
    /// Bir okumayı işler (kutular kareye göre; testler doğrudan çağırır). Dönen görev bu okumanın başlattığı
    /// çevirilerin bitişidir (okuma onu beklemez).
    /// </summary>
    internal Task Process(OcrReading reading, BgraFrame? frame)
    {
        if (_s.Paused?.Invoke() == true)
        {
            DropAll();
            return Task.CompletedTask;
        }
        var now = _clock.NowMs;
        long session;
        lock (_lock) session = _session;
        var phone = _s.PhoneBox?.Invoke(frame);
        var boxed = reading.Lines.Where(l => l.Box is not null).ToList();
        var lines = phone is { } p ? boxed.Where(l => !GameWords.Inside(l.Box!.Value, p)).ToList() : boxed;
        var tasks = new List<Task>();
        var changed = false;

        // Sağ alt: arama ya da mesaj kartı.
        var corner = GameCards.CornerLines(lines);
        var call = GameCards.FindCall(corner);
        var card = call is null ? GameCards.FindCard(corner) : null;
        changed |= CallStep(call, frame, session, tasks);
        changed |= CardStep(card, frame, phone is not null, session, tasks);

        // Üst köşeler (menü ekranında hiç okunmaz).
        if (MenuScreen(boxed.Select(l => l.Text), now))
        {
            changed |= Drop(Kind.TopLeft);
            changed |= Drop(Kind.TopRight);
        }
        else
        {
            changed |= NoticeStep(lines, frame, now, session, tasks);
            changed |= TopLeftStep(lines, frame, now, session, tasks);
        }
        if (changed) Notify();
        return Task.WhenAll(tasks);
    }

    /// <summary>
    /// Menü ekranı açık mı: duraklatma menüsünün sütunu (<c>Map / Game / Store / Help</c>) bu okumada görüldüyse;
    /// görüldükten sonra <see cref="MenuOpenMs"/> boyunca, ikinci ıskaya dek açık sayılır.
    /// </summary>
    bool MenuScreen(IEnumerable<string> lines, long now)
    {
        lock (_lock)
        {
            if (TopLeftHint.IsMenuScreen(lines))
            {
                _menuSeenAt = now;
                _menuMisses = 0;
                return true;
            }
            if (now - _menuSeenAt > MenuOpenMs) return false;
            _menuMisses++;
            if (_menuMisses >= 2)
            {
                _menuSeenAt = long.MinValue / 2;
                _menuMisses = 0;
                return false;
            }
            return true;
        }
    }

    // ---- kartlar ----

    bool CallStep(GameCards.Call? call, BgraFrame? frame, long session, List<Task> tasks)
    {
        var turkish = _s.TargetLanguage == "tr";
        if (call is { State: not GameCards.CallState.Talking } c && !turkish)
        {
            bool ask;
            lock (_lock) ask = !_callTexts.ContainsKey(c.State) && _callAsking.Add(c.State);
            if (ask)
                tasks.Add(Task.Run(async () =>
                {
                    try
                    {
                        if (await TranslateAsync(GameCards.English(c.State)).ConfigureAwait(false) is { } t)
                            lock (_lock) _callTexts[c.State] = t;
                    }
                    finally { lock (_lock) _callAsking.Remove(c.State); }
                }));
        }
        var step = _calls.Observe(call, st =>
        {
            if (turkish) return GameCards.Turkish(st);
            lock (_lock) return _callTexts.GetValueOrDefault(st);
        });
        return step switch
        {
            CornerStep.Missing => Missing(Kind.Call, frame),
            CornerStep.Drop => Drop(Kind.Call),
            CornerStep.Show s => Place(Kind.Call, call!.Box!.Value, frame, s.Item!),
            _ => Keep(Kind.Call, call?.Box, frame),
        };
    }

    bool CardStep(GameCards.Card? card, BgraFrame? frame, bool phoneActive, long session, List<Task> tasks)
    {
        switch (_messages.Observe(card, phoneActive))
        {
            case CornerStep.Missing: return Missing(Kind.Message, frame);
            case CornerStep.Drop: return Drop(Kind.Message);
            case CornerStep.Show s: return Place(Kind.Message, card!.Box!.Value, frame, s.Item!);
            case CornerStep.Translate t:
                var gen = GenOf(Kind.Message);
                tasks.Add(Later(Kind.Message, gen, session, t.Text, _messages.Failed, t.Key, translation =>
                    _messages.Translated(card!, t.Key, translation) is { } e ? (card!.Box!.Value, e) : null, frame));
                return Keep(Kind.Message, card?.Box, frame);
            default: return Keep(Kind.Message, card?.Box, frame);
        }
    }

    // ---- üst köşeler ----

    bool NoticeStep(List<OcrLine> lines, BgraFrame? frame, long now, long session, List<Task> tasks)
    {
        var n = TopRightNotice.Find(lines);
        switch (_notice.Observe(n?.Text, now))
        {
            case CornerStep.Missing: return Missing(Kind.TopRight, frame);
            case CornerStep.Show s: return Place(Kind.TopRight, n!.Box!.Value, frame, TopRightNotice.Element(n, s.Translation));
            case CornerStep.Translate t:
                var gen = GenOf(Kind.TopRight);
                tasks.Add(Later(Kind.TopRight, gen, session, t.Text, _notice.Failed, t.Key, translation =>
                {
                    _notice.Translated(t.Key, translation);
                    return (n!.Box!.Value, TopRightNotice.Element(n, translation));
                }, frame));
                return Keep(Kind.TopRight, n?.Box, frame);
            default: return Keep(Kind.TopRight, n?.Box, frame);
        }
    }

    bool TopLeftStep(List<OcrLine> all, BgraFrame? frame, long now, long session, List<Task> tasks)
    {
        var found = TopLeftHint.Lines(all);
        var lines = found.Count == 0 || TopLeftHint.Translatable(string.Join(" ", found.Select(l => l.Text))) ? found : [];
        var area = GameWords.Union(lines.Select(l => l.Box!.Value));
        var text = lines.Count == 0 ? null : string.Join("\n", lines.Select(l => l.Text));
        switch (_topLeft.Observe(text, now))
        {
            case CornerStep.Missing: return Missing(Kind.TopLeft, frame);
            case CornerStep.Show s:
                return TopLeftHint.Element(lines, s.Translation) is { } e && Place(Kind.TopLeft, area!.Value, frame, e);
            case CornerStep.Translate t:
                var gen = GenOf(Kind.TopLeft);
                tasks.Add(Later(Kind.TopLeft, gen, session, t.Text, _topLeft.Failed, t.Key, translation =>
                {
                    _topLeft.Translated(t.Key, translation);
                    return TopLeftHint.Element(lines, translation) is { } e ? (area!.Value, e) : null;
                }, frame));
                return Keep(Kind.TopLeft, area, frame);
            default: return Keep(Kind.TopLeft, area, frame);
        }
    }

    // ---- çeviri ----

    /// <summary>
    /// Arka planda çevirir; gelince <paramref name="made"/> öğeyi kurar ve (oturum, tür ve harita durumu değişmediyse)
    /// yerine koyar. Çeviri gelmezse ya da hata verirse izleyici bırakılır (yazı yeniden denenebilir).
    /// </summary>
    Task Later(Kind kind, long gen, long session, string text, Action<string> failed, string key,
        Func<string, (Box Area, ScreenItem Item)?> made, BgraFrame? frame) => Task.Run(async () =>
    {
        string? translation = null;
        try { translation = await TranslateAsync(text).ConfigureAwait(false); }
        catch (Exception e) { Log($"köşeler: çeviri hata verdi ({e.GetType().Name})"); }
        finally { if (translation is null) failed(key); }
        if (translation is null) return;
        if (made(translation) is not { } m) return;
        lock (_lock)
            if (session != _session || _held[kind].Gen != gen) return;
        if (_s.Paused?.Invoke() == true) return;
        Log($"köşe ({Name(kind)}): {PhoneText.Short(text)} → {PhoneText.Short(translation)}");
        if (Place(kind, m.Area, frame, m.Item)) Notify();
    });

    /// <summary>Önce yerelde bilinen çeviri, sonra havuz, sonra yedek (havuz yoksa kendi) çevirmen. Gelmezse null.</summary>
    async Task<string?> TranslateAsync(string text)
    {
        if (Ready?.Invoke(text) is { Length: > 0 } r) return Clean(r);
        Translation.ITranslator? rest;
        if (_s.Pool is { } pool)
        {
            var pooled = await OverlayTranslate.PoolAsync(pool, [text], []).ConfigureAwait(false);
            if (pooled[0].Length > 0) return Clean(pooled[0]);
            rest = _s.Fallback;
        }
        else rest = _s.Own;
        if (rest is null) return null;
        var each = await OverlayTranslate.EachAsync(rest, [text], 1).ConfigureAwait(false);
        return Clean(each[0]);
    }

    static string? Clean(string raw)
    {
        var t = PhoneText.StripSymbols(raw).Trim();
        return t.Length == 0 ? null : t;
    }

    static string Name(Kind k) => k switch
    {
        Kind.Message => "mesaj kartı",
        Kind.Call => "arama",
        Kind.TopLeft => "sol üst",
        _ => "sağ üst",
    };

    // ---- kalkma histerezisi ----

    long GenOf(Kind kind)
    {
        lock (_lock) return _held[kind].Gen;
    }

    /// <summary>Tür görüldü, öğesi değişir; kutusu az oynayan aynı öğe eskisiyle kalır. true: liste değişti.</summary>
    bool Place(Kind kind, Box area, BgraFrame? frame, ScreenItem item)
    {
        var signature = frame is null ? null : MapReader.SignatureOf(frame, area);
        lock (_lock)
        {
            var h = _held[kind];
            var keep = GameWords.Near(item, h.Item) ? h.Item! : item;
            var changed = !ReferenceEquals(keep, h.Item);
            h.Item = keep;
            h.Area = area;
            h.Signature = signature;
            h.Misses = 0;
            h.FirstMissAt = null;
            return changed;
        }
    }

    /// <summary>Tür görüldü ama yeni öğe yok: gösterilen öğe durur (kaçırma sayacı sıfırlanır, iz tazelenir).</summary>
    bool Keep(Kind kind, Box? area, BgraFrame? frame)
    {
        if (area is not { } a) return false;
        var signature = frame is null ? null : MapReader.SignatureOf(frame, a);
        lock (_lock)
        {
            var h = _held[kind];
            if (h.Item is null) return false;
            h.Area = a;
            h.Signature = signature;
            h.Misses = 0;
            h.FirstMissAt = null;
        }
        return false;
    }

    /// <summary>Bu okumada tür yok: harita kartıyla aynı histerezis. true: kalktı.</summary>
    bool Missing(Kind kind, BgraFrame? frame)
    {
        int misses;
        lock (_lock)
        {
            var h = _held[kind];
            if (h.Item is null) return false;
            var now = _clock.NowMs;
            h.Misses++;
            h.FirstMissAt ??= now;
            misses = h.Misses;
            if (h.Misses < MapReader.MissesToClear || now - h.FirstMissAt.Value < MapReader.MissClearMs) return false;
            var changed = frame is null || h.Signature is not { } held
                || MapReader.SignatureOf(frame, h.Area) is not { } cur || MapReader.Differs(held, cur);
            if (!changed) return false;
            ClearLocked(h);
        }
        Log($"köşe ({Name(kind)}) kalktı ({misses} okumadır yok, yeri değişti)");
        return true;
    }

    /// <summary>Hemen kalkar. true: liste değişti.</summary>
    bool Drop(Kind kind)
    {
        lock (_lock)
        {
            var h = _held[kind];
            var had = h.Item is not null;
            ClearLocked(h);
            return had;
        }
    }

    static void ClearLocked(Held h)
    {
        h.Item = null;
        h.Signature = null;
        h.Misses = 0;
        h.FirstMissAt = null;
        h.Gen++;
    }

    void DropAll()
    {
        var changed = false;
        foreach (var k in Enum.GetValues<Kind>()) changed |= Drop(k);
        if (changed) Notify();
    }

    /// <summary>Sıfırla: öğeler ve okuma durumu silinir, çeviri hafızası kalır.</summary>
    public void Reset()
    {
        bool had;
        // Sürmekte olan okumanın sonucu atılır.
        Interlocked.Increment(ref _tourGen);
        Volatile.Write(ref _busy, 0);
        lock (_lock)
        {
            _session++;
            had = _held.Values.Any(h => h.Item is not null);
            foreach (var h in _held.Values) ClearLocked(h);
            _lastTour = null;
            _menuSeenAt = long.MinValue / 2;
            _menuMisses = 0;
        }
        _messages.Reset();
        _calls.Reset();
        _topLeft.Reset();
        _notice.Reset();
        if (had) Notify();
    }
}
