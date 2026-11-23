// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.TvInstall;

/// <summary>
/// Eski sürümlerden kalan TV uygulaması kimlikleri. Yalnız eski uygulamayı bulup kaldırmak için vardır; arayüzde hiç
/// gösterilmez. Kaynakta düz yazı olarak durmasınlar diye base64 saklanır ve bu dosyadan başka hiçbir yerde geçmezler.
/// </summary>
public static class LegacyNames
{
    static string Unpack(string encoded) => Encoding.UTF8.GetString(Convert.FromBase64String(encoded));

    /// <summary>Eski Android TV uygulamasının paket adı (yenisinin yanında kalırsa o da bağlanıp altyazı çizer).</summary>
    public static string AndroidTvPackage { get; } = Unpack("Y29tLmNvdWNoc3Vicy50dg==");
}
