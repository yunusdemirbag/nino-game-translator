// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Logging;
using Nino.Core.Translation;

namespace Nino.Translation.Online;

/// <summary>
/// Yapay zekâ çevirmeni: Gemini, OpenAI, Claude ya da yerel model (çeviri tarifi §12). Eksik cümleler tek istekte
/// JSON dizisi olarak gider; "ekranı çevir" metinleri 40'lık parçalarla gerçekten toplu gider.
/// </summary>
public sealed class AiTranslator : ITranslator, IOnlineEngineStatus
{
    /// <summary>Bağlamda tutulan satır sayısı.</summary>
    public const int ContextSize = 3;

    /// <summary>Tam ekran çevirisinin parça boyu.</summary>
    public const int ScreenChunk = 40;

    /// <summary>Dakikalık sınırdaki en uzun bekleme.</summary>
    public static readonly TimeSpan MaxMinuteWait = TimeSpan.FromSeconds(20);

    readonly AiService _service;
    readonly string _model;
    readonly string _apiKey;
    readonly string _target;
    readonly ITranslator? _fallback;
    readonly TranslationCache _cache;
    readonly HttpClient _http;
    readonly Func<string?> _gameName;
    readonly LocalServer? _local;
    readonly RequestBudget? _budget;
    readonly OnlineHealth _health;
    readonly object _gate = new();
    readonly List<ContextLine> _shown = [];
    readonly HashSet<string> _learned = new(StringComparer.Ordinal);

    public AiTranslator(AiService service, string model, string apiKey, string target, ITranslator? fallback,
        TranslationCache cache, HttpClient http, Func<string?>? gameName = null, LocalServer? local = null,
        RequestBudget? budget = null, TimeProvider? clock = null)
    {
        _service = service;
        _local = service == AiService.Local ? local ?? new LocalServer(LocalServer.OllamaUrl, model) : null;
        _model = service == AiService.Local
            ? _local!.Model
            : AiModelCatalog.Default.Resolve(service, model)?.Id ?? model;
        _apiKey = apiKey.Trim();
        _target = TargetLanguages.Code(target);
        _fallback = fallback;
        _cache = cache;
        _http = http;
        _gameName = gameName ?? (() => null);
        _budget = budget;
        _health = new OnlineHealth(clock ?? TimeProvider.System);
        _health.Changed += f => FailureChanged?.Invoke(f);
        LineTimeout = TimeSpan.FromSeconds(service == AiService.Local ? 15 : 5);
        ScreenTimeout = TimeSpan.FromSeconds(service == AiService.Local ? 90 : 30);
    }

    /// <summary>Kullanılan model.</summary>
    public string Model => _model;

    /// <summary>Altyazı isteğinin zaman aşımı (bulut 5 sn, yerel 15 sn).</summary>
    public TimeSpan LineTimeout { get; set; }

    /// <summary>Tam ekran çevirisi isteğinin zaman aşımı (bulut 30 sn, yerel 90 sn).</summary>
    public TimeSpan ScreenTimeout { get; set; }

    /// <inheritdoc />
    public string EngineName => _local?.EngineName ?? EngineNames.Cloud(_service, _model);

    /// <inheritdoc />
    public bool SupportsPretranslation => true;

    /// <inheritdoc />
    public bool SupportsBatch => true;

    /// <inheritdoc />
    public OnlineFailure? LastFailure => _health.Last;

    /// <inheritdoc />
    public bool LastLineHitMinuteLimit => _health.MinuteLimited;

    /// <inheritdoc />
    public event Action<OnlineFailure?>? FailureChanged;

    static string Key(string? game, string text) => string.IsNullOrEmpty(game) ? text : game + "\u001F" + text;

    ITranslator Fallback => _fallback ?? throw new TranslatorUnavailableException(UnavailableReason.DownloadRequired);

    /// <inheritdoc />
    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
        TranslateLineAsync(text, record: true, cancellationToken);

