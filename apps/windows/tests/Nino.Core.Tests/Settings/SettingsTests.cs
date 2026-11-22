// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;
using Nino.Core.Tests.Data;

namespace Nino.Core.Tests.Settings;

public class SettingsTests : IDisposable
{
    readonly TempFolder _tmp = new();

    public void Dispose() => _tmp.Dispose();

    // ayarlar-modeli §6'daki eski uygulamanın ilk kaydı (boşluksuz).
    const string DefaultsJson =
        "{\"Region\":{\"Top\":0.62,\"Bottom\":0.97,\"Left\":0.14,\"Right\":0.86},\"AreaPreset\":\"Bottom\"," +
        "\"ExtraRegion1\":null,\"ExtraRegion2\":null,\"ExtraRegion3\":null,\"ExtraTarget1\":0,\"ExtraTarget2\":0," +
        "\"ExtraTarget3\":0,\"ExtraLive1\":false,\"ExtraLive2\":false,\"ExtraLive3\":false,\"FreeAreaTarget\":0," +
        "\"Style\":{\"FontSize\":46,\"BottomPercent\":7,\"Placement\":\"Cover\",\"Background\":100,\"Bold\":false," +
        "\"TextColor\":\"White\",\"DisplayMode\":\"InApp\",\"StackPrevious\":true,\"BackgroundShape\":\"Fit\"," +
        "\"Font\":\"Condensed\",\"Watermark\":true,\"AutoSize\":null},\"MisreadWaitMs\":800,\"PartialWaitMs\":300," +
        "\"SourceLanguage\":\"en\",\"TargetLanguage\":\"tr\",\"TranslationDevice\":\"Cpu\",\"CpuTranslationThreads\":2," +
        "\"FastSubtitleDetection\":false,\"OnlineTranslation\":false,\"OnlineEngine\":\"DeepL\"," +
        "\"GeminiModel\":\"gemini-3.5-flash-lite\",\"OpenAiModel\":\"gpt-6-luna\",\"ClaudeModel\":\"claude-haiku-5-5\"," +
        "\"LocalAiBaseUrl\":\"http://localhost:11434/v1\",\"LocalAiModel\":\"translategemma:4b\",\"Output\":\"Tv\"," +
        "\"OverlayClickThrough\":false,\"VideoSource\":\"Ps5\",\"GameConsole\":\"Ps5\",\"Overlay\":null," +
        "\"GamePacks\":true,\"SharePool\":true,\"AutoReport\":true,\"Appearance\":\"System\",\"HomeStyle\":\"LivingRoom\"," +
        "\"AskGame\":true,\"ShowSpeakerNames\":true,\"FrameSource\":0,\"XboxLegacyFrameRate\":false," +
        "\"CaptureWindow\":null,\"RemotePlayApp\":0,\"Hotkeys\":[]}";

    [Fact]
    public void VarsayilanlarEskiIlkKayitlaBirebir() =>
        Assert.Equal(DefaultsJson, SettingsJson.Serialize(new AppSettings()));

    [Fact]
    public void DoluParcalarEskiYazimla()
    {
        var s = new AppSettings
        {
            ExtraRegion1 = new Region(0.1, 0.2, 0.3, 0.4),
            ExtraTarget1 = ResultTarget.Both,
            Overlay = new OverlayPlacement { Left = 1, Top = 2, Width = 3 },
            FrameSource = FrameSource.ChosenWindow,
            CaptureWindow = new CaptureWindowChoice { ProcessName = "obs64", Title = "Projector" },
            RemotePlayApp = RemotePlayApp.Chiaki,
            Hotkeys =
            [
                new HotkeyBinding { Action = HotkeyAction.Screen, Slot = 1, Key = new HotkeyKey(KeyModifiers.Alt | KeyModifiers.Control, 65) },
                new HotkeyBinding { Action = HotkeyAction.FreeArea, Slot = 0, Key = null },
            ],
        };
        var json = SettingsJson.Serialize(s);
        Assert.Contains("\"ExtraRegion1\":{\"Top\":0.1,\"Bottom\":0.2,\"Left\":0.3,\"Right\":0.4}", json);
        Assert.Contains("\"ExtraTarget1\":2", json);
        Assert.Contains("\"Overlay\":{\"Left\":1,\"Top\":2,\"Width\":3}", json);
        Assert.Contains("\"FrameSource\":2", json);
        Assert.Contains("\"CaptureWindow\":{\"ProcessName\":\"obs64\",\"Title\":\"Projector\"}", json);
        Assert.Contains("\"RemotePlayApp\":2", json);
        Assert.Contains("\"Hotkeys\":[{\"Action\":\"Screen\",\"Slot\":1,\"Key\":{\"Modifiers\":\"Alt, Control\",\"VirtualKey\":65}},{\"Action\":\"FreeArea\",\"Slot\":0,\"Key\":null}]", json);
        var back = SettingsJson.Deserialize(json);
        Assert.True(back.SameAs(s));
    }

