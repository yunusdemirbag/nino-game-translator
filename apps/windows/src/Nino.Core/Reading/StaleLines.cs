// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Reading;

/// <summary>
/// Eski duran yazı süzgeci (okuma zinciri adım 12, Mac çekirdeğiyle aynı anlam): her satırın (metin anahtarıyla)
/// ekranda ilk görüldüğü an tutulur. Karede yeni bir satır (9 sn'den genç) varken 9 sn ve daha uzun süredir duran
/// satırlar atılır; ekranda yalnız eski satırlar varsa hiçbiri atılmaz. Bir satır bir okumada görünmezse anı unutulur
/// (yeniden görününce yeni sayılır). Platformdan bağımsızdır; iş parçacığı güvenlidir.
/// </summary>
public sealed class StaleLineFilter
{
    /// <summary>Eski sayılma sınırı (ms).</summary>
    public const long DefaultStaleMs = 9_000;

    readonly object _gate = new();
    Dictionary<string, long> _firstSeen = new(StringComparer.Ordinal);

    /// <summary>Eski sayılma sınırı (ms).</summary>
    public long StaleMs { get; init; } = DefaultStaleMs;

    /// <summary>Okumayı süzer ve ilk görülme anlarını günceller.</summary>
    public OcrReading Apply(OcrReading reading, long nowMs)
    {
        lock (_gate)
        {
            var seen = new Dictionary<string, long>(StringComparer.Ordinal);
            var ages = new long[reading.Lines.Count];
            for (var i = 0; i < reading.Lines.Count; i++)
            {
                var key = TextKey.Of(reading.Lines[i].Text);
                if (!seen.TryGetValue(key, out var first))
                {
                    first = _firstSeen.TryGetValue(key, out var known) ? known : nowMs;
                    seen[key] = first;
                }
                ages[i] = nowMs - first;
            }
            _firstSeen = seen;
            if (!ages.Any(a => a < StaleMs)) return reading;
            var index = 0;
            return reading.Where(_ => ages[index++] < StaleMs);
        }
    }

    /// <summary>Bütün anları unutur (hat sıfırlandı).</summary>
    public void Reset()
    {
        lock (_gate) _firstSeen = new(StringComparer.Ordinal);
    }
}
