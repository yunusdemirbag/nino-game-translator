// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows.Markup;
using Nino.Core.Text;

namespace Nino.App.Strings;

/// <summary>
/// Arayüz metinleri. Katalog <c>Nino.Core/Text/Catalog</c>'da (12 dil); Windows'ta arayüz dili Windows'un kendi
/// dilidir ve uygulama açıkken değişmez. Kodda <c>L.Get("common.settings")</c>, <c>L.Format("key", a, b)</c>.
/// </summary>
public static class L
{
    private static TextCatalog? _catalog;

    /// <summary>Kullanılan katalog; ilk erişimde Windows'un arayüz dilinden kurulur.</summary>
    public static TextCatalog Catalog
    {
        get => _catalog ??= TextCatalog.ForSystem();
        set => _catalog = value;
    }

    /// <summary>Arayüz dili ("tr", "en", "fil" …).</summary>
    public static string Language => Catalog.Language;

    /// <summary>Arayüz sağdan sola mı (Arapça, Urduca).</summary>
    public static bool IsRightToLeft => Catalog.IsRightToLeft;

    public static string Get(string key) => Catalog.Get(key);

    public static string Format(string key, params object?[] values) => Catalog.Format(key, values);

    /// <summary>Arayüz dilinin kültürüyle büyük harf.</summary>
    public static string Upper(string key) => Catalog.Upper(key);
}

/// <summary>
/// XAML'de metin: <c>Text="{s:T common.settings}"</c> (xmlns:s="clr-namespace:Nino.App.Strings"). Arayüz dili
/// açıkken değişmediği için değer bir kez okunur. <see cref="Upper"/> doğruysa büyük harfe çevrilir.
/// </summary>
[MarkupExtensionReturnType(typeof(string))]
public sealed class TExtension : MarkupExtension
{
    public TExtension() { }

    public TExtension(string key) => Key = key;

    [ConstructorArgument("key")]
    public string Key { get; set; } = "";

    public bool Upper { get; set; }

    public override object ProvideValue(IServiceProvider serviceProvider) => Upper ? L.Upper(Key) : L.Get(Key);
}
