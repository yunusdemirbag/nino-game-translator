// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Logging;
using Nino.Core.Translation;

namespace Nino.Translation.Online;

/// <summary>
/// DeepL çevirmeni (çeviri tarifi §11): son 3 satır bağlam, Türkçede sözlük terimleri "çevirme" etiketiyle, hata
/// sonrası 60 sn bekleme ve yedek.
/// </summary>
public sealed class DeepLTranslator : ITranslator, IOnlineEngineStatus
{
    /// <summary>Bağlam satırı sayısı.</summary>
    public const int ContextSize = 3;

    readonly string _apiKey;
    readonly string _target;
    readonly ITranslator? _fallback;
    readonly TranslationCache _cache;
    readonly Func<Glossary> _glossary;
    readonly HttpClient _http;
    readonly OnlineHealth _health;
    readonly object _gate = new();
    readonly List<string> _shown = [];
    readonly HashSet<string> _learned = new(StringComparer.Ordinal);

    public DeepLTranslator(string apiKey, string target, ITranslator? fallback, TranslationCache cache,
        Func<Glossary>? glossary, HttpClient http, TimeProvider? clock = null)
    {
        _apiKey = apiKey.Trim();
        _target = TargetLanguages.Code(target).ToUpperInvariant();
        _fallback = fallback;
        _cache = cache;
        _glossary = _target == "TR" && glossary is not null ? glossary : () => Glossary.Empty;
        _http = http;
        _health = new OnlineHealth(clock ?? TimeProvider.System);
        _health.Changed += f => FailureChanged?.Invoke(f);
    }

    /// <summary>İstek zaman aşımı.</summary>
    public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(4);

    /// <summary>Anahtara göre temel adres.</summary>
    public static string BaseUrl(string apiKey) =>
        apiKey.Trim().EndsWith(":fx", StringComparison.Ordinal) ? "https://api-free.deepl.com/v2/" : "https://api.deepl.com/v2/";

    /// <inheritdoc />
    public string EngineName => EngineNames.DeepL;

    /// <inheritdoc />
    public bool SupportsPretranslation => true;

    /// <inheritdoc />
    public bool SupportsBatch => false;

    /// <inheritdoc />
    public OnlineFailure? LastFailure => _health.Last;

    /// <inheritdoc />
    public bool LastLineHitMinuteLimit => false;

    /// <inheritdoc />
    public event Action<OnlineFailure?>? FailureChanged;

    static string Key(Glossary glossary, string text) =>
        glossary.FindTerms(text).Count > 0 ? glossary.Fingerprint + "\u001F" + text : text;

    /// <inheritdoc />
    public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
        TranslateLineAsync(text, record: true, cancellationToken);

