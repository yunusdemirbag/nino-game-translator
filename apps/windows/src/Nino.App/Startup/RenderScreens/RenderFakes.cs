// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.App.Strings;
using Nino.Core.Data;
using Nino.Core.Imaging;
using Nino.Core.Link;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Translation;
using Nino.Core.Tv;
using Nino.RemotePlay;
using Nino.Shell;
using Nino.Shell.Platform;

namespace Nino.App.Startup;

/// <summary>
/// Ekran dökümü kipinin sahte denetleyicisi (ana-ekran §11): ağ, dosya ve kullanıcının gerçek verisi yok (bellekteki
/// ayar ve şifreli depo). Bulunan PS5 "PS5-123" @ 192.168.1.20, bulunan TV "[LG] webOS TV" @ 192.168.1.30.
/// </summary>
public static class RenderFakes
{
    /// <summary>Sahte PS5.</summary>
    public static FoundPs5 Ps5 { get; } = new("192.168.1.20", "PS5-123", true);

    /// <summary>Sahte TV.</summary>
    public static FoundTv Tv { get; } = new("[LG] webOS TV", "192.168.1.30", TvBrand.Lg);

    /// <summary>Sahte denetleyici.</summary>
    /// <param name="setupDone">Kurulum bitmiş saklansın mı (PS5 eşli, hesap ve TV kayıtlı): ana ekran açılır.</param>
    /// <param name="post">Arayüz iş parçacığına aktarma.</param>
    public static NinoController Create(bool setupDone, Action<Action> post)
    {
        var secrets = new MemorySecretStore();
        if (setupDone)
        {
            secrets.Set(SecretKeys.AccountId, Enumerable.Repeat((byte)1, 8).ToArray());
            secrets.Set(SecretKeys.Console, RemotePlayRecords.ConsoleToJson(
                new Ps5Console(Ps5.Host, Ps5.Name, Enumerable.Repeat((byte)0x31, 16).ToArray(), Enumerable.Repeat((byte)2, 16).ToArray())));
            secrets.Set(SecretKeys.Tv, new StoredTv { Name = Tv.Name, Host = Tv.Host, Brand = StoredTvBrand.Lg });
            secrets.Set(SecretKeys.TvKey, "render-key");
            secrets.Set(SecretKeys.SetupComplete, true);
        }
        var settings = new MemorySettingsStore(new AppSettings());
        return new NinoController(new Services(), secrets, settings, new NoSleepGuard(), L.Catalog, post,
            new ShellOptions { Logs = new SilentShellLogs(), Browser = new NoBrowser() });
    }

    sealed class Services : IShellServices
    {
        public Task<IReadOnlyList<FoundPs5>> FindPs5Async(string? host, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<FoundPs5>>([Ps5]);

        public Task<byte[]> AccountIdFromRedirectAsync(string redirectUrl, CancellationToken cancellationToken = default) =>
            Task.FromResult(Enumerable.Repeat((byte)1, 8).ToArray());

        public Task<Ps5Console> RegisterPs5Async(string host, byte[] accountId, uint pin, CancellationToken cancellationToken = default) =>
            Task.FromResult(new Ps5Console(host, Ps5.Name, new byte[16], new byte[16]));

        public IVideoSource CreatePs5Source(Ps5Console console, byte[] accountId, string? loginPasscode) =>
            throw new NotSupportedException("Ekran dökümünde yayın yok.");

        public ISubtitleServer CreateSubtitleServer(Action<string> subtitleLog) => new Server();

        public Task<IReadOnlyList<FoundTv>> FindTvsAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<FoundTv>>([Tv]);

        public Task<PairResult> PairTvAsync(TvRecord tv, string? savedKey, string launchParameters, CancellationToken cancellationToken = default) =>
            Task.FromResult(new PairResult("render-key", true));

        public ITvWatch CreateTvWatch(TvWatchRequest request) => new Watch();

        public ITextReaderFactory Readers { get; } = new Readers();

        public IFreeModel FreeModel { get; } = new NoFreeModel();

        public ITranslatorFactory Translators { get; } = new Translators();
    }

    sealed class Server : ISubtitleServer
    {
        public event Action<int>? TvCountChanged { add { } remove { } }
        public event Action<string>? TvModelReported { add { } remove { } }
        public event Action<LocalSubtitleEvent>? LocalEvent { add { } remove { } }
        public event Action<string>? AndroidTvHostFound { add { } remove { } }
        public bool IsRunning => false;
        public int Port => 8787;
        public int TvCount => 0;
        public bool SendToTv { get; set; }
        public Task<int> StartAsync(CancellationToken cancellationToken = default) => Task.FromResult(8787);
        public void Send(TvEvent e) { }
        public string ServerAddress(string? localIp) => $"http://{localIp ?? "127.0.0.1"}:8787";
        public string LaunchParameters(string? localIp) => "{}";
        public (string Local, string? Network) ObsAddresses(string? lanIp) =>
            ("http://localhost:8787/obs", lanIp is null ? null : $"http://{lanIp}:8787/obs");
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    sealed class Watch : ITvWatch
    {
        public void Start() { }
        public void Stop() { }
        public void ReconnectNow() { }
    }

    sealed class Readers : ITextReaderFactory
    {
        public ITextReader? Create(string language) => null;
    }

    sealed class Translators : ITranslatorFactory
    {
        public ITranslator CreateFree(string target) => new Echo();
        public ITranslator CreateDeepL(string apiKey, string target, ITranslator? fallback) => new Echo();
        public ITranslator CreateAi(AiService service, string model, string apiKey, string target, LocalServer? local,
            ITranslator? fallback, Func<string?> gameName) => new Echo();
    }

    sealed class Echo : ITranslator
    {
        public string EngineName => FreeTranslator.Name;
        public bool SupportsPretranslation => false;
        public bool SupportsBatch => false;
        public Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default) =>
            Task.FromResult(TranslationResult.FromEngine(text));
        public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts, CancellationToken cancellationToken = default) =>
            Task.FromResult(texts);
    }
}
