// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Settings;

/// <summary>Bir tuşun kısayol olup olamayacağı.</summary>
public enum HotkeyValidity
{
    Valid,
    /// <summary>Adı olmayan tuş (ör. Esc, F12).</summary>
    Unsupported,
    /// <summary>Ctrl+Alt (= AltGr; yazı karakterlerini bozar).</summary>
    AltGr,
    /// <summary>Alt+F4: Windows'un kendi işi.</summary>
    Reserved,
    /// <summary>Harf, rakam, ok gibi tuşlar değiştirici ister.</summary>
    NeedsModifier,
}

/// <summary>Tutulacak tek kısayol: tablo sırası (kimlik için), iş, yuva, tuş.</summary>
public sealed record ResolvedHotkey(int Index, HotkeyAction Action, int Slot, HotkeyKey Key);

/// <summary>Atama sonucu: dosyaya yazılacak liste ve (varsa) tuşu elinden alınan başka iş.</summary>
public sealed record HotkeyAssignment(List<HotkeyBinding> Bindings, HotkeyAction? Displaced);

/// <summary>Kısayol tablosu, varsayılanlar, geçerlilik, adlar, çözümleme ve atama.</summary>
public static class Hotkeys
{
    /// <summary>Tablodaki iş sırası (her yuvada).</summary>
    public static IReadOnlyList<HotkeyAction> ActionOrder { get; } =
    [
        HotkeyAction.ExtraRegion1, HotkeyAction.ExtraRegion2, HotkeyAction.ExtraRegion3, HotkeyAction.FreeArea,
        HotkeyAction.Snapshot, HotkeyAction.PauseSubtitles, HotkeyAction.Screen, HotkeyAction.ClickThrough,
    ];

