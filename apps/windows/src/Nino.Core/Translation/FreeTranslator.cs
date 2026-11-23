// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Logging;

namespace Nino.Core.Translation;

/// <summary>Cihaz içi model (OPUS-MT): tek cümleyi çevirir. Süreç kapanması gibi kalıcı hatalarda <see cref="IOException"/>.</summary>
public interface ISentenceEngine : IDisposable
{
    /// <summary>Tek cümleyi çevirir (çağıran iş parçacığında, eşzamanlı).</summary>
    string Translate(string sentence,
        CancellationToken cancellationToken);
}

/// <summary>Bir hedef dilin modeli: kurulu mu, aç.</summary>
public interface ISentenceEngineSource
{
    /// <summary>Model dosyaları yerinde mi.</summary>
    bool IsInstalled { get; }

    /// <summary>Motoru açar; açılamazsa hata fırlatır (çalışma zamanı eksikse <see cref="FileNotFoundException"/>).</summary>
    ISentenceEngine Open(CancellationToken cancellationToken);
}

/// <summary>Ücretsiz çevirmenin durumu.</summary>
public enum FreeTranslatorState { Ready, DownloadRequired, EngineFailed }

/// <summary>
/// Ücretsiz (OPUS-MT) çevirmen (çeviri tarifi §7): kalıcı önbellek, tek seferde tek cümle, kısa satır bağlamı,
/// sözlük, Türkçe kuralları. Motor ilk çeviride açılır; açılamazsa kalıcı olarak "motor açılamadı" olur.
/// </summary>
public sealed class FreeTranslator : ITranslator, IDisposable
{
    /// <summary>Metin hattı sürümü (kurallar değişince artar; eski çeviriler yeniden çevrilir).</summary>
    public const int PipelineVersion = 3;

    /// <summary>Motor adı.</summary>
    public const string Name = "opus-mt-ct2-p3";

    readonly ISentenceEngineSource _source;
    readonly TranslationCache _cache;
    readonly Func<Glossary> _glossary;
    readonly FreeTextPipeline _pipeline;
    readonly ShortLineContext _lastLine;
    readonly SemaphoreSlim _lock = new(1, 1);
    readonly HashSet<string> _learnedNames = new(StringComparer.Ordinal);
    readonly object _namesGate = new();
    ISentenceEngine? _engine;
    Exception? _failure;
    int _failureReported;
    bool _closed;

    /// <param name="source">Model kaynağı.</param>
    /// <param name="target">Hedef dil.</param>
    /// <param name="cache">Kalıcı önbellek (<see cref="TranslationCache.For"/> ile <see cref="Name"/>).</param>
    /// <param name="glossary">Şu anki sözlük (yalnız <c>tr</c>; null: boş).</param>
    /// <param name="clock">Kısa satır bağlamı için saat.</param>
    public FreeTranslator(ISentenceEngineSource source, string target, TranslationCache cache,
        Func<Glossary>? glossary = null, TimeProvider? clock = null)
    {
        _source = source;
        Target = TargetLanguages.Code(target);
        _cache = cache;
        _pipeline = new FreeTextPipeline(Target);
        _glossary = _pipeline.IsTurkish && glossary is not null ? glossary : () => Glossary.Empty;
        _lastLine = new ShortLineContext(clock);
    }

    /// <summary>Hedef dil kodu.</summary>
    public string Target { get; }

    /// <inheritdoc />
    public string EngineName => Name;

    /// <inheritdoc />
    public bool SupportsPretranslation => false;

    /// <inheritdoc />
    public bool SupportsBatch => false;

    /// <summary>Motor açılamadı (bir kez; herhangi bir iş parçacığından).</summary>
    public event Action<Exception>?
        EngineFailed;

    /// <summary>Durum.</summary>
    public FreeTranslatorState State =>
        _failure is not null ? FreeTranslatorState.EngineFailed
        : _engine is not null || _source.IsInstalled ? FreeTranslatorState.Ready
        : FreeTranslatorState.DownloadRequired;

    /// <summary>Motorun açılamama nedeni (yoksa null).</summary>
    public Exception? Failure => _failure;

    /// <summary>
    /// Arka planda <c>Hello.</c> cümlesini (bağlamsız; son satır kaydına dokunmadan) çevirerek ısıtır; hata bırakmaz.
    /// </summary>
    public Task WarmUpAsync() => Task.Run(async () =>
    {
        try
        {
            var glossary = _glossary();
            await TranslateSentenceAsync("Hello.", null, glossary, new HashSet<string>(StringComparer.Ordinal),
                CancellationToken.None).ConfigureAwait(false);
        }
        catch { }
    });

