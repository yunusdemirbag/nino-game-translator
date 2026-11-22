// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Text;

namespace Nino.Core.Health;

/// <summary>Muhtemel sebebin türü.</summary>
public enum HealthCauseKind
{
    Offline,
    DroppedAfterNetwork,
    ConsoleAsleep,
    OtherDevice,
    Dropped,
    Unreachable,
    NetworkFlapping,
    PictureLossWifi,
    PictureLoss,
    FrequentDrops,
    SlowTranslation,
    TvDropped,
}

/// <summary>Bir muhtemel sebep ve metinlerine giren değerler.</summary>
/// <param name="Kind">Tür.</param>
/// <param name="Count">Sayı (ağ kopması, PS5 kopması, TV kopması).</param>
/// <param name="Reason">Son kopma nedeni (PS5 sebeplerinde).</param>
/// <param name="MedianMs">Çeviri ortancası (yavaş çeviride).</param>
/// <param name="Severe">Görüntü kaybında sorun düzeyinde mi.</param>
public sealed record HealthCause(HealthCauseKind Kind, int Count = 0, string? Reason = null, long MedianMs = 0,
    bool Severe = false)
{
    /// <summary>Katalog anahtarının kökü (<c>health.cause.&lt;kök&gt;.title/advice</c>).</summary>
    public string KeyStem => Kind switch
    {
        HealthCauseKind.Offline => "offline",
        HealthCauseKind.DroppedAfterNetwork => "droppedAfterNetwork",
        HealthCauseKind.ConsoleAsleep => "consoleAsleep",
        HealthCauseKind.OtherDevice => "otherDevice",
        HealthCauseKind.Dropped => "dropped",
        HealthCauseKind.Unreachable => "unreachable",
        HealthCauseKind.NetworkFlapping => "networkFlapping",
        HealthCauseKind.PictureLossWifi => "pictureLossWifi",
        HealthCauseKind.PictureLoss => "pictureLoss",
        HealthCauseKind.FrequentDrops => "frequentDrops",
        HealthCauseKind.SlowTranslation => "slowTranslation",
        _ => "tvDropped",
    };

    /// <summary>Ekran dilindeki başlık.</summary>
    public string Title(ITextSource text) => text.Get($"health.cause.{KeyStem}.title");

    /// <summary>Ekran dilinde ne yapılmalı.</summary>
    public string Advice(ITextSource text)
    {
        var key = $"health.cause.{KeyStem}.advice";
        return Kind switch
        {
            HealthCauseKind.NetworkFlapping or HealthCauseKind.FrequentDrops or HealthCauseKind.TvDropped =>
                text.Format(key, (long)Count),
            HealthCauseKind.SlowTranslation => text.Format(key,
                (MedianMs / 1000.0).ToString("0.0", UiLanguage.CultureFor(text.Language))),
            _ => text.Get(key),
        };
    }
}

/// <summary>Muhtemel sebepler, önemliden önemsize (ilk olan başlık olur).</summary>
public static class HealthCauses
{
    /// <summary>Kopma nedenlerinin adları (Remote Play kopma nedenleriyle aynı yazım).</summary>
    public const string ReasonConsoleAsleep = "ConsoleAsleep";
    public const string ReasonInUse = "InUse";

    /// <summary>Sebepleri bulur.</summary>
    public static IReadOnlyList<HealthCause> Find(HealthSnapshot s, NetworkKind network)
    {
        var list = new List<HealthCause>();
        var offline = network == NetworkKind.Offline;
        if (!s.HasData)
        {
            if (offline) list.Add(new HealthCause(HealthCauseKind.Offline));
            return list;
        }
        if (offline) list.Add(new HealthCause(HealthCauseKind.Offline));

        if (s.IsDisconnected && !offline)
        {
            var kind = s.NetworkLosses > 0
                ? HealthCauseKind.DroppedAfterNetwork
                : s.LastReason switch
                {
                    ReasonConsoleAsleep => HealthCauseKind.ConsoleAsleep,
                    ReasonInUse => HealthCauseKind.OtherDevice,
                    _ => HealthCauseKind.Dropped,
                };
            list.Add(new HealthCause(kind, Reason: s.LastReason));
        }
        else if (!s.IsDisconnected && s.Connects == 0 && s.ConnectAttempts >= HealthVerdicts.UnreachableAttempts)
        {
            list.Add(new HealthCause(HealthCauseKind.Unreachable, Reason: s.LastReason));
        }

        if (s.NetworkLosses > 0 && !offline && !s.IsDisconnected)
            list.Add(new HealthCause(HealthCauseKind.NetworkFlapping, s.NetworkLosses));

        var picture = HealthVerdicts.Picture(s);
        if (picture.AtLeastWarning())
        {
            var wireless = network is NetworkKind.Wifi or NetworkKind.Other;
            list.Add(new HealthCause(wireless ? HealthCauseKind.PictureLossWifi : HealthCauseKind.PictureLoss,
                Severe: picture == HealthLevel.Problem));
        }

        if (!s.IsDisconnected && s.Drops >= HealthVerdicts.FrequentDrops && !picture.AtLeastWarning()
            && s.NetworkLosses == 0)
            list.Add(new HealthCause(HealthCauseKind.FrequentDrops, s.Drops));

        if (HealthVerdicts.Speed(s).AtLeastWarning())
            list.Add(new HealthCause(HealthCauseKind.SlowTranslation, MedianMs: s.MedianTranslationMs ?? 0));

        if (s.TvDrops > 0) list.Add(new HealthCause(HealthCauseKind.TvDropped, s.TvDrops));
        return list;
    }

    /// <summary>İlk sebebin ekran dilindeki başlığı; sebep yoksa yok.</summary>
    public static string? FirstTitle(HealthSnapshot s, NetworkKind network, ITextSource text) =>
        Find(s, network) is { Count: > 0 } list ? list[0].Title(text) : null;
}

/// <summary>Sağlık sayfasının "muhtemel sebep" kartı.</summary>
/// <param name="Causes">Sebepler (ilk olan başlık).</param>
/// <param name="AllGood">Sebep yok, oturum sürüyor ve görüntü geliyor: "Her şey yolunda".</param>
public sealed record HealthCauseCard(IReadOnlyList<HealthCause> Causes, bool AllGood)
{
    /// <summary>Kart görünür mü.</summary>
    public bool Visible => Causes.Count > 0 || AllGood;

    /// <summary>Kartı kurar.</summary>
    public static HealthCauseCard Build(HealthSnapshot s, NetworkKind network)
    {
        var causes = HealthCauses.Find(s, network);
        return new HealthCauseCard(causes, causes.Count == 0 && s.Active && s.Streaming);
    }
}

/// <summary>Sağlık metinlerinde kullanılan küçük biçimler.</summary>
internal static class HealthFormat
{
    public static string Invariant(double value, string format) => value.ToString(format, CultureInfo.InvariantCulture);
}
