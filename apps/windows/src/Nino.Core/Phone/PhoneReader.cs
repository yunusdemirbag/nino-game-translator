// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Core.Translation;

namespace Nino.Core.Phone;

/// <summary>Telefon ve harita okuyucularının ortak çeviri yardımcıları.</summary>
static class OverlayTranslate
{
    /// <summary>Metinleri çevirmenle tek tek çevirir (aynı anda en çok <paramref name="parallel"/>); hata → boş.</summary>
    public static async Task<string[]> EachAsync(ITranslator? translator, IReadOnlyList<string> texts, int parallel)
    {
        var results = new string[texts.Count];
        Array.Fill(results, "");
        if (translator is null || texts.Count == 0) return results;
        using var gate = new SemaphoreSlim(parallel);
        await Task.WhenAll(texts.Select(async (text, i) =>
        {
            await gate.WaitAsync().ConfigureAwait(false);
            try { results[i] = (await translator.TranslateAsync(text).ConfigureAwait(false)).Text ?? ""; }
            catch { results[i] = ""; }
            finally { gate.Release(); }
        })).ConfigureAwait(false);
        return results;
    }

    /// <summary>Toplu havuz sorgusu; hata → hepsi boş.</summary>
    public static async Task<string[]> PoolAsync(PoolBatchQuery pool, IReadOnlyList<string> texts,
        IReadOnlyList<string> context)
    {
        var results = new string[texts.Count];
        Array.Fill(results, "");
        try
        {
            var r = await pool(texts, context, CancellationToken.None).ConfigureAwait(false);
            for (var i = 0; i < texts.Count && i < r.Count; i++)
                if (!string.IsNullOrWhiteSpace(r[i])) results[i] = r[i]!;
        }
        catch { }
        return results;
    }
}

/// <summary>
/// Oyun telefonunun okuyucusu (GTA 6 mesajları ve uygulamaları): telefonu karede bulur, kendi tanıyıcısıyla okur,
/// sohbet/uygulama ekranını çıkarır, çevirir ve telefonun yanındaki örtü öğelerini üretir. "Kare ver" hemen döner;
/// okuma arka planda yapılır. Hafıza yalnız bellektedir (okuyucuyla yaşar; sıfırlama silmez).
/// </summary>
public sealed class PhoneReader
{
    /// <summary>Örtü yokken iki okuma arası en az süre.</summary>
    public const long ReadEveryMs = 600;

    /// <summary>Örtü varken iki okuma arası en az süre.</summary>
    public const long ReadEveryWithOverlayMs = 1_000;

    /// <summary>Telefon bu kadar süredir görülmediyse örtü kalkar.</summary>
    public const long UnseenClearMs = 1_200;

    /// <summary>Son mesajların altyazı hattına verildiği süre.</summary>
    public const long RecentMessagesMs = 30_000;

    /// <summary>Hafızanın en çok kaydı (aşarsa boşaltılır).</summary>
    public const int MemoryLimit = 5_000;

    readonly OverlayServices _s;
    readonly IMsClock _clock;
    readonly PhoneTracker _tracker;
    readonly object _lock = new();

    List<ScreenItem> _items = [];
    string _lastKey = "";
    HashSet<string> _previous = new(StringComparer.Ordinal);
    HashSet<string> _shownTexts = new(StringComparer.Ordinal);
    string _shownTitle = "";
    bool _shownChat;
    long? _lastMessageAt;
    long? _lastReadAt;
    int _busy;
    long _session;
    Box? _baseBox;
    List<ScreenItem> _baseItems = [];
    Dictionary<string, double> _anchors = new(StringComparer.Ordinal);
    string[] _recent = [];
    long _recentAt;
    readonly Dictionary<string, string> _memory = new(StringComparer.Ordinal);

    /// <summary>Okuyucu.</summary>
    public PhoneReader(OverlayServices services, Func<BgraFrame, PhoneShape?>? finder = null)
    {
        _s = services;
        _clock = services.Clock;
        _tracker = new PhoneTracker(_clock, finder);
        Ready = services.Ready;
        Glossary = services.Glossary;
    }

    /// <summary>Bilinen çeviri (güncellenebilir).</summary>
    public Func<string, string?>? Ready { get; set; }

