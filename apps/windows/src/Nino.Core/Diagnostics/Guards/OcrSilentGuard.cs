// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>ocr.silent</c>: oturum sürerken kareler geliyor (≥ 1 kare/sn) ama süre (15 dk) boyunca hiç yazı okunmadı. Tek
/// satır okunması, kare akışının kesilmesi ve susturan olaylar sayacı sıfırlar.
/// </summary>
internal sealed class OcrSilentGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    DateTimeOffset? _since;

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "session.start":
                _since = null;
                break;
            case "session.stop":
                _since = null;
                break;
            case "ps5.frame":
                if (!W.SessionRunning || W.Fps < 1) _since = null;
                else _since ??= s.At;
                break;
            case "ocr.text" or "sys.sleep" or "sys.wake" or "app.background" or "app.foreground":
                if (_since is not null) _since = s.At;
                break;
        }
    }

    public override void OnTick()
    {
        if (_since is not { } since) return;
        if (!W.SessionRunning || W.Fps < 1)
        {
            _since = null;
            return;
        }
        var at = since + TimeSpan.FromMinutes(W.Limit(DiagLimitKeys.OcrSilentMin));
        if (W.Now < at) return;
        if (W.IsQuiet(at))
        {
            _since = at;
            return;
        }
        _since = null;
        var host = W.Host();
        var cause = host.FrameLuma is <= 16 || host.FrameSame == true ? "video_black"
            : host.RegionManual == true ? "region_wrong"
            : "no_text";
        W.Fire(DiagRules.OcrSilent, cause, at,
        [
            F("fps", Math.Round(W.Fps)),
            F("frameLuma", host.FrameLuma is { } l ? Math.Round(l) : null),
            F("frameSame", host.FrameSame),
            F("region", host.RegionManual is { } m ? (m ? "manual" : "auto") : null),
            F("ocrMs", W.OcrMs),
        ]);
    }
}
