// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;

namespace Nino.Linux.Hosting;

/// <summary>
/// Makinenin uyuyup uyandığını sonradan anlar. Ekransız sunucuda uyku bildirimi almak için sistem hizmetine
/// (logind) bağlanmak gerekirdi; bunun yerine iki saat karşılaştırılır: tekdüze saat (uykuda durur) ile duvar saati
/// (uykuda da ilerler). Aradaki fark <see cref="Threshold"/>'u aşınca bir uyku geçmiş demektir.
/// </summary>
public sealed class SleepWatch
{
    /// <summary>Bundan kısa farklar saat düzeltmesi ya da gecikme sayılır.</summary>
    public static readonly TimeSpan Threshold = TimeSpan.FromSeconds(15);

    private readonly Func<long> monotonicMs;
    private readonly Func<DateTimeOffset> wall;
    private long lastMonotonic;
    private DateTimeOffset lastWall;

    public SleepWatch(Func<long>? monotonicMs = null, Func<DateTimeOffset>? wall = null)
    {
        this.monotonicMs = monotonicMs ?? (() => Stopwatch.GetTimestamp() * 1000 / Stopwatch.Frequency);
        this.wall = wall ?? (() => DateTimeOffset.UtcNow);
        lastMonotonic = this.monotonicMs();
        lastWall = this.wall();
    }

    /// <summary>Son denetimden beri bir uyku geçtiyse ne kadar sürdüğü; geçmediyse null.</summary>
    public TimeSpan? Check()
    {
        long monotonic = monotonicMs();
        var now = wall();
        var asleep = (now - lastWall) - TimeSpan.FromMilliseconds(monotonic - lastMonotonic);
        lastMonotonic = monotonic;
        lastWall = now;
        return asleep > Threshold ? asleep : null;
    }
}