    /// <summary>Telefon sözlüğü açık mı (güncellenebilir).</summary>
    public bool Glossary { get; set; }

    /// <summary>Okuyucunun telefon takipçisi.</summary>
    public PhoneTracker Tracker => _tracker;

    /// <summary>Son başlatılan arka plan okuması (testler bekler).</summary>
    public Task? Running { get; private set; }

    /// <summary>Oturum numarası (sıfırlamada artar).</summary>
    public long Session
    {
        get { lock (_lock) return _session; }
    }

    /// <summary>Ekrandaki örtü öğeleri (boş = örtü yok).</summary>
    public IReadOnlyList<ScreenItem> Items
    {
        get { lock (_lock) return _items.ToArray(); }
    }

    /// <summary>Son yerleştirmedeki mesaj metinleri (yerleştirmeden sonraki 30 sn içinde; sonra boş).</summary>
    public IReadOnlyList<string> RecentMessages
    {
        get
        {
            lock (_lock) return _recent.Length > 0 && _clock.NowMs - _recentAt <= RecentMessagesMs ? _recent.ToArray() : [];
        }
    }

    /// <summary>Hafızadaki kayıt sayısı.</summary>
    public int MemoryCount
    {
        get { lock (_lock) return _memory.Count; }
    }

    void Log(string line) => _s.Log?.Invoke(line);

    void Notify() => _s.Changed?.Invoke();

    /// <summary>Kare ver: zamanı geldiyse ve okuma sürmüyorsa arka planda okur; hemen döner.</summary>
    public void OfferFrame(BgraFrame frame)
    {
        var now = _clock.NowMs;
        long session;
        lock (_lock)
        {
            var every = _items.Count > 0 ? ReadEveryWithOverlayMs : ReadEveryMs;
            if (_lastReadAt is { } t && now - t <= every) return;
        }
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return;
        lock (_lock)
        {
            _lastReadAt = now;
            session = _session;
        }
        Running = Task.Run(async () =>
        {
            try { await TourAsync(frame, session).ConfigureAwait(false); }
            catch (Exception e) { Log($"telefon: okunamadı ({e.GetType().Name})"); }
            finally { Volatile.Write(ref _busy, 0); }
        });
    }

    /// <summary>Telefon uygulamasına özgü yazılar okuma hattında görüldü (kutular kareye göre): takipçi benimser.</summary>
    public void AdoptPhoneText(BgraFrame frame, IReadOnlyList<Box> boxes) => _tracker.Adopt(frame, boxes);

    async Task TourAsync(BgraFrame frame, long session)
    {
        if (_s.Paused?.Invoke() == true)
        {
            ClearOverlay();
            return;
        }
        var phone = _tracker.Locate(frame);
        if (phone is null)
        {
            ClearIfUnseen();
            return;
        }
        if (_s.Ocr is not { } ocr) return;
        var crop = frame.CropRegion(phone.Box);
        if (crop.Height < 900 && crop.Width * 2 <= 2600 && crop.Height * 2 <= 2600) crop = crop.Upscale(2);
        var reading = ocr.ReadLines(crop, false).PlaceIn(phone.Box);
        await ProcessAsync(reading, phone, frame, session).ConfigureAwait(false);
    }

    void ClearIfUnseen()
    {
        bool clear;
        lock (_lock)
            clear = _items.Count > 0 && (_lastMessageAt is not { } at || _clock.NowMs - at > UnseenClearMs);
        if (clear) ClearOverlay();
    }

    /// <summary>Örtüyü kaldırır (öğeler, taban, son anahtar ve gösterilen bilgiler silinir).</summary>
    public void ClearOverlay()
    {
        lock (_lock)
        {
            if (_items.Count == 0) return;
            ClearShownLocked();
        }
        Notify();
    }

    void ClearShownLocked()
    {
        _items = [];
        _baseBox = null;
        _baseItems = [];
        _lastKey = "";
        _shownTexts = new(StringComparer.Ordinal);
        _shownTitle = "";
        _shownChat = false;
    }

