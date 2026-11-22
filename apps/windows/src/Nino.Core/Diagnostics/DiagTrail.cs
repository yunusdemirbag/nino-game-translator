// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;

namespace Nino.Core.Diagnostics;

/// <summary>İzdeki bir adım: zaman, kod, isteğe bağlı sayı.</summary>
public readonly record struct DiagStep(DateTimeOffset At, string Code, double? Number);

/// <summary>
/// İz halka tamponu: son 10 dakikanın en çok 200 adımı (bellekte). Bildirimde son 40 adım
/// <c>[kaç saniye önce, kod, sayı?]</c> olarak gider. Yalnız kod kuralına uyan adımlar girer (serbest metin asla).
/// İş parçacığı güvenli değildir; sahibi kilitler.
/// </summary>
public sealed class DiagTrail
{
    /// <summary>Tutulan süre.</summary>
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(10);

    /// <summary>En çok adım.</summary>
    public const int Capacity = 200;

    /// <summary>Bildirimde giden en çok adım.</summary>
    public const int Sent = 40;

    readonly DiagStep[] _ring = new DiagStep[Capacity];
    int _start;
    int _count;

    /// <summary>Tampondaki adım sayısı.</summary>
    public int Count => _count;

    /// <summary>
    /// Adım ekler. Kod kurala uymuyorsa atlanır. <paramref name="coalesce"/> verilirse aynı kodlu son adım o süreden
    /// yeniyse yenisi eklenmez (sık olaylar tamponu doldurmasın).
    /// </summary>
    public void Add(DateTimeOffset at, string code, double? number = null, TimeSpan? coalesce = null)
    {
        if (!DiagPayload.IsCode(code)) return;
        if (number is { } n && !DiagPayload.IsNumber(n)) number = null;
        Prune(at);
        if (coalesce is { } gap && _count > 0)
        {
            var last = _ring[(_start + _count - 1) % Capacity];
            if (last.Code == code && at - last.At < gap) return;
        }
        if (_count == Capacity)
        {
            _start = (_start + 1) % Capacity;
            _count--;
        }
        _ring[(_start + _count) % Capacity] = new DiagStep(at, code, number);
        _count++;
    }

    /// <summary>Tampondaki adımlar (eskiden yeniye), <paramref name="now"/>'a göre 10 dakikadan eskiler hariç.</summary>
    public IReadOnlyList<DiagStep> Steps(DateTimeOffset now)
    {
        Prune(now);
        var list = new List<DiagStep>(_count);
        for (var i = 0; i < _count; i++) list.Add(_ring[(_start + i) % Capacity]);
        return list;
    }

    /// <summary>
    /// Bildirimdeki iz: <paramref name="at"/> anına kadarki son 40 adım, saniye farkı (−3600…0) ile, eskiden yeniye.
    /// </summary>
    public JsonArray ToJson(DateTimeOffset at)
    {
        var steps = Steps(at).Where(s => s.At <= at).TakeLast(Sent);
        var array = new JsonArray();
        foreach (var s in steps)
        {
            var ago = (long)Math.Round((s.At - at).TotalSeconds);
            if (ago < -3600 || ago > 0) continue;
            var step = new JsonArray(JsonValue.Create(ago), JsonValue.Create(s.Code));
            if (s.Number is { } n) step.Add(DiagPayload.NumberNode(n));
            array.Add(step);
        }
        return array;
    }

    /// <summary>Hepsini siler.</summary>
    public void Clear()
    {
        _start = 0;
        _count = 0;
    }

    void Prune(DateTimeOffset now)
    {
        while (_count > 0 && now - _ring[_start].At > Window)
        {
            _start = (_start + 1) % Capacity;
            _count--;
        }
    }
}
