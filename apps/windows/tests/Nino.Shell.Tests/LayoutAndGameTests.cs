// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Sockets;
using System.Text;
using Nino.Core.Data;
using Nino.Core.Library;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell.Tests;

// Saf hesaplar (§14.1–14.3) ve oyun/havuz (§13.3).
public sealed class LayoutAndGameTests
{
    static readonly ScreenRect Screen = new(0, 0, 1920, 1080);
    static readonly ScreenRect Work = new(0, 0, 1920, 1032);

    [Fact]
    public void OverlayPlacement()
    {
        var def = OverlayLayout.Place(null, 500, [Screen], Work);
        Assert.Equal(1344, def.Width);
        Assert.Equal(288, def.X);
        Assert.Equal(1032 - 41.28 - 500, def.Y, 6);

        Assert.Equal(new ScreenRect(100, 400, 1000, 500),
            OverlayLayout.Place(new OverlayPlacement { Left = 100, Top = 400, Width = 1000 }, 500, [Screen], Work));
        foreach (var w in new[] { double.NaN, double.PositiveInfinity, 0, -5 })
            Assert.Equal(def, OverlayLayout.Place(new OverlayPlacement { Left = 100, Top = 400, Width = w }, 500, [Screen], Work));
        foreach (var (l, t) in new[] { (2100.0, 400.0), (-3000, 400), (100, 1060), (100, -480) })
            Assert.Equal(def, OverlayLayout.Place(new OverlayPlacement { Left = l, Top = t, Width = 1000 }, 500, [Screen], Work));
        var second = new ScreenRect(-1600, 0, 1600, 900);
        Assert.Equal(new ScreenRect(-1600, 500, 1200, 500),
            OverlayLayout.Place(new OverlayPlacement { Left = -1600, Top = 500, Width = 1200 }, 500, [Screen, second], Work));
        Assert.Equal(1920, OverlayLayout.Place(new OverlayPlacement { Left = 0, Top = 400, Width = 99999 }, 500, [Screen], Work).Width);
        Assert.Equal(320, OverlayLayout.Place(new OverlayPlacement { Left = 100, Top = 400, Width = 10 }, 500, [Screen], Work).Width);
        Assert.Equal(new OverlayPlacement { Left = 10, Top = 21, Width = 800 }, OverlayLayout.ToSave(10.2, 20.6, 799.7));
        Assert.Null(OverlayLayout.ToSave(double.NaN, 1, 1));
        Assert.Equal(2, OverlayLayout.Scale(2160));
        Assert.Equal(1, OverlayLayout.Scale(double.NaN));
        Assert.Equal(46, OverlayLayout.FontSize(0));
        Assert.Equal(200, OverlayLayout.FontSize(500));
        Assert.Equal(Math.Round(46 * 8.1 + 140), OverlayLayout.Height(46, 1));
        Assert.Equal(320, OverlayLayout.ResizeWidth(double.NaN, [Screen]));
        Assert.Equal(1920, OverlayLayout.ResizeWidth(5000, [Screen]));
        Assert.Equal(new ScreenRect(320, 1032 - 41.28 - 500, 1344, 500).Width,
            OverlayLayout.Place(null, double.NaN, [Screen], Work).Width);
    }

    [Fact]
    public void GameWindowRulesExamples()
    {
        Assert.Equal(new PixelRect(360, 0, 1280, 720), GameWindowRules.GameArea(2000, 720));
        Assert.Equal(new PixelRect(0, 60, 1920, 1080), GameWindowRules.GameArea(1920, 1200));
        var over = GameWindowRules.OverlayOverGame(new ScreenRect(100, 100, 1000, 500), 200);
        Assert.Equal(900, over.Width);
        Assert.Equal(150, over.X);
        Assert.Equal(385, over.Y);
        Assert.Equal("chiaki-ng", GameWindowRules.DisplayName("chiaki", ""));
        Assert.Equal("Greenlight", GameWindowRules.DisplayName("greenlight", ""));
        Assert.Equal("Xbox", GameWindowRules.DisplayName("XboxPcApp", ""));
        Assert.Equal("xbox.com/play", GameWindowRules.DisplayName("msedge", "Xbox Cloud"));
        Assert.Equal("PS Remote Play", GameWindowRules.DisplayName("RemotePlay", ""));
        var list = new[]
        {
            new WindowCandidate("RemotePlay", "PS Remote Play", 1280, 720),
            new WindowCandidate("chiaki", "chiaki-ng", 1920, 1080),
            new WindowCandidate("notepad", "remote play notes", 300, 100),
            new WindowCandidate("chrome", "Xbox Cloud Gaming", 1600, 900),
            new WindowCandidate("chrome", "News", 1900, 1000),
        };
        Assert.Equal("chiaki", GameWindowRules.Pick(list, GameConsole.Ps5)!.ProcessName);
        Assert.Equal("Xbox Cloud Gaming", GameWindowRules.Pick(list, GameConsole.Xbox)!.Title);
    }

    [Fact]
    public void LivingRoomScene()
    {
        var ps5 = Nino.Shell.LivingRoomScene.Ps5;
        var xbox = Nino.Shell.LivingRoomScene.Xbox;
        Assert.Equal(72, ps5.ShiftLeft);
        Assert.Equal(6, xbox.ShiftLeft);
        Assert.Equal(1151 / 588.0, ps5.ScreenScale);

        var rest = ps5.Cable(ps5.PlugRest, plugged: false);
        Assert.Equal(new ScenePoint(1600, 845), rest.End);
        Assert.Equal(1600, rest.Control2.X, 6);
        var plugged = ps5.Cable(ps5.Socket, plugged: true);
        Assert.Equal(new ScenePoint(1564, 408), plugged.End);
        Assert.Equal(1597, plugged.Control1.X, 6);
        Assert.Equal(805.3, plugged.Control1.Y, 6);
        Assert.Equal(new ScenePoint(1574, 578), plugged.Control2);

        Assert.Equal(new ScenePoint(1646, 872), xbox.Cable(xbox.PlugRest, false).End);
        var xp = xbox.Cable(xbox.Socket, true);
        Assert.Equal(new ScenePoint(1561, 411), xp.End);
        Assert.Equal(1662, xp.Control1.X, 6);
        Assert.Equal(731, xp.Control1.Y, 6);
        Assert.Equal(0, ps5.PlugRotation(ps5.PlugRest));
    }

