// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Text;

namespace Nino.Core.Health;

/// <summary>Denetimler kartının satırı.</summary>
public enum HealthCheckId
{
    Network,
    Ps5,
    Picture,
    Speed,
    Tv,
}

/// <summary>Bir denetim satırı: ad, düzey (nokta rengi), değer ve (uyarı/sorunda) öneri. Metinler ekran dilinde.</summary>
public sealed record HealthCheckRow(HealthCheckId Id, string Name, HealthLevel Level, string Value, string? Advice)
{
    /// <summary>Düzeyin yazısı: iyi, iyileşebilir, sorunlu ya da ölçüm yok.</summary>
    public string LevelText(ITextSource text) => HealthChecks.LevelText(Level, text);
}

/// <summary>Denetimler kartına giren durum (denetleyiciden).</summary>
/// <param name="Snapshot">Sağlık kaydedicinin görüntüsü.</param>
/// <param name="Network">Ağ türü; henüz okunmadıysa yok ("Denetleniyor…").</param>
/// <param name="Translating">Çeviri sürüyor mu.</param>
/// <param name="SendingToTv">Altyazı TV'ye gidiyor mu.</param>
/// <param name="ConnectedTvs">Bağlı TV uygulaması sayısı.</param>
/// <param name="OnlineOrLocalModel">Çevrimiçi motor etkin ya da motor yerel model mi (yavaş çeviri önerisi).</param>
public sealed record HealthCheckInput(HealthSnapshot Snapshot, NetworkKind? Network, bool Translating,
    bool SendingToTv, int ConnectedTvs, bool OnlineOrLocalModel);

/// <summary>Sağlık sayfasının denetimler kartı (saf model; pencere yalnız çizer).</summary>
public static class HealthChecks
{
    /// <summary>Düzeyin yazısı.</summary>
    public static string LevelText(HealthLevel level, ITextSource text) => text.Get(level switch
    {
        HealthLevel.Good => "health.level.good",
        HealthLevel.Warning => "health.level.warning",
        HealthLevel.Problem => "health.level.problem",
        _ => "health.level.unknown",
    });

    /// <summary>Kartın ipucu: ölçüm yoksa "çeviriyi başlatın", oturum bittiyse "son oturumun sonuçları", sürüyorsa yok.</summary>
    public static string? Hint(HealthSnapshot s, ITextSource text)
    {
        if (!s.HasData) return text.Get("health.checks.hint.noData");
        return s.Active ? null : text.Get("health.checks.hint.lastSession");
    }

    /// <summary>Beş satır, sırayla: ağ, PS5 bağlantısı, PS5 görüntüsü, çeviri hızı, TV.</summary>
    public static IReadOnlyList<HealthCheckRow> Build(HealthCheckInput input, ITextSource text) =>
        [NetworkRow(input, text), Ps5Row(input.Snapshot, text), PictureRow(input.Snapshot, text),
         SpeedRow(input, text), TvRow(input, text)];

    static HealthCheckRow NetworkRow(HealthCheckInput input, ITextSource text)
    {
        var s = input.Snapshot;
        var kind = input.Network ?? NetworkKind.Unknown;
        var level = HealthVerdicts.Network(kind, s);
        var value = text.Get(input.Network switch
        {
            NetworkKind.Wired => "health.check.network.wired",
            NetworkKind.Wifi => "health.check.network.wifi",
            NetworkKind.Other => "health.check.network.other",
            NetworkKind.Offline => "health.check.network.offline",
            _ => "translation.key.testing",
        });
        string? advice = null;
        if (level.AtLeastWarning())
            advice = text.Get(kind == NetworkKind.Offline
                ? "health.check.network.advice.offline"
                : "health.check.network.advice.loss");
        return new HealthCheckRow(HealthCheckId.Network, text.Get("health.check.network.name"), level, value, advice);
    }

