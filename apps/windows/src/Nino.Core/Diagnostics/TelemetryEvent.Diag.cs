// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Core.Diagnostics;

namespace Nino.Core.Telemetry;

public sealed partial class TelemetryEvent
{
    /// <summary>
    /// Otomatik teşhis olayı (<c>k: "diag"</c>). Gövde sunucunun kurallarıyla yeniden süzülür; kural geçersizse null.
    /// Günlük olay sınırından (<c>maxPerDay</c>) muaftır; kendi sınırlarını bekçi uygular.
    /// </summary>
    public static TelemetryEvent? Diag(JsonObject body) =>
        DiagPayload.Clean(body) is { } clean ? new TelemetryEvent(clean) : null;

    /// <summary>Günlük sınıra takılmayan olay mı (çökme ve teşhis).</summary>
    public bool IsExemptFromDailyLimit => IsCrash || Kind == "diag";
}
