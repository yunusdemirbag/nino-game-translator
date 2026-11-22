// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Tv;

/// <summary>TV markası (sayıları depodakiyle aynı).</summary>
public enum TvBrand
{
    Lg = 0,
    Samsung = 1,
    AndroidTv = 2,
}

/// <summary>Eşleşen TV (depodaki biçimi <c>Nino.Core.Data.StoredTv</c>). Android TV'nin adresi boş olabilir.</summary>
public sealed record TvRecord(string Name, string Host, TvBrand Brand)
{
    /// <summary>Kimlikler (LG/Android uygulaması, Samsung uygulaması ve paketi).</summary>
    public const string LgAppId = "com.ninotranslator.tv";
    public const string AndroidPackage = "com.ninotranslator.tv";
    public const string SamsungAppId = "NinoTVApps.Nino";
    public const string SamsungPackageId = "NinoTVApps";

    /// <summary>
    /// Saklanacak TV anahtarı: TV yeni (boş olmayan) jeton verdiyse o; boş verdiyse saklı olan korunur (boş jeton
    /// yazılırsa TV her bağlantıda yeniden izin sorar).
    /// </summary>
    public static string KeyToStore(string? saved, string? incoming) =>
        !string.IsNullOrEmpty(incoming) ? incoming : saved ?? "";
}
