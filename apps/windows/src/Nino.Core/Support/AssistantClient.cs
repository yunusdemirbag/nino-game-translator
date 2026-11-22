// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text.Json;
using Nino.Core.Data;

namespace Nino.Core.Support;

/// <summary>Sohbetteki bir mesajın sahibi.</summary>
public enum AssistantRole
{
    User,
    Assistant,
}

/// <summary>Sunucuya gidecek sohbet mesajı (Nino mesajında fotoğraf olmaz).</summary>
public sealed record AssistantMessage(AssistantRole Role, string Text, IReadOnlyList<byte[]>? Images = null)
{
    public static AssistantMessage User(string text, params byte[][] images) => new(AssistantRole.User, text, images);
    public static AssistantMessage Nino(string text) => new(AssistantRole.Assistant, text);
}

/// <summary>Nino'ya Sor isteğinin sabit alanları.</summary>
public sealed record AssistantContext
{
    public required string Install { get; init; }
    public required string App { get; init; }
    public string Platform { get; init; } = "windows";

    /// <summary>Arayüz dili kodu (sorun bildirme penceresinden farklı olarak çeviri dili değil).</summary>
    public required string Language { get; init; }

    /// <summary>Cihaz özeti (her mesajda yeniden alınır).</summary>
    public string? Device { get; init; }
}

/// <summary>Nino'ya Sor cevabının türü.</summary>
public enum AssistantOutcome
{
    Reply,
    Disabled,
    Busy,
    Limited,
    Rejected,
    Failed,
}

/// <summary>Cevap ya da hata.</summary>
public sealed record AssistantResult(AssistantOutcome Outcome, string? Reply = null, string? ReportId = null,
    TimeSpan? RetryAfter = null)
{
    public static AssistantResult Failed { get; } = new(AssistantOutcome.Failed);
}

/// <summary>Nino'ya Sor istek gövdesinin kurulması (§8.1 kuralları).</summary>
public static class AssistantPayload
{
    /// <summary>Eski fotoğraflı mesajın metnine eklenen işaret.</summary>
    public const string ScreenshotMarker = "[screenshot]";

    /// <summary>Gönderilecek hâline getirilmiş mesaj.</summary>
    public sealed record Prepared(AssistantRole Role, string Text, IReadOnlyList<byte[]> Images);

    /// <summary>
    /// Mesajları kurallara göre hazırlar. Boş metinliler (fotoğraflı kullanıcı mesajı hariç) atılır; hiç kalmazsa ya da
    /// son mesaj kullanıcınınki değilse null. Son 24 mesaj, baştaki Nino mesajları atılır; fotoğrafı en yeni 2
    /// fotoğraflı kullanıcı mesajı taşır (en çok 3), eskilerine <c>[screenshot]</c> eklenir; metin en çok 2000.
    /// </summary>
    public static IReadOnlyList<Prepared>? Prepare(IEnumerable<AssistantMessage> messages)
    {
        static byte[][] Photos(AssistantMessage m) =>
            m.Role == AssistantRole.User ? (m.Images ?? []).Where(i => i is { Length: > 0 }).ToArray() : [];

        var kept = messages
            .Where(m => (m.Text ?? "").Trim().Length > 0 || Photos(m).Length > 0)
            .ToList();
        if (kept.Count == 0 || kept[^1].Role != AssistantRole.User) return null;
        if (kept.Count > SupportLimits.AssistantMessages) kept = kept[^SupportLimits.AssistantMessages..];
        while (kept.Count > 0 && kept[0].Role == AssistantRole.Assistant) kept.RemoveAt(0);
        if (kept.Count == 0) return null;

        var carriers = new HashSet<int>();
        for (var i = kept.Count - 1; i >= 0 && carriers.Count < SupportLimits.AssistantPhotoMessages; i--)
            if (Photos(kept[i]).Length > 0) carriers.Add(i);

        var result = new List<Prepared>(kept.Count);
        for (var i = 0; i < kept.Count; i++)
        {
            var m = kept[i];
            var photos = Photos(m);
            var text = (m.Text ?? "").Trim();
            if (photos.Length > 0 && !carriers.Contains(i))
                result.Add(new Prepared(m.Role, WithMarker(text), []));
            else
                result.Add(new Prepared(m.Role, SupportLimits.Head(text, SupportLimits.AssistantText),
                    photos.Take(SupportLimits.Images).ToArray()));
        }
        return result;
    }

    /// <summary>Metne <c>[screenshot]</c> ekler (boşsa yalnız işaret); toplam 2000'i geçmez.</summary>
    public static string WithMarker(string text)
    {
        text = text.Trim();
        if (text.Length == 0) return ScreenshotMarker;
        var room = SupportLimits.AssistantText - ScreenshotMarker.Length - 1;
        return SupportLimits.Head(text, room) + " " + ScreenshotMarker;
    }

