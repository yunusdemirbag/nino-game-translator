// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Nino.Core.Translation;

namespace Nino.Translation.Online;

/// <summary>Bağlamdaki bir satır: kaynak ve (biliniyorsa) gösterilen çevirisi.</summary>
public sealed record ContextLine(string Source, string? Translation);

/// <summary>Yapay zekâ isteğinin istemleri (çeviri tarifi §12.3).</summary>
public static class AiPrompts
{
    /// <summary>Sistem yönergesi (hedefe göre üç çeşit).</summary>
    public static string Instruction(string target)
    {
        var code = TargetLanguages.Code(target);
        if (code == "tr")
            return "Your job: turn English subtitles from a video game into Turkish as people actually speak it day to "
                + "day. Unless two characters are plainly being formal with each other, they use \"sen\", not \"siz\". "
                + "Leave character names, place names and speaker tags (for example VERA:) untouched, and keep every "
                + "line break where it is. Carry over the full meaning and the tone; add nothing and drop nothing. "
                + "Reply with the translation alone, with no comments, notes or surrounding quotes.";
        var language = TargetLanguages.EnglishName(code);
        var sb = new StringBuilder();
        if (code == "ar")
            sb.Append("Your job: turn English subtitles from a video game into Modern Standard Arabic that reads clearly "
                + "and naturally, like well-made Arabic subtitles for games. ");
        else
            sb.Append($"Your job: turn English subtitles from a video game into {language} that reads naturally, like "
                + $"well-made {language} subtitles for games. ");
        sb.Append("Lines must stay short and quick to read on screen; dialogue should sound like real speech. ");
        sb.Append("Names of characters and places and speaker tags stay exactly as written, in Latin script. ");
        sb.Append("Line breaks, meaning and tone all stay intact. ");
        if (code == "ar") sb.Append("Write Arabic punctuation marks (، ؟ ؛) and use Western digits. ");
        sb.Append("Controller button symbols (✕ ○ △ □, L1, R2 and the like) must not change. ");
        sb.Append("Reply with the translation alone.");
        return sb.ToString();
    }

    /// <summary>Kullanıcı iletisi; son satırı cümlelerin sıkışık JSON dizisidir.</summary>
    public static string UserMessage(IReadOnlyList<string> sentences, string target, string? game,
        IReadOnlyList<ContextLine> context)
    {
        var language = TargetLanguages.EnglishName(target);
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(game)) parts.Add("Game: " + game);
        if (context.Count > 0)
        {
            var sb = new StringBuilder("Earlier subtitles, included only as background; do not translate them again:");
            foreach (var line in context)
            {
                sb.Append("\nEnglish: ").Append(line.Source);
                if (line.Translation is not null) sb.Append('\n').Append(language).Append(": ").Append(line.Translation);
            }
            parts.Add(sb.ToString());
        }
        parts.Add($"Put each string of the JSON array below into {language}. Your whole reply must be one JSON array "
            + $"holding exactly {sentences.Count.ToString(CultureInfo.InvariantCulture)} {language} strings, kept in "
            + "the original order.\n"
            + JsonArray(sentences));
        return string.Join("\n\n", parts);
    }

    /// <summary>Sıkışık JSON dizisi (ASCII dışı kaçışsız).</summary>
    public static string JsonArray(IEnumerable<string> items) => OnlineHttp.Json(w =>
    {
        w.WriteStartArray();
        foreach (var s in items) w.WriteStringValue(s);
        w.WriteEndArray();
    });

    /// <summary>Çeviri modeli kalıbı (TranslateGemma ya da MiLMMT; üçüncü taraf biçimi).</summary>
    public static string TranslationModelPrompt(string model, string target, string text)
    {
        var language = TargetLanguages.EnglishName(target);
        if (model.Contains("milmmt", StringComparison.OrdinalIgnoreCase))
            return "Translate this from English to " + language + ":\nEnglish: " + text + "\n" + language + ":";
        var code = TargetLanguages.Code(target);
        return $"You are a professional English (en) to {language} ({code}) translator. Your goal is to accurately convey "
            + $"the meaning and nuances of the original English text while adhering to {language} grammar, vocabulary, "
            + $"and cultural sensitivities. Produce only the {language} translation, without any additional explanations "
            + $"or commentary. Please translate the following English text into {language}:\n\n\n{text}";
    }

    /// <summary>Çeviri modelinin mesajları (bağlamdaki çevirisi bilinen satırlar örnek konuşma olur).</summary>
    public static List<(string Role, string Content)> TranslationModelMessages(string model, string target,
        IReadOnlyList<string> sentences, IReadOnlyList<ContextLine> context)
    {
        var messages = new List<(string, string)>();
        foreach (var line in context)
        {
            if (line.Translation is null) continue;
            messages.Add(("user", TranslationModelPrompt(model, target, line.Source)));
            messages.Add(("assistant", line.Translation));
        }
        var text = string.Join("\n", sentences.Select(s => s.Replace('\n', ' ')));
        messages.Add(("user", TranslationModelPrompt(model, target, text)));
        return messages;
    }
}