    static TranslationPool Pool(string folder, Uri endpoint) =>
        new(new TranslationPoolOptions(folder, endpoint, "1.0.0", new HttpClient()), "tr", sharePool: true);

    [Fact]
    public void PoolFirstLiveGame()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            var w = new World().WithPs5().WithTv();
            w.Services.PoolService = Pool(folder, new Uri("http://127.0.0.1:9/"));
            var c = w.Open();
            Assert.False(c.PoolFirstLive);
            Assert.Equal("Free", c.TranslationSourceText);
            c.ChooseGame("GTA VI");
            Assert.True(c.PoolFirstLive);
            Assert.Equal(Nino.Core.Text.TextCatalog.For("en").Get("status.translation.poolActive"), c.TranslationSourceText);
            Assert.Equal("GTA VI", w.Secrets.Get<Dictionary<string, string>>(SecretKeys.LastGames)!["PS5-789"]);
            Assert.Equal("GTA VI", c.LastChosenGame);
            c.ChooseGame("Red Dead Redemption 2");
            Assert.False(c.PoolFirstLive);

            var s = c.Settings;
            s.TargetLanguage = "de";
            c.UpdateSettings(s);
            c.ChooseGame("GTA VI");
            Assert.False(c.PoolFirstLive);

            var none = new World().Open();
            none.ChooseGame("GTA VI");
            Assert.False(none.PoolFirstLive);
        }
        finally { Directory.Delete(folder, true); }
    }

    [Fact]
    public async Task DownloadCountFromServerConfig()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var serve = Task.Run(async () =>
        {
            using var client = await listener.AcceptTcpClientAsync();
            using var stream = client.GetStream();
            var buffer = new byte[4096];
            _ = await stream.ReadAsync(buffer);
            var body = "{\"translate\":{\"enabled\":true},\"downloads\":3439}";
            var reply = $"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {Encoding.UTF8.GetByteCount(body)}\r\nConnection: close\r\n\r\n{body}";
            await stream.WriteAsync(Encoding.UTF8.GetBytes(reply));
        });
        try
        {
            var w = new World();
            w.Services.PoolService = Pool(folder, new Uri($"http://127.0.0.1:{port}/"));
            var c = w.Open();
            c.RefreshDownloads();
            await c.WhenIdleAsync();
            await serve;
            Assert.Equal(3439, c.Downloads);
        }
        finally
        {
            listener.Stop();
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void PaketsizOyunSecimi()
    {
        // Uygulamayla gelen paket yok: kullanıcı paket klasörü boşken oyun seçimi ve öneriler çalışır.
        var folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            var w = new World().WithPs5().WithTv();
            w.Services.PackService = new PackLibrary(folder);
            var c = w.Open();
            c.ReloadPacks();
            Assert.Empty(c.Packs);
            Assert.Contains("GTA 6", c.GameSuggestions(null));
            c.ChooseGame("GTA VI");
            Assert.Equal("GTA VI", c.LastChosenGame);
            Assert.Null(w.Services.PackService.SelectedPack);
            Assert.Null(w.Services.PackService.ScopeTitle);
        }
        finally { Directory.Delete(folder, true); }
    }

    [Fact]
    public void GamePickerFlow()
    {
        var c = new World().WithPs5().WithTv().Open();
        c.ChangeGame();
        Assert.True(c.GamePickerOpen);
        c.DismissGamePicker();
        Assert.False(c.GamePickerOpen);
        c.ChooseGame("   ");
        Assert.Null(c.PlayingGame);
        Assert.Contains("GTA 6", c.GameSuggestions(null));
    }

    [Fact]
    public async Task DeviceInfoHasNoPersonalData()
    {
        var w = new World().WithPs5().WithTv();
        var c = w.Open();
        var lines = c.DeviceInfoLines();
        Assert.Equal(["app", "device", "system", "tv", "console", "status"], lines.Select(l => l.Id));
        Assert.Equal("çeviri durdu, PS5: Disconnected, oyun: bilinmiyor", lines[^1].Value);
        Assert.Equal("LG webOS · bağlantı yok", lines[3].Value);
        await c.StartAsync();
        w.Services.Ps5Sessions[0].Status(SourceStatus.Down(DisconnectReason.Rejected, "0x80104a2c"));
        var summary = DeviceInfo.Summary(c.DeviceInfoLines());
        Assert.Contains("çeviri sürüyor, PS5: Disconnected (Rejected 0x80104a2c)", summary);
        Assert.DoesNotContain("PS5-789", summary);
        Assert.DoesNotContain("192.168", summary);
        Assert.DoesNotContain("tv-key", summary);
    }

    [Fact]
    public void NotificationsOnlyWhenValueChanges()
    {
        var c = new World().Open();
        var names = new List<string>();
        c.PropertyChanged += (_, e) => names.Add(e.PropertyName!);
        c.OpenCardGuide();
        Assert.Contains(nameof(NinoController.CardGuideOpen), names);
        names.Clear();
        c.OpenCardGuide();
        Assert.DoesNotContain(nameof(NinoController.CardGuideOpen), names);
    }
}
