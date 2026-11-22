// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core.Logging;

/// <summary>Günlük satırlarındaki metin alıntısı.</summary>
public static class LogQuote
{
    /// <summary>En çok Unicode karakter.</summary>
    public const int MaxChars = 120;

    /// <summary>
    /// Satır sonlarından bölünür, parçalar kırpılır, boşlar atılır, <c> / </c> ile birleşir; 120 karakteri aşarsa ilk
    /// 119 + <c>…</c>; çift tırnak içinde.
    /// </summary>
    public static string Of(string? text)
    {
        var parts = (text ?? "").Split(["\r\n", "\n", "\r"], StringSplitOptions.None)
            .Select(p => p.Trim()).Where(p => p.Length > 0);
        var joined = string.Join(" / ", parts);
        var runes = joined.EnumerateRunes().ToArray();
        if (runes.Length > MaxChars)
        {
            var sb = new StringBuilder();
            foreach (var r in runes.Take(MaxChars - 1)) sb.Append(r.ToString());
            joined = sb.Append('…').ToString();
        }
        return "\"" + joined + "\"";
    }
}

/// <summary>
/// Remote Play kitaplığının satırlarından görüntü duraklamalarını izler ve altyazı günlüğüne yazılacak notu üretir.
/// </summary>
public sealed class VideoStallTracker(TimeProvider? clock = null)
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;
    readonly object _gate = new();
    long? _stallStart;

    /// <summary>Duraklama sürüyor mu.</summary>
    public bool Stalled
    {
        get { lock (_gate) return _stallStart is not null; }
    }

    /// <summary>Kitaplık satırı; yazılacak bir not varsa döner, yoksa null.</summary>
    public string? OnNativeLine(string line)
    {
        lock (_gate)
        {
            if (line.Contains("FEC failed", StringComparison.Ordinal)
                || line.Contains("Video FEC failure", StringComparison.Ordinal))
            {
                if (_stallStart is not null) return null;
                _stallStart = _clock.GetTimestamp();
                return "görüntü durdu (FEC hatası); IDR karesi bekleniyor";
            }
            if (line.Contains("Received IDR frame", StringComparison.Ordinal) && _stallStart is { } start)
            {
                _stallStart = null;
                return $"görüntü yeniden akıyor: IDR karesi geldi, boşluk {GapMs(start)} ms";
            }
            return null;
        }
    }

    /// <summary>PS5 oturumu "görüntü gelmiyor" diye yeniden kurulurken çağrılır; duraklama sıfırlanır.</summary>
    public string OnSessionRestartForNoVideo()
    {
        lock (_gate)
        {
            var text = "görüntü hiç gelmedi; IDR beklenmeyecek, PS5 oturumu yeniden kuruluyor";
            if (_stallStart is { } start) text += $", boşluk {GapMs(start)} ms";
            _stallStart = null;
            return text;
        }
    }

    long GapMs(long start) =>
        (long)_clock.GetElapsedTime(start).TotalMilliseconds;
}

/// <summary>
/// Bir çeviri isteğinin aynı mantıksal akışında önbellekten dönen ve motorun ürettiği parçaları sayar; altyazı
/// günlüğündeki kaynak etiketini (<c>çeviri:deepl</c>, <c>önbellek</c>) üretir.
/// </summary>
public sealed class TranslationProbe
{
    static readonly AsyncLocal<TranslationProbe?> CurrentProbe = new();

    int _cached;
    int _fresh;
    string? _lastEngine;

    /// <summary>Bu akıştaki yoklama (yoksa null).</summary>
    public static TranslationProbe? Current => CurrentProbe.Value;

    /// <summary>Yeni yoklama başlatır; bırakılınca öncekine döner.</summary>
    public static Scope Begin()
    {
        var previous = CurrentProbe.Value;
        var probe = new TranslationProbe();
        CurrentProbe.Value = probe;
        return new Scope(probe, previous);
    }

    /// <summary>Akıştaki yoklamaya "önbellekten döndü" ekler.</summary>
    public static void NoteCached(int count = 1)
    {
        if (CurrentProbe.Value is { } p) Interlocked.Add(ref p._cached, count);
    }

    /// <summary>Akıştaki yoklamaya "motor üretti" ekler.</summary>
    public static void NoteFresh(string? engine, int count = 1)
    {
        if (CurrentProbe.Value is not { } p) return;
        Interlocked.Add(ref p._fresh, count);
        p._lastEngine = engine;
    }

    /// <summary>Etiket: yeni parça varsa <c>çeviri:&lt;motor&gt;</c>, önbellek varsa <c>önbellek</c>.</summary>
    public string Label(string? fallbackEngine = null)
    {
        var fallback = string.IsNullOrEmpty(fallbackEngine) ? "motor" : fallbackEngine;
        if (_fresh > 0) return "çeviri:" + (string.IsNullOrEmpty(_lastEngine) ? fallback : _lastEngine);
        if (_cached > 0) return "önbellek";
        return "çeviri:" + fallback;
    }

    /// <summary>Yoklamanın kapsamı.</summary>
    public readonly struct Scope(TranslationProbe probe, TranslationProbe? previous) : IDisposable
    {
        /// <summary>Yoklama.</summary>
        public TranslationProbe Probe => probe;

        /// <inheritdoc />
        public void Dispose() => CurrentProbe.Value = previous;
    }
}
