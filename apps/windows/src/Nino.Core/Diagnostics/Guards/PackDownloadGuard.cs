// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>pack.download</c>: aynı paket art arda 3 kez ya da 24 saattir indirilemedi. Paket anahtarı yalnız bellekte
/// eşleştirme içindir, bildirime girmez.
/// </summary>
internal sealed class PackDownloadGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    readonly Dictionary<string, (int Fails, DateTimeOffset First)> _packs = new(StringComparer.Ordinal);

    public override void OnSignal(in DiagSignal s)
    {
        if (s.Key is not { } key) return;
        if (s.Code == "pack.ok")
        {
            _packs.Remove(key);
            return;
        }
        if (s.Code != "pack.fail") return;
        var entry = _packs.TryGetValue(key, out var e) ? (e.Fails + 1, e.First) : (1, s.At);
        _packs[key] = entry;
        var due = entry.Item1 >= (int)W.Limit(DiagLimitKeys.PackAttempts)
                  || s.At - entry.Item2 >= TimeSpan.FromHours(W.Limit(DiagLimitKeys.PackHours));
        if (!due || W.IsQuiet(s.At, background: false)) return;
        _packs.Remove(key);
        var http = s.Number is { } h ? (int)h : (int?)null;
        var cause = s.Reason is "offline" or "corrupt" or "storage_full" ? s.Reason
            : W.NetDown || http == 0 ? "offline"
            : http is >= 400 and < 500 ? "http_4xx"
            : http is >= 500 and < 600 ? "http_5xx"
            : null;
        W.Fire(DiagRules.PackDownload, cause, s.At,
        [
            F("attempts", entry.Item1),
            F("http", http is > 0 ? http : null),
            F("sizeKB", s.Extra),
        ]);
    }
}
