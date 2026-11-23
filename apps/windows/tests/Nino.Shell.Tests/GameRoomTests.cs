// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Design;
using Nino.Core.Settings;

namespace Nino.Shell.Tests;

public sealed class GameRoomTests
{
    static World Ready(string region)
    {
        var w = new World().WithPs5().WithTv();
        w.Services.RegionCode = region;
        return w;
    }

    [Fact]
    public void AsksOnceInTurkeyAfterSetupAndSaving()
    {
        var w = Ready("TR");
        var c = w.Open();
        Assert.True(c.IsSetupComplete);
        Assert.True(c.ShouldAskGameRoomName);
        Assert.Equal("Yunus", c.SuggestedGameRoomName);
        Assert.Null(c.GameRoomSignText);

        c.SaveGameRoomName("  Yunus ");
        Assert.False(c.ShouldAskGameRoomName);
        Assert.Equal("YUNUS'S GAMING ROOM", c.GameRoomSignText!.Value.Text);
        Assert.True(w.Saved.GameRoomSign);
        Assert.Equal("Yunus", w.Saved.GameRoomName);
    }

    [Fact]
    public void SkipHidesTheSignAndNeverAsksAgain()
    {
        var w = Ready("TR");
        var c = w.Open();
        c.SkipGameRoomName();
        Assert.Null(c.GameRoomSignText);
        var again = w.Open();
        Assert.False(again.ShouldAskGameRoomName);
    }

    [Fact]
    public void NotAskedOutsideTurkeyAndArabicOrBeforeSetup()
    {
        Assert.False(Ready("US").Open().ShouldAskGameRoomName);
        var arabic = Ready("US");
        arabic.Text = Nino.Core.Text.TextCatalog.For("ar");
        Assert.True(arabic.Open().ShouldAskGameRoomName);
        var fresh = new World();
        fresh.Services.RegionCode = "TR";
        Assert.False(fresh.Open().ShouldAskGameRoomName);
    }

    [Fact]
    public void SettingsToggleUsesSuggestionAndNameChangesApply()
    {
        var w = Ready("US");
        var c = w.Open();
        c.SetGameRoomSign(true);
        Assert.Equal("YUNUS'S GAMING ROOM", c.GameRoomSignText!.Value.Text);
        c.SetGameRoomName("أحمد");
        Assert.Equal(GameRoomScript.Arabic, c.GameRoomSignText!.Value.Script);
        c.SetGameRoomSign(false);
        Assert.Null(c.GameRoomSignText);
        Assert.Equal("أحمد", w.Saved.GameRoomName);
    }

    [Fact]
    public void SignSitsAboveTheTvCenteredAtFortyPercent()
    {
        var scene = LivingRoomScene.Ps5;
        var place = GameRoomSignPlacement.Compute(scene, 1200, 700);
        Assert.Equal(GameRoomSignPlacement.SpaceFor(700), place.TopSpace);
        var view = SceneView.Of(scene, 1200, 700 - place.TopSpace);
        var left = view.Point(new ScenePoint(scene.Frame.X, scene.Frame.Y));
        var right = view.Point(new ScenePoint(scene.Frame.Right, scene.Frame.Y));
        Assert.Equal((left.X + right.X) / 2, place.Box.X + place.Box.Width / 2, 6);
        Assert.Equal((right.X - left.X) * 0.4, place.Box.Width, 6);
        Assert.Equal(left.Y + place.TopSpace - GameRoomSignPlacement.Gap, place.Box.Bottom, 6);
        Assert.True(place.Box.Y >= 0);
    }
}