    /// <inheritdoc />
    public async Task PretranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        try { await TranslateLineAsync(text, record: false, cancellationToken).ConfigureAwait(false); }
        catch { }
    }

    /// <inheritdoc />
    public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) => this.TranslateOneByOneAsync(texts, cancellationToken);

    async Task<string> FallbackAsync(string text, CancellationToken cancellationToken)
    {
        if (_fallback is null) throw new TranslatorUnavailableException(UnavailableReason.DownloadRequired);
        return (await _fallback.TranslateAsync(text, cancellationToken).ConfigureAwait(false)).Text;
    }

    async Task<TranslationResult> TranslateLineAsync(string text, bool record, CancellationToken cancellationToken)
    {
        string? context;
        lock (_gate)
        {
            context = _shown.Count > 0 ? string.Join("\n", _shown) : null;
            if (record && (_shown.Count == 0 || _shown[^1] != text))
            {
                _shown.Add(text);
                if (_shown.Count > ContextSize) _shown.RemoveAt(0);
            }
        }

        var glossary = _glossary();
        var lineKey = Key(glossary, text);
        if (_cache.TryGet(lineKey, out var whole))
        {
            TranslationProbe.NoteCached();
            return TranslationResult.FromEngine(whole);
        }
        if (_health.Paused) return TranslationResult.FromEngine(await FallbackAsync(text, cancellationToken).ConfigureAwait(false));

        var pieces = SubtitleSplitter.Split(text);
        HashSet<string> known;
        lock (_gate)
        {
            foreach (var label in SubtitleSplitter.LabelNames(pieces))
                foreach (var w in label.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                    if (w.Length >= 2) _learned.Add(w.ToLowerInvariant());
            known = new HashSet<string>(_learned, StringComparer.Ordinal);
        }
        known.UnionWith(glossary.KeepUpperWords);

        var parts = pieces.Select(p => p.Text).ToArray();
        var missing = new List<int>();
        for (var i = 0; i < pieces.Count; i++)
        {
            if (!pieces[i].Translatable) continue;
            if (_cache.TryGet(Key(glossary, pieces[i].Text), out var cached))
            {
                TranslationProbe.NoteCached();
                parts[i] = cached;
            }
            else missing.Add(i);
        }

        if (missing.Count > 0)
        {
            var prepared = missing.Select(i => CapsNormalizer.Normalize(pieces[i].Text, known)).ToList();
            var tagged = prepared.Select(p => Tag(p, glossary)).ToList();
            var useTags = tagged.Any(t => t.Tagged);
            var texts = tagged.Select((t, k) => useTags ? t.Text : prepared[k]).ToList();
            IReadOnlyList<string> translated;
            try
            {
                translated = await RequestAsync(texts, context, useTags, cancellationToken).ConfigureAwait(false);
            }
            catch (OnlineRequestException e)
            {
                _health.Failed(e.Failure);
                return TranslationResult.FromEngine(await FallbackAsync(text, cancellationToken).ConfigureAwait(false));
            }
            _health.Succeeded();
            for (var k = 0; k < missing.Count; k++)
            {
                var value = useTags ? Untag(translated[k]) : translated[k];
                parts[missing[k]] = value;
                _cache.Store(Key(glossary, pieces[missing[k]].Text), value);
                TranslationProbe.NoteFresh(EngineName);
            }
        }

        var line = string.Concat(parts);
        _cache.Store(lineKey, line);
        return TranslationResult.FromEngine(line);
    }

    static string Escape(string s) => s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    /// <summary>Terimleri <c>&lt;x&gt;Türkçe&lt;/x&gt;</c> ile etiketler; terim yoksa kaçışlanmış metin.</summary>
    internal static (string Text, bool Tagged) Tag(string text, Glossary glossary)
    {
        var matches = glossary.FindTerms(text);
        if (matches.Count == 0) return (Escape(text), false);
        var sb = new StringBuilder();
        var at = 0;
        foreach (var m in matches)
        {
            sb.Append(Escape(text[at..m.Index])).Append("<x>").Append(Escape(m.Term.Turkish)).Append("</x>");
            at = m.Index + m.Length;
        }
        sb.Append(Escape(text[at..]));
        return (sb.ToString(), true);
    }

    static string Untag(string s) =>
        s.Replace("<x>", "").Replace("</x>", "").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&amp;", "&");

    async Task<IReadOnlyList<string>> RequestAsync(IReadOnlyList<string> texts, string? context, bool tags,
        CancellationToken cancellationToken)
    {
        var body = OnlineHttp.Json(w =>
        {
            w.WriteStartObject();
            w.WriteStartArray("text");
            foreach (var t in texts) w.WriteStringValue(t);
            w.WriteEndArray();
            w.WriteString("source_lang", "EN");
            w.WriteString("target_lang", _target);
            if (context is not null) w.WriteString("context", context);
            if (_target == "TR") w.WriteString("formality", "prefer_less");
            w.WriteBoolean("preserve_formatting", true);
            if (tags)
            {
                w.WriteString("tag_handling", "xml");
                w.WriteStartArray("ignore_tags");
                w.WriteStringValue("x");
                w.WriteEndArray();
            }
            w.WriteEndObject();
        });
        using HttpRequestMessage request = new(HttpMethod.Post, BaseUrl(_apiKey) + "translate");
        request.Headers.TryAddWithoutValidation("Authorization", "DeepL-Auth-Key " + _apiKey);
        request.Content = OnlineHttp.JsonContent(body);
        var (status, response) = await OnlineHttp.SendAsync(_http, request, Timeout, cancellationToken).ConfigureAwait(false);
        if (!OnlineHttp.Success(status)) throw new OnlineRequestException(MapFailure(status));
        try
        {
            using var doc = JsonDocument.Parse(response);
            var list = doc.RootElement.GetProperty("translations");
            if (list.ValueKind != JsonValueKind.Array || list.GetArrayLength() != texts.Count)
                throw new OnlineRequestException(OnlineFailure.Unreachable);
            return list.EnumerateArray().Select(e => e.GetProperty("text").GetString() ?? "").ToList();
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw new OnlineRequestException(OnlineFailure.Unreachable);
        }
    }

    /// <summary>DeepL hata eşlemesi: 401/403 anahtar, 456 kota, gerisi ulaşılamadı.</summary>
    public static OnlineFailure MapFailure(HttpStatusCode status) => (int)status switch
    {
        401 or 403 => OnlineFailure.InvalidKey,
        456 => OnlineFailure.QuotaExhausted,
        _ => OnlineFailure.Unreachable,
    };

    /// <summary>Kullanım denetimi (ayarlardaki "Dene" ve anahtar kaydı, §11.5).</summary>
    public static async Task<DeepLUsageResult> CheckUsageAsync(string apiKey, HttpClient http, CancellationToken cancellationToken = default)
    {
        var key = apiKey.Trim();
        if (key.Length == 0) return new DeepLUsageResult(KeyCheckStatus.InvalidKey, null, null);
        using var request = new HttpRequestMessage(HttpMethod.Get, BaseUrl(key) + "usage");
        request.Headers.TryAddWithoutValidation("Authorization", "DeepL-Auth-Key " + key);
        try
        {
            var (status, body) = await OnlineHttp.SendAsync(http, request, TimeSpan.FromSeconds(4), cancellationToken)
                .ConfigureAwait(false);
            if (!OnlineHttp.Success(status))
                return new DeepLUsageResult(OnlineFailureText.ToStatus(MapFailure(status)), null, null);
            using var doc = JsonDocument.Parse(body);
            var used = doc.RootElement.GetProperty("character_count").GetInt64();
            var limit = doc.RootElement.GetProperty("character_limit").GetInt64();
            var state = limit > 0 && used >= limit ? KeyCheckStatus.QuotaExhausted : KeyCheckStatus.Valid;
            return new DeepLUsageResult(state, used, limit);
        }
        catch (OnlineRequestException)
        {
            return new DeepLUsageResult(KeyCheckStatus.Unreachable, null, null);
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
        {
            return new DeepLUsageResult(KeyCheckStatus.Unreachable, null, null);
        }
    }
}

/// <summary>Yapay zekâ anahtar denemesi (çeviri tarifi §12.9).</summary>
public static class AiKeyCheck
{
    /// <summary>Örnek satır (etiket çevrilmez, cümle çevrilir).</summary>
    public const string SampleLine = "BATMAN: I'm Batman.";

    /// <summary>
    /// Anahtarı örnek satırla dener. Ortak dakikalık hakkı yemez; yedeği her zaman başarısızdır. Yerel modelde 90 sn,
    /// bulutta 5 sn zaman aşımı.
    /// </summary>
    public static async Task<KeyCheckResult> RunAsync(AiService service, string model, string apiKey, string target,
        HttpClient http, LocalServer? local = null, CancellationToken cancellationToken = default)
    {
        var key = apiKey.Trim();
        if (service != AiService.Local && key.Length == 0) return new KeyCheckResult(KeyCheckStatus.InvalidKey, null);
        var translator = new AiTranslator(service, model, key, target, new FailingTranslator(),
            new TranslationCache(null), http, local: local)
        {
            LineTimeout = TimeSpan.FromSeconds(service == AiService.Local ? 90 : 5),
        };
        try
        {
            var result = await translator.TranslateAsync(SampleLine, cancellationToken).ConfigureAwait(false);
            return new KeyCheckResult(KeyCheckStatus.Valid, result.Text);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            if (translator.LastFailure is { } failure) return new KeyCheckResult(OnlineFailureText.ToStatus(failure), null);
            return new KeyCheckResult(
                translator.LastLineHitMinuteLimit ? KeyCheckStatus.QuotaExhausted : KeyCheckStatus.Unreachable, null);
        }
    }

    sealed class FailingTranslator : ITranslator
    {
        public string EngineName => "none";
        public bool SupportsPretranslation => false;
        public bool SupportsBatch => false;

        public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
            Task.FromException<TranslationResult>(new InvalidOperationException("deneme yedeği"));

        public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
            Task.FromException<IReadOnlyList<string>>(new InvalidOperationException("deneme yedeği"));
    }
}
