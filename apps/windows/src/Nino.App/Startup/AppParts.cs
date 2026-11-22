// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Shell.Platform;

namespace Nino.App.Startup;

/// <summary>Denetleyicinin Windows parçaları (Windows hizmetlerinin <c>WindowsPlatform.Create</c> sonucu).</summary>
/// <param name="Services">Ağ, cihaz ve dosya işleri.</param>
/// <param name="Secrets">DPAPI'li şifreli depo (<c>secure.dat</c>).</param>
/// <param name="Settings">Ayar dosyası.</param>
/// <param name="Sleep">Uyku engelleyici.</param>
public sealed record PlatformPieces(IShellServices Services, ISecretStore Secrets, ISettingsStore Settings, ISleepGuard Sleep);

/// <summary>
/// Açılışın başka bölümlerden aldığı parçalar. Her parça bir kısmi yöntemdir: gövdesi o parçayı yazan bölümde
/// (ya da birleştirmede) yazılır; yazılmamışsa parça yok sayılır. Böylece açılış, öbür bölümler bitmeden de derlenir.
/// </summary>
public static partial class AppParts
{
    /// <summary>Windows hizmetleri: <c>WindowsPlatform.Create(dataFolder, post)</c>.</summary>
    public static PlatformPieces? CreatePlatform(string dataFolder, Action<Action> post)
    {
        PlatformPieces? pieces = null;
        CreatePlatform(dataFolder, post, ref pieces);
        return pieces;
    }

    /// <summary>Uygulama içi PSN giriş penceresi (kurulum bölümü); yoksa null (giriş tarayıcıda yapılır).</summary>
    public static IPsnSignInWindow? CreatePsnSignInWindow()
    {
        IPsnSignInWindow? window = null;
        CreatePsnSignInWindow(ref window);
        return window;
    }

    static partial void CreatePlatform(string dataFolder, Action<Action> post, ref PlatformPieces? pieces);

    static partial void CreatePsnSignInWindow(ref IPsnSignInWindow? window);
}
