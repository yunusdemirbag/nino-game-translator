// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Design;
using Nino.Core.Library;
using Nino.Core.Settings;
using Nino.Core.Tv;
using Nino.Shell.Panels;
using Nino.Translation.Online;

namespace Nino.Shell.Tests;

public class SettingsPagesTests
{
    [Fact]
    public void VisibleListMatchesMacGroupsWithShortcutsAfterTranslation()
    {
        var groups = SettingsPages.VisibleGroups.Select(g => g.ToArray()).ToArray();
        Assert.Equal(
        [
            [SettingsPage.Connection, SettingsPage.Passcode],
            [SettingsPage.Appearance, SettingsPage.Home, SettingsPage.Translation, SettingsPage.Shortcuts],
            [SettingsPage.Obs],
            [SettingsPage.Health, SettingsPage.Updates, SettingsPage.AskNino, SettingsPage.Report, SettingsPage.About],
            [SettingsPage.Reset],
        ], groups);
    }

    [Theory]
    [InlineData(SettingsPage.Interface)]
    [InlineData(SettingsPage.Language)]
    [InlineData(SettingsPage.Packs)]
    [InlineData(SettingsPage.Area)]
    public void TuckedAwayPagesStayInGroupsButNotInList(SettingsPage page)
    {
        Assert.True(SettingsPages.IsTuckedAway(page));
        Assert.Contains(SettingsPages.Groups, g => g.Contains(page));
        Assert.DoesNotContain(SettingsPages.VisibleGroups, g => g.Contains(page));
    }

    [Fact]
    public void EveryPageAppearsOnceInGroups() =>
        Assert.Equal(Enum.GetValues<SettingsPage>().Order(), SettingsPages.Groups.SelectMany(g => g).Order());

    [Theory]
    [InlineData(SettingsPage.Connection, "settings.section.connection", SettingsPageOpens.Page)]
    [InlineData(SettingsPage.AskNino, "settings.section.askNino", SettingsPageOpens.CloseThenAskNino)]
    [InlineData(SettingsPage.Health, "settings.section.health", SettingsPageOpens.Window)]
    [InlineData(SettingsPage.Report, "settings.section.report", SettingsPageOpens.Window)]
    [InlineData(SettingsPage.About, "settings.section.about", SettingsPageOpens.Page)]
    [InlineData(SettingsPage.Reset, "settings.section.reset", SettingsPageOpens.Page)]
    public void TitleKeysAndOpening(SettingsPage page, string key, SettingsPageOpens opens)
    {
        Assert.Equal(key, SettingsPages.TitleKey(page));
        Assert.Equal(opens, SettingsPages.Opens(page));
        Assert.Equal(page, SettingsPages.FromId(SettingsPages.Id(page)));
    }

    [Fact]
    public void WidthsAndColorsFollowMac()
    {
        Assert.Equal(900, SettingsPages.Width(SettingsPage.Appearance));
        Assert.Equal(640, SettingsPages.Width(SettingsPage.Translation));
        Assert.Equal(560, SettingsPages.Width(SettingsPage.About));
        Assert.True(SettingsPages.DrawsOwnHeader(SettingsPage.About));
        Assert.Equal(((byte)26, (byte)115, (byte)242), SettingsPages.Color(SettingsPage.Connection));
        Assert.Equal(((byte)0, (byte)158, (byte)191), SettingsPages.Color(SettingsPage.Translation));
        Assert.True(SettingsPages.DrawsOwnHeader(SettingsPage.Packs));
        Assert.Null(SettingsPages.FromId("yok"));
    }

    [Fact]
    public void LibraryAlwaysStartsWithGta6AndSkipsDuplicatesAndGeneralPack()
    {
        var packs = new[]
        {
            new PackInfo("pool-gta-6", "Grand Theft Auto VI", 900),
            new PackInfo(PackLibrary.GeneralPackId, "Genel", 50),
            new PackInfo("pool-gta-5", "Grand Theft Auto V", 500),
            new PackInfo("community-gtav", "GTA V (benim)", 10),
            new PackInfo("red-dead-redemption-2", "Red Dead Redemption 2", 300),
            new PackInfo("community-cyberpunk-2077", "Cyberpunk 2077", 20),
        };
        Assert.Equal(["GTA 6", "GTA 5", "Red Dead Redemption 2", "Cyberpunk 2077"], SettingsLibrary.GameNames(packs));
        Assert.Equal(["GTA 6"], SettingsLibrary.GameNames([]));
    }

