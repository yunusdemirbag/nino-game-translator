// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>ps5.no_return</c>: çeviri sürerken PS5 koptu ve eşik (180 sn) içinde geri gelmedi. Süre ilk kopmadan sayılır
/// (başarısız denemeler yeniden başlatmaz); tetik anı kopma + eşik. Kopma susturma içindeyse (uyanış, açılış…) sayılmaz.
/// </summary>
internal sealed class Ps5NoReturnGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    DateTimeOffset? _dropAt;
    string? _reason;
    bool _netLost;
    int _retries;
    double _lastFps;

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            // Uykudan önceki kopma uykunun sonucudur; uyanıştan sonra sayaç yeniden başlar (sonraki kopmayla).
            case "session.start" or "session.stop" or "ps5.connect" or "sys.sleep" or "sys.wake":
                _dropAt = null;
                break;
            case "ps5.drop":
                if (!W.SessionRunning || _dropAt is not null) break;
                if (W.IsQuiet(s.At)) break;
                _dropAt = s.At;
                _reason = s.Reason;
                _netLost = W.NetDown;
                _retries = 0;
                _lastFps = W.Fps;
                break;
            case "ps5.retry" when _dropAt is not null:
                _retries = s.Number is { } n ? (int)n : _retries + 1;
                break;
            case "net.down" when _dropAt is not null:
                _netLost = true;
                break;
        }
    }

    public override void OnTick()
    {
        if (_dropAt is not { } drop || !W.SessionRunning) return;
        var at = drop + TimeSpan.FromSeconds(W.Limit(DiagLimitKeys.Ps5NoReturnSec));
        if (W.Now < at) return;
        _dropAt = null;
        if (W.IsQuiet(at)) return;
        W.Fire(DiagRules.Ps5NoReturn, Cause(), at, [F("retries", _retries), F("lastFps", Math.Round(_lastFps))]);
    }

    string Cause()
    {
        if (_netLost || W.NetDown || _reason == "network_lost") return "network_lost";
        return _reason switch
        {
            "standby" or "ps5_standby" => "ps5_standby",
            "ps5_closed" => "ps5_closed",
            "kicked" => "kicked",
            "stalled" => "stalled",
            _ => "timeout",
        };
    }
}