    [Fact]
    public void TurkceHarfKacislaYazilirIkisiDeOkunur()
    {
        var s = new AppSettings { LocalAiModel = "çeviri<&>'+\"" };
        var json = SettingsJson.Serialize(s);
        Assert.Contains("\\u00E7eviri\\u003C\\u0026\\u003E\\u0027\\u002B\\u0022", json);
        Assert.Equal("çeviri", SettingsJson.Deserialize("{\"LocalAiModel\":\"çeviri\"}").LocalAiModel);
    }

    [Fact]
    public void AlanAdlariHarfDuyarli()
    {
        var s = SettingsJson.Deserialize("{\"output\":\"Computer\",\"Output\":\"Both\"}");
        Assert.Equal(SubtitleOutput.Both, s.Output);
        Assert.Equal(SubtitleOutput.Tv, SettingsJson.Deserialize("{\"output\":\"Computer\"}").Output);
    }

    [Fact]
    public void YaziylaTutulanEnumHarfDuyarsizVeSayiKabulEder()
    {
        Assert.Equal(SubtitleOutput.Computer, SettingsJson.Deserialize("{\"Output\":\"computer\"}").Output);
        Assert.Equal(SubtitleOutput.Computer, SettingsJson.Deserialize("{\"Output\":1}").Output);
        Assert.Equal(VideoSource.Card, SettingsJson.Deserialize("{\"VideoSource\":\"CARD\"}").VideoSource);
    }

    [Theory]
    [InlineData("{\"AreaPreset\":null}")]
    [InlineData("{\"Output\":\"Radio\"}")]
    [InlineData("{\"GamePacks\":\"yes\"}")]
    [InlineData("{\"MisreadWaitMs\":\"800\"}")]
    [InlineData("{bozuk")]
    [InlineData("[]")]
    [InlineData("null")]
    public void HerhangiHataDosyanınTamaminiGecersizKilar(string json)
    {
        File.WriteAllText(_tmp.File("settings.json"), json);
        var store = new JsonFileSettingsStore(_tmp.File("settings.json"), () => "ar-SA");
        var s = store.Load();
        Assert.Equal(SettingsLoadStatus.Corrupt, store.LastLoadStatus);
        Assert.Equal("tr", s.TargetLanguage); // sistem dili değil
        Assert.True(s.SameAs(new AppSettings()));
    }

    [Fact]
    public void BozukDosyaIlkKayittanOnceBirKezKenaraAlinir()
    {
        var path = _tmp.File("settings.json");
        File.WriteAllText(path, "{bozuk");
        var store = new JsonFileSettingsStore(path, () => "tr");
        store.Load();
        Assert.Equal("{bozuk", File.ReadAllText(path)); // yüklemek dokunmaz
        Assert.True(store.Save(new AppSettings()));
        Assert.True(store.Save(new AppSettings { AskGame = false }));
        var aside = Directory.GetFiles(_tmp.Path, "settings.json.bozuk-*");
        Assert.Single(aside);
        Assert.Equal("{bozuk", File.ReadAllText(aside[0]));
        Assert.False(store.Load().AskGame);
        Assert.False(File.Exists($"{path}.tmp"));
    }

    [Theory]
    [InlineData("ar", "ar")]
    [InlineData("tr", "tr")]
    [InlineData("en", "tr")]
    [InlineData("", "tr")]
    [InlineData("vi", "vi")]
    [InlineData("fil", "tl")]
    [InlineData("fi", "tr")]
    [InlineData("ar-SA", "ar")]
    public void IlkAcilistaCeviriDiliSistemDilinden(string ui, string expected)
    {
        var store = new JsonFileSettingsStore(_tmp.File("yok", "settings.json"), () => ui);
        Assert.Equal(expected, store.Load().TargetLanguage);
        Assert.Equal(SettingsLoadStatus.Missing, store.LastLoadStatus);
    }

