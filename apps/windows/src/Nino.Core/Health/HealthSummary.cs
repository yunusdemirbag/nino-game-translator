// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Health;

/// <summary>
/// Destek için düz metin özeti: altı Türkçe satır, sayılar nokta ondalıklı; altyazı metni ve adres içermez.
/// </summary>
public static class HealthSummary
{
    /// <summary>Altyazı günlüğüne yazılan özetin başı.</summary>
    public const string LogPrefix = "sağlık: ";

    /// <summary>Altı satır.</summary>
    public static IReadOnlyList<string> Lines(HealthSnapshot s, NetworkKind network)
    {
        var first = $"ağ: {network.Wire()}, oturumdaki ağ kaybı {s.NetworkLosses}, TV kaybı {s.TvDrops}";
        if (s.IsDisconnected) first += $", PS5 {(long)s.DisconnectedSeconds} sn'den beri yok";
        return
        [
            first,
            $"akış: {HealthFormat.Invariant(s.StreamedMinutes, "0.0")} dk, bağlanma denemesi {s.ConnectAttempts}, " +
            $"bağlandı {s.Connects}, akışta kopma {s.Drops}",
            $"son kopma sebebi: {(string.IsNullOrEmpty(s.LastReason) ? "-" : s.LastReason)}",
            $"tekrar istenen paket {s.Resends}, dolan tampon {s.Overflows}, dakikada {Rate(s.LossPerMinute)} kayıp",
            $"görüntü durması {s.Stalls} ({Rate(s.StallsPerMinute)}/dk), bozuk kare {s.CorruptFrames}",
            $"{s.Lines} satır okundu, {s.Translations} çevrildi; çeviri süresi ortanca " +
            (s.MedianTranslationMs is { } m ? $"{m} ms" : "-") + $", en uzun {s.LongestTranslationMs} ms",
        ];
    }

    /// <summary>Satırlar <c>\n</c> ile.</summary>
    public static string Text(HealthSnapshot s, NetworkKind network) => string.Join("\n", Lines(s, network));

    /// <summary>Oturum sonunda altyazı günlüğüne yazılan satır: <c>sağlık: </c> + satırlar " · " ile.</summary>
    public static string LogLine(HealthSnapshot s, NetworkKind network) =>
        LogPrefix + string.Join(" · ", Lines(s, network));

    static string Rate(double? value) => value is { } v ? HealthFormat.Invariant(v, "0.0") : "-";
}
