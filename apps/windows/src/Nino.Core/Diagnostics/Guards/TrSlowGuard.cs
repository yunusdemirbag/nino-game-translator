// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>tr.slow</c>: son 50 satırda (en az 20) <c>tr.total</c> p90 eşikten (3000 ms) büyük. Sebep: çevirmen payı yarıdan
/// çok ve çevirmen süresi p90'ı eşiğin yarısını aşıyorsa <c>provider_slow</c>; havuz için aynısı <c>pool_slow</c>;
/// yazı tanıma p90'ı 1 sn'yi aşıyorsa <c>device_busy</c>; aksi <c>network_slow</c>.
/// </summary>
internal sealed class TrSlowGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    const int Window = 50;
    const int Minimum = 20;
    const double DeviceBusyOcrMs = 1000;
    readonly Queue<(double Total, string Origin, double? Tr, double? Ocr)> _lines = new();

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "session.start" or "session.stop":
                _lines.Clear();
                break;
            case "line" when s.Number is { } total && total >= 0:
                Line(total, s.Reason ?? "", s.Extra, s.Extra2, s.At);
                break;
        }
    }

    void Line(double total, string origin, long? tr, long? ocr, DateTimeOffset at)
    {
        var threshold = W.Limit(DiagLimitKeys.TrSlowP90Ms);
        if (total > threshold) W.Trail.Add(at, "tr.slow", total, TimeSpan.FromSeconds(10));
        _lines.Enqueue((total, origin, tr, ocr));
        while (_lines.Count > Window) _lines.Dequeue();
        if (_lines.Count < Minimum) return;
        var totals = _lines.Select(l => l.Total).ToList();
        var p90 = Percentile(totals, 0.9);
        if (p90 <= threshold || W.IsQuiet(at)) return;

        var n = (double)_lines.Count;
        var providerShare = _lines.Count(l => l.Origin == "provider") / n;
        var poolShare = _lines.Count(l => l.Origin == "pool") / n;
        double P90Of(string o) => Percentile(_lines.Where(l => l.Origin == o && l.Tr is not null).Select(l => (double)l.Tr!.Value).ToList(), 0.9);
        var ocrP90 = Percentile(_lines.Where(l => l.Ocr is not null).Select(l => (double)l.Ocr!.Value).ToList(), 0.9);
        var cause = providerShare > 0.5 && P90Of("provider") >= threshold / 2 ? "provider_slow"
            : poolShare > 0.5 && P90Of("pool") >= threshold / 2 ? "pool_slow"
            : ocrP90 >= DeviceBusyOcrMs ? "device_busy"
            : "network_slow";
        var state = new List<KeyValuePair<string, object?>>
        {
            F("p50", Math.Round(Percentile(totals, 0.5))),
            F("p90", Math.Round(p90)),
            F("provider", W.Host().Provider),
            F("poolShare", Math.Round(poolShare, 2)),
            F("providerShare", Math.Round(providerShare, 2)),
            F("ocrP90", Math.Round(ocrP90)),
        };
        _lines.Clear();
        W.Fire(DiagRules.TrSlow, cause, at, state);
    }
}
