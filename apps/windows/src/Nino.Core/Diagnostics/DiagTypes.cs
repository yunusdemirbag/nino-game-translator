// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Core.Telemetry;

namespace Nino.Core.Diagnostics;

/// <summary>
/// Bekçinin kendisinin bilemediği, tetik anında okunan durum (hepsi isteğe bağlı; yalnız sayı, doğru/yanlış, kod).
/// </summary>
public sealed record DiagHostState
{
    /// <summary>Bağlı TV sayısı.</summary>
    public int? TvCount { get; init; }

    /// <summary>TV protokolü: <c>nino</c> ya da <c>legacy</c>.</summary>
    public string? Proto { get; init; }

    /// <summary>Son karenin ortalama parlaklığı (0–255).</summary>
    public double? FrameLuma { get; init; }

    /// <summary>Kareler bir süredir hep aynı mı.</summary>
    public bool? FrameSame { get; init; }

    /// <summary>Okuma alanı elle seçilmiş mi.</summary>
    public bool? RegionManual { get; init; }

    /// <summary>En çok kullanılan çevirmenin ölçüm adı (<c>deepl</c>, <c>gemini</c>, <c>free</c>…).</summary>
    public string? Provider { get; init; }

    /// <summary>Isı durumu: <c>nominal</c>/<c>fair</c>/<c>serious</c>/<c>critical</c>.</summary>
    public string? Thermal { get; init; }

    /// <summary>Yazı tanımayı bekleyen kare sayısı.</summary>
    public int? Queue { get; init; }
}

/// <summary>Gönderilen bir teşhis bildirimi (yalnız kodlar; cümle uygulamanın ekranında koddan üretilir).</summary>
/// <param name="Rule">Kural kodu.</param>
/// <param name="Cause">Sebep kodu.</param>
/// <param name="Severity">Önem.</param>
/// <param name="At">Tetik anı (koşulun ilk sağlandığı an; olayın <c>t</c>'si).</param>
/// <param name="Body">Süzülmüş <c>diag</c> olayı.</param>
public sealed record DiagReport(string Rule, string Cause, DiagSeverity Severity, DateTimeOffset At, JsonObject Body)
{
    /// <summary>Ölçüm kuyruğuna eklenecek olay.</summary>
    public TelemetryEvent? ToTelemetryEvent() => TelemetryEvent.Diag((JsonObject)Body.DeepClone());
}

/// <summary>Bekçinin kurulumu.</summary>
public sealed record DiagOptions
{
    /// <summary>Saat (testte sahte).</summary>
    public TimeProvider Clock { get; init; } = TimeProvider.System;

    /// <summary>Tetik anında okunan durum.</summary>
    public Func<DiagHostState>? State { get; init; }

    /// <summary>Bağlı TV'nin markası, modeli, TV'deki Nino sürümü.</summary>
    public Func<DiagTv?>? Tv { get; init; }

    /// <summary>Oyun kimliği (havuz biçimi).</summary>
    public Func<string?>? Game { get; init; }

    /// <summary>Bileşen sürümleri (<c>core</c>, <c>remoteplay</c>, <c>ocr</c>, <c>tvApp</c>…).</summary>
    public Func<IReadOnlyDictionary<string, string?>>? Versions { get; init; }

    /// <summary>Günlük sınır sayımı (null: yalnız bellekte).</summary>
    public DiagDailyLimits? Limits { get; init; }

    /// <summary>Platformun varsayılan eşikleri (ör. telefonda bellek 800); uzak ayar bunların üstüne gelir.</summary>
    public IReadOnlyDictionary<string, double>? PlatformDefaults { get; init; }
}
