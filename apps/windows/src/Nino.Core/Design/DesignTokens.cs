// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;

namespace Nino.Core.Design;

/// <summary>Bir rengin açık ve koyu temadaki değeri ("#RRGGBB").</summary>
public sealed record ThemeColor(string Light, string Dark)
{
    /// <summary>İstenen temadaki değer.</summary>
    public string Pick(bool dark) => dark ? Dark : Light;
}

/// <summary>Bir yazı stilinin boyu ve kalınlığı ("regular", "medium", "semibold").</summary>
public sealed record TypeStyle(double Size, string Weight);

/// <summary>
/// Tasarım belirteçleri: renkler (açık/koyu), yazı boyları, boşluk, köşe ve ölçüler. Uygulamaya gömülü
/// <c>design/tokens.json</c>'dan okunur; Windows ve Linux arayüzleri buradan kendi kaynaklarını türetir.
/// </summary>
public sealed class DesignTokens
{
    /// <summary>Gömülü kaynağın adı.</summary>
    public const string ResourceName = "design/tokens.json";

    public required string Name { get; init; }
    public required int Version { get; init; }
    /// <summary>Platform → yazı ailesi adı (ör. "windows" → "Segoe UI Variable").</summary>
    public required IReadOnlyDictionary<string, string> FontFamily { get; init; }
    public required IReadOnlyDictionary<string, ThemeColor> Colors { get; init; }
    public required IReadOnlyDictionary<string, TypeStyle> Fonts { get; init; }
    public required IReadOnlyDictionary<string, double> Space { get; init; }
    public required IReadOnlyDictionary<string, double> Radius { get; init; }
    public required IReadOnlyDictionary<string, double> Size { get; init; }

    private static readonly Lazy<DesignTokens> Embedded = new(LoadEmbedded);

    /// <summary>Gömülü belirteçler (bir kez okunur). Bulunamazsa ya da bozuksa hata fırlatır.</summary>
    public static DesignTokens Default => Embedded.Value;

    /// <summary>Renk değeri; yoksa hata.</summary>
    public ThemeColor Color(string name) =>
        Colors.TryGetValue(name, out var c) ? c : throw new KeyNotFoundException("Tasarım rengi yok: " + name);

    private static DesignTokens LoadEmbedded()
    {
        using var stream = typeof(DesignTokens).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidDataException("Gömülü tasarım belirteçleri bulunamadı: " + ResourceName);
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    }

    /// <summary>JSON'dan okur. Alan adları harf duyarsız, bilinmeyen alanlar atlanır. Bozuksa hata fırlatır.</summary>
    public static DesignTokens Parse(string json)
    {
        using var doc = JsonDocument.Parse(json, new JsonDocumentOptions
        {
            CommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        });
        var root = doc.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new InvalidDataException("Tasarım belirteçleri bir nesne olmalı.");

        string name = "";
        int version = 0;
        var fontFamily = NewMap<string>();
        var colors = NewMap<ThemeColor>();
        var fonts = NewMap<TypeStyle>();
        var space = NewMap<double>();
        var radius = NewMap<double>();
        var size = NewMap<double>();

        foreach (var prop in root.EnumerateObject())
        {
            switch (prop.Name.ToLowerInvariant())
            {
                case "name": name = prop.Value.GetString() ?? ""; break;
                case "version": version = prop.Value.GetInt32(); break;
                case "fontfamily":
                    foreach (var f in Objects(prop)) fontFamily[f.Name] = f.Value.GetString() ?? "";
                    break;
                case "color":
                    foreach (var c in Objects(prop)) colors[c.Name] = ReadColor(c);
                    break;
                case "font":
                    foreach (var f in Objects(prop)) fonts[f.Name] = ReadFont(f);
                    break;
                case "space": ReadNumbers(prop, space); break;
                case "radius": ReadNumbers(prop, radius); break;
                case "size": ReadNumbers(prop, size); break;
            }
        }

        if (colors.Count == 0) throw new InvalidDataException("Tasarım belirteçlerinde renk yok.");
        return new DesignTokens
        {
            Name = name, Version = version, FontFamily = fontFamily, Colors = colors, Fonts = fonts,
            Space = space, Radius = radius, Size = size,
        };
    }

    private static Dictionary<string, T> NewMap<T>() => new(StringComparer.OrdinalIgnoreCase);

    private static JsonElement.ObjectEnumerator Objects(JsonProperty prop) =>
        prop.Value.ValueKind == JsonValueKind.Object
            ? prop.Value.EnumerateObject()
            : throw new InvalidDataException($"'{prop.Name}' bir nesne olmalı.");

    private static void ReadNumbers(JsonProperty prop, Dictionary<string, double> into)
    {
        foreach (var p in Objects(prop)) into[p.Name] = p.Value.GetDouble();
    }

    private static ThemeColor ReadColor(JsonProperty prop)
    {
        string? light = null, dark = null;
        foreach (var p in Objects(prop))
        {
            if (p.Name.Equals("light", StringComparison.OrdinalIgnoreCase)) light = p.Value.GetString();
            else if (p.Name.Equals("dark", StringComparison.OrdinalIgnoreCase)) dark = p.Value.GetString();
        }
        if (light is null || dark is null)
            throw new InvalidDataException($"'{prop.Name}' renginin açık ya da koyu değeri yok.");
        return new ThemeColor(light, dark);
    }

    private static TypeStyle ReadFont(JsonProperty prop)
    {
        double? fontSize = null;
        string weight = "regular";
        foreach (var p in Objects(prop))
        {
            if (p.Name.Equals("size", StringComparison.OrdinalIgnoreCase)) fontSize = p.Value.GetDouble();
            else if (p.Name.Equals("weight", StringComparison.OrdinalIgnoreCase)) weight = p.Value.GetString() ?? "regular";
        }
        return new TypeStyle(fontSize ?? throw new InvalidDataException($"'{prop.Name}' yazısının boyu yok."),
            weight.ToLowerInvariant());
    }

    /// <summary>Belirteç adı ile WPF/GTK kaynak adının ortak kuralı: renk fırçası "&lt;ad&gt;Brush".</summary>
    public static string BrushKey(string colorName) => colorName + "Brush";

    /// <summary>Renk kaynağı adı: "&lt;ad&gt;Color".</summary>
    public static string ColorKey(string colorName) => colorName + "Color";
}
