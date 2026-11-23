// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Nino.Linux.Hosting;
using Nino.Linux.Imaging;
using Nino.Linux.Panel;
using Nino.Linux.Ports;

namespace Nino.Linux.Tests;

public sealed class PanelRulesTests
{
    private const string Prefix = "https://remoteplay.dl.playstation.net/remoteplay/redirect";

    [Theory]
    [InlineData(0.62, 0.97, 0.14, 0.86, true)]
    [InlineData(0, 1, 0, 1, true)]
    [InlineData(-0.01, 0.5, 0.1, 0.9, false)]
    [InlineData(0.5, 1.01, 0.1, 0.9, false)]
    [InlineData(0.5, 0.54, 0.1, 0.9, false)]  // çok alçak
    [InlineData(0.5, 0.6, 0.4, 0.49, false)]  // çok dar
    [InlineData(0.5, 0.75, 0.25, 0.75, true)]
    public void BolgeDenetimi(double top, double bottom, double left, double right, bool usable) =>
        Assert.Equal(usable, PanelRules.IsUsable(new PanelRegion(top, bottom, left, right)));

    [Fact]
    public void YonlendirmeAdresiUcBicimde()
    {
        Assert.Equal($"{Prefix}?code=AbC123", PanelRules.RedirectFrom($"  {Prefix}?code=AbC123 ", Prefix)!.AbsoluteUri);
        Assert.Equal($"{Prefix}?code=AbC123&cid=9", PanelRules.RedirectFrom("?code=AbC123&cid=9", Prefix)!.AbsoluteUri);
        Assert.Equal($"{Prefix}?code=AbC123", PanelRules.RedirectFrom("AbC123", Prefix)!.AbsoluteUri);
        Assert.Null(PanelRules.RedirectFrom("   ", Prefix));
        Assert.Null(PanelRules.RedirectFrom("ht!tp://", Prefix));
    }

    [Theory]
    [InlineData(" sk-ant-api03-xyz ", "Claude")]
    [InlineData("0f1e2d3c-aaaa-bbbb-cccc-123456789abc:fx", "DeepL")]
    public void AnahtarTuru(string key, string engine) => Assert.Equal(engine, PanelRules.EngineForKey(key));
}

/// <summary>Çağrıları ve hangi iş parçacığında yapıldıklarını kaydeden sahte denetleyici.</summary>
internal sealed class RecordingBackend : INinoBackend
{
    public List<string> Calls { get; } = [];
    public HashSet<int> Threads { get; } = [];
    public Exception? Throw { get; set; }
    public BgraPicture? LatestFrame { get; set; }
    public PanelRegion? Region { get; private set; }
    public JsonObject? Style { get; private set; }
    public bool? Online { get; private set; }
    public bool? Speaker { get; private set; }

    public string RedirectPrefix => "https://remoteplay.dl.playstation.net/remoteplay/redirect";

    private Task Note(string call)
    {
        Calls.Add(call);
        Threads.Add(Environment.CurrentManagedThreadId);
        return Throw is { } error ? Task.FromException(error) : Task.CompletedTask;
    }

    public PanelState State()
    {
        Threads.Add(Environment.CurrentManagedThreadId);
        return new PanelState { Version = "9.9.9", Step = "Done", OnlineEngine = "DeepL", Ps5 = new PanelPs5("Bağlı", "Good") };
    }

    public Task AdvanceAsync() => Note("advance");
    public Task BackAsync() => Note("back");
    public Task SignInAsync(Uri redirect) => Note("psn " + redirect.Query);
    public async Task<IReadOnlyList<PanelConsole>> FindConsolesAsync() { await Note("consoles"); return [new PanelConsole("PS5-123", "192.168.0.20", false)]; }
    public Task RegisterConsoleAsync(string host, string pin) => Note($"register {host} {pin}");
    public async Task<IReadOnlyList<PanelTv>> FindTvsAsync() { await Note("tvs"); return [new PanelTv("Salon", "192.168.0.110", "AndroidTv")]; }
    public Task PairTvAsync(PanelTv tv) => Note($"pair {tv.Name} {tv.Host} {tv.Brand}");
    public Task InstallTvAppAsync(string passphrase) => Note("install " + passphrase);
    public Task RefreshTvAppAsync() => Note("refresh");
    public Task DownloadModelAsync() => Note("model");
    public Task SendTestSubtitleAsync() => Note("test");
    public Task ResetAsync() => Note("reset");
    public Task StartAsync() => Note("start");
    public Task StopAsync() => Note("stop");
    public Task TogglePauseAsync() => Note("pause");