    /// <summary>Sıfırla: oturum artar, örtü ve okuma durumu silinir, takipçi sıfırlanır; hafıza kalır.</summary>
    public void Reset()
    {
        bool had;
        lock (_lock)
        {
            _session++;
            had = _items.Count > 0;
            ClearShownLocked();
            _previous = new(StringComparer.Ordinal);
            _recent = [];
            _anchors = new(StringComparer.Ordinal);
        }
        _tracker.Reset();
        if (had) Notify();
    }

    /// <summary>
    /// Hafızadan bulma: anahtar 5 sözcükten azsa yalnız birebir; değilse birebir ya da anahtarla başlayan/biten en
    /// uzun anahtarlı kayıt.
    /// </summary>
    internal static string? FindIn(IReadOnlyDictionary<string, string> memory, string key)
    {
        if (key.Length == 0) return null;
        if (memory.TryGetValue(key, out var exact)) return exact;
        if (PhoneText.Words(key).Length < 5) return null;
        string? bestKey = null;
        string? best = null;
        var head = key + " ";
        var tail = " " + key;
        foreach (var (k, v) in memory)
            if ((k.StartsWith(head, StringComparison.Ordinal) || k.EndsWith(tail, StringComparison.Ordinal))
                && (bestKey is null || k.Length > bestKey.Length))
            {
                bestKey = k;
                best = v;
            }
        return best;
    }