    [Fact]
    public void EksikAlanVarsayilaniAlirAreaPresetBolgedenCikarilir()
    {
        var s = SettingsJson.Deserialize("{\"Region\":{\"Top\":0.03,\"Bottom\":0.38,\"Left\":0.14,\"Right\":0.86}}");
        Assert.Equal(AreaPreset.Top, s.AreaPreset);
        Assert.Equal(800, s.MisreadWaitMs);
        Assert.Equal(AreaPreset.Custom, SettingsJson.Deserialize("{\"Region\":{\"Top\":0.5}}").AreaPreset);
        Assert.Equal(0.97, SettingsJson.Deserialize("{\"Region\":{\"Top\":0.5}}").Region.Bottom);
        Assert.Equal(AreaPreset.Full, SettingsJson.Deserialize("{\"Region\":{\"Top\":0.0005,\"Bottom\":1,\"Left\":0,\"Right\":1}}").AreaPreset);
        Assert.Equal(AreaPreset.Bottom, SettingsJson.Deserialize("{\"Region\":{\"Top\":0.03,\"Bottom\":0.38,\"Left\":0.14,\"Right\":0.86},\"AreaPreset\":\"Bottom\"}").AreaPreset);
    }

    [Fact]
    public void StilYalnizYaziBoyuVerilirse()
    {
        var s = SettingsJson.Deserialize("{\"Style\":{\"FontSize\":30}}");
        Assert.Equal(30, s.Style.FontSize);
        Assert.Equal(SubtitleFont.Condensed, s.Style.Font);
        Assert.False(s.Style.EffectiveAutoSize);
        Assert.True(new SubtitleStyle().EffectiveAutoSize);
        Assert.False(new SubtitleStyle { AutoSize = false }.EffectiveAutoSize);
    }

    [Fact]
    public void TanimsizSayiVarsayilanaDoner()
    {
        var s = SettingsJson.Deserialize("{\"FrameSource\":7,\"ExtraTarget2\":9,\"RemotePlayApp\":-1,\"Output\":5}");
        Assert.Equal(FrameSource.Ps5, s.FrameSource);
        Assert.Equal(ResultTarget.Tv, s.ExtraTarget2);
        Assert.Equal(RemotePlayApp.Automatic, s.RemotePlayApp);
        Assert.Equal(SubtitleOutput.Tv, s.Output);
    }

    [Fact]
    public void HotkeysNullHepsiVarsayilan()
    {
        var s = SettingsJson.Deserialize("{\"Hotkeys\":null}");
        Assert.NotNull(s.Hotkeys);
        Assert.Empty(s.Hotkeys!);
        Assert.Equal(new HotkeyKey(KeyModifiers.None, 0x69), Hotkeys.KeyFor(s.Hotkeys, HotkeyAction.Screen, 0));
    }

    [Fact]
    public void BilinmeyenAlanYokSayilir() =>
        Assert.True(SettingsJson.Deserialize("{\"translateCorners\":true,\"Dubbing\":{}}").SameAs(new AppSettings()));

    [Fact]
    public void KaydetmeHatasiIsiDurdurmaz()
    {
        var blocker = _tmp.File("dosya");
        File.WriteAllText(blocker, "");
        string? logged = null;
        var store = new JsonFileSettingsStore(Path.Combine(blocker, "settings.json"), () => "tr", (m, _) => logged = m);
        Assert.False(store.Save(new AppSettings()));
        Assert.Equal("Ayarlar kaydedilemedi", logged);
    }

    // ---- Kurallar ----

    [Theory]
    [InlineData(1, 1, 1, 1, 1)]
    [InlineData(2, 2, 2, 2, 2)]
    [InlineData(3, 2, 2, 2, 2)]
    [InlineData(4, 2, 2, 4, 2)]
    [InlineData(6, 2, 2, 4, 2)]
    [InlineData(8, 2, 2, 8, 2)]
    [InlineData(12, 2, 2, 12, 2)]
    [InlineData(16, 2, 2, 12, 2)]
    [InlineData(20, 2, 2, 12, 2)]
    [InlineData(32, 2, 2, 12, 2)]
    public void IslemciIsParcacigi(int cpus, int from1, int from2, int from12, int from0)
    {
        Assert.Equal(from1, SettingsRules.NormalizeCpuThreads(1, cpus));
        Assert.Equal(from2, SettingsRules.NormalizeCpuThreads(2, cpus));
        Assert.Equal(from12, SettingsRules.NormalizeCpuThreads(12, cpus));
        Assert.Equal(from0, SettingsRules.NormalizeCpuThreads(0, cpus));
    }

