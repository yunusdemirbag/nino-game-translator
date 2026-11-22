// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>Tek bir kuralın küçük bekçisi. Bütün çağrılar sahibin kilidi içinde gelir.</summary>
internal abstract class DiagGuard(DiagnosticsWatcher owner)
{
    protected DiagnosticsWatcher W { get; } = owner;

    /// <summary>Bir olay geldi.</summary>
    public virtual void OnSignal(in DiagSignal s) { }

    /// <summary>Saniyelik değerlendirme.</summary>
    public virtual void OnTick() { }

    /// <summary>Durum alanı kısaltması.</summary>
    protected static KeyValuePair<string, object?> F(string key, object? value) => new(key, value);

    /// <summary>Sıralı dizide en yakın sıra yüzdeliği (boşsa 0).</summary>
    protected static double Percentile(IReadOnlyList<double> values, double p)
    {
        if (values.Count == 0) return 0;
        var sorted = values.OrderBy(v => v).ToArray();
        var rank = (int)Math.Ceiling(p * sorted.Length) - 1;
        return sorted[Math.Clamp(rank, 0, sorted.Length - 1)];
    }
}
