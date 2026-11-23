// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Logging;
using Nino.Core.Settings;
using Nino.Core.Translation;

namespace Nino.Core.Reading;

/// <summary>Sürekli okunan bir ek alan: kimlik (<c>area1</c>…), günlükteki adı ve karedeki bölgesi.</summary>
public sealed record WatchedArea(string Id, string Name, Box Region)
{
    /// <summary>Ayarlardan izlenen alanlar: sürekli oku açık ve bölgesi olan her yuva.</summary>
    public static IReadOnlyList<WatchedArea> FromSettings(AppSettings settings)
    {
        var list = new List<WatchedArea>();
        void Add(int slot, Region? region, bool live)
        {
            if (live && region is not null) list.Add(new($"area{slot}", $"Area {slot}", Box.FromRegion(region)));
        }
        Add(1, settings.ExtraRegion1, settings.ExtraLive1);
        Add(2, settings.ExtraRegion2, settings.ExtraLive2);
        Add(3, settings.ExtraRegion3, settings.ExtraLive3);
        return list;
    }
}

/// <summary>
/// Ek alan izleyicisi: en çok 3 köşe yazısını (görev paneli, bilgi kutusu…) saniyede en çok bir kez okur ve çevirisini
/// TV'de kendi yerinde gösterir. Altyazı hattından bağımsızdır; kendi okuyucusu vardır, okumaları derin değildir.
/// Ek alan satırları ortak havuza önerilmez.
/// </summary>
public sealed class ExtraAreaTracker(ITextReader reader, ITranslator translator, ISubtitleOutput output,
    IMsClock? clock = null, ISubtitlePackLookup? pack = null, Action<string>? log = null)
{
    /// <summary>İki tur arasındaki en kısa süre.</summary>
    public const long RoundIntervalMs = 1000;

    sealed record Candidate(IReadOnlyList<string> Parts, string Key, Box? Box, double? LineHeight);

    sealed class State
    {
        public byte[]? Signature;
        public string? LastReadKey;
        public Candidate? Pending;
        public string? ShownKey;
        public string? DrawnKey;
        public string DrawnText = "";
        public Box? DrawnBox;
        public double? DrawnLine;
    }

    readonly IMsClock _clock = clock ?? SystemMsClock.Instance;
    readonly object _lock = new();
    readonly Dictionary<string, State> _states = new(StringComparer.Ordinal);
    IReadOnlyList<WatchedArea> _areas = [];
    long _session;
    long? _lastRoundAt;
    bool _busy;
    Task _round = Task.CompletedTask;

    /// <summary>İzlenen alanlar (uygulama ayar değişince verir).</summary>
    public IReadOnlyList<WatchedArea> Areas
    {
        get { lock (_lock) return _areas; }
        set { lock (_lock) _areas = value; }
    }

    /// <summary>Tur sürüyor mu.</summary>
    public bool IsBusy { get { lock (_lock) return _busy; } }

    /// <summary>Tur sayısı.</summary>
    public int Rounds { get; private set; }

    /// <summary>Okuma sayısı.</summary>
    public int Reads { get; private set; }

    /// <summary>Bir okumanın süresi (ms; ölçüm dinleyicisi).</summary>
    public event Action<long>? ReadTimed;

    /// <summary>
    /// Kare sunar: en çok 1000 ms'de bir tur; önceki tur bitmediyse kare atlanır. Hemen döner; tur arka planda yürür.
    /// </summary>
    public void Offer(BgraFrame frame)
    {
        lock (_lock)
        {
            if (_areas.Count == 0 && _states.Values.All(s => s.DrawnText.Length == 0)) return;
            var now = _clock.NowMs;
            if (_lastRoundAt is { } last && now - last < RoundIntervalMs) return;
            if (_busy) return;
            _busy = true;
            _lastRoundAt = now;
            _round = Task.Run(async () =>
            {
                try { await RoundAsync(frame).ConfigureAwait(false); }
                catch (Exception e) { log?.Invoke("ek bölgeler okunurken hata çıktı: " + e.Message); }
                finally { lock (_lock) _busy = false; }
            });
        }
    }

    /// <summary>Süren tur bitene kadar bekler.</summary>
    public Task WaitIdleAsync()
    {
        lock (_lock) return _round;
    }

    /// <summary>Bir tur: kalkan alanların kutuları kaldırılır, her alan sırayla ziyaret edilir.</summary>
    public async Task RoundAsync(BgraFrame frame)
    {
        long session;
        IReadOnlyList<WatchedArea> areas;
        lock (_lock)
        {
            session = _session;
            areas = _areas;
            Rounds++;
            var ids = areas.Select(a => a.Id).ToHashSet(StringComparer.Ordinal);
            foreach (var id in _states.Keys.Where(k => !ids.Contains(k)).ToArray())
            {
                if (_states[id].DrawnText.Length > 0) output.ShowRegion(id, "", null, null);
                _states.Remove(id);
            }
        }
        foreach (var area in areas)
        {
            await VisitAsync(area, frame, session).ConfigureAwait(false);
            lock (_lock)
                if (_session != session) return;
        }
    }

    async Task VisitAsync(WatchedArea area, BgraFrame frame, long session)
    {
        var region = frame.CropRegion(area.Region);
        var signature = RegionSignature.Of(region);
        State state;
        Candidate? toCommit = null;
        lock (_lock)
        {
            if (!_states.TryGetValue(area.Id, out state!)) _states[area.Id] = state = new State();
            var changed = state.Signature is null || RegionSignature.Changed(state.Signature, signature);
            state.Signature = signature;
            if (!changed)
            {
                toCommit = state.Pending;
                state.Pending = null;
                if (toCommit is null) return;
            }
        }
        if (toCommit is not null)
        {
            await CommitAsync(toCommit, area, state, session).ConfigureAwait(false);
            return;
        }
        OcrReading reading;
        var start = _clock.NowMs;
        try
        {
            reading = reader.ReadLines(region, false);
        }
        catch
        {
            lock (_lock)
            {
                state.Signature = null;
                state.LastReadKey = null;
                state.Pending = null;
            }
            return;
        }
        lock (_lock)
        {
            if (_session != session) return;
            Reads++;
        }
        ReadTimed?.Invoke(_clock.NowMs - start);
        var candidate = BuildCandidate(reading, area.Region);
        lock (_lock)
        {
            if (candidate.Key == state.LastReadKey)
            {
                state.Pending = null;
                toCommit = candidate;
            }
            else
            {
                state.LastReadKey = candidate.Key;
                state.Pending = candidate;
            }
        }
        if (toCommit is not null) await CommitAsync(toCommit, area, state, session).ConfigureAwait(false);
    }

    static Candidate BuildCandidate(OcrReading reading, Box region)
    {
        var r = OcrJunk.Clean(ButtonHints.Remove(reading));
        var lines = r.Lines.Where(l => Paragraphs.IsText(l.Text)).Select((l, i) => (l, i))
            .OrderBy(p => p.l.Box?.Top ?? 0).ThenBy(p => p.i).Select(p => p.l).ToArray();
        var parts = Paragraphs.Build(lines.Select(l => l.Text));
        var boxed = new OcrReading(lines);
        Box? box = boxed.Box is { } b ? b.PlaceIn(region) : null;
        var lineHeight = Paragraphs.UpperMedian(lines.Where(l => l.Box is not null).Select(l => l.Box!.Value.Height * region.Height));
        return new Candidate(parts, TextKey.Of(string.Join(" ", parts)), box, lineHeight);
    }

    async Task CommitAsync(Candidate candidate, WatchedArea area, State state, long session)
    {
        string? previous;
        lock (_lock)
        {
            if (state.ShownKey == candidate.Key)
            {
                if (state.DrawnKey != candidate.Key || state.DrawnText.Length == 0) return;
                if (state.DrawnBox == candidate.Box && state.DrawnLine == candidate.LineHeight) return;
                output.ShowRegion(area.Id, state.DrawnText, candidate.Box, candidate.LineHeight);
                state.DrawnBox = candidate.Box;
                state.DrawnLine = candidate.LineHeight;
                return;
            }
            previous = state.ShownKey;
            state.ShownKey = candidate.Key;
            if (candidate.Key.Length == 0)
            {
                ClearDrawn(area.Id, state);
                log?.Invoke($"ek alan {area.Name}: boşaldı");
                return;
            }
        }
        var texts = new string?[candidate.Parts.Count];
        var unknown = new List<int>();
        for (var i = 0; i < candidate.Parts.Count; i++)
        {
            if (pack?.Find(candidate.Parts[i]) is { } hit) texts[i] = hit.Translation;
            else unknown.Add(i);
        }
        var fromPack = candidate.Parts.Count - unknown.Count;
        try
        {
            if (unknown.Count > 0)
            {
                var sources = unknown.Select(i => candidate.Parts[i]).ToArray();
                IReadOnlyList<string> results;
                if (translator.SupportsBatch) results = await translator.TranslateBatchAsync(sources).ConfigureAwait(false);
                else
                {
                    var list = new List<string>();
                    foreach (var s in sources) list.Add((await translator.TranslateAsync(s).ConfigureAwait(false)).Text);
                    results = list;
                }
                for (var k = 0; k < unknown.Count; k++) texts[unknown[k]] = k < results.Count ? results[k] : null;
            }
        }
        catch (Exception e)
        {
            lock (_lock)
            {
                if (_session == session && state.ShownKey == candidate.Key)
                {
                    state.ShownKey = previous;
                    state.Pending = candidate;
                }
            }
            log?.Invoke($"ek alan {area.Name}: {LogQuote.Of(string.Join("\n", candidate.Parts))} çevrilemedi ({e.GetType().Name})");
            return;
        }
        lock (_lock)
        {
            if (_session != session || state.ShownKey != candidate.Key) return;
            var shown = candidate.Parts.Select((p, i) => texts[i]?.Trim() is { Length: > 0 } t ? t : p).ToArray();
            if (candidate.Parts.Select((p, i) => (p, i)).All(x =>
                    TextKey.Similar(TextKey.Of(x.p), TextKey.Of(shown[x.i]), Stabilizer.SameLanguageThreshold)))
            {
                ClearDrawn(area.Id, state);
                return;
            }
            var origin = fromPack == candidate.Parts.Count ? "paket" : fromPack > 0 ? "paket+motor" : "motor";
            log?.Invoke($"ek alan {area.Name}: {LogQuote.Of(string.Join("\n", candidate.Parts))} → {origin}");
            var text = string.Join("\n", shown);
            output.ShowRegion(area.Id, text, candidate.Box, candidate.LineHeight);
            state.DrawnKey = candidate.Key;
            state.DrawnText = text;
            state.DrawnBox = candidate.Box;
            state.DrawnLine = candidate.LineHeight;
        }
    }

    void ClearDrawn(string id, State state)
    {
        if (state.DrawnText.Length > 0) output.ShowRegion(id, "", null, null);
        state.DrawnKey = null;
        state.DrawnText = "";
        state.DrawnBox = null;
        state.DrawnLine = null;
    }

    /// <summary>
    /// Sıfırlar (çeviri durdu, hat yeniden kuruldu): süren tur bırakılır; gösterilen bir şey varsa TV'deki bütün ek alan
    /// kutuları kaldırılır.
    /// </summary>
    public void Reset()
    {
        lock (_lock)
        {
            _session++;
            if (_states.Values.Any(s => s.DrawnText.Length > 0)) output.ClearRegions();
            _states.Clear();
            _lastRoundAt = null;
        }
    }
}
