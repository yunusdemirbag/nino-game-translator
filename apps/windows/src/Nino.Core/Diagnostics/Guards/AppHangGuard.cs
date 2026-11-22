// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>app.hang</c>: ana iş parçacığı eşik (5 sn) boyunca yanıt vermedi (izleyici iş parçacığı bildirir) ya da önceki
/// çalışma askıda kalarak bitti (açılışta bildirilir; açılış susturması uygulanmaz).
/// </summary>
internal sealed class AppHangGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "ui.blocked" when s.Number is { } sec && sec >= W.Limit(DiagLimitKeys.HangSec):
                if (W.IsQuiet(s.At)) break;
                Fire(sec, s.At);
                break;
            case "app.hung_before" when s.Number is { } before:
                Fire(before, s.At);
                break;
        }
    }

    void Fire(double blocked, DateTimeOffset at) =>
        W.Fire(DiagRules.AppHang, "main_thread", at,
        [
            F("blockedSec", Math.Round(blocked)),
            F("memMB", W.MemMB),
            F("cpu", W.Cpu),
        ]);
}
