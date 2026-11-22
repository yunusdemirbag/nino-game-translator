// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Core.Tests.Settings;

public class HotkeyTests
{
    static HotkeyKey K(KeyModifiers m, int vk) => new(m, vk);

    const KeyModifiers C = KeyModifiers.Control, A = KeyModifiers.Alt, S = KeyModifiers.Shift, N = KeyModifiers.None;

    [Fact]
    public void Gecerlilik()
    {
        Assert.Equal(HotkeyValidity.Valid, Hotkeys.Validate(K(N, 0x69)));
        Assert.Equal(HotkeyValidity.Valid, Hotkeys.Validate(K(N, 0x71)));
        Assert.Equal(HotkeyValidity.Unsupported, Hotkeys.Validate(K(N, 0x7B)));
        Assert.Equal(HotkeyValidity.Unsupported, Hotkeys.Validate(K(N, 0x1B)));
        Assert.Equal(HotkeyValidity.NeedsModifier, Hotkeys.Validate(K(N, 'T')));
        Assert.Equal(HotkeyValidity.NeedsModifier, Hotkeys.Validate(K(S, 'T')));
        Assert.Equal(HotkeyValidity.NeedsModifier, Hotkeys.Validate(K(C, 'C')));
        Assert.Equal(HotkeyValidity.Valid, Hotkeys.Validate(K(A, 'T')));
        Assert.Equal(HotkeyValidity.Valid, Hotkeys.Validate(K(A | S, 'T')));
        Assert.Equal(HotkeyValidity.Valid, Hotkeys.Validate(K(C | S, 'T')));
        Assert.Equal(HotkeyValidity.AltGr, Hotkeys.Validate(K(C | A, '3')));
        Assert.Equal(HotkeyValidity.Reserved, Hotkeys.Validate(K(A, 0x73)));
    }

    [Fact]
    public void Adlar()
    {
        Assert.Equal("Ctrl+Shift+9", Hotkeys.DisplayName(K(C | S, '9')));
        Assert.Equal("Alt+F2", Hotkeys.DisplayName(K(A, 0x71)));
        Assert.Equal("Num 9", Hotkeys.DisplayName(K(N, 0x69)));
        Assert.Equal("0x1B", Hotkeys.DisplayName(K(N, 0x1B)));
        Assert.Equal("F24", Hotkeys.KeyName(0x87));
    }

    [Fact]
    public void VarsayilanlarVeTabloSirasi()
    {
        Assert.Equal(16, Hotkeys.Table.Count);
        Assert.Equal((HotkeyAction.ExtraRegion1, 0), Hotkeys.Table[0]);
        Assert.Equal((HotkeyAction.ClickThrough, 0), Hotkeys.Table[7]);
        Assert.Equal((HotkeyAction.ExtraRegion1, 1), Hotkeys.Table[8]);
        Assert.Equal(K(C | S, 0x39), Hotkeys.DefaultKey(HotkeyAction.Screen, 1));
        var all = Hotkeys.Resolve([]);
        Assert.Equal(16, all.Count);
        Assert.Equal(0x61, all[0].Key.VirtualKey);
    }

    [Fact]
    public void CozumlemeGecersizVeTekrariAtlar()
    {
        var bindings = new List<HotkeyBinding>
        {
            new() { Action = HotkeyAction.Screen, Slot = 1, Key = K(N, 'A') },
            new() { Action = HotkeyAction.FreeArea, Slot = 1, Key = K(N, 0x69) },
        };
        var resolved = Hotkeys.Resolve(bindings);
        Assert.Equal(14, resolved.Count);
        Assert.DoesNotContain(resolved, r => r.Action == HotkeyAction.Screen && r.Slot == 1);
        Assert.DoesNotContain(resolved, r => r.Action == HotkeyAction.FreeArea && r.Slot == 1);
        Assert.Equal(resolved.Count, resolved.Select(r => r.Key).Distinct().Count());
    }

    [Fact]
    public void SonOgeGecerli()
    {
        var bindings = new List<HotkeyBinding>
        {
            new() { Action = HotkeyAction.Screen, Slot = 0, Key = K(A, 'S') },
            new() { Action = HotkeyAction.Screen, Slot = 0, Key = null },
        };
        Assert.Null(Hotkeys.KeyFor(bindings, HotkeyAction.Screen, 0));
    }

    [Fact]
    public void AtamaVeGidisDonus()
    {
        var first = Hotkeys.Assign([], HotkeyAction.Screen, 0, K(A | S, 'S'));
        var second = Hotkeys.Assign(first.Bindings, HotkeyAction.Screen, 1, null);
        var s = new AppSettings { Hotkeys = second.Bindings };
        var json = SettingsJson.Serialize(s);
        Assert.Contains("\"Screen\"", json);
        var back = SettingsJson.Deserialize(json);
        var screen = Hotkeys.Resolve(back.Hotkeys).Where(r => r.Action == HotkeyAction.Screen).ToArray();
        Assert.Single(screen);
        Assert.Equal(K(A | S, 'S'), screen[0].Key);
    }

    [Fact]
    public void BaskaIstenAlinanTuşBildirilir()
    {
        var result = Hotkeys.Assign([], HotkeyAction.Screen, 0, K(N, 0x61));
        Assert.Equal(HotkeyAction.ExtraRegion1, result.Displaced);
        Assert.Null(Hotkeys.KeyFor(result.Bindings, HotkeyAction.ExtraRegion1, 0));
        Assert.Equal(2, result.Bindings.Count);
    }
}
