// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Core.Tests.Data;
using static Nino.Core.Tests.Compat.CompatFixtures;

namespace Nino.Core.Tests.Compat;

/// <summary>
/// <c>settings.json</c>: eski uygulamanın yazdığı dosyalar yeni kodla aynı değerlerle okunuyor ve yeni kod onları
/// bayt bayt aynı yazıyor mu (aynı yazılan dosyayı eski uygulama da aynı okur).
/// </summary>
public class SettingsCompatTests
{
    static string OldSettings(string name) => OldText("settings", name);

    [Fact]
    public void FullOldFileRoundTripsByteForByte()
    {
        var old = OldSettings("settings-full.json");
        var s = SettingsJson.Deserialize(old);
        SameText(old, SettingsJson.Serialize(s), "dolu ayar dosyası");

        // Değerler (eski uygulamada verilenler).
        Assert.Equal(new Region(0.55, 0.93, 0.1, 0.9), s.Region);
        Assert.Equal(AreaPreset.Custom, s.AreaPreset);
        Assert.Equal(new Region(0.05, 0.25, 0.7, 0.98), s.ExtraRegion1);
        Assert.Null(s.ExtraRegion3);
        Assert.Equal(ResultTarget.Computer, s.ExtraTarget1);
        Assert.Equal(ResultTarget.Both, s.ExtraTarget2);
        Assert.True(s.ExtraLive1);
        Assert.True(s.ExtraLive3);
        Assert.Equal(ResultTarget.Both, s.FreeAreaTarget);
        Assert.Equal(58, s.Style.FontSize);
        Assert.Equal(12, s.Style.BottomPercent);
        Assert.Equal(SubtitlePlacement.Fixed, s.Style.Placement);
        Assert.Equal(70, s.Style.Background);
        Assert.True(s.Style.Bold);
        Assert.Equal(SubtitleTextColor.Yellow, s.Style.TextColor);
        Assert.Equal(SubtitleDisplayMode.Overlay, s.Style.DisplayMode);
        Assert.False(s.Style.StackPrevious);
        Assert.Equal(SubtitleBackgroundShape.Band, s.Style.BackgroundShape);
        Assert.Equal(SubtitleFont.Rounded, s.Style.Font);
        Assert.False(s.Style.Watermark);
        Assert.False(s.Style.AutoSize);
        Assert.Equal(1200, s.MisreadWaitMs);
        Assert.Equal(0, s.PartialWaitMs);
        Assert.Equal("ar", s.TargetLanguage);
        Assert.Equal(TranslationDevice.Gpu, s.TranslationDevice);
        Assert.Equal(6, s.CpuTranslationThreads);
        Assert.True(s.FastSubtitleDetection);
        Assert.True(s.OnlineTranslation);
        Assert.Equal(OnlineEngine.Claude, s.OnlineEngine);
        Assert.Equal("gemini-3.6-flash", s.GeminiModel);
        Assert.Equal("gpt-6.1-terra", s.OpenAiModel);
        Assert.Equal("claude-sonnet-5-5", s.ClaudeModel);
        Assert.Equal("http://localhost:1234/v1", s.LocalAiBaseUrl);
        Assert.Equal("qwen2.5:7b", s.LocalAiModel);
        Assert.Equal(SubtitleOutput.Both, s.Output);
        Assert.True(s.OverlayClickThrough);
        Assert.Equal(VideoSource.Card, s.VideoSource);
        Assert.Equal(GameConsole.Xbox, s.GameConsole);
        Assert.Equal(new OverlayPlacement { Left = 120.5, Top = 640, Width = 1280 }, s.Overlay);
        Assert.False(s.GamePacks);
        Assert.False(s.SharePool);
        Assert.False(s.AutoReport);
        Assert.Equal(Appearance.Dark, s.Appearance);
        Assert.Equal(HomeStyle.Toggle, s.HomeStyle);
        Assert.False(s.AskGame);
        Assert.False(s.ShowSpeakerNames);
        Assert.Equal(FrameSource.ChosenWindow, s.FrameSource);
        Assert.True(s.XboxLegacyFrameRate);
        Assert.Equal("obs64", s.CaptureWindow!.ProcessName);
        Assert.Equal("Windowed Projector (Preview) – \"Oyun\" <1> & ğüşiöç", s.CaptureWindow.Title);
        Assert.Equal(RemotePlayApp.Chiaki, s.RemotePlayApp);
        Assert.Equal(4, s.Hotkeys!.Count);
        Assert.Equal(new HotkeyBinding { Action = HotkeyAction.Screen, Slot = 0, Key = new HotkeyKey(KeyModifiers.Control | KeyModifiers.Shift, 0x53) },
            s.Hotkeys[0]);
        Assert.Equal(new HotkeyBinding { Action = HotkeyAction.PauseSubtitles, Slot = 1, Key = null }, s.Hotkeys[1]);
        Assert.Equal(KeyModifiers.Alt, s.Hotkeys[2].Key!.Modifiers);
        Assert.Equal(KeyModifiers.None, s.Hotkeys[3].Key!.Modifiers);
    }

