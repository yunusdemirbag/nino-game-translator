// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Json.Nodes;
using Nino.Core.Data;

namespace Nino.Core.Diagnostics;

/// <summary>
/// Günlük sınırlar: kurulum başına günde en çok 5 bildirim, aynı kural günde en çok 2. Günler sunucuyla aynı biçimde
/// Türkiye saatiyle (UTC+3) sayılır. Dosya verilirse sayım yeniden açılışta korunur (<c>telemetry/diag-limits.json</c>).
/// İş parçacığı güvenli değildir; sahibi kilitler.
/// </summary>
public sealed class DiagDailyLimits
{
    /// <summary>Dosya adı.</summary>
    public const string FileName = "diag-limits.json";

    /// <summary>Günde en çok bildirim.</summary>
    public const int PerDay = 5;

    /// <summary>Aynı kural günde en çok.</summary>
    public const int PerRuleDay = 2;

    static readonly TimeSpan DayOffset = TimeSpan.FromHours(3);

    readonly string? _path;
    readonly Dictionary<string, int> _rules = new(StringComparer.Ordinal);
    string _day = "";

    /// <param name="path">Sayım dosyası; null ise yalnız bellekte.</param>
    public DiagDailyLimits(string? path)
    {
        _path = path;
        Load();
    }

    static string DayOf(DateTimeOffset at) => (at.ToUniversalTime() + DayOffset).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    /// <summary>Bu kural bugün gönderilebilir mi.</summary>
    public bool Allows(string rule, DateTimeOffset now)
    {
        Roll(now);
        return _rules.Values.Sum() < PerDay && _rules.GetValueOrDefault(rule) < PerRuleDay;
    }

    /// <summary>Gönderilen bildirimi sayar.</summary>
    public void Count(string rule, DateTimeOffset now)
    {
        Roll(now);
        _rules[rule] = _rules.GetValueOrDefault(rule) + 1;
        Save();
    }

    void Roll(DateTimeOffset now)
    {
        var day = DayOf(now);
        if (day == _day) return;
        _day = day;
        _rules.Clear();
    }

    void Load()
    {
        if (_path is null) return;
        try
        {
            if (!File.Exists(_path) || JsonNode.Parse(File.ReadAllText(_path, FileIo.Utf8)) is not JsonObject root) return;
            _day = root["day"] is JsonValue d && d.TryGetValue<string>(out var day) ? day : "";
            if (root["rules"] is JsonObject rules)
                foreach (var (k, v) in rules)
                    if (DiagPayload.IsRule(k) && v is JsonValue n && n.TryGetValue<int>(out var count) && count > 0)
                        _rules[k] = count;
        }
        catch (Exception e) when (FileIo.IsIoError(e) || e is System.Text.Json.JsonException or InvalidOperationException
                                      or FormatException)
        {
            _day = "";
            _rules.Clear();
        }
    }

    void Save()
    {
        if (_path is null) return;
        var rules = new JsonObject();
        foreach (var (k, v) in _rules) rules[k] = v;
        try { FileIo.WriteAtomic(_path, new JsonObject { ["day"] = _day, ["rules"] = rules }.ToJsonString()); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }
}
