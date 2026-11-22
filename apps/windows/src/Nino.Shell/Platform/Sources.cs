// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.RemotePlay;

namespace Nino.Shell.Platform;

// Görüntü kaynakları. Hepsi Nino.RemotePlay'deki IVideoSource "yayın oturumu" sözleşmesini taşır (kare, durum, konsol
// yeni adreste; başlat, durdur [bloklamaz], şimdi yeniden bağlan, bırak). Olaylar kaynağın kendi iş parçacığındadır.

/// <summary>Ekrandaki bir dikdörtgen (piksel).</summary>
public readonly record struct PixelRect(int X, int Y, int Width, int Height);

/// <summary>Oyunun penceresi okuyucusunun durumu (adları cihaz bilgisine metin olarak yazılır).</summary>
public enum WindowCaptureState { Stopped, LookingForWindow, Capturing }

/// <summary>HDMI yakalama kartının durumu (adları cihaz bilgisine metin olarak yazılır).</summary>
public enum CardCaptureState { Stopped, NeedsPermission, NoCard, BlackPicture, Capturing }

/// <summary>Kartın durumu ve (görüntü varken) aygıtın adı.</summary>
public sealed record CardStatus(CardCaptureState State, string? DeviceName = null);

/// <summary>Yerel bilgisayardaki oyun penceresini (PS Remote Play / chiaki-ng ya da Xbox penceresi) okuyan kaynak.</summary>
public interface IGameWindowSource : IVideoSource
{
    /// <summary>Pencere durumu ve okunan uygulamanın gösterilen adı.</summary>
    event Action<WindowCaptureState, string?>? WindowStateChanged;

    /// <summary>Oyun alanının ekrandaki yeri ya da yok.</summary>
    event Action<PixelRect?>? GameAreaChanged;
}

/// <summary>HDMI yakalama kartı kaynağı.</summary>
public interface ICaptureCardSource : IVideoSource
{
    /// <summary>Kart durumu.</summary>
    event Action<CardStatus>? CardStatusChanged;

    /// <summary>Oyunu gösteren pencerenin oyun alanı ya da yok.</summary>
    event Action<PixelRect?>? GameAreaChanged;

    /// <summary>Oyunu bu bilgisayarda gösteren pencereyi kullanıcı kapattı (çeviri durur).</summary>
    event Action? GameWindowClosed;

    /// <summary>Oyun penceresinin tam ekran durumunu tersine çevirir.</summary>
    void ToggleFullScreen();
}

/// <summary>Seçilebilecek görünür bir pencere.</summary>
public sealed record VisibleWindow(string ProcessName, string Title);

/// <summary>Xbox girişi için Microsoft'un verdiği kod.</summary>
public sealed record XboxSignInCode(string UserCode, string Url, TimeSpan ExpiresIn);

/// <summary>Xbox doğrudan ev yayını hizmeti (yalnız Windows; köprü süreci).</summary>
public interface IXboxService : IDisposable
{
    /// <summary>Hizmet jetonu kendisi yeniledi (herhangi bir iş parçacığından).</summary>
    event Action<string>? TokenRefreshed;

    /// <summary>Girişi ve önbelleği temizler ("Tümünü sıfırla").</summary>
    void Clear();

    /// <summary>Girişi başlatır: kod, adres, süre.</summary>
    Task<XboxSignInCode> BeginSignInAsync(CancellationToken cancellationToken = default);

    /// <summary>Kullanıcı kodu girince jetonu döner.</summary>
    Task<string> FinishSignInAsync(CancellationToken cancellationToken = default);

    /// <summary>Hesaptaki konsollar.</summary>
    Task<IReadOnlyList<StoredXboxConsole>> FindConsolesAsync(string token, CancellationToken cancellationToken = default);

    /// <summary>
    /// Yayın oturumu. <paramref name="quality"/>: istenen görüntü (720p'de oturum açma isteğinin ekran boyu ve
    /// yayının çözünürlük üst sınırı 1280×720 olur; kendiliğinden ise 1920×1080).
    /// </summary>
    IVideoSource CreateStream(StoredXboxConsole console, string token, bool legacyFrameRate, XboxStreamQuality quality);
}
