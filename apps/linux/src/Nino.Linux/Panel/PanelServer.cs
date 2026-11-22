// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Nino.Linux.Hosting;
using Nino.Linux.Imaging;
using Nino.Linux.Ports;

namespace Nino.Linux.Panel;

/// <summary>
/// Tarayıcı paneli: tek sayfa ve onun JSON uçları. Denetleyiciye giden her çağrı seri sıradan geçer.
/// Başarılı eylem <c>{ok:true}</c>, sorgu kendi sonucunu döner; hata <c>{error}</c> ile 400 (kullanıcı sorunu)
/// ya da 500 olur ve günlüğe yazılır.
/// </summary>
public static class PanelServer
{
    public const int DefaultPort = 8788;

    public static int PortFromEnvironment() =>
        int.TryParse(Environment.GetEnvironmentVariable("NINO_PANEL_PORT"), out var port) && port is > 0 and < 65536 ? port : DefaultPort;

    public static WebApplication Build(INinoBackend backend, SerialWorker serial, Journal journal, int port, string[]? args = null)
    {
        var builder = WebApplication.CreateSlimBuilder(args ?? []);
        builder.WebHost.ConfigureKestrel(kestrel => kestrel.ListenAnyIP(port));
        builder.Logging.AddFilter(level => level >= LogLevel.Warning);
        builder.Services.ConfigureHttpJsonOptions(options => Configure(options.SerializerOptions));
        var app = builder.Build();
        Map(app, backend, serial, journal);
        return app;
    }

    internal static void Configure(JsonSerializerOptions options)
    {
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.Converters.Add(new JsonStringEnumConverter());
        options.TypeInfoResolverChain.Insert(0, new System.Text.Json.Serialization.Metadata.DefaultJsonTypeInfoResolver());
    }

    private sealed record RedirectBody(string? Redirect);
    private sealed record RegisterBody(string? Host, string? Pin);
    private sealed record PairBody(string? Name, string? Host, string? Brand);
    private sealed record PassphraseBody(string? Passphrase);
    private sealed record KeyBody(string? Key);
    private sealed record TextBody(string? Text);
    private sealed record SettingsBody(PanelRegion? Region, JsonObject? Style, bool? OnlineTranslation);