    [Fact]
    public void DefaultsMatchOldDefaultsByteForByte() =>
        SameText(OldSettings("settings-default.json"), SettingsJson.Serialize(new AppSettings()), "varsayılan ayarlar");

    [Fact]
    public void OldVersionFileGetsSameDefaultsAsOldReader()
    {
        // Eski sürüm dosyası: AreaPreset, Hotkeys ve stilin yeni alanları yok; bölge "Üst" hazır seçiminin bölgesi.
        var s = SettingsJson.Deserialize(OldSettings("settings-oldversion.json"));
        SameText(OldSettings("settings-oldversion.oldread.json"), SettingsJson.Serialize(s), "eski sürüm dosyası");
        Assert.Equal(AreaPreset.Top, s.AreaPreset);
        Assert.True(s.Style.EffectiveAutoSize);
        Assert.Empty(s.Hotkeys!);
    }

    [Fact]
    public void UnknownFieldsAndNumericEnumsReadLikeOldReader()
    {
        var s = SettingsJson.Deserialize(OldSettings("settings-extra.json"));
        SameText(OldSettings("settings-extra.oldread.json"), SettingsJson.Serialize(s), "ek alanlı dosya");
        Assert.Equal(OnlineEngine.OpenAi, s.OnlineEngine);
        Assert.Equal(Appearance.Light, s.Appearance);
        Assert.Equal(SubtitlePlacement.Below, s.Style.Placement);
    }

    [Fact]
    public void ComputedValuesMatchOldReader()
    {
        using var computed = JsonDocument.Parse(OldSettings("settings-computed.oldread.json"));
        foreach (var (name, file) in new[] { ("full", "settings-full.json"), ("oldversion", "settings-oldversion.json"), ("extra", "settings-extra.json") })
        {
            var expected = computed.RootElement.GetProperty(name);
            var s = SettingsJson.Deserialize(OldSettings(file));
            Assert.Equal(expected.GetProperty("AreaPreset").GetString(), s.AreaPreset.ToString());
            Assert.Equal(expected.GetProperty("MatchesGameSize").GetBoolean(), s.Style.EffectiveAutoSize);
            Assert.Equal(expected.GetProperty("Engine").GetString(), SettingsRules.SelectedEngine(s).ToString());
            Assert.Equal(expected.GetProperty("HotkeyCount").GetInt32(), s.Hotkeys!.Count);
        }
    }

    [Fact]
    public void FileStoreReadsOldFileAndWritesItBackUnchanged()
    {
        using var temp = new TempFolder();
        var path = Path.Combine(temp.Path, JsonFileSettingsStore.FileName);
        File.Copy(Old("settings", "settings-full.json"), path);
        var store = new JsonFileSettingsStore(path, () => "tr-TR");
        var s = store.Load();
        Assert.Equal(SettingsLoadStatus.Loaded, store.LastLoadStatus);
        Assert.True(store.Save(s));
        SameBytes(OldBytes("settings", "settings-full.json"), File.ReadAllBytes(path), "depo üstünden yazılan dosya");
        Assert.Empty(Directory.GetFiles(temp.Path, "*.bozuk-*"));
    }
}

/// <summary>Her ayar enum'unun her üyesi (adla ya da sayıyla) eski dosyadaki gibi okunup aynı yazılıyor mu.</summary>
public class SettingsEnumCoverageTests
{
    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    [InlineData(5)]
    [InlineData(6)]
    [InlineData(7)]
    public void EveryEnumMemberRoundTrips(int variant)
    {
        var old = CompatFixtures.OldText("settings", $"settings-variant{variant}.json");
        var s = SettingsJson.Deserialize(old);
        CompatFixtures.SameText(old, SettingsJson.Serialize(s), $"çeşit {variant}");
        Assert.Equal(2, s.Hotkeys!.Count);
        Assert.Equal((HotkeyAction)variant, s.Hotkeys[0].Action);
    }
}
