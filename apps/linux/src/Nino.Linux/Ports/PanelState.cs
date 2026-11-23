// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;

namespace Nino.Linux.Ports;

// Panelin /api/state ile okuduğu durum. Alan adları panel sayfasının sözleşmesidir (JSON'da camelCase).

public sealed record PanelState
{
    public string Version { get; init; } = "0";
    public string Language { get; init; } = "en";
    public string Step { get; init; } = "Welcome";
    public int StepNumber { get; init; } = 1;
    public int StepCount { get; init; } = 8;
    public bool CanAdvance { get; init; }
    public bool HasAccount { get; init; }
    public string PsnLoginUrl { get; init; } = "";
    public string RedirectPrefix { get; init; } = "";
    public PanelDevice? Console { get; init; }
    public PanelTv? Tv { get; init; }
    public PanelTvApp TvApp { get; init; } = new();
    public bool CanInstallTvApp { get; init; }
    public string? BundledTvApp { get; init; }
    public int? DevModeHoursLeft { get; init; }
    public string? ComputerAddress { get; init; }
    public int ServerPort { get; init; }
    public PanelModel Model { get; init; } = new();
    public bool Running { get; init; }
    public bool Starting { get; init; }
    public bool Paused { get; init; }
    public PanelPs5 Ps5 { get; init; } = new();
    public PanelTvStatus TvStatus { get; init; } = new();
    public string? LastSource { get; init; }
    public string? LastTranslation { get; init; }
    public string Translator { get; init; } = "Ready";
    public bool OcrMissing { get; init; }
    public bool NativeAvailable { get; init; }
    public bool HasFrame { get; init; }
    public bool HasDeepLKey { get; init; }
    public string? OnlineEngine { get; init; }
    public PanelSettings Settings { get; init; } = new();
    /// <summary>Çekirdek henüz bağlı değilse panel bunu gösterir.</summary>
    public string? Notice { get; init; }
    /// <summary>Nino sitesindeki rehberler (arayüz diline göre).</summary>
    public PanelGuides Guides { get; init; } = new("", "", "");
}

public sealed record PanelDevice(string Name, string Host);

public sealed record PanelTv(string Name, string Host, string Brand);

public sealed record PanelTvApp(string Kind = "Unknown", string? Version = null, string? Error = null, string? Url = null, string? Reason = null);

public sealed record PanelModel(bool Installed = false, bool Downloading = false, double Progress = 0, string? Error = null);

public sealed record PanelPs5(string Text = "", string Tone = "Idle", string? Phase = null, string? Reason = null, string? Detail = null);

public sealed record PanelTvStatus(string Text = "", string Tone = "Idle", int Clients = 0);

/// <summary>Altyazı bölgesi, karenin kenarlarına oranla (0–1).</summary>
public sealed record PanelRegion(double Top = 0.62, double Bottom = 0.97, double Left = 0.14, double Right = 0.86);

/// <summary>TV görünümü; panel yalnız yazı boyu ve yeri değiştirir, öbür alanlar olduğu gibi geri gönderilir.</summary>
public sealed record PanelSettings
{
    public PanelRegion Region { get; init; } = new();
    public JsonObject Style { get; init; } = new();
    public string SourceLanguage { get; init; } = "en";
    public string TargetLanguage { get; init; } = "tr";
    public bool OnlineTranslation { get; init; }
    public bool ShowSpeakerNames { get; init; } = true;
}

/// <summary>Rehber bağlantıları: kurulum, TV uygulamasını elle kurma, sitenin kökü (kaynak kodu ve lisans).</summary>
public sealed record PanelGuides(string Setup, string TvApp, string Site);

public sealed record PanelConsole(string Name, string Host, bool IsAwake);

public sealed record RegionProbe(long Ms, int Width, int Height, string[] Lines, string Subtitle);

public sealed record SampleTranslation(string Text, long Ms, string Engine);

public sealed record KeyCheck(string State);
