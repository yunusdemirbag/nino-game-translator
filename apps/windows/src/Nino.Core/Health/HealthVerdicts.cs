// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Health;

/// <summary>Bir denetimin sonucu (renk: gri / yeşil / sarı / kırmızı).</summary>
public enum HealthLevel
{
    Unknown,
    Good,
    Warning,
    Problem,
}

/// <summary>Sağlık kararları; eşikler tarifteki gibi birebir.</summary>
public static class HealthVerdicts
{
    public const double LossProblem = 100;
    public const double StallsProblem = 4;
    public const double LossWarning = 10;
    public const double StallsWarning = 2.5;
    public const long SlowProblemMs = 3000;
    public const long SlowWarningMs = 1500;
    public const int FrequentDrops = 3;
    public const int UnreachableAttempts = 2;

    /// <summary>Uyarı ya da sorun mu.</summary>
    public static bool AtLeastWarning(this HealthLevel level) => level is HealthLevel.Warning or HealthLevel.Problem;

    // Önce ağır eşik, sonra hafif eşik; ikisi de aşılmadıysa iyi.
    static HealthLevel Tier(bool severe, bool mild) =>
        severe ? HealthLevel.Problem : mild ? HealthLevel.Warning : HealthLevel.Good;

    /// <summary>PS5 görüntüsü: kayıp ≥ 100/dk ya da durma ≥ 4/dk sorun; ≥ 10 ya da ≥ 2,5 uyarı.</summary>
    public static HealthLevel Picture(HealthSnapshot s)
    {
        var lost = s.LossPerMinute;
        var stalled = s.StallsPerMinute;
        if (lost is null || stalled is null) return HealthLevel.Unknown;
        return Tier(
            severe: lost.Value >= LossProblem || stalled.Value >= StallsProblem,
            mild: lost.Value >= LossWarning || stalled.Value >= StallsWarning);
    }

    /// <summary>PS5 bağlantısı.</summary>
    public static HealthLevel Connection(HealthSnapshot s)
    {
        if (!s.HasData) return HealthLevel.Unknown;
        if (s.IsDisconnected) return HealthLevel.Problem;
        if (s.Connects != 0) return Tier(severe: false, mild: s.Drops >= FrequentDrops);
        // Hiç bağlanamadı: yeterince denendiyse ulaşılamıyor demektir.
        return s.ConnectAttempts < UnreachableAttempts ? HealthLevel.Unknown : HealthLevel.Problem;
    }

    /// <summary>Çeviri hızı (ortanca).</summary>
    public static HealthLevel Speed(HealthSnapshot s) =>
        s.MedianTranslationMs is long median
            ? Tier(severe: median >= SlowProblemMs, mild: median >= SlowWarningMs)
            : HealthLevel.Unknown;

    /// <summary>Yerel bilgisayarın ağı: kablo iyi, ağ yok sorun; Wi-Fi ve diğerinde görüntünün kararı.</summary>
    public static HealthLevel Network(NetworkKind kind, HealthSnapshot s)
    {
        if (kind == NetworkKind.Unknown) return HealthLevel.Unknown;
        if (kind == NetworkKind.Offline) return HealthLevel.Problem;
        return kind == NetworkKind.Wired ? HealthLevel.Good : Picture(s);
    }
}
