// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay.Tests;

public class DataTests
{
    [Fact]
    public void WakeCredentialIsHexOfRegistKeyPrefix()
    {
        byte[] key = [.. "1a2b3c4d"u8.ToArray(), 0, 0, 0, 0, 0, 0, 0, 0];
        Assert.Equal(0x1a2b3c4dUL, Ps5Console.ComputeWakeCredential(key));
        Assert.Null(Ps5Console.ComputeWakeCredential(new byte[16]));
        Assert.Null(Ps5Console.ComputeWakeCredential("zz\0"u8.ToArray()));
        Assert.Null(Ps5Console.ComputeWakeCredential(null));
    }

    [Fact]
    public void KeysAreFittedToFixedLength()
    {
        Assert.Equal(new byte[] { 1, 2, 0, 0 }, KeyBytes.Fit([1, 2], 4));
        Assert.Equal(new byte[] { 1, 2 }, KeyBytes.Fit([1, 2, 3], 2));
        Assert.Equal(new byte[3], KeyBytes.Fit(null, 3));
    }

    [Fact]
    public void FixedNameStopsAtFirstZero()
    {
        Assert.Equal("PS5-123", NativeBridge.FixedName("PS5-123\0garbage"u8));
        Assert.Equal("abc", NativeBridge.FixedName("abc"u8));
    }

    [Fact]
    public void LegacyConsoleRecordIsRead()
    {
        // Eski uygulamanın yazdığı biçim; WakeCredential yok sayılır.
        string legacy = "{\"Host\":\"192.168.0.5\",\"Name\":\"PS5-123\",\"RegistKey\":\"MWEyYjNjNGQAAAAAAAAAAA==\","
                        + "\"Morning\":\"AQEBAQEBAQEBAQEBAQEBAQ==\",\"WakeCredential\":439041101}";
        Ps5Console? c = RemotePlayRecords.ConsoleFromJsonText(legacy);
        Assert.NotNull(c);
        Assert.Equal("192.168.0.5", c.Host);
        Assert.Equal("PS5-123", c.Name);
        Assert.Equal(16, c.RegistKey.Length);
        Assert.Equal(0x1a2b3c4dUL, c.WakeCredential);
        Assert.All(c.Morning, b => Assert.Equal(1, b));

        // WakeCredential null ve anahtarlar 16 bayt değil: olduğu gibi okunur, köprüye giderken sabit uzunluğa getirilir.
        Ps5Console? odd = RemotePlayRecords.ConsoleFromJsonText(
            "{\"Host\":\"10.0.0.2\",\"Name\":\"PS5\",\"RegistKey\":\"AQI=\",\"Morning\":\"AQIDBAUGBwgJCgsMDQ4PEBES\",\"WakeCredential\":null}");
        Assert.NotNull(odd);
        Assert.Equal(new byte[] { 1, 2 }, odd.RegistKey);
        Assert.Equal(18, odd.Morning.Length);
        Assert.Null(odd.WakeCredential);
    }

    [Fact]
    public void ConsoleRecordRoundTripsWithLegacyFieldNames()
    {
        var c = Samples.Console();
        JsonObject json = RemotePlayRecords.ConsoleToJson(c);
        Assert.Equal("192.168.1.70", (string?)json["Host"]);
        Assert.Equal("PS5-123", (string?)json["Name"]);
        Assert.Equal(Convert.ToBase64String(c.RegistKey), (string?)json["RegistKey"]);
        Assert.Equal(Convert.ToBase64String(c.Morning), (string?)json["Morning"]);
        Assert.Equal(0x1a2b3c4dUL, (ulong?)json["WakeCredential"]);

        Ps5Console? back = RemotePlayRecords.ConsoleFromJson(JsonNode.Parse(json.ToJsonString()));
        Assert.NotNull(back);
        Assert.Equal(c.Host, back.Host);
        Assert.Equal(c.RegistKey, back.RegistKey);
        Assert.Equal(c.Morning, back.Morning);
    }

    [Fact]
    public void BrokenConsoleRecordsAreIgnored()
    {
        Assert.Null(RemotePlayRecords.ConsoleFromJsonText(null));
        Assert.Null(RemotePlayRecords.ConsoleFromJsonText("not json"));
        Assert.Null(RemotePlayRecords.ConsoleFromJsonText("{\"Name\":\"PS5\"}"));
        Assert.Null(RemotePlayRecords.ConsoleFromJsonText("{\"Host\":\"1.2.3.4\",\"RegistKey\":\"!!\",\"Morning\":\"AA==\"}"));
        Assert.Null(RemotePlayRecords.ConsoleFromJsonText("\"text\""));
    }

    [Fact]
    public void AccountIdIsBase64String()
    {
        byte[] id = [1, 2, 3, 4, 5, 6, 7, 8];
        JsonNode node = RemotePlayRecords.AccountIdToJson(id);
        Assert.Equal("\"AQIDBAUGBwg=\"", node.ToJsonString());
        Assert.Equal(id, RemotePlayRecords.AccountIdFromJson(JsonNode.Parse("\"AQIDBAUGBwg=\"")));
        Assert.Null(RemotePlayRecords.AccountIdFromJson(JsonNode.Parse("12")));
        Assert.Null(RemotePlayRecords.AccountIdFromJson(null));
    }
}
