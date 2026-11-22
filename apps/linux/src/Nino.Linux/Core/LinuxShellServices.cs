// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Reading;
using Nino.Shell.Platform;
using Nino.TvInstall;

namespace Nino.Linux.Core;

/// <summary>
/// Çekirdeğin platform hizmetlerinin Linux hâli. PS5, TV, çeviri ve model işleri çekirdekten olduğu gibi gelir;
/// Linux yalnız okuyucuyu (Tesseract) ve kendi ayarlarını verir: veri klasörü, eski ONNX Türkçe modelinin korunması,
/// gönderici kimliği. Ortak havuz ve paket sunucusu kapalıdır (eski Linux sunucusunda da yoktu); kullanıcının kendi
/// paket klasörü çekirdekteki gibi okunur.
/// </summary>
public sealed class LinuxShellServices(LinuxPlatform platform) : CoreShellServices(new CoreShellServicesOptions
{
    DataFolder = platform.Data.Root,
    Secrets = platform.Secrets,
    Http = platform.Http,
    AppVersion = platform.Version,
    TvAppFolder = Path.Combine(AppContext.BaseDirectory, TvAppPackages.FolderName),
    KeepLegacyTurkish = true,
    RemotePlayLog = platform.RemotePlayLog,
    Identity = new SenderIdentity
    {
        Name = Environment.MachineName,
        Id = platform.InstallId,
        Device = "Linux",
        Client = $"nino-linux/{platform.Version}",
    },
})
{
    public override ITextReaderFactory Readers { get; } = new TesseractReaders(platform.Readers);

    /// <summary>Okuyucu fabrikası: Tesseract; oyun dilinin verisi yoksa İngilizce veriyle.</summary>
    private sealed class TesseractReaders(ReaderCache cache) : ITextReaderFactory
    {
        public ITextReader? Create(string language) => cache.For(language);

        public bool HasLanguagePack(string language) => Ocr.TesseractReader.IsAvailable(language);

        public byte[]? SmallJpeg(BgraFrame frame, int maxWidth, int quality) => null;
    }
}

/// <summary>Denetleyicinin günlükleri: remoteplay.log (PS5 kütüphanesiyle aynı dosya), altyazi.log, hata.log.</summary>
public sealed class LinuxShellLogs(LinuxPlatform platform) : IShellLogs
{
    public string? RemotePlayLogPath => platform.Data.RemotePlayLog;

    public void RemotePlay(string line) => platform.RemotePlayLog.Nino(line);

    public void Subtitle(string line) => platform.SubtitleLog.Write(line);

    public void Error(string message, Exception? error = null)
    {
        platform.ErrorLog.Write(message, error);
        platform.Journal.Write("hata", error is null ? message : $"{message}: {error.Message}");
    }
}
