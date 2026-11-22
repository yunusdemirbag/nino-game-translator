// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>
/// Harita okuyucusu: 2 sn'de bir karenin 0,03–0,95'ini kendi tanıyıcısıyla okur; harita ekranıysa "harita açık"
/// süresini uzatır ve seçili görevin kartını çevirip kartın yanına koyar. Okuma çeviriyi beklemez. Gösterilen kart
/// tek bir kaçırılan okumayla kalkmaz: art arda <see cref="MissesToClear"/> okumada yoksa, ilk kaçırmadan beri
/// <see cref="MissClearMs"/> geçtiyse ve kartın kutusu görüntüde belirgin biçimde değiştiyse kalkar.
/// </summary>
public sealed class MapReader
{
    /// <summary>İki tur arası en az süre.</summary>
    public const long ReadEveryMs = 2_000;

    /// <summary>Harita ekranı görüldükten sonra "açık" sayılan süre.</summary>
    public const long OpenForMs = 5_000;

    /// <summary>Telefon okuyucusunun sorduğu ek süre.</summary>
    public const long PhonePauseMs = 8_000;

    /// <summary>Kart hafızasının en çok kaydı (aşarsa boşaltılır).</summary>
    public const int MemoryLimit = 200;

    /// <summary>Windows yazı tanımasının okuyabildiği en büyük kenar.</summary>
    public const int MaxSide = 2_600;

    /// <summary>Kartın kalkması için art arda en az kaç okumada görülmemesi gerekir.</summary>
    public const int MissesToClear = 3;

    /// <summary>Kartın kalkması için ilk kaçırmadan beri geçmesi gereken en az süre.</summary>
    public const long MissClearMs = 4_000;

    /// <summary>Kart kutusunun izinde "değişti" sayılmak için değişmesi gereken örnek oranı.</summary>
    public const double ChangedShare = 0.10;

    /// <summary>Haritada okunacak alan; üstteki sekmeler ve alt kenar dışarıda kalır.</summary>
    public static readonly Box ReadArea = new(0, 0.03, 1, 0.95);

    readonly OverlayServices _s;
    readonly IMsClock _clock;
    readonly object _lock = new();
    List<ScreenItem> _items = [];
    string _lastKey = "";
    MapCardText? _pending;
    long? _openUntil;
    long? _lastTour;
    BgraFrame? _lastFrame;
    int _busy;
    long _session;
    bool _translating;
    string _shownTitle = "";
    double _shownTop;
    string _shownFull = "";
    int _misses;
    long? _firstMissAt;
    Box? _heldBox;
    byte[]? _heldSignature;
    readonly Dictionary<string, string[]> _memory = new(StringComparer.Ordinal);

    /// <summary>Okuyucu.</summary>
    public MapReader(OverlayServices services)
    {
        _s = services;
        _clock = services.Clock;
        Ready = services.Ready;
    }

    /// <summary>Bilinen çeviri (güncellenebilir).</summary>
    public Func<string, string?>? Ready { get; set; }

    /// <summary>Son başlatılan arka plan okuması (testler bekler).</summary>
    public Task? Running { get; private set; }

    /// <summary>Son başlatılan kart gösterimi (testler bekler).</summary>
    public Task? Showing { get; private set; }

    /// <summary>Ekrandaki kart öğesi (boş = örtü yok).</summary>
    public IReadOnlyList<ScreenItem> Items
    {
        get { lock (_lock) return _items.ToArray(); }
    }

    /// <summary>Harita ekranı açık mı.</summary>
    public bool IsOpen
    {
        get { lock (_lock) return _openUntil is { } u && _clock.NowMs < u; }
    }

    /// <summary>Harita yakında açıktı mı (açık süre + ek süre) ya da kart örtüsü ekranda mı.</summary>
    public bool RecentlyOpen(long extraMs)
    {
        lock (_lock) return (_openUntil is { } u && _clock.NowMs < u + extraMs) || _items.Count > 0;
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
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return;
        Running = Task.Run(() =>
        {
            try
            {
                if (_s.Ocr is not { } ocr) return;
                var region = frame.CropRegion(ReadArea);
                while (region.Width > MaxSide || region.Height > MaxSide) region = Halve(region);
                var reading = OcrJunk.Clean(ocr.ReadLines(region, false)).PlaceIn(ReadArea);
                Process(reading, frame);
            }
            catch (Exception e) { Log($"harita: okunamadı ({e.GetType().Name})"); }
            finally { Volatile.Write(ref _busy, 0); }
        });
    }