    [Fact]
    public void IslemciEkOrnekler()
    {
        Assert.Equal(8, SettingsRules.NormalizeCpuThreads(12, 8));
        Assert.Equal(8, SettingsRules.NormalizeCpuThreads(8, 20));
        Assert.True(SettingsRules.CpuThreadsNearCapacity(8, 8));
        Assert.False(SettingsRules.CpuThreadsNearCapacity(12, 20));
        Assert.Equal(new[] { 2, 4 }, SettingsRules.CpuThreadOptions(6));
    }

    [Fact]
    public void AcilisDuzeltmeleri()
    {
        var s = new AppSettings
        {
            GeminiModel = "gemini-eski", ClaudeModel = "claude-sonnet-5-5", LocalAiModel = "  ",
            CpuTranslationThreads = 12, Output = SubtitleOutput.Both,
        };
        Assert.True(SettingsRules.ApplyStartupFixes(s, 8));
        Assert.Equal("gemini-3.5-flash-lite", s.GeminiModel);
        Assert.Equal("claude-sonnet-5-5", s.ClaudeModel);
        Assert.Equal("translategemma:4b", s.LocalAiModel);
        Assert.Equal(8, s.CpuTranslationThreads);
        Assert.Equal(SubtitleOutput.Tv, s.Output);

        var card = new AppSettings { Output = SubtitleOutput.Both, VideoSource = VideoSource.Card, LocalAiModel = "qwen2.5:7b" };
        Assert.False(SettingsRules.ApplyStartupFixes(card, 8));
        Assert.Equal(SubtitleOutput.Both, card.Output);
        Assert.Equal("qwen2.5:7b", card.LocalAiModel);
        var computer = new AppSettings { Output = SubtitleOutput.Computer };
        Assert.False(SettingsRules.ApplyStartupFixes(computer, 8));
    }

    [Fact]
    public void YazmaKurallariTekKaynakGibi()
    {
        var prev = new AppSettings { VideoSource = VideoSource.Window };
        var next = prev.Clone();
        next.FrameSource = FrameSource.RemotePlayWindow;
        Assert.True(SettingsRules.ApplyWriteRules(prev, next, 8));
        Assert.Equal(VideoSource.Ps5, next.VideoSource);

        prev = new AppSettings { FrameSource = FrameSource.ChosenWindow };
        next = prev.Clone();
        next.VideoSource = VideoSource.Card;
        SettingsRules.ApplyWriteRules(prev, next, 8);
        Assert.Equal(FrameSource.Ps5, next.FrameSource);

        prev = new AppSettings { VideoSource = VideoSource.Card, Output = SubtitleOutput.Both };
        next = prev.Clone();
        next.VideoSource = VideoSource.Ps5;
        SettingsRules.ApplyWriteRules(prev, next, 8);
        Assert.Equal(SubtitleOutput.Tv, next.Output);

        prev = new AppSettings();
        Assert.False(SettingsRules.ApplyWriteRules(prev, prev.Clone(), 8));
    }

    [Fact]
    public void SeciliMotor()
    {
        Assert.Equal(OnlineEngine.Free, SettingsRules.SelectedEngine(new AppSettings()));
        Assert.Equal(OnlineEngine.DeepL, SettingsRules.SelectedEngine(SettingsJson.Deserialize("{\"OnlineTranslation\":true}")));
        Assert.Equal(OnlineEngine.Free, SettingsRules.SelectedEngine(new AppSettings { OnlineTranslation = true, OnlineEngine = OnlineEngine.Free }));
        Assert.Null(SettingsRules.LocalServer(new AppSettings { LocalAiBaseUrl = "bozuk adres" }));
        Assert.NotNull(SettingsRules.LocalServer(new AppSettings()));
    }

    [Fact]
    public void Kaydiricilar()
    {
        var r = RegionPresets.FromSliders(new Region(0.62, 0.97, 0.14, 0.86), 90, 20);
        Assert.Equal(0.8, r.Top, 6);
        Assert.Equal(1.0, r.Bottom, 6);
        Assert.Equal(0.14, r.Left);
        var small = RegionPresets.FromSliders(r, 10, 1);
        Assert.Equal(0.05, small.Bottom - small.Top, 6);
        var s = new AppSettings();
        RegionPresets.Apply(s, AreaPreset.Full);
        Assert.Equal(RegionPresets.Full, s.Region);
        RegionPresets.Apply(s, AreaPreset.Custom);
        Assert.Equal(RegionPresets.Full, s.Region);
    }

    [Fact]
    public void BeklemeSureleri()
    {
        Assert.Equal(2000, SettingsRules.ClampWait(5000));
        Assert.Equal(0, SettingsRules.ClampWait(-3));
        Assert.Equal(1235, SettingsRules.SecondsToWaitMs(1.2345));
    }
}
