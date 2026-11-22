// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.TvInstall;

/// <summary>Samsung ve Android TV kurulumunun hata türleri. Adlar yardımcının JSON <c>code</c> değeriyle birebir aynıdır.</summary>
public enum TvInstallFailure
{
    Unreachable,
    LoginFailed,
    CertificateFailed,
    TooOld,
    InstallFailed,
    NotEnoughSpace,
    CertificateMismatch,
    CertificateRejected,
    TvClockWrong,
    PackageBlocked,
    ConnectionLost,
    NotApproved,
}

/// <summary>Kurulum hatası: tür + isteğe bağlı ayrıntı. İleti "Tür: ayrıntı" (ayrıntı yoksa yalnız tür).</summary>
public sealed class TvInstallException : Exception
{
    public TvInstallException(TvInstallFailure failure, string? detail = null, Exception? inner = null)
        : base(string.IsNullOrEmpty(detail) ? failure.ToString() : $"{failure}: {detail}", inner)
    {
        Failure = failure;
        Detail = detail ?? "";
    }

    public TvInstallFailure Failure { get; }

    /// <summary>Ayrıntı (boş olabilir).</summary>
    public string Detail { get; }
}

/// <summary>Kurulumun sonucu: TV'deki sürüm ve gerçekten kurulup kurulmadığı.</summary>
public sealed record TvInstallResult(string Version, bool Installed);