    /// <summary>Yarıya küçültme (2 × 2 noktanın ortalaması, <c>(toplam + 2) / 4</c>).</summary>
    internal static BgraFrame Halve(BgraFrame f)
    {
        var w = f.Width / 2;
        var h = f.Height / 2;
        var r = BgraFrame.Blank(w, h);
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
            {
                var o = r.IndexOf(x, y);
                for (var c = 0; c < 4; c++)
                {
                    var sum = f.Pixels[f.IndexOf(2 * x, 2 * y) + c] + f.Pixels[f.IndexOf(2 * x + 1, 2 * y) + c]
                        + f.Pixels[f.IndexOf(2 * x, 2 * y + 1) + c] + f.Pixels[f.IndexOf(2 * x + 1, 2 * y + 1) + c];
                    r.Pixels[o + c] = (byte)((sum + 2) / 4);
                }
            }
        return r;
    }

    /// <summary>Bir okumayı işler (kutular kareye göre; testler doğrudan çağırır).</summary>
    internal void Process(OcrReading reading, BgraFrame? frame)
    {
        var lines = reading.Lines.Select(l => l.Text).ToArray();
        if (MapScreen.ShowsGta6(lines)) _s.Gta6Seen?.Invoke();
        if (!MapScreen.IsMapScreen(lines))
        {
            Missed(frame);
            return;
        }
        lock (_lock)
        {
            _openUntil = _clock.NowMs + OpenForMs;
            if (frame is not null) _lastFrame = frame;
        }
        if (MapCard.Find(reading) is { } card)
        {
            if (Showable(card)) Seen(card, frame);
            Showing = ShowAsync(card);
        }
        else Missed(frame);
    }

    /// <summary>Kart yeniden okundu: kaçırma sayacı sıfırlanır; kart gösteriliyorsa kutusunun izi tazelenir.</summary>
    void Seen(MapCardText card, BgraFrame? frame)
    {
        lock (_lock)
        {
            _misses = 0;
            _firstMissAt = null;
            if (_items.Count > 0 && frame is not null)
            {
                _heldBox = card.Box;
                _heldSignature = SignatureOf(frame, card.Box);
            }
        }
    }

    /// <summary>
    /// Bu okumada kart yok (ya da harita ekranı değil). Örtü yoksa yalnız anahtar unutulur. Örtü varsa kaçırma
    /// sayılır; kart ancak art arda <see cref="MissesToClear"/> kaçırma, ilk kaçırmadan beri
    /// <see cref="MissClearMs"/> ve kart kutusunun görüntüsü değişmişse kalkar. Kare yoksa ya da kutunun izi
    /// yoksa görüntü "değişti" sayılır (bakılamaz).
    /// </summary>
    void Missed(BgraFrame? frame)
    {
        int misses;
        lock (_lock)
        {
            if (_items.Count == 0)
            {
                _lastKey = "";
                ClearHoldLocked();
                return;
            }
            var now = _clock.NowMs;
            _misses++;
            _firstMissAt ??= now;
            misses = _misses;
            if (_misses < MissesToClear || now - _firstMissAt.Value < MissClearMs) return;
            if (!ImageChangedLocked(frame)) return;
        }
        Log($"harita kartı kalktı ({misses} okumadır yok, kartın yeri değişti)");
        ClearOverlay(forgetKey: true);
    }

    bool ImageChangedLocked(BgraFrame? frame)
    {
        if (frame is null || _heldBox is not { } box || _heldSignature is not { } held) return true;
        return SignatureOf(frame, box) is not { } now || Differs(held, now);
    }

    void ClearHoldLocked()
    {
        _misses = 0;
        _firstMissAt = null;
        _heldBox = null;
        _heldSignature = null;
    }

