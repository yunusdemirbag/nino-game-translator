// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Shell;

// Kurulum sihirbazı ekranlarının denetleyiciden istediği küçük ekler (kurulum.md §3, §4, §8.1). Ağ ya da disk okuyan
// her şey özellik değil yöntemdir: gözlenen özellikler her yenilemede okunur.
public sealed partial class NinoController
{
    /// <summary>Yerel bilgisayarın TV'ye dönük adresi (Samsung "Host PC IP"); bilinmiyorsa null. Ağı okur.</summary>
    public string? ThisComputerAddress()
    {
        try { return _services.AddressNear(_tv?.Host); }
        catch (Exception) { return null; }
    }

    /// <summary>
    /// Yerel bilgisayarda ne PS Remote Play ne de chiaki-ng kurulu mu ("otomatik" uygulama seçimiyle; İkinci hesap adımının
    /// indirme bölümü). Diske bakar.
    /// </summary>
    public bool IsRemotePlayAppMissing()
    {
        try { return !_services.IsRemotePlayAppInstalled(RemotePlayApp.Automatic); }
        catch (Exception) { return false; }
    }

    /// <summary>remoteplay.log'a ekranın notu (ör. WebView2 eksik notu).</summary>
    public void NoteRemotePlay(string line) => _logs.RemotePlay(line);

    /// <summary>remoteplay.log'un tam yolu (biliniyorsa).</summary>
    public string? RemotePlayLogPath => _logs.RemotePlayLogPath;

    /// <summary>
    /// Giriş penceresi yönlendirme olmadan kapandığında gösterilecek ileti (<see cref="SignInToPsnAsync"/> ile aynı
    /// kural): sorun yoksa "pencere kapandı", "429" içeriyorsa sınır, değilse "sayfa açılamadı (sorun)" + günlük ipucu.
    /// Günlüğe de yazılır.
    /// </summary>
    public string PsnWindowClosedText(string? problem)
    {
        _logs.RemotePlay("PSN oturumu tamamlanmadan giriş penceresi kapatıldı" + (string.IsNullOrWhiteSpace(problem) ? "" : ": " + problem));
        if (string.IsNullOrWhiteSpace(problem)) return _text.Get("wizard.psn.error.windowClosed");
        if (problem.Contains("429", StringComparison.Ordinal)) return _text.Get("wizard.psn.error.rateLimited");
        return $"{_text.Get("wizard.psn.error.pageFailed")} ({problem}) {LogHint()}";
    }
}