    [Fact]
    public void LibraryShowsEightAndCountsTheRest()
    {
        var names = Enumerable.Range(1, 11).Select(i => "Oyun " + i).ToList();
        var (shown, more) = SettingsLibrary.Shown(names);
        Assert.Equal(8, shown.Count);
        Assert.Equal(3, more);
        Assert.Equal(0, SettingsLibrary.Shown(["GTA 6"]).More);
    }

    [Fact]
    public void ProvidersAreInMacOrder() =>
        Assert.Equal([OnlineEngine.Gemini, OnlineEngine.DeepL, OnlineEngine.OpenAi, OnlineEngine.Claude, OnlineEngine.Local],
            ApiProviders.Order);

    [Theory]
    [InlineData(OnlineEngine.Gemini, OnlineEngine.Gemini, true, ApiProviderState.InUse)]
    [InlineData(OnlineEngine.Gemini, OnlineEngine.Gemini, false, ApiProviderState.None)]
    [InlineData(OnlineEngine.DeepL, OnlineEngine.Free, true, ApiProviderState.Saved)]
    [InlineData(OnlineEngine.DeepL, OnlineEngine.Gemini, false, ApiProviderState.None)]
    [InlineData(OnlineEngine.Local, OnlineEngine.Local, false, ApiProviderState.InUse)]
    [InlineData(OnlineEngine.Local, OnlineEngine.Free, true, ApiProviderState.Off)]
    public void ProviderStates(OnlineEngine engine, OnlineEngine selected, bool hasKey, ApiProviderState expected) =>
        Assert.Equal(expected, ApiProviders.State(engine, selected, hasKey));

    [Fact]
    public void ProviderStatusTextsDotsAndButtons()
    {
        Assert.Equal("settings.api.inUse", ApiProviders.StatusKey(ApiProviderState.InUse));
        Assert.Equal("settings.api.saved", ApiProviders.StatusKey(ApiProviderState.Saved));
        Assert.Equal("settings.api.none", ApiProviders.StatusKey(ApiProviderState.None));
        Assert.Equal("settings.api.off", ApiProviders.StatusKey(ApiProviderState.Off));
        Assert.Equal(StatusTone.Good, ApiProviders.Tone(ApiProviderState.Saved));
        Assert.Equal(StatusTone.Idle, ApiProviders.Tone(ApiProviderState.Off));
        Assert.Equal(ApiProviderAction.Use, ApiProviders.Action(OnlineEngine.DeepL, ApiProviderState.Saved));
        Assert.Equal(ApiProviderAction.Use, ApiProviders.Action(OnlineEngine.Local, ApiProviderState.Off));
        Assert.Equal(ApiProviderAction.Stop, ApiProviders.Action(OnlineEngine.Local, ApiProviderState.InUse));
        Assert.Equal(ApiProviderAction.None, ApiProviders.Action(OnlineEngine.Gemini, ApiProviderState.InUse));
        Assert.Equal(ApiProviderAction.None, ApiProviders.Action(OnlineEngine.Claude, ApiProviderState.None));
    }

    [Fact]
    public void ChoosingAndStoppingAProvider()
    {
        var s = new AppSettings();
        ApiProviders.Choose(s, OnlineEngine.Claude);
        Assert.True(s.OnlineTranslation);
        Assert.Equal(OnlineEngine.Claude, SettingsRules.SelectedEngine(s));
        ApiProviders.Choose(s, null);
        Assert.False(s.OnlineTranslation);
        Assert.Equal(OnlineEngine.Claude, s.OnlineEngine);
        Assert.Equal(OnlineEngine.Free, SettingsRules.SelectedEngine(s));
    }

    [Fact]
    public void LocalUseNeedsAValidAddress()
    {
        var s = new AppSettings { LocalAiBaseUrl = "olmayan adres" };
        Assert.False(ApiProviders.CanUse(OnlineEngine.Local, s));
        Assert.True(ApiProviders.CanUse(OnlineEngine.Gemini, s));
        s.LocalAiBaseUrl = "http://localhost:11434";
        Assert.True(ApiProviders.CanUse(OnlineEngine.Local, s));
    }

    [Fact]
    public void AccordionKeepsOneRowOpen()
    {
        Assert.Equal(OnlineEngine.DeepL, ApiProviders.Toggle(null, OnlineEngine.DeepL));
        Assert.Equal(OnlineEngine.Gemini, ApiProviders.Toggle(OnlineEngine.DeepL, OnlineEngine.Gemini));
        Assert.Null(ApiProviders.Toggle(OnlineEngine.Gemini, OnlineEngine.Gemini));
    }

