// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>ocr.stalled</c>: yazı tanıma süresi içinde (10 sn) dönmedi, 5 dk'da 3 kez; ya da PS5 bağlıyken 30 sn hiç kare
/// gelmedi (çözücü hatası yakınsa sebep <c>decoder</c>).
/// </summary>
internal sealed class OcrStalledGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    static readonly TimeSpan StallWindow = TimeSpan.FromMinutes(5);
    const int StallCount = 3;
    readonly List<DateTimeOffset> _stalls = [];
    DateTimeOffset? _reportedFrameGap;

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "session.start" or "session.stop" or "sys.sleep" or "sys.wake":
                _stalls.Clear();
                break;
            case "ocr.stall":
                var at = s.At;
                _stalls.RemoveAll(t => at - t > StallWindow);
                _stalls.Add(at);
                if (_stalls.Count < StallCount) break;
                _stalls.Clear();
                if (W.IsQuiet(at)) break;
                Fire("ocr_hang", at);
                break;
        }
    }

    public override void OnTick()
    {
        if (!W.SessionRunning || !W.Ps5Up || W.LastFrameAt is not { } last) return;
        var at = last + TimeSpan.FromSeconds(W.Limit(DiagLimitKeys.FrameStallSec));
        if (W.Now < at || _reportedFrameGap == last) return;
        _reportedFrameGap = last;
        if (W.IsQuiet(at)) return;
        var decoder = W.DecoderFailedAt is { } d && (at - d).Duration() < TimeSpan.FromSeconds(60);
        Fire(decoder ? "decoder" : "frames_stopped", at);
    }

    void Fire(string cause, DateTimeOffset at)
    {
        var host = W.Host();
        W.Fire(DiagRules.OcrStalled, cause, at,
        [
            F("ocrMs", W.OcrMs),
            F("queue", host.Queue),
            F("fps", Math.Round(W.Fps)),
            F("memMB", W.MemMB),
            F("cpu", W.Cpu),
        ]);
    }
}
