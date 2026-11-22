// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Core.Text;

/// <summary>
/// Bir işin kısayol tuşlarının ekrandaki metni. Tuş yoksa yok; bir tuşsa adı; iki ya da daha çoksa ilk ikisi
/// "A ya da B". Başlıkta tuş yoksa "kısayol yok"; cümlede tuş yoksa cümlenin yerine "kısayol atanmamış" cümlesi.
/// </summary>
public static class ShortcutText
{
    /// <summary>Ayarlar › Kısayollar'daki sıra (en çok kullanılandan aza).</summary>
    public static IReadOnlyList<HotkeyAction> DisplayOrder { get; } =
    [
        HotkeyAction.Screen, HotkeyAction.FreeArea, HotkeyAction.ExtraRegion1, HotkeyAction.ExtraRegion2,
        HotkeyAction.ExtraRegion3, HotkeyAction.PauseSubtitles, HotkeyAction.ClickThrough, HotkeyAction.Snapshot,
    ];

    /// <summary>İşin adının katalog anahtarı.</summary>
    public static string ActionKey(HotkeyAction action) => action switch
    {
        HotkeyAction.Screen => "shortcut.action.translateScreen",
        HotkeyAction.FreeArea => "shortcut.action.freeArea",
        HotkeyAction.ExtraRegion1 => "shortcut.action.translateArea1",
        HotkeyAction.ExtraRegion2 => "shortcut.action.translateArea2",
        HotkeyAction.ExtraRegion3 => "shortcut.action.translateArea3",
        HotkeyAction.PauseSubtitles => "shortcut.action.pauseResume",
        HotkeyAction.ClickThrough => "shortcut.action.clickThrough",
        HotkeyAction.Snapshot => "shortcut.action.refreshPicture",
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    /// <summary>İşin çalışan tuşlarının adları, yuva sırasıyla.</summary>
    public static IReadOnlyList<string> KeyNames(IReadOnlyList<HotkeyBinding>? bindings, HotkeyAction action) =>
        Hotkeys.Resolve(bindings)
            .Where(h => h.Action == action)
            .OrderBy(h => h.Slot)
            .Select(h => Hotkeys.DisplayName(h.Key))
            .ToList();

    /// <summary>Tuşların metni; tuş yoksa null.</summary>
    public static string? Keys(ITextSource text, IReadOnlyList<string> keyNames) => keyNames.Count switch
    {
        0 => null,
        1 => keyNames[0],
        _ => text.Format("shortcut.keysTwo", keyNames[0], keyNames[1]),
    };

    /// <summary>Tuşların metni; tuş yoksa null.</summary>
    public static string? Keys(ITextSource text, IReadOnlyList<HotkeyBinding>? bindings, HotkeyAction action) =>
        Keys(text, KeyNames(bindings, action));

    /// <summary>Başlık biçimi: tuşlar ya da "kısayol yok".</summary>
    public static string ForTitle(ITextSource text, IReadOnlyList<HotkeyBinding>? bindings, HotkeyAction action) =>
        Keys(text, bindings, action) ?? text.Get("shortcut.none");

    /// <summary>
    /// Cümle biçimi: tuş varsa <paramref name="sentenceKey"/> metni tuşlarla doldurulur (tek <c>%@</c>); yoksa
    /// bütün cümlenin yerine "kısayol atanmamış" cümlesi.
    /// </summary>
    public static string ForSentence(ITextSource text, string sentenceKey, IReadOnlyList<HotkeyBinding>? bindings,
        HotkeyAction action) =>
        Keys(text, bindings, action) is { } keys ? text.Format(sentenceKey, keys) : text.Get("shortcut.noneSentence");
}