/// <summary>İstek gövdeleri, yanıt okuma ve hata eşlemesi (çeviri tarifi §12.3–§12.5).</summary>
public static partial class AiProtocol
{
    /// <summary>Altyazıdaki çıktı sınırı.</summary>
    public const int SubtitleMaxTokens = 1024;

    /// <summary>Tam ekran çevirisindeki çıktı sınırı.</summary>
    public const int ScreenMaxTokens = 8192;

    /// <summary>Gemini'nin "bu satırı çevirmem" bitiş nedenleri (OTHER gibi belirsizler ulaşılamadı sayılır).</summary>
    static readonly HashSet<string> RefusalReasons =
        ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION", "IMAGE_SAFETY", "LANGUAGE"];

    /// <summary>Gemini'de süzgeci kapatılan güvenlik sınıfları.</summary>
    public static readonly IReadOnlyList<string> GeminiSafetyCategories =
    [
        "HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH", "HARM_CATEGORY_SEXUALLY_EXPLICIT",
        "HARM_CATEGORY_DANGEROUS_CONTENT",
    ];

    /// <summary>İsteği kurar.</summary>
    public static HttpRequestMessage BuildRequest(AiService service, string model, string apiKey, string target,
        IReadOnlyList<string> sentences, string? game, IReadOnlyList<ContextLine> context, int maxTokens,
        LocalServer? local)
    {
        var key = apiKey.Trim();
        var info = AiModelCatalog.Default.Resolve(service, model);
        var effort = info?.Id == model ? info.Effort : null;
        var thinking = info?.Id == model ? info.Thinking : null;
        HttpRequestMessage request;
        string body;
        switch (service)
        {
            case AiService.Gemini:
            {
                var instruction = AiPrompts.Instruction(target);
                var message = AiPrompts.UserMessage(sentences, target, game, context);
                request = new(HttpMethod.Post,
                    "https://generativelanguage.googleapis.com/v1beta/models/" + Uri.EscapeDataString(model) + ":generateContent");
                request.Headers.TryAddWithoutValidation("x-goog-api-key", key);
                body = OnlineHttp.Json(w =>
                {
                    w.WriteStartObject();
                    w.WriteStartObject("systemInstruction");
                    w.WriteStartArray("parts");
                    w.WriteStartObject();
                    w.WriteString("text", instruction);
                    w.WriteEndObject();
                    w.WriteEndArray();
                    w.WriteEndObject();
                    w.WriteStartArray("contents");
                    w.WriteStartObject();
                    w.WriteString("role", "user");
                    w.WriteStartArray("parts");
                    w.WriteStartObject();
                    w.WriteString("text", message);
                    w.WriteEndObject();
                    w.WriteEndArray();
                    w.WriteEndObject();
                    w.WriteEndArray();
                    w.WriteStartObject("generationConfig");
                    w.WriteNumber("maxOutputTokens", maxTokens);
                    if (thinking is not null)
                    {
                        w.WriteStartObject("thinkingConfig");
                        w.WriteString("thinkingLevel", thinking);
                        w.WriteEndObject();
                    }
                    w.WriteEndObject();
                    // Oyun diyaloğu küfür ve argo içerir: varsayılan güvenlik süzgeci satırı boş döndürüyordu (havuz
                    // sunucusu da süzgeci kapatır). Çeviri metni üretmez, var olan metni çevirir.
                    w.WriteStartArray("safetySettings");
                    foreach (var category in GeminiSafetyCategories)
                    {
                        w.WriteStartObject();
                        w.WriteString("category", category);
                        w.WriteString("threshold", "BLOCK_NONE");
                        w.WriteEndObject();
                    }
                    w.WriteEndArray();
                    w.WriteEndObject();
                });
                break;
            }
            case AiService.OpenAi:
            {
                var instruction = AiPrompts.Instruction(target);
                var message = AiPrompts.UserMessage(sentences, target, game, context);
                request = new(HttpMethod.Post, "https://api.openai.com/v1/chat/completions");
                request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + key);
                body = OnlineHttp.Json(w =>
                {
                    w.WriteStartObject();
                    w.WriteString("model", model);
                    w.WriteStartArray("messages");
                    Message(w, "developer", instruction);
                    Message(w, "user", message);
                    w.WriteEndArray();
                    w.WriteNumber("max_completion_tokens", maxTokens);
                    if (effort is not null) w.WriteString("reasoning_effort", effort);
                    w.WriteEndObject();
                });
                break;
            }
            case AiService.Claude:
            {
                var instruction = AiPrompts.Instruction(target);
                var message = AiPrompts.UserMessage(sentences, target, game, context);
                request = new(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
                request.Headers.TryAddWithoutValidation("x-api-key", key);
                request.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
                body = OnlineHttp.Json(w =>
                {
                    w.WriteStartObject();
                    w.WriteString("model", model);
                    w.WriteNumber("max_tokens", maxTokens);
                    w.WriteString("system", instruction);
                    w.WriteStartArray("messages");
                    Message(w, "user", message);
                    w.WriteEndArray();
                    if (effort is not null)
                    {
                        w.WriteStartObject("output_config");
                        w.WriteString("effort", effort);
                        w.WriteEndObject();
                    }
                    if (thinking is not null)
                    {
                        w.WriteStartObject("thinking");
                        w.WriteString("type", thinking);
                        w.WriteEndObject();
                    }
                    w.WriteEndObject();
                });
                break;
            }
            default:
            {
                var server = local ?? new LocalServer(LocalServer.OllamaUrl, model);
                List<(string Role, string Content)> messages = server.IsTranslationModel
                    ? AiPrompts.TranslationModelMessages(server.Model, target, sentences, context)
                    : [("system", AiPrompts.Instruction(target)), ("user", AiPrompts.UserMessage(sentences, target, game, context))];
                request = new(HttpMethod.Post, server.ChatUrl);
                if (key.Length > 0) request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + key);
                body = OnlineHttp.Json(w =>
                {
                    w.WriteStartObject();
                    w.WriteString("model", server.Model);
                    w.WriteStartArray("messages");
                    foreach (var (role, content) in messages) Message(w, role, content);
                    w.WriteEndArray();
                    w.WriteNumber("temperature", 0.2);
                    w.WriteNumber("max_tokens", maxTokens);
                    w.WriteBoolean("stream", false);
                    w.WriteEndObject();
                });
                break;
            }
        }
        request.Content = OnlineHttp.JsonContent(body);
        return request;
    }

    static void Message(Utf8JsonWriter w, string role, string content)
    {
        w.WriteStartObject();
        w.WriteString("role", role);
        w.WriteString("content", content);
        w.WriteEndObject();
    }

    static OnlineRequestException Unreachable() => new(OnlineFailure.Unreachable);

    /// <summary>Yanıttan modelin metnini çıkarır; yoksa "ulaşılamadı".</summary>
    public static string ExtractText(AiService service, string body)
    {
        string? text;
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            text = service switch
            {
                AiService.Gemini => Gemini(root),
                AiService.Claude => Claude(root),
                _ => Chat(root),
            };
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or IndexOutOfRangeException
                                      or KeyNotFoundException)
        {
            if (service == AiService.Gemini && GeminiRefusal(body) is { } reason) throw new OnlineLineRefusedException(reason);
            throw Unreachable();
        }
        if (string.IsNullOrWhiteSpace(text))
        {
            if (service == AiService.Gemini && GeminiRefusal(body) is { } reason) throw new OnlineLineRefusedException(reason);
            throw Unreachable();
        }
        return text;
    }

    /// <summary>
    /// Gemini satırı çevirmeyi reddettiyse nedeni (<c>promptFeedback.blockReason</c> ya da metinsiz adayın
    /// <c>finishReason</c>'ı: SAFETY, PROHIBITED_CONTENT, BLOCKLIST, RECITATION…; promptFeedback hep sayılır); değilse null.
    /// </summary>
    public static string? GeminiRefusal(string body)
    {
        try
        {
            using var doc = JsonDocument.Parse(body);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            if (root.TryGetProperty("promptFeedback", out var feedback) && feedback.ValueKind == JsonValueKind.Object
                && feedback.TryGetProperty("blockReason", out var block) && block.ValueKind == JsonValueKind.String)
                return block.GetString();
            if (root.TryGetProperty("candidates", out var candidates) && candidates.ValueKind == JsonValueKind.Array
                && candidates.GetArrayLength() > 0 && candidates[0].ValueKind == JsonValueKind.Object
                && candidates[0].TryGetProperty("finishReason", out var finish) && finish.ValueKind == JsonValueKind.String
                && finish.GetString() is { } reason && RefusalReasons.Contains(reason))
                return reason;
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    static string? Gemini(JsonElement root)
    {
        var parts = root.GetProperty("candidates")[0].GetProperty("content").GetProperty("parts");
        var sb = new StringBuilder();
        foreach (var part in parts.EnumerateArray())
        {
            if (part.TryGetProperty("thought", out var t) && t.ValueKind == JsonValueKind.True) continue;
            if (part.TryGetProperty("text", out var text)) sb.Append(text.GetString());
        }
        return sb.ToString();
    }

    static string? Claude(JsonElement root)
    {
        var sb = new StringBuilder();
        foreach (var block in root.GetProperty("content").EnumerateArray())
            if (block.TryGetProperty("type", out var type) && type.GetString() == "text")
                sb.Append(block.GetProperty("text").GetString());
        return sb.ToString();
    }

    static string? Chat(JsonElement root) =>
        root.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString();

    [GeneratedRegex(@"</?s>|<\|[A-Za-z0-9_]{1,32}\|>|</?(?:start_of_turn|end_of_turn|eos|bos|pad)>")]
    private static partial Regex ControlTokens();

    [GeneratedRegex(@",\s*\]$")]
    private static partial Regex TrailingComma();

    [GeneratedRegex(@"(?<=[.!?…""”])\s*,")]
    private static partial Regex CommaAfterSentence();

    static readonly char[] Quotes = ['"', '“', '”'];

    /// <summary>Metinden <paramref name="count"/> çeviri çıkarır (§12.4); tutmazsa "ulaşılamadı".</summary>
    public static IReadOnlyList<string> ParseList(string text, int count)
    {
        var t = text.Trim();
        var think = t.LastIndexOf("</think>", StringComparison.Ordinal);
        if (think >= 0) t = t[(think + "</think>".Length)..].Trim();
        t = ControlTokens().Replace(t, "").Trim();
        if (t.StartsWith("```", StringComparison.Ordinal))
        {
            var lines = t.Replace("\r\n", "\n").Split('\n').Skip(1)
                .Where(l => !l.TrimStart().StartsWith("```", StringComparison.Ordinal));
            t = string.Join("\n", lines).Trim();
        }

        var open = t.IndexOf('[');
        var close = t.LastIndexOf(']');
        if (open >= 0 && close > open)
        {
            var candidate = TrailingComma().Replace(t[open..(close + 1)], "]");
            try
            {
                using var doc = JsonDocument.Parse(candidate);
                if (doc.RootElement.ValueKind == JsonValueKind.Array
                    && doc.RootElement.EnumerateArray().All(e => e.ValueKind == JsonValueKind.String))
                {
                    var items = doc.RootElement.EnumerateArray().Select(e => e.GetString()!.Trim()).ToList();
                    if (items.Count != count) throw Unreachable();
                    return items;
                }
            }
            catch (JsonException) { }
        }

        if (t.Length >= 2 && t[0] == '[' && t[^1] == ']')
        {
            var inner = t[1..^1];
            IEnumerable<IEnumerable<string>> options = count == 1
                ? [[inner]]
                : [
                    inner.Replace("\r\n", "\n").Split('\n').Where(l => l.Trim().Length > 0),
                    CommaAfterSentence().Split(inner),
                    inner.Split(','),
                ];
            foreach (var option in options)
            {
                var items = option.Select(Clean).ToList();
                if (items.Count == count && items.All(i => i.Length > 0)) return items;
            }
        }

        if (count > 1)
        {
            var lines = t.Replace("\r\n", "\n").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
            if (lines.Count != count) throw Unreachable();
            return lines;
        }
        return [t.Trim(Quotes)];
    }

    static string Clean(string item)
    {
        var s = item.Trim();
        if (s.EndsWith(',')) s = s[..^1];
        return s.Trim().Trim(Quotes).Trim();
    }

    /// <summary>Dakikalık sınır yanıtı mı (yalnız 429; §12.5).</summary>
    public static MinuteLimit? ParseMinuteLimit(HttpStatusCode status, string body)
    {
        if ((int)status != 429 || string.IsNullOrWhiteSpace(body)) return null;
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty("error", out var error) || error.ValueKind != JsonValueKind.Object
                || !error.TryGetProperty("details", out var details) || details.ValueKind != JsonValueKind.Array)
                return null;
            var violations = new List<JsonElement>();
            foreach (var d in details.EnumerateArray())
                if (d.ValueKind == JsonValueKind.Object && d.TryGetProperty("violations", out var v)
                    && v.ValueKind == JsonValueKind.Array)
                    violations.AddRange(v.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Object));
            var ids = violations.Select(v => v.TryGetProperty("quotaId", out var q) && q.ValueKind == JsonValueKind.String
                ? q.GetString()!
                : null).ToList();
            var named = ids.Where(i => i is not null).Cast<string>().ToList();
            if (named.Any(i => i.Contains("PerDay", StringComparison.Ordinal))
                || !named.Any(i => i.Contains("PerMinute", StringComparison.Ordinal)))
                return null;

            TimeSpan? retry = null;
            foreach (var d in details.EnumerateArray())
            {
                if (d.ValueKind != JsonValueKind.Object || !d.TryGetProperty("retryDelay", out var r)
                    || r.ValueKind != JsonValueKind.String) continue;
                var s = r.GetString()!.Trim();
                if (s.EndsWith('s')) s = s[..^1];
                if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var sec))
                    retry = TimeSpan.FromSeconds(sec);
                break;
            }

            int? limit = null;
            for (var i = 0; i < violations.Count; i++)
            {
                if (ids[i] is not { } id || !id.Contains("Requests", StringComparison.Ordinal)) continue;
                if (violations[i].TryGetProperty("quotaValue", out var qv))
                {
                    double value = 0;
                    if (qv.ValueKind == JsonValueKind.Number) value = qv.GetDouble();
                    else if (qv.ValueKind == JsonValueKind.String)
                        double.TryParse(qv.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out value);
                    if (value > 0) limit = (int)Math.Min(value, int.MaxValue);
                }
                break;
            }
            return new MinuteLimit(retry, limit);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>Başarısız yanıtın hata türü (gövde yalnız eşleme için okunur).</summary>
    public static OnlineFailure MapFailure(HttpStatusCode status, string body)
    {
        var code = (int)status;
        var lower = (body ?? "").ToLowerInvariant();
        return code switch
        {
            401 or 403 => OnlineFailure.InvalidKey,
            402 or 429 => OnlineFailure.QuotaExhausted,
            400 when lower.Contains("api_key_invalid") || lower.Contains("api key not valid") => OnlineFailure.InvalidKey,
            400 when lower.Contains("credit balance") || lower.Contains("insufficient_quota") => OnlineFailure.QuotaExhausted,
            400 or 404 => OnlineFailure.ModelRejected,
            _ => OnlineFailure.Unreachable,
        };
    }

    /// <summary>Başarısız yanıttan istisna (dakikalık sınır önce).</summary>
    public static OnlineRequestException Failure(HttpStatusCode status, string body) =>
        ParseMinuteLimit(status, body) is { } minute
            ? new OnlineRequestException(OnlineFailure.QuotaExhausted, minute)
            : new OnlineRequestException(MapFailure(status, body));
}