    /// <summary>Bir okumayı işler (telefon verilmiş; testler doğrudan çağırır).</summary>
    internal async Task ProcessAsync(OcrReading reading, PhoneShape phone, BgraFrame frame, long? sessionOverride = null)
    {
        long session;
        lock (_lock) session = sessionOverride ?? _session;
        var now = _clock.NowMs;

        if (reading.Lines.Any(l => MapScreen.IsMapButton(l.Text)))
        {
            ClearOverlay();
            return;
        }

        var content = PhoneScreen.Read(reading, phone);
        var messages = content.Messages.ToList();
        if (messages.Count == 0)
        {
            ClearIfUnseen();
            return;
        }
        lock (_lock) _lastMessageAt = now;
        _s.Gta6Seen?.Invoke();

        var readKey = string.Join("|", messages.Select(m =>
            PhoneText.Key(m.Text) + "@" + (int)Math.Floor((m.Box.Top - phone.Box.Top) * 60)));
        HashSet<string> previous;
        Dictionary<string, string> memory;
        var notify = false;
        lock (_lock)
        {
            if (session != _session || readKey == _lastKey) return;
            if (_baseBox is not null && _items.Count > 0)
            {
                var readTops = new Dictionary<string, double>(StringComparer.Ordinal);
                foreach (var m in messages) readTops.TryAdd(PhoneText.Key(m.Text), m.Box.Top - phone.Box.Top);
                var baseKeys = _baseItems.Where(i => !i.Backdrop).Select(i => PhoneText.Key(i.Source)).ToList();
                var common = baseKeys.Distinct(StringComparer.Ordinal).Where(readTops.ContainsKey).ToList();
                var moved = common.Any(k => _anchors.TryGetValue(k, out var a) && Math.Abs(readTops[k] - a) > 0.02);
                var steady = messages.All(m => PhoneText.SimilarToAny(m.Text, _previous));
                if ((moved || common.Count * 2 < baseKeys.Count) && steady)
                {
                    _items = [];
                    _baseBox = null;
                    _baseItems = [];
                    _lastKey = "";
                    notify = true;
                }
            }
            previous = _previous;
            _previous = messages.Select(m => PhoneText.Key(m.Text)).Where(k => k.Length > 0).ToHashSet(StringComparer.Ordinal);
            memory = new Dictionary<string, string>(_memory, StringComparer.Ordinal);
        }
        if (notify) Notify();

        if (content.IsChat)
        {
            var last = messages[^1];
            if (FindIn(memory, PhoneText.Key(last.Text)) is null && last.Box.Bottom > phone.Box.Bottom - 0.06
                && last.Box.Height > last.LineHeight * 1.8 && !PhoneText.EndsWithAny(last.Text, ".!?…\")"))
                messages.RemoveAt(messages.Count - 1);
            if (messages.Count == 0) return;
            var first = messages[0];
            if (messages.Count > 1 && FindIn(memory, PhoneText.Key(first.Text)) is null && PhoneText.StartsLower(first.Text)
                && first.Box.Top < phone.Box.Top + 0.095)
                messages.RemoveAt(0);
        }

        var ready = Ready;
        var glossary = Glossary;
        var translations = messages.Select(m =>
        {
            if (glossary && PhoneGlossary.Lookup(m.Text) is { } g) return g;
            if (ready?.Invoke(m.Text) is { Length: > 0 } r) return r;
            return FindIn(memory, PhoneText.Key(m.Text)) ?? "";
        }).ToArray();

        var rawTitle = content.IsChat ? content.Title ?? "" : "";
        var usedTitle = PhoneText.Words(rawTitle).Length <= 3 && !rawTitle.Any(".,!?…".Contains) ? rawTitle : "";
        var texts = messages.Select(m => m.Text).ToArray();
        bool hasOverlay;
        string? oldTitle = null;
        lock (_lock)
        {
            if (session != _session) return;
            if (_items.Count > 0 && usedTitle.Length > 0 && _shownTitle.Length > 0
                && PhoneText.Key(usedTitle) != PhoneText.Key(_shownTitle))
            {
                oldTitle = _shownTitle;
                ClearShownLocked();
            }
        }
        if (oldTitle is not null)
        {
            Log($"telefon: başka bir konuşma açıldı ({oldTitle} → {usedTitle}); önceki panel temizlendi");
            Notify();
        }
        lock (_lock)
        {
            if (session != _session) return;
            hasOverlay = _items.Count > 0;
            if (hasOverlay && content.IsChat == _shownChat && PhoneText.SameMessages(texts, _shownTexts))
            {
                _lastKey = readKey;
                return;
            }
            if (hasOverlay)
            {
                var shown = _shownTexts;
                var fresh = texts.Where(t => !PhoneText.SimilarToAny(t, shown)).ToArray();
                if (fresh.Length == 0)
                {
                    _lastKey = readKey;
                    return;
                }
                if (fresh.Any(t => !PhoneText.SimilarToAny(t, previous))) return;
            }
        }

        var unknown = Enumerable.Range(0, messages.Count).Where(i => translations[i].Length == 0).ToArray();
        var confirmed = unknown.All(i => previous.Contains(PhoneText.Key(messages[i].Text)));
        var known = messages.Count - unknown.Length;
        var place = new Placement(messages, phone, frame, content.IsChat, rawTitle, readKey, session);
        if (!confirmed && unknown.Length > 0)
        {
            if (unknown.Length < messages.Count && !hasOverlay)
                Place(place, translations, false,
                    $"{known} hazır gösterildi, {unknown.Length} yeni mesaj bir okuma daha bekleyecek");
            return;
        }
        if (unknown.Length == 0)
        {
            Place(place, translations, true, "hepsi hazırdı");
            return;
        }
        if (unknown.Length < messages.Count && !hasOverlay)
            Place(place, translations, true, $"{known} hazır, {unknown.Length} bekleniyor");

        var start = _clock.NowMs;
        var (results, fromPool, single) = await TranslateAsync(messages, unknown, content.IsChat).ConfigureAwait(false);
        lock (_lock)
        {
            if (session != _session) return;
            for (var k = 0; k < unknown.Length; k++)
                if (results[k].Length > 0) _memory[PhoneText.Key(messages[unknown[k]].Text)] = results[k];
            if (_memory.Count > MemoryLimit) _memory.Clear();
        }
        for (var k = 0; k < unknown.Length; k++) translations[unknown[k]] = results[k];
        Place(place, translations, true, $"çeviri {_clock.NowMs - start} ms ({fromPool} havuz, {single} tek tek)");
    }

