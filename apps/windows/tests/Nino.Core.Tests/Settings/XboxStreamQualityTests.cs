// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;

namespace Nino.Core.Tests.Settings;

/// <summary>Xbox yayın çözünürlüğü alanı: geriye uyumlu (varsayılanken yazılmaz, eski dosyada yoksa kendiliğinden).</summary>
public sealed class XboxStreamQualityTests
{
    [Fact]
    public void DefaultIsNotWritten()
    {
        var json = SettingsJson.Serialize(new AppSettings());
        Assert.DoesNotContain("XboxStreamQuality", json);
        Assert.EndsWith("\"Hotkeys\":[]}", json);
    }

    [Fact]
    public void P720IsWrittenAsNumberAndReadBack()
    {
        var json = SettingsJson.Serialize(new AppSettings { XboxStreamQuality = XboxStreamQuality.P720 });
        Assert.EndsWith("\"Hotkeys\":[],\"XboxStreamQuality\":1}", json);
        Assert.Equal(XboxStreamQuality.P720, SettingsJson.Deserialize(json).XboxStreamQuality);
    }

    [Fact]
    public void OldFileWithoutFieldAndUnknownNumberFallBack()
    {
        Assert.Equal(XboxStreamQuality.Auto, SettingsJson.Deserialize("{\"GameConsole\":\"Xbox\"}").XboxStreamQuality);
        Assert.Equal(XboxStreamQuality.Auto, SettingsJson.Deserialize("{\"XboxStreamQuality\":7}").XboxStreamQuality);
    }
}