    public Task ChangeSettingsAsync(PanelRegion? region, JsonObject? style, bool? onlineTranslation, bool? showSpeakerNames = null)
    {
        Region = region; Style = style; Online = onlineTranslation; Speaker = showSpeakerNames;
        return Note("settings");
    }

    public async Task<KeyCheck> SaveOnlineKeyAsync(string key) { await Note("key " + key); return new KeyCheck("Valid"); }
    public Task RemoveOnlineKeyAsync() => Note("unkey");

    public async Task<RegionProbe> ProbeRegionAsync(BgraPicture frame) { await Note("probe"); return new RegionProbe(5, frame.Width, frame.Height, ["Hi"], "Hi"); }

    public async Task<SampleTranslation> TranslateSampleAsync(string text) { await Note("translate " + text); return new SampleTranslation("Merhaba", 3, "yerel model"); }

    public void Dispose() { }
}

public sealed class PanelServerTests : IAsyncLifetime
{
    private readonly RecordingBackend backend = new();
    private readonly Journal journal = new();
    private SerialWorker serial = null!;
    private WebApplication app = null!;
    private HttpClient http = null!;

    public async Task InitializeAsync()
    {
        serial = new SerialWorker();
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.ConfigureHttpJsonOptions(options => PanelServer.Configure(options.SerializerOptions));
        app = builder.Build();
        PanelServer.Map(app, backend, serial, journal);
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.First();
        http = new HttpClient { BaseAddress = new Uri(address) };
    }

    public async Task DisposeAsync()
    {
        http.Dispose();
        await app.StopAsync();
        await app.DisposeAsync();
        serial.Dispose();
    }

    private async Task<JsonNode> Json(HttpResponseMessage response) => JsonNode.Parse(await response.Content.ReadAsStringAsync())!;