    static HealthCheckRow Ps5Row(HealthSnapshot s, ITextSource text)
    {
        var level = HealthVerdicts.Connection(s);
        string value;
        if (!s.HasData) value = text.Get("health.check.notStarted");
        else if (s.IsDisconnected)
            value = text.Format("health.check.ps5.disconnectedFor", Math.Max(1L, (long)(s.DisconnectedSeconds / 60)));
        else if (s.Connects == 0) value = text.Format("health.check.ps5.neverConnected", (long)s.ConnectAttempts);
        else if (s.Drops == 0) value = text.Get("health.check.ps5.noDrops");
        else value = text.Format("health.check.ps5.drops", (long)s.Drops);
        var advice = level.AtLeastWarning() ? text.Get(Ps5AdviceKey(s.LastReason)) : null;
        return new HealthCheckRow(HealthCheckId.Ps5, text.Get("health.check.ps5.name"), level, value, advice);
    }

    /// <summary>PS5 satırının öneri anahtarı, son kopma nedenine göre.</summary>
    public static string Ps5AdviceKey(string? reason) => reason switch
    {
        "ConsoleAsleep" => "health.check.ps5.advice.asleep",
        "InUse" => "health.check.ps5.advice.otherDevice",
        "LoginPasscode" or "LoginPasscodeIncorrect" => "health.check.ps5.advice.loginPasscode",
        "RemotePlayDisabled" => "health.check.ps5.advice.remotePlayOff",
        "RegistrationInvalid" or "Rejected" => "health.check.ps5.advice.pairing",
        "NotFound" => "health.check.ps5.advice.notFound",
        _ => "health.check.ps5.advice.other",
    };

    static HealthCheckRow PictureRow(HealthSnapshot s, ITextSource text)
    {
        var level = HealthVerdicts.Picture(s);
        string value;
        if (s.LossPerMinute is { } loss && s.StallsPerMinute is { } stalls)
            value = text.Format("health.check.picture.rate", (long)Math.Round(loss),
                stalls.ToString("0.0", UiLanguage.CultureFor(text.Language)));
        else if (!s.HasData) value = text.Get("health.check.notStarted");
        else if (!s.Streaming) value = text.Get("health.check.picture.noPicture");
        else value = text.Get("health.check.picture.measuring");
        var advice = level.AtLeastWarning() ? text.Get("health.check.picture.advice") : null;
        return new HealthCheckRow(HealthCheckId.Picture, text.Get("health.check.picture.name"), level, value, advice);
    }

    static HealthCheckRow SpeedRow(HealthCheckInput input, ITextSource text)
    {
        var s = input.Snapshot;
        var level = HealthVerdicts.Speed(s);
        string value;
        if (s.MedianTranslationMs is { } ms)
            value = text.Format("health.check.speed.perLine",
                (ms / 1000.0).ToString("0.0", UiLanguage.CultureFor(text.Language)), (long)s.Translations);
        else if (!s.HasData) value = text.Get("health.check.notStarted");
        else if (s.Lines > 0) value = text.Format("health.check.speed.allInstant", (long)s.Lines);
        else value = text.Get("health.check.speed.noSubtitles");
        string? advice = null;
        if (level.AtLeastWarning())
            advice = text.Get(input.OnlineOrLocalModel
                ? "health.check.speed.advice.freeEngine"
                : "health.check.speed.advice.closeApps");
        return new HealthCheckRow(HealthCheckId.Speed, text.Get("health.check.speed.name"), level, value, advice);
    }

    static HealthCheckRow TvRow(HealthCheckInput input, ITextSource text)
    {
        HealthLevel level;
        if (!input.Translating || !input.SendingToTv) level = HealthLevel.Unknown;
        else level = input.ConnectedTvs > 0 ? HealthLevel.Good : HealthLevel.Problem;
        string value;
        if (!input.SendingToTv) value = text.Get("health.check.tv.notSent");
        else if (!input.Translating) value = text.Get("health.check.notStarted");
        else value = text.Get(input.ConnectedTvs > 0 ? "status.common.connected" : "status.common.notConnected");
        var advice = level.AtLeastWarning() ? text.Get("health.check.tv.advice") : null;
        return new HealthCheckRow(HealthCheckId.Tv, text.Get("reading.target.tv"), level, value, advice);
    }
}