    /// <summary>İşin rakamı.</summary>
    public static int Digit(HotkeyAction action) => action switch
    {
        HotkeyAction.ExtraRegion1 => 1,
        HotkeyAction.ExtraRegion2 => 2,
        HotkeyAction.ExtraRegion3 => 3,
        HotkeyAction.FreeArea => 5,
        HotkeyAction.Snapshot => 8,
        HotkeyAction.PauseSubtitles => 0,
        HotkeyAction.Screen => 9,
        HotkeyAction.ClickThrough => 7,
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    /// <summary>Tablo sırası: önce bütün yuva 0'lar, sonra yuva 1'ler; her yuvada iş sırası.</summary>
    public static IReadOnlyList<(HotkeyAction Action, int Slot)> Table { get; } =
        [.. ActionOrder.Select(a => (a, 0)), .. ActionOrder.Select(a => (a, 1))];

    /// <summary>Varsayılan tuş: yuva 0 → Num rakam; yuva 1 → Ctrl+Shift+rakam.</summary>
    public static HotkeyKey DefaultKey(HotkeyAction action, int slot) => slot == 0
        ? new HotkeyKey(KeyModifiers.None, 0x60 + Digit(action))
        : new HotkeyKey(KeyModifiers.Control | KeyModifiers.Shift, 0x30 + Digit(action));

    /// <summary>Bir yuvanın tuşu: listedeki son öğe; öğe yoksa varsayılan; <c>Key: null</c> ise null (kapalı).</summary>
    public static HotkeyKey? KeyFor(IReadOnlyList<HotkeyBinding>? bindings, HotkeyAction action, int slot)
    {
        if (bindings is not null)
            for (var i = bindings.Count - 1; i >= 0; i--)
                if (bindings[i].Action == action && bindings[i].Slot == slot)
                    return bindings[i].Key;
        return DefaultKey(action, slot);
    }

    /// <summary>Tuşun adı (kısayol olabilmesi için gerekir); adı yoksa null.</summary>
    public static string? KeyName(int vk) => vk switch
    {
        (>= 0x30 and <= 0x39) or (>= 0x41 and <= 0x5A) => char.ConvertFromUtf32(vk),
        >= 0x60 and <= 0x69 => "Num " + (vk - 0x60),
        0x6A => "Num *",
        0x6B => "Num +",
        0x6D => "Num -",
        0x6E => "Num .",
        0x6F => "Num /",
        0x7B => null,
        >= 0x70 and <= 0x87 => "F" + (vk - 0x6F),
        0x13 => "Pause",
        0x91 => "Scroll Lock",
        0x2D => "Insert",
        0x24 => "Home",
        0x23 => "End",
        0x21 => "Page Up",
        0x22 => "Page Down",
        0x25 => "←",
        0x26 => "↑",
        0x27 => "→",
        0x28 => "↓",
        _ => null,
    };

    /// <summary>Ekrandaki ad: "Ctrl", "Alt", "Shift" (olanlar, bu sırayla) + tuş, <c>+</c> ile.</summary>
    public static string DisplayName(HotkeyKey key)
    {
        var parts = new List<string>(4);
        if (key.Modifiers.HasFlag(KeyModifiers.Control)) parts.Add("Ctrl");
        if (key.Modifiers.HasFlag(KeyModifiers.Alt)) parts.Add("Alt");
        if (key.Modifiers.HasFlag(KeyModifiers.Shift)) parts.Add("Shift");
        var keyName = KeyName(key.VirtualKey);
        parts.Add(keyName ?? "0x" + key.VirtualKey.ToString("X2", System.Globalization.CultureInfo.InvariantCulture));
        return string.Join("+", parts);
    }

    /// <summary>Tuş geçerliliği (tarifteki kural sırasıyla).</summary>
    public static HotkeyValidity Validate(HotkeyKey key)
    {
        var vk = key.VirtualKey;
        var m = key.Modifiers;
        if (KeyName(vk) is null) return HotkeyValidity.Unsupported;
        if (m.HasFlag(KeyModifiers.Control) && m.HasFlag(KeyModifiers.Alt)) return HotkeyValidity.AltGr;
        if (m.HasFlag(KeyModifiers.Alt) && vk == 0x73) return HotkeyValidity.Reserved;
        if (vk is >= 0x60 and <= 0x6F or >= 0x70 and <= 0x87 or 0x13 or 0x91) return HotkeyValidity.Valid;
        var mods = m & (KeyModifiers.Alt | KeyModifiers.Control | KeyModifiers.Shift);
        return mods is (KeyModifiers.Control | KeyModifiers.Shift) or KeyModifiers.Alt
            or (KeyModifiers.Alt | KeyModifiers.Shift)
            ? HotkeyValidity.Valid
            : HotkeyValidity.NeedsModifier;
    }

    /// <summary>
    /// Tutulacak kısayollar: tablo sırasıyla her yuvanın tuşu; kapalı, geçersiz ya da daha önce verilmiş tuş atlanır.
    /// </summary>
    public static IReadOnlyList<ResolvedHotkey> Resolve(IReadOnlyList<HotkeyBinding>? bindings)
    {
        var result = new List<ResolvedHotkey>();
        var taken = new HashSet<HotkeyKey>();
        for (var i = 0; i < Table.Count; i++)
        {
            var (action, slot) = Table[i];
            var key = KeyFor(bindings, action, slot);
            if (key is null || Validate(key) != HotkeyValidity.Valid || !taken.Add(key)) continue;
            result.Add(new ResolvedHotkey(i, action, slot, key));
        }
        return result;
    }

    /// <summary>
    /// Ayarlar'da tuş atama: seçilen yuvaya yeni tuş (null = kapat) konur; aynı tuş başka yuvadaysa o yuva kapanır.
    /// Dönen liste yalnız varsayılandan farklı yuvaları içerir.
    /// </summary>
    public static HotkeyAssignment Assign(IReadOnlyList<HotkeyBinding>? bindings, HotkeyAction action, int slot,
        HotkeyKey? key)
    {
        var map = Table.ToDictionary(t => t, t => KeyFor(bindings, t.Action, t.Slot));
        HotkeyAction? displaced = null;
        if (key is not null)
        {
            foreach (var entry in Table)
            {
                if (entry == (action, slot) || map[entry] != key) continue;
                map[entry] = null;
                if (entry.Action != action) displaced ??= entry.Action;
            }
        }
        map[(action, slot)] = key;

        var list = new List<HotkeyBinding>();
        foreach (var entry in Table)
            if (map[entry] != DefaultKey(entry.Action, entry.Slot))
                list.Add(new HotkeyBinding { Action = entry.Action, Slot = entry.Slot, Key = map[entry] });
        return new HotkeyAssignment(list, displaced);
    }
}
