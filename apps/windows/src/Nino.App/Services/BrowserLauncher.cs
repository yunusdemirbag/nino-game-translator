// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Runtime.InteropServices;
using Nino.Core.Logging;
using Nino.Shell.Platform;

namespace Nino.App.Services;

/// <summary>
/// Varsayılan tarayıcıda açma (kimlikler-veri §12.3): açmadan hemen önce "her süreç öne gelebilir" izni verilir
/// (Samsung giriş sayfası arkada açılıp görünmüyordu). Açılamazsa <c>hata.log</c>'a ve <c>tvinstall.log</c>'a yazılır.
/// </summary>
public sealed class BrowserLauncher(ErrorLog? errors = null, TvInstallLog? tvInstall = null) : IBrowser
{
    const int AnyProcess = -1;

    [DllImport("user32.dll")]
    static extern bool AllowSetForegroundWindow(int processId);

    /// <inheritdoc />
    public void Open(string url) => TryOpen(url);

    /// <summary>Açar; açılamazsa false.</summary>
    public bool TryOpen(string url)
    {
        try
        {
            try { AllowSetForegroundWindow(AnyProcess); }
            catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { }
            using var _ = Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            return true;
        }
        catch (Exception e)
        {
            try
            {
                errors?.Write("Tarayıcı açılamadı", e);
                tvInstall?.Write($"Tarayıcı açılamadı: {url}: {e.GetType().Name}: {e.Message}");
            }
            catch (Exception) { }
            return false;
        }
    }
}
