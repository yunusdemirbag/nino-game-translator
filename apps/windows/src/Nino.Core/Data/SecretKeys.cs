// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Data;

/// <summary>Şifreli depodaki anahtar adları (eski dosyalarla birebir).</summary>
public static class SecretKeys
{
    public const string
        AccountId = "accountId",
        Console = "console",
        ConsoleKind = "consoleKind",
        ConsoleKindLocked = "consoleKindLocked",
        XboxToken = "xboxToken",
        XboxConsole = "xboxConsole",
        Tv = "tv",
        TvKey = "tvKey",
        TvDevKey = "tvDevKey",
        TvAppVersion = "tvAppVersion",
        LastGames = "lastGames",
        CaptureCardId = "captureCardId",
        StreamBackground = "streamBackground",
        SetupComplete = "setupComplete",
        LoginPasscode = "loginPasscode",
        DeepLKey = "deepLKey",
        GeminiKey = "geminiKey",
        OpenAIKey = "openAIKey",
        ClaudeKey = "claudeKey",
        LocalAIKey = "localAIKey",
        SamsungClientName = "samsungClientName";

    /// <summary>LG geliştirici modu süresinin bu TV için son uzatıldığı an: adres kırpılır, küçük harfe çevrilir.</summary>
    public static string DevSessionRenewed(string tvHost) =>
        "devSessionRenewed." + tvHost.Trim().ToLowerInvariant();

    /// <summary>"Tümünü sıfırla"da silinenler (çeviri anahtarları, oyunlar, kart, zemin, LG süreleri kalır).</summary>
    public static IReadOnlyList<string> ResetEverything { get; } =
    [
        AccountId, Console, ConsoleKind, ConsoleKindLocked, XboxToken, XboxConsole,
        Tv, TvKey, TvDevKey, TvAppVersion, SetupComplete, LoginPasscode,
    ];

    /// <summary>"TV'yi değiştir"de silinenler.</summary>
    public static IReadOnlyList<string> ResetTv { get; } = [Tv, TvKey, TvDevKey, TvAppVersion, SetupComplete];

    /// <summary>Listedeki anahtarları siler.</summary>
    public static void RemoveAll(this ISecretStore store, IEnumerable<string> keys)
    {
        foreach (var key in keys) store.Remove(key);
    }

    /// <summary>PS5 oturum şifresi: kırpılmış hali tam 4 rakamsa o, değilse null.</summary>
    public static string? NormalizePasscode(string? input)
    {
        var trimmed = input?.Trim();
        return trimmed is { Length: 4 } && trimmed.All(c => c is >= '0' and <= '9') ? trimmed : null;
    }

    /// <summary>Yayıncı penceresi zemini: harf duyarsız; bilinmeyen ya da boş değer yeşil.</summary>
    public static StreamBackground ParseStreamBackground(string? value) =>
        value?.Trim().ToLowerInvariant() switch
        {
            "black" => Data.StreamBackground.Black,
            "magenta" => Data.StreamBackground.Magenta,
            _ => Data.StreamBackground.Green,
        };

    /// <summary>Depoya yazılan ad (<c>green</c>, <c>black</c>, <c>magenta</c>).</summary>
    public static string ToStoredName(this StreamBackground value) => value switch
    {
        Data.StreamBackground.Black => "black",
        Data.StreamBackground.Magenta => "magenta",
        _ => "green",
    };
}

/// <summary>Yayıncı penceresi zemin rengi.</summary>
public enum StreamBackground
{
    Green,
    Black,
    Magenta,
}

/// <summary>Konsol türü (depoda sayı).</summary>
public enum StoredConsoleKind
{
    PlayStation = 0,
    Xbox = 1,
}

/// <summary>TV markası (depoda sayı).</summary>
public enum StoredTvBrand
{
    Lg = 0,
    Samsung = 1,
    AndroidTv = 2,
}

/// <summary><c>console</c> anahtarının biçimi.</summary>
public sealed record StoredConsole
{
    public string Host { get; init; } = "";
    public string Name { get; init; } = "";
    public byte[] RegistKey { get; init; } = [];
    public byte[] Morning { get; init; } = [];
    /// <summary>Hesaplanan alan; eski uygulama yazar ama okurken yok sayar.</summary>
    public ulong? WakeCredential { get; init; }
}

/// <summary><c>tv</c> anahtarının biçimi.</summary>
public sealed record StoredTv
{
    public string Name { get; init; } = "";
    public string Host { get; init; } = "";
    public StoredTvBrand Brand { get; init; } = StoredTvBrand.Lg;
}

/// <summary><c>xboxConsole</c> anahtarının biçimi.</summary>
public sealed record StoredXboxConsole
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string Model { get; init; } = "";
    public bool StreamingEnabled { get; init; }
}