    /// <summary>
    /// Gövdenin JSON baytları; <paramref name="maxBytes"/>'ı aşarsa fotoğraf taşıyanların en eskisi metne indirilir,
    /// sığana ya da fotoğraflı kalmayana kadar. Mesajlar kurulamazsa null.
    /// </summary>
    public static byte[]? Build(AssistantContext context, IEnumerable<AssistantMessage> messages,
        int maxBytes = SupportLimits.AssistantBodyBytes)
    {
        if (Prepare(messages) is not { } prepared) return null;
        var list = prepared.ToList();
        while (true)
        {
            var json = Write(context, list);
            if (json.Length <= maxBytes) return json;
            var oldest = list.FindIndex(p => p.Images.Count > 0);
            if (oldest < 0) return json;
            list[oldest] = list[oldest] with { Text = WithMarker(list[oldest].Text), Images = [] };
        }
    }

    static byte[] Write(AssistantContext context, IReadOnlyList<Prepared> messages)
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms, SupportLimits.Writer))
        {
            w.WriteStartObject();
            w.WriteNumber("v", 1);
            w.WriteString("install", context.Install);
            w.WriteString("app", SupportLimits.Head((context.App ?? "").Trim(), SupportLimits.App));
            w.WriteString("platform", context.Platform);
            if (!string.IsNullOrEmpty(context.Language)) w.WriteString("language", context.Language);
            w.WriteStartArray("messages");
            foreach (var m in messages)
            {
                w.WriteStartObject();
                w.WriteString("role", m.Role == AssistantRole.User ? "user" : "assistant");
                w.WriteString("text", m.Text);
                if (m.Role == AssistantRole.User && m.Images.Count > 0)
                {
                    w.WriteStartArray("images");
                    foreach (var image in m.Images)
                    {
                        w.WriteStartObject();
                        w.WriteString("mime", "image/jpeg");
                        w.WriteString("data", Convert.ToBase64String(image));
                        w.WriteEndObject();
                    }
                    w.WriteEndArray();
                }
                w.WriteEndObject();
            }
            w.WriteEndArray();
            if (DeviceInfo.ForRequest(context.Device) is { } device) w.WriteString("device", device);
            w.WriteEndObject();
        }
        return ms.ToArray();
    }
}

/// <summary><c>POST /v1/assistant</c> istemcisi. İstisna fırlatmaz (yalnız dışarıdan iptal edilince).</summary>
public sealed class AssistantClient(HttpClient http, Uri? root, TimeProvider? clock = null)
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;

    /// <summary>Gövde sınırı (testler küçültür).</summary>
    public int MaxBodyBytes { get; init; } = SupportLimits.AssistantBodyBytes;

    /// <summary>Sohbeti gönderir.</summary>
    public async Task<AssistantResult> AskAsync(AssistantContext context, IEnumerable<AssistantMessage> messages,
        CancellationToken cancellationToken = default)
    {
        if (SupportEndpoints.For(root, SupportEndpoints.Assistant) is not { } uri) return AssistantResult.Failed;
        if (AssistantPayload.Build(context, messages, MaxBodyBytes) is not { } json) return AssistantResult.Failed;
        var reply = await SupportHttp.PostAsync(http, uri, json, _clock, cancellationToken).ConfigureAwait(false);
        return reply is null ? AssistantResult.Failed : Map(reply.Status, reply.Body, reply.RetryAfter);
    }

    /// <summary>Cevap eşlemesi (§8.2).</summary>
    internal static AssistantResult Map(HttpStatusCode status, byte[] body, TimeSpan? retryAfter)
    {
        string? error = null, text = null, report = null;
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                string? Str(string name) => doc.RootElement.TryGetProperty(name, out var p)
                                            && p.ValueKind == JsonValueKind.String ? p.GetString() : null;
                error = Str("error");
                text = Str("reply");
                report = Str("report");
            }
        }
        catch (JsonException) { }

        switch ((int)status)
        {
            case 200:
                var trimmed = text?.Trim();
                if (string.IsNullOrEmpty(trimmed)) return AssistantResult.Failed;
                var id = report?.Trim();
                return new AssistantResult(AssistantOutcome.Reply, trimmed, string.IsNullOrEmpty(id) ? null : id);
            case 503 when error == "assistant_disabled":
                return new AssistantResult(AssistantOutcome.Disabled);
            case 429 when error == "busy":
                return new AssistantResult(AssistantOutcome.Busy, RetryAfter: retryAfter);
            case 429:
                return new AssistantResult(AssistantOutcome.Limited, RetryAfter: retryAfter);
            case 400 or 413:
                return new AssistantResult(AssistantOutcome.Rejected);
            default:
                return AssistantResult.Failed;
        }
    }
}
