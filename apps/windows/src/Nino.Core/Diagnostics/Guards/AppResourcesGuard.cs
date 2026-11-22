// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>app.resources</c>: bellek eşikten (masaüstü 1500 MB) ya da işlemci %90'dan fazla, 2 dk boyunca; ısı
/// <c>serious</c>/<c>critical</c> da aynı süreyle sayılır. Sistemin düşük bellek uyarısı hemen sayılır.
/// </summary>
internal sealed class AppResourcesGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    DateTimeOffset? _memSince;
    DateTimeOffset? _cpuSince;
    DateTimeOffset? _hotSince;

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "sys.sleep" or "sys.wake" or "app.background" or "app.foreground":
                _memSince = _cpuSince = _hotSince = null;
                break;
            case "mem.warning":
                if (!W.IsQuiet(s.At)) Fire("memory_high", s.At);
                break;
            case "resources":
                Sample(s.At);
                break;
        }
    }

    void Sample(DateTimeOffset at)
    {
        var memHigh = W.MemMB is { } m && m > W.Limit(DiagLimitKeys.MemHighMB);
        var cpuHigh = W.Cpu is { } c && c > W.Limit(DiagLimitKeys.CpuHighPct);
        var hot = W.Thermal is "serious" or "critical";
        if (memHigh && _memSince is null) W.Trail.Add(at, "mem.high", W.MemMB);
        if (cpuHigh && _cpuSince is null) W.Trail.Add(at, "cpu.high", W.Cpu);
        _memSince = memHigh ? _memSince ?? at : null;
        _cpuSince = cpuHigh ? _cpuSince ?? at : null;
        _hotSince = hot ? _hotSince ?? at : null;

        var span = TimeSpan.FromSeconds(W.Limit(DiagLimitKeys.ResourceSec));
        bool Long(DateTimeOffset? since) => since is { } t && at - t >= span;
        var cause = Long(_hotSince) ? "thermal" : Long(_memSince) ? "memory_high" : Long(_cpuSince) ? "cpu_high" : null;
        if (cause is null || W.IsQuiet(at)) return;
        _memSince = _cpuSince = _hotSince = null;
        Fire(cause, at);
    }

    void Fire(string cause, DateTimeOffset at)
    {
        var sessionMin = W.SessionStart is { } start ? (long?)Math.Max(0, (long)(at - start).TotalMinutes) : null;
        W.Fire(DiagRules.AppResources, cause, at,
        [
            F("memMB", W.MemMB),
            F("cpu", W.Cpu),
            F("thermal", W.Thermal),
            F("sessionMin", sessionMin),
        ]);
    }
}
