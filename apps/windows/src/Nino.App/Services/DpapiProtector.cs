// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Security.Cryptography;
using Nino.Core.Data;

namespace Nino.App.Services;

/// <summary>Windows veri koruması (DPAPI), geçerli kullanıcı kapsamı: <c>secure.dat</c>'ın şifresi.</summary>
public sealed class DpapiProtector : ISecretProtector
{
    /// <inheritdoc />
    public byte[] Protect(byte[] plain, byte[] entropy) =>
        ProtectedData.Protect(plain, entropy, DataProtectionScope.CurrentUser);

    /// <inheritdoc />
    public byte[] Unprotect(byte[] protectedBytes, byte[] entropy) =>
        ProtectedData.Unprotect(protectedBytes, entropy, DataProtectionScope.CurrentUser);
}