    /// <summary>Karenin kutu bölgesinin izi (kutu 0–1'e kırpılır; bölge boşsa null).</summary>
    internal static byte[]? SignatureOf(BgraFrame frame, Box box)
    {
        var b = new Box(Math.Clamp(box.Left, 0, 1), Math.Clamp(box.Top, 0, 1), Math.Clamp(box.Right, 0, 1),
            Math.Clamp(box.Bottom, 0, 1));
        var crop = frame.CropRegion(b);
        return crop.Width == 0 || crop.Height == 0 ? null : RegionSignature.Of(crop);
    }

    /// <summary>
    /// İki iz belirgin biçimde farklı mı: örneklerin en az <see cref="ChangedShare"/>'ı
    /// <see cref="RegionSignature.DefaultThreshold"/>'tan çok değişmiş (tek tük kıpırtı sayılmaz).
    /// </summary>
    internal static bool Differs(ReadOnlySpan<byte> previous, ReadOnlySpan<byte> current)
    {
        if (previous.Length != current.Length || current.Length == 0) return true;
        var changed = 0;
        for (var i = 0; i < current.Length; i++)
            if (Math.Abs(previous[i] - current[i]) > RegionSignature.DefaultThreshold) changed++;
        return changed >= ChangedShare * current.Length;
    }

    /// <summary>Gösterme kurallarının ilk dördü (§9.3 1–4): kart gösterilebilir mi.</summary>
    static bool Showable(MapCardText card)
    {
        if (HasTurkishLetters(card.All) || card.Sentences.Count == 0) return false;
        if (card.Title.Length == 0 && PhoneText.Words(card.All).Length < 6) return false;
        if (card.Title.Length == 0 && card.Box.Left > 0.6 && card.Box.Top < 0.32) return false;
        return card.Box.Top >= 0.1;
    }

    void ClearOverlay(bool forgetKey)
    {
        lock (_lock)
        {
            if (forgetKey) _lastKey = "";
            ClearHoldLocked();
            if (_items.Count == 0) return;
            _items = [];
        }
        Notify();
    }

    /// <summary>Sıfırla: örtü, anahtar, bekleyen kart ve "harita açık" süresi silinir (hafıza kalır).</summary>
    public void Reset()
    {
        bool had;
        lock (_lock)
        {
            _session++;
            had = _items.Count > 0;
            _items = [];
            _lastKey = "";
            _pending = null;
            _openUntil = null;
            _lastFrame = null;
            ClearHoldLocked();
        }
        if (had) Notify();
    }

    static bool HasTurkishLetters(string text) => text.Any("ğışĞİŞ".Contains);

    async Task ShowAsync(MapCardText card)
    {
        try { await ShowCoreAsync(card).ConfigureAwait(false); }
        catch (Exception e) { Log($"harita kartı çeviride hata verdi ({e.GetType().Name})"); }
    }

    async Task ShowCoreAsync(MapCardText card)
    {
        var all = card.All;
        if (!Showable(card)) return;
        var full = PhoneText.Key(all);
        var key = full + "@" + (int)Math.Floor(card.Box.Top * 50);
        var titleKey = PhoneText.Key(card.Title);
        long session;
        bool cleared = false;
        string[]? remembered;
        var queued = false;
        lock (_lock)
        {
            if (card.Title.Length > 0 && titleKey == _shownTitle && _shownFull.StartsWith(full, StringComparison.Ordinal)
                && _shownFull != full) return;
            if (key == _lastKey) return;
            _lastKey = key;
            session = _session;
            var sameCard = card.Title.Length > 0 && titleKey == _shownTitle && Math.Abs(card.Box.Top - _shownTop) < 0.04;
            if (!sameCard && _items.Count > 0)
            {
                _items = [];
                cleared = true;
            }
            remembered = _memory.GetValueOrDefault(key);
            if (remembered is null)
            {
                if (_translating)
                {
                    _pending = card;
                    queued = true;
                }
                else
                {
                    _translating = true;
                    _pending = null;
                }
            }
        }
        if (cleared) Notify();
        if (remembered is not null)
        {
            Place(card, key, remembered, session);
            return;
        }
        if (queued) return;

        string[] lines;
        try { lines = await TranslateAsync(card).ConfigureAwait(false); }
        finally
        {
            lock (_lock) _translating = false;
        }

        MapCardText? next = null;
        lock (_lock)
        {
            if (session != _session) return;
            if (lines.Length > 0)
            {
                _memory[key] = lines;
                if (_memory.Count > MemoryLimit) _memory.Clear();
            }
            if (_pending is { } p)
            {
                next = p;
                _pending = null;
                _lastKey = "";
            }
        }
        if (next is not null)
        {
            await ShowCoreAsync(next).ConfigureAwait(false);
            return;
        }
        lock (_lock)
        {
            if (_lastKey != key || lines.Length == 0) return;
            if (!(_openUntil is { } u && _clock.NowMs < u))
            {
                _lastKey = "";
                return;
            }
        }
        Place(card, key, lines, session);
    }

