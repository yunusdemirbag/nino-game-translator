// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Translation;

namespace Nino.Core.Library;

/// <summary>Okuma hattının o anki dil ve ayar durumu (her satırda okunur).</summary>
/// <param name="Source">Kaynak dil.</param>
/// <param name="Target">Hedef dil.</param>
/// <param name="GamePacks">"Paketler" ayarı.</param>
/// <param name="SharePool">"Ortak havuz" ayarı.</param>
/// <param name="PoolFirst">Oyun havuz öncelikli mi (havuzun kararı, o anki oyunla).</param>
public readonly record struct LookupState(string Source, string Target, bool GamePacks, bool SharePool, bool PoolFirst)
{
    /// <summary>Paketler etkin: ayar açık, kaynak <c>en</c>, hedef <c>tr</c>.</summary>
    public bool PacksEnabled =>
        GamePacks && TargetLanguages.Code(Source) == "en" && TargetLanguages.Code(Target) == "tr";
}

/// <summary>
/// Satır kuyruğa girerken "paket + havuz bakışı" (çeviri tarifi §1, madde 1): paketler etkinse ve oyun havuz
/// öncelikli değilse parçalı paket araması; bulunmadıysa (ortak havuz açık ya da havuz öncelikli ise) indirilmiş havuz
/// çevirilerinde satırın tamamı. Kaynak <c>en</c> değilse bakılmaz.
/// </summary>
public sealed class SubtitleLookup(PackLibrary? packs, TranslationPool? pool)
{
    /// <summary>Bulunan çeviri ve kaynağı (<c>true</c>: paket, <c>false</c>: havuz); yoksa null.</summary>
    public (string Text, bool FromPack)? Find(string text, LookupState state)
    {
        if (TargetLanguages.Code(state.Source) != "en") return null;
        if (packs is not null && state.PacksEnabled && !state.PoolFirst && packs.Lookup(text) is { } packed)
            return (packed, true);
        if (pool is not null && (state.SharePool || state.PoolFirst) && pool.Lookup(text) is { } pooled)
            return (pooled, false);
        return null;
    }

    /// <summary>
    /// Satır havuza önerilmeli mi (havuz/paket tarifi §6.1 sonu): kaynak <c>en</c>; paketler kapalıysa (ve oyun havuz
    /// öncelikli değilse) yalnız hiçbir pakette bulunmayan satır.
    /// </summary>
    public bool ShouldSuggest(string text, LookupState state)
    {
        if (TargetLanguages.Code(state.Source) != "en") return false;
        if (!state.PacksEnabled && !state.PoolFirst && packs is not null) return packs.FindAnyPack(text) is null;
        return true;
    }
}