    [Fact]
    public async Task SayfaVeLogoGomulu()
    {
        var page = await http.GetAsync("/");
        Assert.Equal("text/html", page.Content.Headers.ContentType!.MediaType);
        Assert.Contains("/api/state", await page.Content.ReadAsStringAsync());
        var logo = await http.GetAsync("/logo.svg");
        Assert.Equal("image/svg+xml", logo.Content.Headers.ContentType!.MediaType);
        Assert.Contains("<svg", await logo.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task DurumCamelCaseVeSeriSiradanGelir()
    {
        var state = await Json(await http.GetAsync("/api/state"));
        Assert.Equal("9.9.9", (string?)state["version"]);
        Assert.Equal("Done", (string?)state["step"]);
        Assert.Equal("Good", (string?)state["ps5"]!["tone"]);
        Assert.Equal(0.62, (double)state["settings"]!["region"]!["top"]!);
        Assert.Null(state["settings"]!["deepLKey"]);
        await http.PostAsync("/api/start", null);
        var worker = await serial.Invoke(() => Environment.CurrentManagedThreadId);
        Assert.Equal([worker], backend.Threads);
    }

    [Fact]
    public async Task EylemlerDogruCagriyaGider()
    {
        Assert.Equal("{\"ok\":true}", await (await http.PostAsync("/api/advance", null)).Content.ReadAsStringAsync());
        await http.PostAsync("/api/back", null);
        await http.PostAsJsonAsync("/api/psn", new { redirect = "Kod42" });
        await http.PostAsJsonAsync("/api/register", new { host = " 192.168.0.20 ", pin = "12345678" });
        await http.PostAsJsonAsync("/api/pair", new { name = "LG TV", host = " 10.0.0.5", brand = "Lg" });
        await http.PostAsJsonAsync("/api/tv-app/install", new { passphrase = "ABC123" });
        foreach (var path in new[] { "/api/tv-app/refresh", "/api/model/download", "/api/test-subtitle", "/api/reset", "/api/stop", "/api/pause" })
            Assert.Equal(HttpStatusCode.OK, (await http.PostAsync(path, null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await http.DeleteAsync("/api/deepl")).StatusCode);
        Assert.Equal(["advance", "back", "psn ?code=Kod42", "register 192.168.0.20 12345678", "pair LG TV 10.0.0.5 Lg", "install ABC123",
                      "refresh", "model", "test", "reset", "stop", "pause", "unkey"], backend.Calls);
    }

    [Fact]
    public async Task SorgularSonucDoner()
    {
        var consoles = await Json(await http.GetAsync("/api/consoles"));
        Assert.Equal("192.168.0.20", (string?)consoles[0]!["host"]);
        Assert.False((bool)consoles[0]!["isAwake"]!);
        var tvs = await Json(await http.GetAsync("/api/tvs"));
        Assert.Equal("AndroidTv", (string?)tvs[0]!["brand"]);
        var key = await Json(await http.PostAsJsonAsync("/api/deepl", new { key = "k" }));
        Assert.Equal("Valid", (string?)key["state"]);
        var sample = await Json(await http.PostAsJsonAsync("/api/translate-test", new { text = "" }));
        Assert.Equal("Merhaba", (string?)sample["text"]);
        Assert.Contains("translate Stay close to me and keep your voice down.", backend.Calls);
    }

    [Fact]
    public async Task GecersizBolgeYokSayilirOburAlanlarUygulanir()
    {
        await http.PostAsJsonAsync("/api/settings", new { region = new { top = 0.9, bottom = 0.92, left = 0.1, right = 0.9 }, onlineTranslation = true });
        Assert.Null(backend.Region);
        Assert.True(backend.Online);
        await http.PostAsJsonAsync("/api/settings", new { region = new { top = 0.5, bottom = 0.9, left = 0.1, right = 0.9 }, style = new { fontSize = 58, placement = "Below", bold = true } });
        Assert.Equal(new PanelRegion(0.5, 0.9, 0.1, 0.9), backend.Region);
        Assert.Equal(58, (int)backend.Style!["fontSize"]!);
        Assert.True((bool)backend.Style!["bold"]!);
        Assert.Null(backend.Online);
        await http.PostAsJsonAsync("/api/settings", new { showSpeakerNames = false });
        Assert.False(backend.Speaker);
    }

    [Fact]
    public async Task HatalarIkiTurlu()
    {
        backend.Throw = new PanelProblem("PS5 bulunamadı");
        var user = await http.PostAsync("/api/start", null);
        Assert.Equal(HttpStatusCode.BadRequest, user.StatusCode);
        Assert.Equal("PS5 bulunamadı", (string?)(await Json(user))["error"]);

        backend.Throw = new InvalidOperationException("şimdi olmaz");
        Assert.Equal(HttpStatusCode.BadRequest, (await http.PostAsync("/api/stop", null)).StatusCode);

        backend.Throw = new IOException("disk");
        Assert.Equal(HttpStatusCode.InternalServerError, (await http.PostAsync("/api/stop", null)).StatusCode);
        Assert.Contains(journal.Recent(), line => line.Contains("[panel] disk (IOException)"));
    }

    [Fact]
    public async Task GecersizGirisAdresi400()
    {
        var response = await http.PostAsJsonAsync("/api/psn", new { redirect = "  " });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.DoesNotContain(backend.Calls, call => call.StartsWith("psn"));
    }

    [Fact]
    public async Task KareYoksa404VarsaPngVeOkumaDenemesi()
    {
        Assert.Equal(HttpStatusCode.NotFound, (await http.GetAsync("/api/frame.png")).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await http.PostAsync("/api/read-test", null)).StatusCode);

        backend.LatestFrame = BgraPictureTests.Solid(320, 180, 0, 0, 0);
        var png = await http.GetAsync("/api/frame.png?width=200");
        Assert.Equal("image/png", png.Content.Headers.ContentType!.MediaType);
        var bytes = await png.Content.ReadAsByteArrayAsync();
        Assert.Equal(160, System.Buffers.Binary.BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(16)));
        var probe = await Json(await http.PostAsync("/api/read-test", null));
        Assert.Equal(320, (int)probe["width"]!);
        Assert.Equal("Hi", (string?)probe["subtitle"]);
    }

    [Fact]
    public async Task GunlukUcu()
    {
        journal.Write("ocr", "deneme");
        var log = await Json(await http.GetAsync("/api/log"));
        Assert.EndsWith("[ocr] deneme", (string?)log["lines"]![0]);
    }
}
