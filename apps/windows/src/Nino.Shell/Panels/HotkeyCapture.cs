// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Shell.Panels;

/// <summary>Ayarlar › Kısayollar'da bekleyen yuvaya basılan tuşun sonucu.</summary>
public enum CaptureStepKind
{
    /// <summary>Yalnız değiştirici: beklemeye devam.</summary>
    Wait,

    /// <summary>Değiştiricisiz Esc: kayıt bırakılır, değişiklik yok.</summary>
    Cancel,

    /// <summary>Değiştiricisiz Geri silme / Delete: yuva kapatılır.</summary>
    Clear,

    /// <summary>Hata (beklemeye devam): <see cref="CaptureStep.Problem"/>.</summary>
    Error,

    /// <summary>Atanacak tuş: <see cref="CaptureStep.Key"/>.</summary>
    Assign,
}

/// <summary>Tuşun sonucu. Hata ise <see cref="Problem"/> doğrulama sonucudur (Win tuşu "ayrılmış" sayılır).</summary>
public sealed record CaptureStep(CaptureStepKind Kind, HotkeyKey? Key = null, HotkeyValidity Problem = HotkeyValidity.Valid);

/// <summary>Kısayol kaydının tuş kararı (ayarlar tarifi §9.2); Windows sanal tuş kodlarıyla.</summary>
public static class HotkeyCapture
{
    const int Escape = 0x1B, Back = 0x08, Delete = 0x2E;

    /// <summary>Değiştirici tuş mu (Shift, Ctrl, Alt, Win; sol/sağ).</summary>
    public static bool IsModifier(int vk) => vk is 0x10 or 0x11 or 0x12 or >= 0xA0 and <= 0xA5 or 0x5B or 0x5C;

    /// <summary>Basılan tuşun sonucu.</summary>
    public static CaptureStep Decide(int vk, bool control, bool alt, bool shift, bool windows)
    {
        if (IsModifier(vk)) return new CaptureStep(CaptureStepKind.Wait);
        var noModifier = !control && !alt && !shift && !windows;
        if (noModifier && vk == Escape) return new CaptureStep(CaptureStepKind.Cancel);
        if (noModifier && vk is Back or Delete) return new CaptureStep(CaptureStepKind.Clear);
        if (windows) return new CaptureStep(CaptureStepKind.Error, Problem: HotkeyValidity.Reserved);
        var mods = KeyModifiers.None;
        if (control) mods |= KeyModifiers.Control;
        if (alt) mods |= KeyModifiers.Alt;
        if (shift) mods |= KeyModifiers.Shift;
        var key = new HotkeyKey(mods, vk);
        var validity = Hotkeys.Validate(key);
        return validity == HotkeyValidity.Valid
            ? new CaptureStep(CaptureStepKind.Assign, key)
            : new CaptureStep(CaptureStepKind.Error, key, validity);
    }

    /// <summary>Doğrulama sorununun katalog anahtarı.</summary>
    public static string ProblemKey(HotkeyValidity problem) => problem switch
    {
        HotkeyValidity.AltGr => "settings.shortcuts.error.altGr",
        HotkeyValidity.Reserved => "settings.shortcuts.error.reserved",
        HotkeyValidity.NeedsModifier => "settings.shortcuts.error.needsModifier",
        _ => "settings.shortcuts.error.unsupported",
    };
}