    /// <inheritdoc />
    public async Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        var context = _lastLine.ContextFor(text);
        var pieces = SubtitleSplitter.Split(text);
        HashSet<string> known;
        lock (_namesGate)
        {
            foreach (var label in SubtitleSplitter.LabelNames(pieces))
                foreach (var word in label.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                    if (word.Length >= 2) _learnedNames.Add(word.ToLowerInvariant());
            known = new HashSet<string>(_learnedNames, StringComparer.Ordinal);
        }
        var glossary = _glossary();
        if (_pipeline.IsTurkish) known.UnionWith(glossary.KeepUpperWords);

        string? previous = null;
        if (context is not null)
            previous = SubtitleSplitter.Split(context).Where(p => p.Translatable).Select(p => p.Text).LastOrDefault();

        var translations = new List<string>();
        var indexes = new List<int>();
        for (var i = 0; i < pieces.Count; i++)
        {
            var piece = pieces[i];
            if (!piece.Translatable) continue;
            var sentenceContext = _pipeline.IsTurkish && ShortLineContext.IsShort(piece.Text) ? previous : null;
            translations.Add(await TranslateSentenceAsync(piece.Text, sentenceContext, glossary, known,
                cancellationToken).ConfigureAwait(false));
            indexes.Add(i);
            previous = piece.Text;
        }
        IReadOnlyList<string> final = _pipeline.IsTurkish ? TurkishPolish.UnifyAddress(translations) : translations;
        var parts = pieces.Select(p => p.Text).ToArray();
        for (var k = 0; k < indexes.Count; k++) parts[indexes[k]] = final[k];
        return TranslationResult.FromEngine(string.Concat(parts));
    }

    async Task<string> TranslateSentenceAsync(string sentence, string? context, Glossary glossary,
        IReadOnlySet<string> known, CancellationToken cancellationToken)
    {
        var key = _pipeline.CacheKey(sentence, context, glossary);
        if (_cache.TryGet(key, out var cached))
        {
            TranslationProbe.NoteCached();
            return cached;
        }

        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_closed) throw new TranslatorUnavailableException(UnavailableReason.Closed);
            if (_cache.TryGet(key, out cached))
            {
                TranslationProbe.NoteCached();
                return cached;
            }
            if (_failure is not null) throw new TranslatorUnavailableException(UnavailableReason.EngineFailed, null, _failure);
            if (_engine is null)
            {
                if (!_source.IsInstalled) throw new TranslatorUnavailableException(UnavailableReason.DownloadRequired);
                try { _engine = _source.Open(cancellationToken); }
                catch (OperationCanceledException) { throw; }
                catch (Exception e) { throw Fail(e); }
            }

            var engine = _engine;
            string result;
            try
            {
                result = await Task.Run(() => _pipeline.Translate(sentence, context, glossary, known,
                    s => engine.Translate(s, cancellationToken)), cancellationToken).ConfigureAwait(false);
            }
            catch (IOException e)
            {
                throw Fail(e);
            }
            _cache.Store(key, result);
            TranslationProbe.NoteFresh(Name);
            return result;
        }
        finally
        {
            _lock.Release();
        }
    }

    TranslatorUnavailableException Fail(Exception e)
    {
        _failure ??= e;
        try { _engine?.Dispose(); }
        catch { }
        _engine = null;
        if (Interlocked.Exchange(ref _failureReported, 1) == 0) EngineFailed?.Invoke(e);
        return new TranslatorUnavailableException(UnavailableReason.EngineFailed, null, e);
    }

    /// <inheritdoc />
    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

    /// <inheritdoc />
    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken cancellationToken = default) => this.TranslateOneByOneAsync(texts, cancellationToken);

    /// <summary>Motoru kapatır; sonra önbellekte olmayan çeviri "kapatıldı" hatası verir.</summary>
    public void Dispose()
    {
        _lock.Wait();
        try
        {
            _closed = true;
            _engine?.Dispose();
            _engine = null;
        }
        finally
        {
            _lock.Release();
        }
    }
}

/// <summary>Her çeviride aynı nedenle hata fırlatan çevirmen ("kullanılamaz").</summary>
public sealed class UnavailableTranslator(UnavailableReason reason, string engineName = FreeTranslator.Name) : ITranslator
{
    /// <summary>Neden.</summary>
    public UnavailableReason Reason => reason;

    /// <inheritdoc />
    public string EngineName => engineName;

    /// <inheritdoc />
    public bool SupportsPretranslation => false;

    /// <inheritdoc />
    public bool SupportsBatch => false;

    /// <inheritdoc />
    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
        Task.FromException<TranslationResult>(new TranslatorUnavailableException(reason));

    /// <inheritdoc />
    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

    /// <inheritdoc />
    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken cancellationToken = default) =>
        Task.FromException<IReadOnlyList<string>>(new TranslatorUnavailableException(reason));
}