    [Fact]
    public void ResultTextsUseMacEngineKeys()
    {
        var s = new AppSettings { LocalAiBaseUrl = "http://localhost:11434", LocalAiModel = "gemma3:4b" };
        var bad = ApiProviders.Result(OnlineEngine.OpenAi, KeyCheckStatus.InvalidKey, s);
        Assert.Equal("settings.engine.badKey", bad.Key);
        Assert.Equal(["OpenAI"], bad.Args);
        Assert.True(bad.Error);
        var works = ApiProviders.Result(OnlineEngine.Gemini, KeyCheckStatus.Valid, s, "Merhaba");
        Assert.Equal("settings.key.works", works.Key);
        Assert.Equal(["Merhaba"], works.Args);
        Assert.False(works.Error);
        Assert.Equal("settings.deepl.limit", ApiProviders.Result(OnlineEngine.DeepL, KeyCheckStatus.QuotaExhausted, s).Key);
        var down = ApiProviders.Result(OnlineEngine.Local, KeyCheckStatus.Unreachable, s);
        Assert.Equal("settings.engine.local.ollamaDown", down.Key);
        Assert.Equal("gemma3:4b", down.Args[1]);
        s.LocalAiBaseUrl = "http://localhost:1234/v1";
        Assert.Equal("settings.engine.local.missingLMStudio",
            ApiProviders.Result(OnlineEngine.Local, KeyCheckStatus.ModelRejected, s).Key);
    }

    [Fact]
    public void TvOverlaySwitchOnlyForAndroidTv()
    {
        Assert.True(TvSettingsRules.ShowsOverlaySwitch(new TvRecord("TCL", "192.168.0.110", TvBrand.AndroidTv)));
        Assert.False(TvSettingsRules.ShowsOverlaySwitch(new TvRecord("LG", "192.168.0.5", TvBrand.Lg)));
        Assert.False(TvSettingsRules.ShowsOverlaySwitch(null));
        var s = new AppSettings();
        Assert.False(TvSettingsRules.OverlayOn(s.Style));
        TvSettingsRules.SetOverlay(s, true);
        Assert.Equal(SubtitleDisplayMode.Overlay, s.Style.DisplayMode);
        TvSettingsRules.SetOverlay(s, false);
        Assert.Equal(SubtitleDisplayMode.InApp, s.Style.DisplayMode);
        Assert.Equal("settings.tv.connected", TvSettingsRules.StateKey(1));
        Assert.Equal("settings.tv.waiting", TvSettingsRules.StateKey(0));
        Assert.Equal(StatusTone.Warning, TvSettingsRules.Tone(0));
    }

    [Fact]
    public void SubtitleLookCardRules()
    {
        Assert.Equal("settings.style.onTV", SubtitleLookRules.TitleKey(SubtitleOutput.Tv));
        Assert.Equal("settings.style.title", SubtitleLookRules.TitleKey(SubtitleOutput.Both));
        Assert.Equal((60, 100), SubtitleLookRules.BackgroundRange(SubtitlePlacement.Cover));
        Assert.Equal((0, 100), SubtitleLookRules.BackgroundRange(SubtitlePlacement.Above));
        Assert.Equal("settings.style.background.light", SubtitleLookRules.BackgroundMinKey(SubtitlePlacement.Cover));
        Assert.Equal("settings.style.background.none", SubtitleLookRules.BackgroundMinKey(SubtitlePlacement.Fixed));
        Assert.Equal(60, SubtitleLookRules.ClampBackground(20, SubtitlePlacement.Cover));
        Assert.Equal(20, SubtitleLookRules.ClampBackground(20, SubtitlePlacement.Below));
        Assert.Equal(20, SubtitleLookRules.ClampSize(5));
        Assert.Equal(80, SubtitleLookRules.ClampSize(99.6));
        Assert.Equal(6, SubtitleLookRules.DemoLines.Count);
    }

    [Fact]
    public void PreviewFontSizeFollowsTheFormula()
    {
        var auto = new SubtitleStyle { AutoSize = true, FontSize = 70 };
        Assert.Equal(38 / 1920.0 * 470 * 1.6, SubtitleLookRules.PreviewFontSize(auto, 470), 6);
        var manual = new SubtitleStyle { AutoSize = false, FontSize = 70 };
        Assert.Equal(70 / 1920.0 * 470 * 1.6, SubtitleLookRules.PreviewFontSize(manual, 470), 6);
        Assert.Equal(10, SubtitleLookRules.PreviewFontSize(manual, 50));
    }
}
