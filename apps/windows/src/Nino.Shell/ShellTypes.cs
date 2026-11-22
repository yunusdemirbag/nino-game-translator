// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Tv;
using Nino.Shell.Platform;

namespace Nino.Shell;

/// <summary>Kurulum sihirbazının adımları (sırasıyla).</summary>
public enum SetupStep
{
    Welcome,
    SecondAccount,
    PsnSignIn,
    Console,
    Tv,
    Model,
    Test,
    BetterTranslation,
    Done,
}

/// <summary>Çevirmenin durumu (ana ekran uyarısı).</summary>
public enum TranslatorStatus
{
    Ready,
    Unsupported,
    DownloadRequired,
    EngineFailed,
}

/// <summary>TV uygulaması kartının türü.</summary>
public enum TvAppKind
{
    /// <summary>Bilinmiyor (kart yok).</summary>
    Unknown,

    /// <summary>Kuruluyor.</summary>
    Installing,

    /// <summary>Hazır (sürüm).</summary>
    UpToDate,

    /// <summary>Geliştirici modu (ya da Android'de hata ayıklama) kapalı.</summary>
    DevModeOff,

    /// <summary>LG: parola gerekiyor.</summary>
    PassphraseNeeded,

    /// <summary>Kurulamadı.</summary>
    Failed,

    /// <summary>Samsung: tarayıcıda giriş bekleniyor.</summary>
    SamsungSignIn,

    /// <summary>Android: TV ekranında onay bekleniyor.</summary>
    ConfirmOnTv,
}

/// <summary>TV uygulaması kartının durumu. Metinleri arayüz yazar.</summary>
/// <param name="Kind">Tür.</param>
/// <param name="Version">Sürüm (hazırken).</param>
/// <param name="Error">Hata (başarısız ya da parola gerekiyor hâlinde).</param>
/// <param name="Reason">Sebep metni (kurallı; boş olabilir).</param>
/// <param name="TvHostPcIp">Samsung Host PC uyuşmazlığında TV'deki adres.</param>
/// <param name="ThisComputer">Yerel bilgisayarın adresi (Samsung Host PC IP olarak yazılacak).</param>
/// <param name="SignInUrl">Samsung giriş sayfası.</param>
public sealed record TvAppStatus(TvAppKind Kind, string? Version = null, TvError? Error = null, string? Reason = null,
    string? TvHostPcIp = null, string? ThisComputer = null, string? SignInUrl = null)
{
    /// <summary>Bilinmiyor.</summary>
    public static TvAppStatus Unknown { get; } = new(TvAppKind.Unknown);
}

/// <summary>Güvenlik duvarı önerisinin durumu.</summary>
public enum FirewallHint
{
    /// <summary>Yok.</summary>
    None,

    /// <summary>Öner (düğme).</summary>
    Suggest,

    /// <summary>Windows izni bekleniyor.</summary>
    Working,

    /// <summary>İzin verildi.</summary>
    Allowed,

    /// <summary>Başarısız (düğme yeniden).</summary>
    Failed,

    /// <summary>Kural var ama ağ Ortak (düğme yok; ağı Özel yapın).</summary>
    PublicNetwork,
}

/// <summary>Ayarlar ekranındaki güvenlik duvarı bilgisi.</summary>
public sealed record FirewallInfo(bool HasRule, bool PublicNetwork);

/// <summary>Tek seferlik okuma (ek bölge, serbest alan, ekranı çevir) sonucu.</summary>
public enum OneShotResult
{
    /// <summary>Gösterildi.</summary>
    Shown,

    /// <summary>Yazı yok.</summary>
    NoText,

    /// <summary>Bölge ayarlı değil.</summary>
    NotConfigured,

    /// <summary>Çeviri ya da okuyucu yok.</summary>
    NotRunning,

    /// <summary>Önceki istek sürüyor.</summary>
    Busy,

    /// <summary>Çevirmen kullanılamıyor.</summary>
    NoTranslator,

    /// <summary>Başarısız.</summary>
    Failed,

    /// <summary>Ekran çevirisi temizlendi.</summary>
    Cleared,
}

/// <summary>Serbest seçim okumasının sonucu: sonuç türü ve (gösterildiyse) çeviri.</summary>
public sealed record FreeAreaResult(OneShotResult Result, string? Source = null, string? Translation = null, int DurationMs = 0);

/// <summary>Bilgisayar penceresine giden kısa açılır ileti (ek bölge).</summary>
public sealed record PopupText(string Text, int DurationMs);