    public static void Map(IEndpointRouteBuilder app, INinoBackend backend, SerialWorker serial, Journal journal)
    {
        var page = Embedded.Text("nino.panel.html");
        var logo = Embedded.Bytes("nino.logo.png");
        app.MapGet("/", () => Results.Content(page, "text/html; charset=utf-8"));
        app.MapGet("/logo.png", () => Results.Bytes(logo, "image/png"));

        app.MapGet("/api/state", () => serial.Invoke(backend.State));
        app.MapGet("/api/log", () => Results.Ok(new { lines = journal.Recent() }));

        IResult Fail(Exception error) => Failure(error, journal);
        Task<IResult> Act(Func<Task> work) => Guard(serial, async () => { await work(); return Results.Ok(new { ok = true }); }, Fail);
        Task<IResult> Ask<T>(Func<Task<T>> work) => Guard(serial, async () => Results.Ok(await work()), Fail);

        // Kurulum sihirbazı
        app.MapPost("/api/advance", () => Act(backend.AdvanceAsync));
        app.MapPost("/api/back", () => Act(backend.BackAsync));
        app.MapPost("/api/psn", (RedirectBody body) => Act(() =>
            backend.SignInAsync(PanelRules.RedirectFrom(body.Redirect ?? "", backend.RedirectPrefix)
                                ?? throw new PanelProblem(Words.InvalidSignIn))));
        app.MapGet("/api/consoles", () => Ask(backend.FindConsolesAsync));
        app.MapPost("/api/register", (RegisterBody body) => Act(() => backend.RegisterConsoleAsync((body.Host ?? "").Trim(), body.Pin ?? "")));
        app.MapGet("/api/tvs", () => Ask(backend.FindTvsAsync));
        app.MapPost("/api/pair", (PairBody body) => Act(() =>
            backend.PairTvAsync(new PanelTv(body.Name ?? "", (body.Host ?? "").Trim(), body.Brand ?? "Lg"))));
        app.MapPost("/api/tv-app/install", (PassphraseBody body) => Act(() => backend.InstallTvAppAsync(body.Passphrase ?? "")));
        app.MapPost("/api/tv-app/refresh", () => Act(backend.RefreshTvAppAsync));
        app.MapPost("/api/model/download", () => Act(backend.DownloadModelAsync));
        app.MapPost("/api/test-subtitle", () => Act(backend.SendTestSubtitleAsync));
        app.MapPost("/api/reset", () => Act(backend.ResetAsync));

        // Çeviri
        app.MapPost("/api/start", () => Act(backend.StartAsync));
        app.MapPost("/api/stop", () => Act(backend.StopAsync));
        app.MapPost("/api/pause", () => Act(backend.TogglePauseAsync));
        app.MapPost("/api/settings", (SettingsBody body) => Act(() =>
            backend.ChangeSettingsAsync(body.Region is { } region && PanelRules.IsUsable(region) ? region : null,
                                        body.Style, body.OnlineTranslation)));
        app.MapPost("/api/deepl", (KeyBody body) => Ask(() => backend.SaveOnlineKeyAsync(body.Key ?? "")));
        app.MapDelete("/api/deepl", () => Act(backend.RemoveOnlineKeyAsync));

        // Tanı
        app.MapGet("/api/frame.png", async (int? width) =>
        {
            var frame = await serial.Invoke(() => backend.LatestFrame);
            if (frame is null) return Results.NotFound();
            var bytes = await Task.Run(() => PreviewPng.Render(frame, PreviewPng.ClampWidth(width)));
            return Results.Bytes(bytes, "image/png");
        });
        app.MapPost("/api/read-test", () => Ask(async () =>
        {
            var frame = backend.LatestFrame ?? throw new PanelProblem(Words.NoPictureYet);
            return await backend.ProbeRegionAsync(frame);
        }));
        app.MapPost("/api/translate-test", (TextBody body) => Ask(() =>
            backend.TranslateSampleAsync(string.IsNullOrWhiteSpace(body.Text) ? Words.SampleSentence : body.Text)));
    }

    private static async Task<IResult> Guard(SerialWorker serial, Func<Task<IResult>> work, Func<Exception, IResult> fail)
    {
        try { return await serial.Invoke(work); }
        catch (Exception error) { return fail(error); }
    }

    internal static IResult Failure(Exception error, Journal journal)
    {
        journal.Write("panel", $"{error.Message} ({error.GetType().Name})");
        var status = error is PanelProblem or InvalidOperationException ? StatusCodes.Status400BadRequest : StatusCodes.Status500InternalServerError;
        return Results.Json(new { error = error.Message }, statusCode: status);
    }
}

/// <summary>Sunucunun panele döndürdüğü kısa metinler; dil <c>NINO_LANG</c>'den.</summary>
public static class Words
{
    public static bool Turkish => Hosting.Language.Turkish;

    public static string InvalidSignIn => Turkish
        ? "Bu adreste giriş kodu bulunamadı. Sony sayfasından sonra açılan adresin tamamını yapıştırın."
        : "No sign-in code in that address. Paste the full address you landed on after Sony's page.";

    public static string NoPictureYet => Turkish ? "Okunacak kare yok; önce çeviriyi açın." : "There is no frame to read; turn translation on first.";

    public static string SampleSentence => "Stay close to me and keep your voice down.";
}

internal static class Embedded
{
    public static string Text(string name)
    {
        using var source = typeof(Embedded).Assembly.GetManifestResourceStream(name)
                           ?? throw new FileNotFoundException("gömülü kaynak yok", name);
        var copy = new MemoryStream();
        source.CopyTo(copy);
        return System.Text.Encoding.UTF8.GetString(copy.GetBuffer(), 0, (int)copy.Length);
    }

    public static byte[] Bytes(string name)
    {
        using var source = typeof(Embedded).Assembly.GetManifestResourceStream(name)
                           ?? throw new FileNotFoundException("gömülü kaynak yok", name);
        var copy = new MemoryStream();
        source.CopyTo(copy);
        return copy.ToArray();
    }
}
