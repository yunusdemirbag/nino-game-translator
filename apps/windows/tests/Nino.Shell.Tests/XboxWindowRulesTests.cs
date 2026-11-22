// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Settings;
using Nino.Shell;

namespace Nino.Shell.Tests;

/// <summary>Xbox uygulamasının pencere kuralları: (süreç, sınıf, başlık) üçlüleri.</summary>
public sealed class XboxWindowRulesTests
{
    [Theory]
    [InlineData("XboxPcApp", "", "Xbox")]
    [InlineData("XboxPcApp", "", "Remote Play")]
    [InlineData("XboxApp", "", "Xbox")]
    [InlineData("Xbox", "", "Uzaktan oynatma")]
    [InlineData("GamingApp", "", "Xbox")]
    [InlineData("Microsoft Gaming App", "", "Xbox")]
    [InlineData("XBOXPCAPP.exe", "", "")]
    [InlineData("ApplicationFrameHost", "ApplicationFrameWindow", "Xbox")]
    [InlineData("ApplicationFrameHost", "ApplicationFrameWindow", "Xbox Console Companion")]
    [InlineData("XboxApp", "ApplicationFrameWindow", "Xbox – Uzaktan Oynat")]
    [InlineData("greenlight", "", "Greenlight")]
    [InlineData("chrome", "Chrome_WidgetWin_1", "Xbox Cloud Gaming on Xbox.com - Google Chrome")]
    [InlineData("msedge", "", "Play Xbox games - Microsoft Edge")]
    public void Accepted(string process, string className, string title)
    {
        Assert.True(GameWindowRules.IsXboxWindow(process, title, className));
        Assert.False(GameWindowRules.IsPs5Window(process, title, className));
    }

    [Theory]
    [InlineData("GameBar", "", "Xbox Game Bar")]
    [InlineData("XboxGameBarWidgets", "", "Xbox")]
    [InlineData("ApplicationFrameHost", "ApplicationFrameWindow", "Xbox Game Bar")]
    [InlineData("ApplicationFrameHost", "ApplicationFrameWindow", "Settings")]
    [InlineData("ApplicationFrameHost", "", "Xbox")]
    [InlineData("XboxAppServices", "", "Xbox")]
    [InlineData("RemotePlay", "", "PS Remote Play")]
    [InlineData("notepad", "", "xbox alışveriş.txt")]
    [InlineData("chrome", "", "Hava durumu - Google Chrome")]
    [InlineData("app", "", "Uzaktan oynatma")]
    public void Rejected(string process, string className, string title) =>
        Assert.False(GameWindowRules.IsXboxWindow(process, title, className));

    [Theory]
    [InlineData("Remote Play")]
    [InlineData("remote-play")]
    [InlineData("REMOTE PLAY")]
    [InlineData("Uzaktan oynatma")]
    [InlineData("Uzaktan Oynat")]
    [InlineData("UZAKTAN OYNATMA")]
    [InlineData("Lecture à distance")]
    [InlineData("Remote-Play")]
    [InlineData("Reproducción remota")]
    [InlineData("Riproduzione remota")]
    [InlineData("Remotespiel")]
    [InlineData("Reprodução remota")]
    [InlineData("Xbox – Remote play")]
    public void RemotePlayTitlesInManyLanguages(string title) => Assert.True(GameWindowRules.HasRemotePlayTitle(title));

    [Theory]
    [InlineData("Xbox")]
    [InlineData("Game Pass")]
    [InlineData("")]
    public void LibraryTitlesAreNotRemotePlay(string title) => Assert.False(GameWindowRules.HasRemotePlayTitle(title));

    [Fact]
    public void Ps5DoesNotPickTheXboxRemotePlayWindow()
    {
        Assert.False(GameWindowRules.IsPs5Window("XboxPcApp", "Remote Play"));
        Assert.False(GameWindowRules.IsPs5Window("ApplicationFrameHost", "Xbox Remote Play", "ApplicationFrameWindow"));
        Assert.True(GameWindowRules.IsPs5Window("RemotePlay", "PS Remote Play"));
        Assert.True(GameWindowRules.IsPs5Window("app", "PS Remote Play"));
    }

    [Fact]
    public void TarifListsStillPick()
    {
        var xbox = new List<WindowCandidate>
        {
            new("chrome", "Hava durumu - Google Chrome", 1800, 1000),
            new("msedge", "Xbox Cloud Gaming on Xbox.com - Microsoft Edge", 1400, 800),
            new("RemotePlay", "PS Remote Play", 1600, 900),
            new("notepad", "xbox alışveriş.txt", 1700, 900),
        };
        Assert.Equal("msedge", GameWindowRules.Pick(xbox, GameConsole.Xbox)!.ProcessName);
        Assert.Equal("RemotePlay", GameWindowRules.Pick(xbox, GameConsole.Ps5)!.ProcessName);
        xbox.Add(new("XboxPcApp", "Xbox", 1500, 850));
        Assert.Equal("XboxPcApp", GameWindowRules.Pick(xbox, GameConsole.Xbox)!.ProcessName);
        Assert.Equal("RemotePlay", GameWindowRules.Pick(xbox, GameConsole.Ps5)!.ProcessName);
        Assert.Null(GameWindowRules.Pick([new WindowCandidate("Greenlight", "Greenlight", 300, 150)], GameConsole.Xbox));
    }

    [Fact]
    public void RemotePlayTitledXboxWindowWinsOverBiggerLibrary()
    {
        var list = new[]
        {
            new WindowCandidate("XboxPcApp", "Xbox", 1900, 1000),
            new WindowCandidate("XboxPcApp", "Uzaktan oynatma", 1280, 720),
            new WindowCandidate("chrome", "Xbox Cloud Gaming", 1920, 1080),
        };
        Assert.Equal("Uzaktan oynatma", GameWindowRules.Pick(list, GameConsole.Xbox)!.Title);
    }

    [Fact]
    public void FramedXboxWindowIsPicked()
    {
        var list = new[]
        {
            new WindowCandidate("ApplicationFrameHost", "Settings", 1600, 900, "ApplicationFrameWindow"),
            new WindowCandidate("ApplicationFrameHost", "Xbox", 1280, 720, "ApplicationFrameWindow"),
        };
        var pick = GameWindowRules.Pick(list, GameConsole.Xbox);
        Assert.Equal("Xbox", pick!.Title);
        Assert.Equal("Xbox", GameWindowRules.DisplayName(pick.ProcessName, pick.Title, pick.ClassName));
    }

    [Fact]
    public void DisplayNames()
    {
        Assert.Equal("Xbox", GameWindowRules.DisplayName("XboxApp", "Remote Play"));
        Assert.Equal("Xbox", GameWindowRules.DisplayName("GamingApp", ""));
        Assert.Equal("xbox.com/play", GameWindowRules.DisplayName("chrome", "Xbox"));
        Assert.Equal("PS Remote Play", GameWindowRules.DisplayName("RemotePlay", ""));
    }

    [Fact]
    public void FoldRemovesAccentsAndCase()
    {
        Assert.Equal("lecture a distance", GameWindowRules.Fold("Lecture À Distance"));
        Assert.Equal("remote play", GameWindowRules.Fold("Remote-Play"));
        Assert.Equal("uzaktan oynatma", GameWindowRules.Fold("UZAKTAN OYNATMA"));
    }
}
