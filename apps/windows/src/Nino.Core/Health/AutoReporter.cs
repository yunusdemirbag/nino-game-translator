// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Support;

namespace Nino.Core.Health;

/// <summary>
/// Otomatik sorun bildirimi: günde en çok 3, gönderilemeyen bildirim dosyada bekler ve sonraki açılışta gider
/// (<c>otomatik-bildirim.json</c>: <c>Day</c>, <c>Sent</c>, <c>Pending</c>). Yol yoksa yalnız bellek.
/// </summary>
public sealed class AutoReporter
{
    /// <summary>Dosya adı (sağlık klasöründe).</summary>
    public const string FileName = "otomatik-bildirim.json";

    /// <summary>Günde en çok otomatik bildirim.</summary>
    public const int DailyLimit = 3;

    readonly string? _path;
    readonly Func<ReportBody, CancellationToken, Task<ReportResult>> _send;
    readonly TimeProvider _clock;
    readonly object _gate = new();
    string _day = "";
    int _sent;
    string? _pending;

    /// <param name="path">Dosya yolu; null ise yalnız bellek.</param>
    /// <param name="send">Bildirimi sunucuya gönderen işlev (denetleyicinin "sorun bildirimini gönder"i).</param>
    /// <param name="clock">Yerel gün için saat.</param>
    public AutoReporter(string? path, Func<ReportBody, CancellationToken, Task<ReportResult>> send,
        TimeProvider? clock = null)
    {
        _path = path;
        _send = send;
        _clock = clock ?? TimeProvider.System;
        Load();
    }

    /// <summary>Sağlık klasöründen kurar.</summary>
    public static AutoReporter InFolder(string? healthFolder, Func<ReportBody, CancellationToken, Task<ReportResult>> send,
        TimeProvider? clock = null) =>
        new(healthFolder is null ? null : Path.Combine(healthFolder, FileName), send, clock);

    /// <summary>Bekleyen bildirim var mı.</summary>
    public bool HasPending
    {
        get { lock (_gate) return _pending is not null; }
    }

    /// <summary>Bugün gönderilebilir mi.</summary>
    public bool CanSendToday
    {
        get { lock (_gate) return _day != Today() || _sent < DailyLimit; }
    }

    /// <summary>
    /// Otomatik bildirimi gönderir: tür <c>auto</c>, günlük/iletişim yok, fotoğraf yok. Bugünün hakkı bittiyse false.
    /// Gövde, ilk beklemeden önce dosyaya "bekleyen" olarak yazılır. Gönderildiyse true.
    /// </summary>
    public Task<bool> SendAsync(ReportBody body, CancellationToken cancellationToken = default)
    {
        var auto = body with { Kind = ReportBody.AutoKind, Log = null, Contact = null, Images = [] };
        var json = auto.ToJsonText();
        lock (_gate)
        {
            var today = Today();
            if (_day != today)
            {
                _day = today;
                _sent = 0;
            }
            if (_sent >= DailyLimit) return Task.FromResult(false);
            _sent++;
            _pending = json;
            Save();
        }
        return DeliverAsync(auto, json, cancellationToken);
    }

    /// <summary>Önceki açılıştan kalan bildirimi gönderir; yoksa false.</summary>
    public Task<bool> SendPendingAsync(CancellationToken cancellationToken = default)
    {
        string? json;
        lock (_gate) json = _pending;
        if (json is null) return Task.FromResult(false);
        ReportBody? body;
        try
        {
            using var doc = JsonDocument.Parse(json);
            body = ReportBody.Parse(doc.RootElement);
        }
        catch (JsonException) { body = null; }
        if (body is null)
        {
            lock (_gate)
            {
                if (_pending == json) _pending = null;
                Save();
            }
            return Task.FromResult(false);
        }
        return DeliverAsync(body, json, cancellationToken);
    }

    async Task<bool> DeliverAsync(ReportBody body, string json, CancellationToken cancellationToken)
    {
        ReportResult result;
        try
        {
            result = await _send(body, cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            result = ReportResult.Failed;
        }
        if (result.Status == ReportStatus.Failed) return false;
        lock (_gate)
        {
            if (_pending is not null && JsonEquals(_pending, json))
            {
                _pending = null;
                Save();
            }
        }
        return result.Status == ReportStatus.Sent;
    }

    string Today() => _clock.GetLocalNow().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    static bool JsonEquals(string a, string b)
    {
        if (a == b) return true;
        try
        {
            using var x = JsonDocument.Parse(a);
            using var y = JsonDocument.Parse(b);
            return JsonElement.DeepEquals(x.RootElement, y.RootElement);
        }
        catch (JsonException) { return false; }
    }

    void Load()
    {
        if (_path is null) return;
        try
        {
            if (!File.Exists(_path)) return;
            using var doc = JsonDocument.Parse(File.ReadAllText(_path, FileIo.Utf8));
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return;
            if (root.TryGetProperty("Day", out var d) && d.ValueKind == JsonValueKind.String) _day = d.GetString() ?? "";
            if (root.TryGetProperty("Sent", out var s) && s.ValueKind == JsonValueKind.Number && s.TryGetInt32(out var n))
                _sent = Math.Max(0, n);
            if (root.TryGetProperty("Pending", out var p) && p.ValueKind == JsonValueKind.Object)
                _pending = p.GetRawText();
        }
        catch (Exception e) when (e is JsonException || FileIo.IsIoError(e)) { }
    }

    // Kilit tutulurken çağrılır.
    void Save()
    {
        if (_path is null) return;
        try
        {
            // Dosya eski uygulamanın yazımıyla: .NET'in varsayılan kaçışı (ASCII dışı ve " < > & ' + → \uXXXX).
            using var ms = new MemoryStream();
            using (var w = new Utf8JsonWriter(ms, new JsonWriterOptions { Encoder = JavaScriptEncoder.Default }))
            {
                w.WriteStartObject();
                w.WriteString("Day", _day);
                w.WriteNumber("Sent", _sent);
                if (_pending is not null)
                {
                    w.WritePropertyName("Pending");
                    using var pending = JsonDocument.Parse(_pending);
                    pending.RootElement.WriteTo(w);
                }
                w.WriteEndObject();
            }
            FileIo.WriteAtomic(_path, ms.ToArray());
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }
}
