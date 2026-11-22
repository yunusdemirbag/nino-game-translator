// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;

namespace Nino.Core.Telemetry;

/// <summary>
/// Sabit kovalı süre histogramı (ms). Kova üst sınırları herkes için aynı; değer <c>v ≤ sınır</c> olan ilk kovaya
/// girer, 10 000 ms'den uzunlar son kovaya.
/// </summary>
public sealed class TimingHistogram
{
    /// <summary>Kova üst sınırları (son kova sınırsız).</summary>
    public static IReadOnlyList<long> Bounds { get; } =
        [5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000];

    /// <summary>Kova sayısı (19).</summary>
    public static int BucketCount => Bounds.Count + 1;

    readonly long[] _buckets = new long[BucketCount];

    /// <summary>Adet.</summary>
    public long Count { get; private set; }

    /// <summary>Toplam ms.</summary>
    public long Sum { get; private set; }

    /// <summary>En büyük ms.</summary>
    public long Max { get; private set; }

    /// <summary>Değerin kovası.</summary>
    public static int BucketOf(long ms)
    {
        for (var i = 0; i < Bounds.Count; i++)
            if (ms <= Bounds[i]) return i;
        return Bounds.Count;
    }

    /// <summary>Bir süre ekler (negatif 0 sayılır).</summary>
    public void Add(long ms)
    {
        ms = Math.Max(0, ms);
        _buckets[BucketOf(ms)]++;
        Count++;
        Sum += ms;
        if (ms > Max) Max = ms;
    }

    /// <summary><c>{"n","sum","max","h"}</c>; sondaki sıfır kovalar atılır.</summary>
    public JsonObject ToJson()
    {
        var last = Array.FindLastIndex(_buckets, b => b != 0);
        var h = new JsonArray();
        for (var i = 0; i <= last; i++) h.Add(_buckets[i]);
        return new JsonObject { ["n"] = Count, ["sum"] = Sum, ["max"] = Max, ["h"] = h };
    }
}

/// <summary>
/// Bir çeviri oturumunun süre ölçümleri (<c>session.h</c>). Satır başına olay gönderilmez; oturum bitince tek olayda
/// gider. Oturum başına en çok 24 ölçüm; geçersiz adlar atlanır. İş parçacığı güvenlidir.
/// </summary>
public sealed class SessionTimings
{
    /// <summary>Oturum başına en çok ölçüm adı.</summary>
    public const int MaxMetrics = 24;

    public const string Ocr = "ocr";
    public const string Cache = "tr.cache";
    public const string Pack = "tr.pack";
    public const string Pool = "tr.pool";
    public const string Provider = "tr.provider";
    public const string Total = "tr.total";
    public const string FirstFrame = "first_frame";
    public const string FirstSubtitle = "first_subtitle";

    /// <summary>Çevirmen adıyla ölçüm (<c>tr.provider:deepl</c>).</summary>
    public static string ProviderNamed(string provider) => Provider + ":" + provider;

    readonly object _gate = new();
    readonly Dictionary<string, TimingHistogram> _metrics = new(StringComparer.Ordinal);
    readonly List<string> _order = [];

    /// <summary>Bir süre ekler.</summary>
    public void Add(string metric, long ms)
    {
        if (!TelemetryText.IsMetricName(metric)) return;
        lock (_gate)
        {
            if (!_metrics.TryGetValue(metric, out var histogram))
            {
                if (_metrics.Count >= MaxMetrics) return;
                _metrics[metric] = histogram = new TimingHistogram();
                _order.Add(metric);
            }
            histogram.Add(ms);
        }
    }

    /// <summary>Bir süre ekler.</summary>
    public void Add(string metric, TimeSpan elapsed) => Add(metric, (long)elapsed.TotalMilliseconds);

    /// <summary>Hiç ölçüm yok mu.</summary>
    public bool IsEmpty
    {
        get { lock (_gate) return _metrics.Count == 0; }
    }

    /// <summary>Ad → histogram nesnesi (eklenme sırasıyla).</summary>
    public JsonObject ToJson()
    {
        lock (_gate)
        {
            var o = new JsonObject();
            foreach (var name in _order) o[name] = _metrics[name].ToJson();
            return o;
        }
    }
}