    async Task<string[]> TranslateAsync(MapCardText card)
    {
        var start = _clock.NowMs;
        var hasTitle = card.Title.Length > 0;
        var parts = (hasTitle ? new[] { PhoneText.TitleCase(card.Title) } : []).Concat(card.Sentences).ToArray();
        var results = new string[parts.Length];
        var ready = Ready;
        var known = 0;
        for (var i = 0; i < parts.Length; i++)
        {
            results[i] = ready?.Invoke(parts[i]) is { Length: > 0 } r ? r : "";
            if (results[i].Length > 0) known++;
        }
        var missing = Enumerable.Range(0, parts.Length).Where(i => results[i].Length == 0).ToArray();
        var fromPool = 0;
        Translation.ITranslator? rest;
        if (_s.Pool is { } pool)
        {
            if (missing.Length > 0)
            {
                var pooled = await OverlayTranslate.PoolAsync(pool, missing.Select(i => parts[i]).ToArray(), [])
                    .ConfigureAwait(false);
                for (var k = 0; k < missing.Length; k++)
                    if (pooled[k].Length > 0)
                    {
                        results[missing[k]] = pooled[k];
                        fromPool++;
                    }
            }
            rest = _s.Fallback;
        }
        else rest = _s.Own;
        var remaining = Enumerable.Range(0, parts.Length).Where(i => results[i].Length == 0).ToArray();
        if (rest is not null && remaining.Length > 0)
        {
            var each = await OverlayTranslate.EachAsync(rest, remaining.Select(i => parts[i]).ToArray(),
                Math.Max(1, remaining.Length)).ConfigureAwait(false);
            for (var k = 0; k < remaining.Length; k++) results[remaining[k]] = each[k];
        }
        var lines = new List<string>();
        for (var i = 0; i < parts.Length; i++)
        {
            var t = PhoneText.StripSymbols(results[i]).Trim();
            if (t.Length == 0) continue;
            if (i == 0 && hasTitle)
                t = _s.TargetLanguage == "tr" ? PhoneText.TurkishUpper(t) : t.ToUpperInvariant();
            else t = MapCardLayout.FixTerms(PhoneText.DecodeEntities(t));
            lines.Add(t);
        }
        Log($"harita kartı {_clock.NowMs - start} ms'de çevrildi; {known + fromPool}/{parts.Length} parça hazırdı");
        return lines.ToArray();
    }

    void Place(MapCardText card, string key, IReadOnlyList<string> lines, long session)
    {
        BgraFrame? frame;
        lock (_lock) frame = _lastFrame;
        var found = frame is null ? null : MapCard.FindFrame(frame, card.Box);
        var item = MapCardLayout.Layout(card, lines, found);
        lock (_lock)
        {
            if (session != _session || _lastKey != key) return;
            _items = [item];
            _shownTitle = PhoneText.Key(card.Title);
            _shownTop = card.Box.Top;
            _shownFull = PhoneText.Key(card.All);
            _misses = 0;
            _firstMissAt = null;
            _heldBox = card.Box;
            _heldSignature = frame is null ? null : SignatureOf(frame, card.Box);
        }
        var head = card.Title.Length > 0 ? card.Title : card.Sentences.FirstOrDefault() ?? "";
        Log($"harita kartı: {PhoneText.Short(head)} → {PhoneText.Short(lines.FirstOrDefault())}");
        Notify();
    }
}
