// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;

namespace Nino.Core.Diagnostics;

/// <summary>
/// Uzak ayar <c>telemetry.diag</c>: <c>{ "off": ["ocr.silent"], "limits": { "tr.slow.p90Ms": 4000 } }</c>.
/// Bilinmeyen anahtarlar yok sayılır; verilmeyen eşik varsayılanında kalır.
/// </summary>
public sealed class DiagConfig
{
    readonly HashSet<string> _off;
    readonly Dictionary<string, double> _limits;

    DiagConfig(HashSet<string> off, Dictionary<string, double> limits)
    {
        _off = off;
        _limits = limits;
    }

    /// <summary>Varsayılanlar (hiçbir kural kapalı değil).</summary>
    public static DiagConfig Default { get; } = new([], []);

    /// <summary>Kural kapalı mı.</summary>
    public bool IsOff(string rule) => _off.Contains(rule);

    /// <summary>Kapatılan kurallar.</summary>
    public IReadOnlyCollection<string> Off => _off;

    /// <summary>Eşiğin geçerli değeri.</summary>
    public double this[DiagLimit limit] => _limits.TryGetValue(limit.Key, out var v) ? v : limit.Default;

    /// <summary>Elle kurulum (testler, platform varsayılanı).</summary>
    public static DiagConfig Create(IEnumerable<string>? off = null, IReadOnlyDictionary<string, double>? limits = null)
    {
        var o = new HashSet<string>(StringComparer.Ordinal);
        foreach (var r in off ?? []) if (DiagPayload.IsRule(r)) o.Add(r);
        var l = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var (k, v) in limits ?? new Dictionary<string, double>())
            if (Find(k) is { } limit && Valid(limit, v) is { } value) l[limit.Key] = value;
        return new DiagConfig(o, l);
    }

    /// <summary>Bu ayarın üstüne bir platform varsayılanı (ör. telefonda bellek 800 MB) koyar; uzak değer önce gelir.</summary>
    public DiagConfig WithDefault(DiagLimit limit, double value)
    {
        if (_limits.ContainsKey(limit.Key) || Valid(limit, value) is not { } v) return this;
        return new DiagConfig(_off, new Dictionary<string, double>(_limits) { [limit.Key] = v });
    }

    /// <summary>
    /// Cevaptaki <c>telemetry.diag</c> bloğunu okur (kökte ya da <c>config</c> altında). Blok yoksa null (geçerli ayar
    /// korunur).
    /// </summary>
    public static DiagConfig? FromResponse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            if (JsonNode.Parse(json) is not JsonObject root) return null;
            var telemetry = root["telemetry"] as JsonObject ?? (root["config"] as JsonObject)?["telemetry"] as JsonObject;
            return telemetry?["diag"] is JsonObject diag ? FromJson(diag) : null;
        }
        catch (Exception e) when (e is System.Text.Json.JsonException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    /// <summary><c>diag</c> nesnesinden ayar.</summary>
    public static DiagConfig FromJson(JsonObject diag)
    {
        var off = new List<string>();
        if (diag["off"] is JsonArray list)
            foreach (var item in list)
                if (item is JsonValue v && v.TryGetValue<string>(out var s)) off.Add(s);
        var limits = new Dictionary<string, double>(StringComparer.Ordinal);
        if (diag["limits"] is JsonObject map)
            foreach (var (k, node) in map)
                if (DiagPayload.Number(node) is { } d) limits[k] = d;
        return Create(off, limits);
    }

    static DiagLimit? Find(string key) =>
        DiagLimitKeys.All.FirstOrDefault(l => l.Key == key || l.Alias == key);

    static double? Valid(DiagLimit limit, double value)
    {
        if (!double.IsFinite(value) || value <= 0 || value > 1e7) return null;
        if (limit == DiagLimitKeys.TrErrorRate && value > 1) value /= 100;
        return value > 1 && limit == DiagLimitKeys.TrErrorRate ? null : value;
    }
}