    async Task<(string[] Results, int FromPool, int Single)> TranslateAsync(IReadOnlyList<PhoneMessage> messages,
        int[] unknown, bool chat)
    {
        var sources = unknown.Select(i => messages[i].Text).ToArray();
        var results = new string[sources.Length];
        Array.Fill(results, "");
        var fromPool = 0;
        ITranslator? rest;
        if (_s.Pool is { } pool)
        {
            var first = unknown.Length > 0 ? unknown[0] : 0;
            IReadOnlyList<string> context = chat
                ? messages.Skip(Math.Max(0, first - 4)).Take(first - Math.Max(0, first - 4)).Select(m => m.Text).ToArray()
                : [];
            var pooled = await OverlayTranslate.PoolAsync(pool, sources, context).ConfigureAwait(false);
            for (var i = 0; i < pooled.Length; i++)
                if (pooled[i].Length > 0)
                {
                    results[i] = pooled[i];
                    fromPool++;
                }
            rest = _s.Fallback;
        }
        else rest = _s.Own;

        var remaining = Enumerable.Range(0, sources.Length).Where(i => results[i].Length == 0).ToArray();
        var single = 0;
        if (rest is not null && remaining.Length > 0)
        {
            var each = await OverlayTranslate.EachAsync(rest, remaining.Select(i => sources[i]).ToArray(), 2)
                .ConfigureAwait(false);
            for (var k = 0; k < remaining.Length; k++) results[remaining[k]] = each[k];
            single = remaining.Length;
        }
        for (var i = 0; i < results.Length; i++) results[i] = PhoneText.CleanTranslation(results[i]);
        return (results, fromPool, single);
    }

    sealed record Placement(IReadOnlyList<PhoneMessage> Messages, PhoneShape Phone, BgraFrame Frame, bool Chat,
        string RawTitle, string ReadKey, long Session);

    static ScreenItem Shift(ScreenItem item, double dx, double dy) =>
        item with { Box = new Box(item.Box.Left + dx, item.Box.Top + dy, item.Box.Right + dx, item.Box.Bottom + dy) };

    void Place(Placement p, IReadOnlyList<string> translations, bool definite, string note)
    {
        var sampler = new BrightenedSampler(p.Frame, p.Phone);
        var items = p.Chat
            ? PhoneLayout.ChatPanel(p.Messages, translations, p.Phone, sampler, p.RawTitle)
            : PhoneLayout.AppBubbles(p.Messages, translations, p.Phone, sampler);
        lock (_lock)
        {
            if (p.Session != _session) return;
            _recent = p.Messages.Select(m => m.Text).ToArray();
            _recentAt = _clock.NowMs;
            var anchors = new Dictionary<string, double>(StringComparer.Ordinal);
            foreach (var m in p.Messages) anchors.TryAdd(PhoneText.Key(m.Text), m.Box.Top - p.Phone.Box.Top);
            _anchors = anchors;

            var baseBox = p.Phone.Box;
            if (_baseBox is { } old)
            {
                var dx = (baseBox.Left + baseBox.Right - old.Left - old.Right) / 2;
                var dy = (baseBox.Top + baseBox.Bottom - old.Top - old.Bottom) / 2;
                if (Math.Abs(dx) < 0.05 && Math.Abs(dy) < 0.05)
                {
                    items = items.Select(i => Shift(i, -dx, -dy)).ToList();
                    baseBox = old;
                }
            }
            var olds = _baseItems;
            if (!p.Chat && olds.Count == items.Count && olds.Count > 0
                && olds.Zip(items).All(z => z.First.Text == z.Second.Text && Math.Abs(z.First.Box.Top - z.Second.Box.Top) < 0.06))
                items = olds;
            else
            {
                var (dl, dt) = p.Chat ? (0.012, 0.015) : (0.04, 0.06);
                items = items.Select(n => olds.FirstOrDefault(o => o.Source == n.Source && o.Text == n.Text
                    && Math.Abs(o.Box.Left - n.Box.Left) < dl && Math.Abs(o.Box.Top - n.Box.Top) < dt) ?? n).ToList();
            }
            _baseBox = baseBox;
            _baseItems = items;
            _items = items;
            if (definite)
            {
                _lastKey = p.ReadKey;
                _shownTexts = p.Messages.Select(m => PhoneText.Key(m.Text)).Where(k => k.Length > 0)
                    .ToHashSet(StringComparer.Ordinal);
                _shownChat = p.Chat;
                _shownTitle = p.Chat ? p.RawTitle : "";
            }
        }
        var bubbles = items.Where(i => !i.Backdrop).ToArray();
        var head = bubbles.Length > 0 ? $" ({PhoneText.Short(bubbles[0].Source)} → {PhoneText.Short(bubbles[0].Text)})" : "";
        Log($"telefon: {bubbles.Length} yazı{head}{(p.Chat ? "" : " · uygulama")} · {note}");
        Notify();
    }
}
