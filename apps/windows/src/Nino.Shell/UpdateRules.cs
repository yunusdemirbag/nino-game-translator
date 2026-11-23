// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Tv;
using Nino.TvInstall;

namespace Nino.Shell;

/// <summary>"Güncellemeleri Denetle" sonucunun uygulama satırı.</summary>
public enum AppUpdateKind
{
    /// <summary>Henüz denetlenmedi (satır sürümü gösterir).</summary>
    Idle,

    /// <summary>Yeni sürüm aranıyor.</summary>
    Checking,

    /// <summary>Nino güncel.</summary>
    UpToDate,

    /// <summary>Yeni sürüm var (Kur düğmesi).</summary>
    Available,

    /// <summary>İniyor ve kuruluyor (ilerleme).</summary>
    Downloading,

    /// <summary>Güncelleme sunucusuna ulaşılamadı ya da kurulum yarıda kaldı.</summary>
    Failed,
}

/// <summary>Uygulama güncellemesinin gösterilen durumu.</summary>
/// <param name="Kind">Tür.</param>
/// <param name="Version">Bulunan yeni sürüm (varsa).</param>
/// <param name="Progress">İndirme ilerlemesi (0–1; yalnız indirirken).</param>
/// <param name="Error">Kurulum hatasının metni (yalnız kurulum yarıda kaldıysa; denetim hatasında null).</param>
public sealed record AppUpdateState(AppUpdateKind Kind, string? Version = null, double Progress = 0, string? Error = null)
{
    public static AppUpdateState Idle { get; } = new(AppUpdateKind.Idle);
}

/// <summary>Eşli TV'deki Nino'nun güncelleme durumu ("Güncellemeleri Denetle"nin TV satırı).</summary>
public enum TvUpdateKind
{
    /// <summary>Eşli TV yok ya da bu marka için paket yok: satır gösterilmez.</summary>
    None,

    /// <summary>TV'ye bakılıyor.</summary>
    Checking,

    /// <summary>TV'deki Nino güncel (<see cref="TvUpdateState.Installed"/>).</summary>
    UpToDate,

    /// <summary>TV'deki sürüm eski (Installed boşsa okunamadı): "Yeni Sürümü Kur".</summary>
    Outdated,

    /// <summary>TV kapalı ya da ağda bulunamadı.</summary>
    Unreachable,

    /// <summary>TV açık ama Nino açık değil; sürüm bilinmiyor.</summary>
    AppClosed,

    /// <summary>"Yeni Sürümü Kur"a basıldı, kurulum sürüyor.</summary>
    Installing,

    /// <summary>Kurulum kullanıcıdan bir şey bekliyor (parola, onay, giriş ya da hata): TV ayarlarındaki kartta sürer.</summary>
    ContinueInSettings,
}

/// <summary>TV satırının durumu.</summary>
/// <param name="Kind">Tür.</param>
/// <param name="Installed">TV'deki sürüm (güncel ya da eskiyken; okunamadıysa boş).</param>
/// <param name="Bundled">Nino'nun içindeki paketin sürümü.</param>
public sealed record TvUpdateState(TvUpdateKind Kind, string? Installed = null, string? Bundled = null)
{
    public static TvUpdateState None { get; } = new(TvUpdateKind.None);

    /// <summary>TV satırı "her şey güncel" sayılır mı (satır yoksa da evet).</summary>
    public bool IsCurrentOrAbsent => Kind is TvUpdateKind.None or TvUpdateKind.UpToDate;
}

/// <summary>Güncelleme denetiminin saf kuralları (Windows ve Linux aynı).</summary>
public static class UpdateRules
{
    /// <summary>"4.1.0" → "V4.1 (4.1.0)" (kısa ad: ilk iki parça; ön sürüm eki tam sürümde kalır).</summary>
    public static string VersionLine(string? version)
    {
        var full = string.IsNullOrWhiteSpace(version) ? "0.0" : version.Trim();
        var core = full.Split('-', '+')[0];
        var parts = core.Split('.');
        return $"V{string.Join('.', parts.Take(2))} ({full})";
    }

    /// <summary>"4.0.2 → 4.1.0"; okunamayan sürüm "?".</summary>
    public static string Versions(string? installed, string? bundled) =>
        $"{(string.IsNullOrWhiteSpace(installed) ? "?" : installed)} → {bundled}";

