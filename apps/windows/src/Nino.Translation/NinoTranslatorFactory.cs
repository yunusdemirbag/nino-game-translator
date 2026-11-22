// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Translation;
using Nino.Translation.Local;
using Nino.Translation.Online;

namespace Nino.Translation;

/// <summary>Fabrikanın ayarları.</summary>
public sealed record TranslatorFactoryOptions
{
    /// <summary>Çeviri önbellek klasörü (<c>%LOCALAPPDATA%\Nino\translations</c>; null: yalnız bellek).</summary>
    public string? CacheFolder { get; init; }

    /// <summary>Kullanıcı sözlükleri (<c>glossary\</c>); null: yalnız genel sözlük.</summary>
    public GlossaryFolder? Glossary { get; init; }

    /// <summary>Çevrimiçi motorların paylaşılan HTTP istemcisi.</summary>
    public required HttpClient Http { get; init; }

    /// <summary>Ücretsiz motorun aygıt ayarları (null: ücretsiz model yok, ör. yalnız çevrimiçi çeviri).</summary>
    public FreeEngineOptions? Free { get; init; }

    /// <summary>Ücretsiz motor açılamadı (bir kez, herhangi bir iş parçacığından).</summary>
    public Action<Exception>? FreeEngineFailed { get; init; }

    /// <summary>Saat (testler).</summary>
    public TimeProvider? Clock { get; init; }
}

/// <summary>
/// Zincirin parçalarını kurar (<see cref="ITranslatorFactory"/>): ücretsiz çevirmen hedef başına bir nesne olarak
/// yeniden kullanılır; aygıt ya da iş parçacığı değişince <see cref="CloseFreeTranslators"/> ile kapatılır.
/// </summary>
public sealed class NinoTranslatorFactory(TranslatorFactoryOptions options) : ITranslatorFactory, IDisposable
{
    readonly Dictionary<string, FreeTranslator> _free = new(StringComparer.Ordinal);
    readonly object _gate = new();
    FreeEngineOptions? _engine = options.Free;

    /// <summary>
    /// Aygıtı ya da CPU iş parçacığı sayısını değiştirir: açık ücretsiz çevirmenler kapatılır, sonraki çeviride yeni
    /// ayarla kurulur.
    /// </summary>
    public void ConfigureFreeEngine(bool useGpu, int cpuThreads)
    {
        lock (_gate)
        {
            if (_engine is null) return;
            _engine = _engine with { UseGpu = useGpu, CpuThreads = cpuThreads };
        }
        CloseFreeTranslators();
    }

    TranslationCache CacheFor(string engine, string target) =>
        options.CacheFolder is null
            ? new TranslationCache(null)
            : TranslationCache.For(options.CacheFolder, engine, "en", TargetLanguages.Code(target));

    Func<Glossary>? GlossaryFor(string target) =>
        TargetLanguages.Code(target) == "tr" ? () => options.Glossary?.Current ?? Glossary.General : null;

    /// <inheritdoc />
    public ITranslator CreateFree(string target)
    {
        var code = TargetLanguages.Code(target);
        lock (_gate)
        {
            if (_engine is not { } engineOptions || !TargetLanguages.FreeModelSupports("en", code))
                return new UnavailableTranslator(UnavailableReason.Unsupported);
            if (_free.TryGetValue(code, out var existing))
                return existing.State == FreeTranslatorState.EngineFailed
                    ? new UnavailableTranslator(UnavailableReason.EngineFailed)
                    : existing;
            if (!engineOptions.Store.IsInstalled(code)) return new UnavailableTranslator(UnavailableReason.DownloadRequired);
            try
            {
                var translator = new FreeTranslator(new FreeEngineSource(code, engineOptions), code,
                    CacheFor(FreeTranslator.Name, code), GlossaryFor(code), options.Clock);
                if (options.FreeEngineFailed is { } failed) translator.EngineFailed += failed;
                _free[code] = translator;
                _ = translator.WarmUpAsync();
                return translator;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or GlossaryFormatException)
            {
                return new UnavailableTranslator(UnavailableReason.EngineFailed);
            }
        }
    }

    /// <summary>Açık ücretsiz çevirmenleri kapatır (aygıt ya da iş parçacığı değişti).</summary>
    public void CloseFreeTranslators()
    {
        List<FreeTranslator> open;
        lock (_gate)
        {
            open = _free.Values.ToList();
            _free.Clear();
        }
        foreach (var t in open) t.Dispose();
    }

    /// <inheritdoc />
    public ITranslator CreateDeepL(string apiKey, string target, ITranslator? fallback) =>
        new DeepLTranslator(apiKey, target, fallback, CacheFor(EngineNames.DeepL, target), GlossaryFor(target),
            options.Http, options.Clock);

    /// <inheritdoc />
    public ITranslator CreateAi(AiService service, string model, string apiKey, string target, LocalServer? local,
        ITranslator? fallback, Func<string?> gameName)
    {
        string engine;
        RequestBudget? budget = null;
        if (service == AiService.Local && local is not null) engine = local.EngineName;
        else
        {
            var info = AiModelCatalog.Default.Resolve(service, model);
            model = info?.Id ?? model;
            engine = EngineNames.Cloud(service, model);
            budget = RequestBudget.Shared(engine, info?.RequestsPerMinute, options.Clock);
        }
        return new AiTranslator(service, model, apiKey, target, fallback, CacheFor(engine, target), options.Http,
            gameName, local, budget, options.Clock);
    }

    /// <inheritdoc />
    public void Dispose() => CloseFreeTranslators();
}
