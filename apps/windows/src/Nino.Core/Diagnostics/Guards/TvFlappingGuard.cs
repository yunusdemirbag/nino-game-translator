// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>tv.flapping</c>: pencere (10 dk) içinde eşik (3) kopma; tetik anı son kopma. Arka plan susturması uygulanmaz
/// (<c>resume</c> kopmanın kendisidir); açılış, uyku/uyanma ve kullanıcının durdurması sayacı sıfırlar. Sebep:
/// kopmaların çoğunun nedeni, çoğunluk yoksa <c>mixed</c>.
/// </summary>
internal sealed class TvFlappingGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    readonly List<(DateTimeOffset At, string Code, double? Up)> _drops = [];
    DateTimeOffset? _connectedAt;

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "sys.sleep" or "sys.wake" or "session.start" or "session.stop":
                _drops.Clear();
                break;
            case "tv.connect":
                _connectedAt = s.At;
                break;
            case "tv.drop":
                Drop(s);
                break;
        }
    }

    void Drop(in DiagSignal s)
    {
        var up = s.Number ?? (_connectedAt is { } c ? Math.Max(0, (s.At - c).TotalSeconds) : null);
        _connectedAt = null;
        if (W.IsQuiet(s.At, background: false))
        {
            _drops.Clear();
            return;
        }
        var window = TimeSpan.FromMinutes(W.Limit(DiagLimitKeys.TvFlapWindowMin));
        var at = s.At;
        _drops.RemoveAll(d => at - d.At > window);
        _drops.Add((s.At, Normalize(s.Reason), up));
        if (_drops.Count < (int)Math.Max(2, W.Limit(DiagLimitKeys.TvFlapCount))) return;

        var host = W.Host();
        var ups = _drops.Where(d => d.Up is not null).Select(d => d.Up!.Value).ToList();
        var state = new List<KeyValuePair<string, object?>>
        {
            F("drops", _drops.Count),
            F("tvCount", host.TvCount),
            F("proto", host.Proto is "nino" or "legacy" ? host.Proto : null),
            F("avgUpSec", ups.Count > 0 ? Math.Round(ups.Average()) : null),
        };
        var cause = Majority();
        _drops.Clear();
        W.Fire(DiagRules.TvFlapping, cause, at, state);
    }

    string Majority()
    {
        var top = _drops.GroupBy(d => d.Code).OrderByDescending(g => g.Count()).First();
        return top.Count() * 2 > _drops.Count ? top.Key : "mixed";
    }

    static string Normalize(string? code) => code switch
    {
        "close" or "tv_closed" or "closed" => "closed",
        "write_error" or "timeout" or "resume" or "network_change" or "replaced" => code,
        _ => "other",
    };
}
