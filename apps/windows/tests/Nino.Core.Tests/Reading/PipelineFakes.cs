// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using Nino.Core.Imaging;
using Nino.Core.Logging;
using Nino.Core.Reading;
using Nino.Core.Translation;

namespace Nino.Core.Tests.Reading;

/// <summary>Sırayla verilen metinleri (yalnız metin) döndürür, bitince boş; okumanın iş parçacığını kaydeder.</summary>
sealed class SequenceReader(params string[] texts) : ITextReader
{
    readonly Queue<string> _texts = new(texts);
    public List<int> Threads { get; } = [];
    public int Calls { get; private set; }

    public string ReadText(BgraFrame image)
    {
        lock (_texts)
        {
            Calls++;
            Threads.Add(Environment.CurrentManagedThreadId);
            return _texts.Count > 0 ? _texts.Dequeue() : "";
        }
    }

    public void Push(params string[] more)
    {
        lock (_texts) foreach (var t in more) _texts.Enqueue(t);
    }
}

/// <summary>Her çağrıda verilen işlevin okumasını döndürür.</summary>
sealed class FuncReader(Func<BgraFrame, OcrReading> read) : ITextReader
{
    public int Calls;

    public string ReadText(BgraFrame image) => ReadLines(image, false).Text;

    public OcrReading ReadLines(BgraFrame image, bool deep)
    {
        Interlocked.Increment(ref Calls);
        return read(image);
    }
}

/// <summary>Okumaya girince haber verir, test bırakana kadar (en çok 10 sn) bekler.</summary>
sealed class BlockingReader(string text) : ITextReader
{
    public ManualResetEventSlim Entered { get; } = new();
    public ManualResetEventSlim Release { get; } = new();

    public string ReadText(BgraFrame image)
    {
        Entered.Set();
        Release.Wait(TimeSpan.FromSeconds(10));
        return text;
    }
}

/// <summary>"TR: " + metin; istekleri kaydeder; istenirse hata ya da ilk N çağrıda zaman aşımı verir.</summary>
class FakeTranslator(ManualMsClock? clock = null, long advanceMs = 0) : ITranslator
{
    public ConcurrentQueue<string> Requests { get; } = new();
    public UnavailableReason? FailReason { get; set; }
    public int TimeoutsFirst { get; set; }
    public bool Pretranslates { get; set; }
    public List<string> Pretranslated { get; } = new();
    public Func<string, string>? Map { get; set; }
    public bool FromCache { get; set; }

    public string EngineName => "fake";
    public bool SupportsPretranslation => Pretranslates;
    public virtual bool SupportsBatch => false;

    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        lock (Pretranslated) Pretranslated.Add(text);
        return Task.CompletedTask;
    }

    public virtual Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        Requests.Enqueue(text);
        if (advanceMs > 0) clock!.Advance(advanceMs);
        if (FailReason is { } r) throw new TranslatorUnavailableException(r);
        if (TimeoutsFirst > 0 && Requests.Count <= TimeoutsFirst) throw new TimeoutException();
        if (FromCache) TranslationProbe.NoteCached();
        else TranslationProbe.NoteFresh("fake");
        return Task.FromResult(TranslationResult.FromEngine(Map?.Invoke(text) ?? "TR: " + text));
    }

    public virtual Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken cancellationToken = default) => this.TranslateOneByOneAsync(texts, cancellationToken);
}

/// <summary>Çevirileri test bırakana kadar bekletir (iptale uyar ya da uymaz).</summary>
sealed class PendingTranslator(bool honorsCancel = true) : ITranslator
{
    readonly object _lock = new();
    readonly List<(string Text, TaskCompletionSource<TranslationResult> Tcs)> _pending = [];
    bool _open;
    public List<string> Requests { get; } = new();
    public int CancelRequested;
    public Func<string, Exception?>? FailWith { get; set; }

    /// <summary>Çeviriyi üretir (varsayılanı "TR: " + metin).</summary>
    public Func<string, string>? Map { get; set; }

    public string EngineName => "pending";
    public bool SupportsPretranslation => false;
    public bool SupportsBatch => false;
    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
        this.TranslateOneByOneAsync(texts, cancellationToken);

    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellation = default)
    {
        var tcs = new TaskCompletionSource<TranslationResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_lock)
        {
            Requests.Add(text);
            if (_open)
            {
                Complete(text, tcs);
                return tcs.Task;
            }
            _pending.Add((text, tcs));
        }
        cancellation.Register(() =>
        {
            Interlocked.Increment(ref CancelRequested);
            if (honorsCancel) tcs.TrySetCanceled();
        });
        return tcs.Task;
    }

    void Complete(string text, TaskCompletionSource<TranslationResult> tcs)
    {
        if (FailWith?.Invoke(text) is { } e) tcs.TrySetException(e);
        else tcs.TrySetResult(TranslationResult.FromEngine(Map?.Invoke(text) ?? "TR: " + text));
    }

    /// <summary>En eski bekleyeni bırakır.</summary>
    public void ReleaseNext()
    {
        (string Text, TaskCompletionSource<TranslationResult> Tcs) item;
        lock (_lock)
        {
            while (_pending.Count > 0 && _pending[0].Tcs.Task.IsCompleted) _pending.RemoveAt(0);
            if (_pending.Count == 0) return;
            item = _pending[0];
            _pending.RemoveAt(0);
        }
        Complete(item.Text, item.Tcs);
    }

    public int PendingCount
    {
        get { lock (_lock) return _pending.Count(p => !p.Tcs.Task.IsCompleted); }
    }

    /// <summary>Hepsini bırakır; sonra gelenler beklemez.</summary>
    public void Open()
    {
        List<(string, TaskCompletionSource<TranslationResult>)> all;
        lock (_lock)
        {
            _open = true;
            all = [.. _pending];
            _pending.Clear();
        }
        foreach (var (t, tcs) in all) Complete(t, tcs);
    }
}

