// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Core;

/// <summary>
/// Eski sürümlerden kalan adlar. Yalnız eski kayıtları bulup taşımak için vardır; arayüzde hiç gösterilmez.
/// Kaynakta düz yazı olarak durmasınlar diye base64 saklanır ve bu dosyadan başka hiçbir yerde geçmezler.
/// </summary>
public static class LegacyNames
{
    static string Unpack(string encoded) => Encoding.UTF8.GetString(Convert.FromBase64String(encoded));

    /// <summary>Eski veri klasörünün (ve eski güvenlik duvarı kuralının) adı.</summary>
    public static string DataFolder { get; } = Unpack("Q291Y2hTdWJz");

    /// <summary>
    /// Asıl (eski adlı) uygulamanın Velopack kurulum klasörü, %LOCALAPPDATA% altında. Varsa eski veri klasörü onunla
    /// ortaktır: taşınmaz, kopyalanır. (Ad temizliği sırasında eski kodda yanlışlıkla "NinoApp" olmuştu.)
    /// </summary>
    public static string InstallFolder { get; } = DataFolder + "App";

    /// <summary>Asıl (eski adlı) uygulamanın çalıştırılabilir dosyası; açık süreç adı uzantısız olarak bundan çıkar.</summary>
    public static string Executable { get; } = DataFolder + ".exe";

    /// <summary>Eski şifreli dosyanın DPAPI ek anahtarı.</summary>
    public static byte[] SecretsEntropy { get; } =
        Encoding.UTF8.GetBytes(Unpack("Y291Y2hzdWJzLXNlY3VyZS1zdG9yZQ=="));
}