    /// <inheritdoc />
    public async Task PretranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        try { await TranslateLineAsync(text, record: false, cancellationToken).ConfigureAwait(false); }
        catch { }
    }

    async Task<TranslationResult> TranslateLineAsync(string text, bool record, CancellationToken cancellationToken)
    {
        var game = _gameName()?.Trim();
        List<ContextLine> context;
        int slot;
        lock (_gate)
        {
            context = _shown.ToList();
            slot = -1;
            if (record)
            {
                if (_shown.Count > 0 && _shown[^1].Source == text) context.RemoveAt(context.Count - 1);
                else
                {
                    _shown.Add(new ContextLine(text, null));
                    if (_shown.Count > ContextSize) _shown.RemoveAt(0);
                }
                slot = _shown.Count - 1;
            }
        }

        var result = await TranslateCoreAsync(text, game, context, cancellationToken).ConfigureAwait(false);
        if (record)
            lock (_gate)
                if (slot >= 0 && slot < _shown.Count && _shown[slot].Source == text)
                    _shown[slot] = new ContextLine(text, result);
        return TranslationResult.FromEngine(result);
    }

    async Task<string> TranslateCoreAsync(string text, string? game, IReadOnlyList<ContextLine> context,
        CancellationToken cancellationToken)
    {
        _health.MinuteLimited = false;
        if (_cache.TryGet(Key(game, text), out var whole))
        {
            TranslationProbe.NoteCached();
            return whole;
        }

        var pieces = SubtitleSplitter.Split(text);
        HashSet<string> known;
        lock (_gate)
        {
            foreach (var label in SubtitleSplitter.LabelNames(pieces))
                foreach (var w in label.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                    if (w.Length >= 2) _learned.Add(w.ToLowerInvariant());
            known = new HashSet<string>(_learned, StringComparer.Ordinal);
        }

        var parts = pieces.Select(p => p.Text).ToArray();
        var missing = new List<int>();
        for (var i = 0; i < pieces.Count; i++)
        {
            if (!pieces[i].Translatable) continue;
            if (_cache.TryGet(Key(game, pieces[i].Text), out var cached))
            {
                TranslationProbe.NoteCached();
                parts[i] = cached;
            }
            else missing.Add(i);
        }
        if (missing.Count == 0) return string.Concat(parts);

        if (_health.Paused)
        {
            if (_health.PausedForMinute) _health.MinuteLimited = true;
            return await FallbackLineAsync(text, cancellationToken).ConfigureAwait(false);
        }
        if (_budget is not null && !_budget.TryAcquire())
        {
            _health.MinuteLimited = true;
            return await FallbackLineAsync(text, cancellationToken).ConfigureAwait(false);
        }

        var sentences = missing.Select(i => CapsNormalizer.Normalize(pieces[i].Text, known)).ToList();
        IReadOnlyList<string> translated;
        try
        {
            translated = await RequestAsync(sentences, game, context, AiProtocol.SubtitleMaxTokens, LineTimeout, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OnlineRequestException e)
        {
            HandleFailure(e);
            return await FallbackLineAsync(text, cancellationToken).ConfigureAwait(false);
        }
        _health.Succeeded();

        var echoFallbackUsed = false;
        for (var k = 0; k < missing.Count; k++)
        {
            var i = missing[k];
            var source = pieces[i].Text;
            var translation = translated[k];
            if (EchoCheck.IsEcho(source, translation) && _fallback is not null)
            {
                string? alternative = null;
                try { alternative = (await _fallback.TranslateAsync(source, cancellationToken).ConfigureAwait(false)).Text; }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch { }
                if (alternative is not null && !EchoCheck.IsEcho(source, alternative))
                {
                    parts[i] = alternative;
                    echoFallbackUsed = true;
                    continue;
                }
            }
            parts[i] = translation;
            _cache.Store(Key(game, source), translation);
            TranslationProbe.NoteFresh(EngineName);
        }
        var line = string.Concat(parts);
        if (!echoFallbackUsed) _cache.Store(Key(game, text), line);
        return line;
    }

    void HandleFailure(OnlineRequestException e)
    {
        if (e.MinuteLimit is { } minute)
        {
            if (minute.RequestLimit is { } limit) _budget?.Lower(limit);
            var wait = minute.RetryAfter is { } r && r < MaxMinuteWait ? r : MaxMinuteWait;
            if (wait < TimeSpan.FromSeconds(1)) wait = TimeSpan.FromSeconds(1);
            _health.MinuteLimited = true;
            _health.PauseFor(wait, minute: true);
            return;
        }
        _health.Failed(e.Failure);
    }

    async Task<string> FallbackLineAsync(string text, CancellationToken cancellationToken) =>
        (await Fallback.TranslateAsync(text, cancellationToken).ConfigureAwait(false)).Text;

    async Task<IReadOnlyList<string>> RequestAsync(IReadOnlyList<string> sentences, string? game,
        IReadOnlyList<ContextLine> context, int maxTokens, TimeSpan timeout, CancellationToken cancellationToken)
    {
        using var request = AiProtocol.BuildRequest(_service, _model, _apiKey, _target, sentences, game, context,
            maxTokens, _local);
        var (status, body) = await OnlineHttp.SendAsync(_http, request, timeout, cancellationToken).ConfigureAwait(false);
        if (!OnlineHttp.Success(status)) throw AiProtocol.Failure(status, body);
        var text = AiProtocol.ExtractText(_service, body);
        return AiProtocol.ParseList(text, sentences.Count);
    }

    /// <summary>Tam ekran çevirisi: bağımsız metinler 40'lık parçalarla, her parça tek istekte (§12.8).</summary>
    public async Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default)
    {
        var game = _gameName()?.Trim();
        var results = new string?[texts.Count];
        var missing = new List<int>();
        for (var i = 0; i < texts.Count; i++)
        {
            if (_cache.TryGet(Key(game, texts[i]), out var cached))
            {
                TranslationProbe.NoteCached();
                results[i] = cached;
            }
            else missing.Add(i);
        }

        var stop = _health.Paused;
        for (var start = 0; start < missing.Count && !stop; start += ScreenChunk)
        {
            var chunk = missing.Skip(start).Take(ScreenChunk).ToList();
            _health.MinuteLimited = false;
            _budget?.Count();
            try
            {
                var translated = await RequestAsync(chunk.Select(i => texts[i]).ToList(), game, [],
                    AiProtocol.ScreenMaxTokens, ScreenTimeout, cancellationToken).ConfigureAwait(false);
                _health.Succeeded();
                for (var k = 0; k < chunk.Count; k++)
                {
                    results[chunk[k]] = translated[k];
                    _cache.Store(Key(game, texts[chunk[k]]), translated[k]);
                    TranslationProbe.NoteFresh(EngineName);
                }
            }
            catch (OnlineRequestException e)
            {
                HandleFailure(e);
                stop = true;
            }
        }

        for (var i = 0; i < texts.Count; i++)
            results[i] ??= (await Fallback.TranslateAsync(texts[i], cancellationToken).ConfigureAwait(false)).Text;
        return results!;
    }
}