/// <summary>TV'ye gidenleri kaydeder.</summary>
sealed class FakeOutput : ISubtitleOutput
{
    readonly object _lock = new();
    public List<SubtitleShow> Shows { get; } = [];
    public int Clears;
    public List<string> Texts { get { lock (_lock) return Shows.Select(s => s.Text).ToList(); } }

    public void ShowSubtitle(SubtitleShow show)
    {
        lock (_lock) Shows.Add(show);
    }

    public void ClearSubtitle() => Interlocked.Increment(ref Clears);

    public List<(string Id, string Text, Box? Box, double? Line)> Regions { get; } = [];
    public int RegionClears;
    public List<(IReadOnlyList<ScreenItem> Items, int Duration)> Screens { get; } = [];
    public int ScreenClears;

    public void ShowRegion(string id, string text, Box? box, double? lineHeight)
    {
        lock (_lock) Regions.Add((id, text, box, lineHeight));
    }

    public void ClearRegions() => Interlocked.Increment(ref RegionClears);

    public void ShowScreen(IReadOnlyList<ScreenItem> items, int durationMs, bool overlay)
    {
        lock (_lock) Screens.Add((items, durationMs));
    }

    public void ClearScreen() => Interlocked.Increment(ref ScreenClears);
}

/// <summary>Anahtarı (sadeleştirilmiş metin) verilen satırlar.</summary>
sealed class FakePack(string? name = null) : ISubtitlePackLookup
{
    readonly ConcurrentDictionary<string, string> _lines = new();

    public FakePack Add(string text, string translation)
    {
        _lines[TextKey.Of(text)] = translation;
        return this;
    }

    public PackMatch? Find(string text) =>
        _lines.TryGetValue(TextKey.Of(text), out var t) ? new PackMatch(t, name is null ? null : "pack-" + name, name) : null;
}

/// <summary>Hat testlerinin ortak düzeni: 64 × 64 boş kare, varsayılan bölge.</summary>
sealed class Harness
{
    public static readonly Box DefaultArea = new(0.14, 0.62, 0.86, 0.97);
    public static readonly BgraFrame Blank = BgraFrame.Blank(64, 64);

    public ManualMsClock Clock { get; }
    public FakeOutput Output { get; } = new();
    public SubtitlePipeline Pipeline { get; }
    public List<string> Log { get; } = [];
    public List<ShownPair> Pairs { get; } = [];
    public List<string> NotInPack { get; } = [];
    public List<SubtitleMetrics> Metrics { get; } = [];
    public List<(bool Ok, UnavailableReason? Status)> Results { get; } = [];

    public Harness(ITextReader reader, ITranslator translator, ManualMsClock? clock = null,
        Func<SubtitlePipelineOptions, SubtitlePipelineOptions>? configure = null, ISubtitlePackLookup? pack = null,
        bool holdWithoutPack = false)
    {
        ThreadPool.SetMinThreads(32, 32);
        Clock = clock ?? new ManualMsClock();
        var options = new SubtitlePipelineOptions
        {
            Pack = pack,
            HoldWithoutPack = holdWithoutPack,
            Log = line => { lock (Log) Log.Add(line); },
        };
        if (configure is not null) options = configure(options);
        Pipeline = new SubtitlePipeline(reader, translator, Output, Clock, options);
        Pipeline.PairShown += p => { lock (Pairs) Pairs.Add(p); };
        Pipeline.NotInPack += s => { lock (NotInPack) NotInPack.Add(s); };
        Pipeline.MetricsReady += m => { lock (Metrics) Metrics.Add(m); };
        Pipeline.TranslationFinished += (ok, s) => { lock (Results) Results.Add((ok, s)); };
    }

    /// <summary>Bir kare: işlenir, (istenirse) çeviriler beklenir, saat ilerler.</summary>
    public async Task Frame(long advanceAfter = 50, bool waitTranslations = true, Box? area = null, BgraFrame? frame = null,
        long? arrivedAt = null)
    {
        await Pipeline.ProcessFrameAsync(frame ?? Blank, area ?? DefaultArea, arrivedAt);
        if (waitTranslations) await WaitAll();
        Clock.Advance(advanceAfter);
    }

    public async Task Frames(int count, long advanceAfter = 50, bool waitTranslations = true)
    {
        for (var i = 0; i < count; i++) await Frame(advanceAfter, waitTranslations);
    }

    public async Task WaitAll()
    {
        var wait = Pipeline.WaitForTranslationsAsync();
        if (await Task.WhenAny(wait, Task.Delay(TimeSpan.FromSeconds(30))) != wait)
            throw new TimeoutException("çeviriler bitmedi");
    }
}

/// <summary>Metin dizisini sırayla veren, gerektiğinde yeni metin eklenen okuyucu kısayolu.</summary>
static class Script
{
    public static string[] Repeat(string text, int count) => Enumerable.Repeat(text, count).ToArray();

    public static string[] Of(params object[] parts) =>
        parts.SelectMany(p => p is string s ? [s] : (string[])p).ToArray();
}
