// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Translation;

namespace Nino.Core.Library;

/// <summary>
/// Oyun paketlerinin dilleri. Sunucu her dil için ayrı paket verir (<c>v1/packs?lang=</c>); her dilin paketleri ayrı
/// klasördedir. Türkçe eski yerinde kalır (<c>packs</c>), diğerleri <c>packs-&lt;dil&gt;</c>.
/// </summary>
public static class PackLanguage
{
    /// <summary>Paketi olan hedef diller.</summary>
    public static IReadOnlyList<string> Supported { get; } = ["tr", "ar"];

    /// <summary>Hedef dilin paketi var mı.</summary>
    public static bool IsSupported(string? target) => Supported.Contains(TargetLanguages.Code(target ?? ""));

    /// <summary>Paket dili: desteklenen hedef dil, yoksa <c>tr</c>.</summary>
    public static string For(string? target)
    {
        var code = TargetLanguages.Code(target ?? "");
        return Supported.Contains(code) ? code : "tr";
    }

    /// <summary>Dilin paket klasörü (Türkçe: temel klasörün kendisi).</summary>
    public static string Folder(string baseFolder, string lang) =>
        lang == "tr" ? baseFolder : baseFolder.TrimEnd('/', '\\') + "-" + lang;

    /// <summary>Dilin durum dosyası (Türkçe: temel dosyanın kendisi; diğerleri <c>ad-&lt;dil&gt;.json</c>).</summary>
    public static string StateFile(string baseFile, string lang)
    {
        if (lang == "tr") return baseFile;
        var ext = Path.GetExtension(baseFile);
        return baseFile[..^ext.Length] + "-" + lang + ext;
    }
}