    /// <summary>
    /// TV'deki sürüm güncel mi: boşsa hayır; paket ondan katı karşılaştırmayla yeni değilse evet (kurulum yolunun
    /// "kurduğum sürüm eskidi mi" kuralıyla aynı; "eski" kararı her zaman gerçek kuruluma götürür).
    /// </summary>
    public static bool IsCurrent(string? installed, string bundled) =>
        !string.IsNullOrWhiteSpace(installed) && !TvVersions.IsNewerStrict(bundled, installed.Trim());

    /// <summary>TV'nin açık olduğunu anlamak için yoklanan uçlar (LG SSAP, Samsung uzaktan kumanda, Android ADB/Cast).</summary>
    public static IReadOnlyList<int> WakePorts(TvBrand brand) => brand switch
    {
        TvBrand.Lg => [3001, 3000],
        TvBrand.Samsung => [8001, 8002],
        _ => [5555, 8008, 8009],
    };

    /// <summary>
    /// Okunan bilgilerden TV satırının kararı.
    /// </summary>
    /// <param name="paired">Eşli TV var mı.</param>
    /// <param name="bundled">Paketin sürümü (bu marka için paket yoksa null).</param>
    /// <param name="connected">Şu an bağlı TV uygulamalarının bildirdiği sürümler (bildirmeyen null).</param>
    /// <param name="known">Bilinen sürüm (TV uygulaması kartı ya da saklı sürüm).</param>
    /// <param name="tvOn">TV açık mı (TV uygulaması bağlanmadıysa bakılır).</param>
    public static TvUpdateState DecideTv(bool paired, string? bundled, IReadOnlyCollection<string?> connected, string? known,
        bool tvOn)
    {
        if (!paired || string.IsNullOrWhiteSpace(bundled)) return TvUpdateState.None;
        if (connected.Count > 0)
        {
            var versions = connected.Where(v => !string.IsNullOrWhiteSpace(v)).Select(v => v!.Trim()).ToList();
            if (versions.Count == 0)
            {
                // Sürüm bildirmeyen uygulama (8787'de sürüm okunmaz): bilinen sürüm varsa ona göre, yoksa eski.
                return string.IsNullOrWhiteSpace(known) ? new TvUpdateState(TvUpdateKind.Outdated, "", bundled) : FromKnown(known, bundled);
            }
            var newest = versions.Aggregate((a, b) => TvVersions.IsNewerLoose(b, a) ? b : a);
            return FromKnown(newest, bundled);
        }
        if (!tvOn) return new TvUpdateState(TvUpdateKind.Unreachable, Bundled: bundled);
        if (string.IsNullOrWhiteSpace(known)) return new TvUpdateState(TvUpdateKind.AppClosed, Bundled: bundled);
        return FromKnown(known, bundled);
    }

    static TvUpdateState FromKnown(string installed, string bundled) => IsCurrent(installed, bundled)
        ? new TvUpdateState(TvUpdateKind.UpToDate, installed.Trim(), bundled)
        : new TvUpdateState(TvUpdateKind.Outdated, installed.Trim(), bundled);

    /// <summary>
    /// Kurulum başladıktan sonra TV uygulaması kartına göre gösterilen durum: kart hazırsa ve kurulum bittiyse güncel;
    /// kart kuruyorsa (ya da kurulum henüz başlamadıysa) kuruluyor; kart kullanıcıdan bir şey bekliyorsa ayarlarda sürer.
    /// </summary>
    /// <param name="state">Saklı durum.</param>
    /// <param name="card">TV uygulaması kartı.</param>
    /// <param name="installDone">"Yeni Sürümü Kur"un başlattığı denetim bitti mi.</param>
    public static TvUpdateState Resolve(TvUpdateState state, TvAppStatus card, bool installDone)
    {
        if (state.Kind != TvUpdateKind.Installing) return state;
        if (card.Kind == TvAppKind.UpToDate && installDone)
            return new TvUpdateState(TvUpdateKind.UpToDate, card.Version ?? state.Bundled, state.Bundled);
        if (card.Kind == TvAppKind.Installing || (!installDone && card.Kind is TvAppKind.Unknown or TvAppKind.UpToDate))
            return state;
        return state with { Kind = TvUpdateKind.ContinueInSettings };
    }
}
