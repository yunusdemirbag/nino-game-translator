// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Linux.Imaging;

namespace Nino.Linux.Ports;

/// <summary>
/// Panelin konuştuğu taraf: ortak çekirdeğin denetleyicisi üstüne kurulan uyarlayıcı. Panel her çağrıyı
/// <see cref="Hosting.SerialWorker"/> üzerinden yapar; uygulayıcı tek iş parçacığından çağrıldığını varsayabilir.
/// Kullanıcının düzeltebileceği hatalar <see cref="PanelProblem"/> (ya da <see cref="InvalidOperationException"/>)
/// olarak atılır ve panelde eylemin yanında gösterilir.
/// </summary>
public interface INinoBackend : IDisposable
{
    PanelState State();

    /// <summary>PSN giriş yönlendirmesinin öneki (yalnız kodu yapıştıranlar için tam adres buradan kurulur).</summary>
    string RedirectPrefix { get; }

    Task AdvanceAsync();
    Task BackAsync();
    Task SignInAsync(Uri redirect);
    Task<IReadOnlyList<PanelConsole>> FindConsolesAsync();
    Task RegisterConsoleAsync(string host, string pin);
    Task<IReadOnlyList<PanelTv>> FindTvsAsync();
    Task PairTvAsync(PanelTv tv);
    Task InstallTvAppAsync(string passphrase);
    Task RefreshTvAppAsync();
    Task DownloadModelAsync();
    Task SendTestSubtitleAsync();
    Task ResetAsync();
    Task StartAsync();
    Task StopAsync();
    Task TogglePauseAsync();

    /// <summary>Yalnız verilen alanlar değişir; bölge panelde doğrulanmıştır.</summary>
    Task ChangeSettingsAsync(PanelRegion? region, JsonObject? style, bool? onlineTranslation);

    Task<KeyCheck> SaveOnlineKeyAsync(string key);
    Task RemoveOnlineKeyAsync();

    /// <summary>PS5'ten gelen son kare; yoksa null.</summary>
    BgraPicture? LatestFrame { get; }

    /// <summary>Son karede altyazı bölgesini bir kez okur (sıra dışında, iş parçacığı havuzunda çalışabilir).</summary>
    Task<RegionProbe> ProbeRegionAsync(BgraPicture frame);

    Task<SampleTranslation> TranslateSampleAsync(string text);
}

/// <summary>Kullanıcıya gösterilecek, düzeltilebilir bir sorun (HTTP 400).</summary>
public sealed class PanelProblem(string message) : Exception(message);
