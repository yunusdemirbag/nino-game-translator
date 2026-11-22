// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using System.Text.Json.Nodes;

namespace Nino.RemotePlay;

/// <summary>
/// Remote Play kayıtlarının saklandığı yer (uygulamada şifreli depo; bağlamayı denetleyici yapar).
/// Değerlerin biçimi <see cref="RemotePlayRecords"/> ile şifreli depodaki eski kayıtlarla birebir uyumludur.
/// </summary>
public interface IRemotePlayStore
{
    /// <summary>8 baytlık PSN hesap numarası (anahtar <c>accountId</c>) ya da yok.</summary>
    byte[]? LoadAccountId();
    void SaveAccountId(byte[] accountId);

    /// <summary>Eşleşmiş PS5 (anahtar <c>console</c>) ya da yok.</summary>
    Ps5Console? LoadConsole();
    void SaveConsole(Ps5Console console);

    /// <summary>İkinci hesabın PS5 oturum şifresi (anahtar <c>loginPasscode</c>) ya da yok.</summary>
    string? LoadLoginPasscode();
}

/// <summary>Şifreli depodaki Remote Play değerlerinin JSON biçimi (anahtar adları ve alanlar eski kayıtlarla aynı).</summary>
public static class RemotePlayRecords
{
    public const string AccountIdKey = "accountId";
    public const string ConsoleKey = "console";
    public const string LoginPasscodeKey = "loginPasscode";

    /// <summary>Hesap kimliği: base64 dizgesi, ör. <c>"AQIDBAUGBwg="</c>.</summary>
    public static JsonNode AccountIdToJson(byte[] accountId) => JsonValue.Create(Convert.ToBase64String(accountId));

    public static byte[]? AccountIdFromJson(JsonNode? node)
    {
        if (node is not JsonValue value || !value.TryGetValue(out string? text) || string.IsNullOrEmpty(text))
            return null;
        try
        {
            return Convert.FromBase64String(text);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    /// <summary>
    /// PS5 kaydı: <c>{"Host","Name","RegistKey"(base64),"Morning"(base64),"WakeCredential"}</c>.
    /// WakeCredential eski sürümlerin okuyabilmesi için yazılır; okurken yok sayılır.
    /// </summary>
    public static JsonObject ConsoleToJson(Ps5Console console)
    {
        ulong? wake = console.WakeCredential;
        return new JsonObject
        {
            ["Host"] = console.Host,
            ["Name"] = console.Name,
            ["RegistKey"] = Convert.ToBase64String(console.RegistKey),
            ["Morning"] = Convert.ToBase64String(console.Morning),
            ["WakeCredential"] = wake is { } w ? JsonValue.Create(w) : null,
        };
    }

    public static Ps5Console? ConsoleFromJson(JsonNode? node)
    {
        if (node is not JsonObject obj)
            return null;
        string? host = Text(obj, "Host");
        if (string.IsNullOrEmpty(host))
            return null;
        byte[]? key = Bytes(obj, "RegistKey");
        byte[]? morning = Bytes(obj, "Morning");
        if (key is null || morning is null)
            return null;
        return new Ps5Console(host, Text(obj, "Name") ?? "", key, morning);
    }

    public static string ConsoleToJsonText(Ps5Console console) => ConsoleToJson(console).ToJsonString();

    public static Ps5Console? ConsoleFromJsonText(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
            return null;
        try
        {
            return ConsoleFromJson(JsonNode.Parse(json));
        }
        catch (JsonException)
        {
            return null;
        }
    }

    static JsonNode? Field(JsonObject obj, string name)
    {
        if (obj.TryGetPropertyValue(name, out JsonNode? exact))
            return exact;
        foreach (var pair in obj)
            if (string.Equals(pair.Key, name, StringComparison.OrdinalIgnoreCase))
                return pair.Value;
        return null;
    }

    static string? Text(JsonObject obj, string name) =>
        Field(obj, name) is JsonValue v && v.TryGetValue(out string? s) ? s : null;

    static byte[]? Bytes(JsonObject obj, string name)
    {
        string? text = Text(obj, name);
        if (text is null)
            return null;
        try
        {
            return Convert.FromBase64String(text);
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
