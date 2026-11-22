// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Translation;
using Nino.Translation.Local;

namespace Nino.Translation.Tests.Local;

public class FactoryTests
{
    static (NinoTranslatorFactory Factory, string Root) Create(bool installTurkish, Func<string, IPieceTokenizer>? tokenizer = null)
    {
        var root = Path.Combine(Path.GetTempPath(), "nino-factory-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "models", "en-tr-ct2");
        Directory.CreateDirectory(folder);
        if (installTurkish)
            foreach (var f in new[] { "model.bin", "config.json", "source.spm", "vocab.json", "shared_vocabulary.json" })
                File.WriteAllText(Path.Combine(folder, f), "x");
        var http = new HttpClient(new FileServer());
        var downloader = new ModelDownloader(http);
        var factory = new NinoTranslatorFactory(new TranslatorFactoryOptions
        {
            CacheFolder = Path.Combine(root, "translations"),
            Http = http,
            Free = new FreeEngineOptions
            {
                Store = new FreeModelStore(Path.Combine(root, "models"), downloader),
                Runtime = new Ct2Runtime(Path.Combine(root, "ct2-yok")),
                LoadTokenizer = tokenizer,
            },
        });
        return (factory, root);
    }

    [Fact]
    public void UcretsizCevirmenDurumlari()
    {
        var (missing, _) = Create(installTurkish: false);
        Assert.Equal(UnavailableReason.DownloadRequired, Assert.IsType<UnavailableTranslator>(missing.CreateFree("tr")).Reason);
        Assert.Equal(UnavailableReason.Unsupported, Assert.IsType<UnavailableTranslator>(missing.CreateFree("th")).Reason);
        Assert.Equal(UnavailableReason.DownloadRequired, Assert.IsType<UnavailableTranslator>(missing.CreateFree("ar")).Reason);

        var (ready, root) = Create(installTurkish: true, _ => new SpaceTokenizer());
        var first = Assert.IsType<FreeTranslator>(ready.CreateFree("tr"));
        Assert.Same(first, ready.CreateFree("tr"));
        Assert.EndsWith("v1-opus_mt_ct2_p3-en-tr.jsonl", Path.Combine(root, "translations", Nino.Core.Data.TranslationCache.FileName(first.EngineName, "en", "tr")));
    }

    [Fact]
    public async Task CalismaZamaniEksikseMotorAcilamadi()
    {
        var (factory, _) = Create(installTurkish: true, _ => new SpaceTokenizer());
        var failures = 0;
        var free = Assert.IsType<FreeTranslator>(factory.CreateFree("tr"));
        free.EngineFailed += _ => failures++;
        var e = await Assert.ThrowsAsync<TranslatorUnavailableException>(() => free.TranslateAsync("We go to the boat now."));
        Assert.Equal(UnavailableReason.EngineFailed, e.Reason);
        Assert.IsType<FileNotFoundException>(e.InnerException);
        Assert.Equal(UnavailableReason.EngineFailed, Assert.IsType<UnavailableTranslator>(factory.CreateFree("tr")).Reason);
        factory.CloseFreeTranslators();
        Assert.IsType<FreeTranslator>(factory.CreateFree("tr"));
        Assert.True(failures <= 1);
    }

    [Fact]
    public void CevrimiciMotorAdlari()
    {
        var (factory, _) = Create(installTurkish: false);
        var deepl = factory.CreateDeepL("k:fx", "tr", null);
        Assert.Equal("deepl", deepl.EngineName);
        var gemini = factory.CreateAi(AiService.Gemini, "eski-model", "k", "tr", null, null, () => null);
        Assert.Equal("gemini:gemini-3.5-flash-lite", gemini.EngineName);
        var local = factory.CreateAi(AiService.Local, "qwen2.5:7b", "", "tr", LocalServer.Create("localhost:11434", "qwen2.5:7b"), null, () => null);
        Assert.Equal("local:localhost:11434/qwen2.5:7b", local.EngineName);
    }
}

public class FactoryDeviceTests
{
    [Fact]
    public void AygitDegisinceYenidenKurulur()
    {
        var root = Path.Combine(Path.GetTempPath(), "nino-factory-dev-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "en-tr-ct2");
        Directory.CreateDirectory(folder);
        foreach (var f in new[] { "model.bin", "config.json", "source.spm", "vocab.json", "shared_vocabulary.json" })
            File.WriteAllText(Path.Combine(folder, f), "x");
        var http = new HttpClient(new FileServer());
        var factory = new NinoTranslatorFactory(new TranslatorFactoryOptions
        {
            Http = http,
            Free = new FreeEngineOptions { Store = new FreeModelStore(root, new ModelDownloader(http)), LoadTokenizer = _ => new SpaceTokenizer() },
        });
        var first = factory.CreateFree("tr");
        factory.ConfigureFreeEngine(useGpu: true, cpuThreads: 4);
        Assert.NotSame(first, factory.CreateFree("tr"));
    }
}
