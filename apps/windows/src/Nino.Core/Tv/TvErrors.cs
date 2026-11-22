// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Tv;

/// <summary>TV kurulumu ve bağlantısının ortak hata türleri (kullanıcı metinleri uygulama katmanında).</summary>
public enum TvError
{
    Unreachable,
    KeyServerClosed,
    WrongPassphrase,
    KeyRejected,
    InstallFailed,
    ToolMissing,
    TooOld,
    LoginFailed,
    CertificateFailed,
    NotApproved,
    NotEnoughSpace,
    CertificateMismatch,
    CertificateRejected,
    TvClockWrong,
    PackageBlocked,
    ConnectionLost,
    HostPcMismatch,
}

/// <summary>Türü ve isteğe bağlı ayrıntısı olan TV hatası.</summary>
public sealed class TvException(TvError error, string? detail = null, Exception? inner = null)
    : Exception(detail is { Length: > 0 } ? $"{error}: {detail}" : error.ToString(), inner)
{
    public TvError Error { get; } = error;
    public string Detail { get; } = detail ?? "";
}

/// <summary>
/// TV uzaktan kumanda bağlantısının (LG SSAP, Samsung) hatası. <see cref="Reason"/> kısa İngilizce sebep:
/// <c>cannot connect</c>, <c>timeout</c>, <c>closed</c>, <c>rejected</c>, <c>bad response</c> ya da TV'nin metni.
/// <see cref="IsProtocol"/>: TV yanıt verdi ama kabul etmedi (diğer uç denenmez).
/// </summary>
public sealed class TvRemoteException(string reason, bool isProtocol = false, Exception? inner = null)
    : Exception(reason, inner)
{
    public const string CannotConnect = "cannot connect";
    public const string Timeout = "timeout";
    public const string Closed = "closed";
    public const string Rejected = "rejected";
    public const string BadResponse = "bad response";

    public string Reason { get; } = reason;
    public bool IsProtocol { get; } = isProtocol;
}
