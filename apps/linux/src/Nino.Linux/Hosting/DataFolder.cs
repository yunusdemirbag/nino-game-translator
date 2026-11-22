// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Linux.Hosting;

/// <summary>
/// Sunucunun kalıcı verisinin durduğu yer. Docker imajı <c>NINO_DATA=/data</c> verir; verilmezse kullanıcının
/// yerel uygulama verisi altında "Nino" klasörü kullanılır.
/// </summary>
public sealed class DataFolder
{
    public DataFolder(string root) => Root = root;

    public string Root { get; }

    public static DataFolder FromEnvironment()
    {
        var chosen = Environment.GetEnvironmentVariable("NINO_DATA");
        if (string.IsNullOrWhiteSpace(chosen))
            chosen = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Nino");
        return new DataFolder(chosen);
    }

    public string File(string name) => Path.Combine(Root, name);

    public string SecretsFile => File("secure.json");
    public string SettingsFile => File("settings.json");
    public string ModelsFolder => File("models");
    public string RemotePlayLog => File("remoteplay.log");
    public string TvInstallLog => File("tvinstall.log");

    public void Ensure() => Directory.CreateDirectory(Root);
}
