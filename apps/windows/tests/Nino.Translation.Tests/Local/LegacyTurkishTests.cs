// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Translation.Local;

namespace Nino.Translation.Tests.Local;

public class LegacyTurkishTests
{
    static string MakeRoot(bool legacyOnnx)
    {
        var root = Path.Combine(Path.GetTempPath(), "nino-legacy-tr-" + Guid.NewGuid().ToString("N"));
        var legacy = Path.Combine(root, ModelCatalog.LegacyTurkishFolder);
        Directory.CreateDirectory(legacy);
        if (legacyOnnx)
            foreach (var name in ModelCatalog.OnnxFileNames) File.WriteAllText(Path.Combine(legacy, name), "x");
        return root;
    }

    [Fact]
    public void SecenekKapaliykenEskiModelSayilmaz()
    {
        var root = MakeRoot(legacyOnnx: true);
        var store = new FreeModelStore(root, new ModelDownloader(new HttpClient()));
        Assert.False(store.IsInstalled("tr"));
        Assert.Null(store.LegacyTurkishInUse("tr"));
    }

    [Fact]
    public void SecenekAcikkenEskiOnnxModeliKullanilirVeKorunur()
    {
        var root = MakeRoot(legacyOnnx: true);
        var store = new FreeModelStore(root, new ModelDownloader(new HttpClient()), keepLegacyTurkish: true);
        Assert.True(store.IsInstalled("tr"));
        Assert.Equal(Path.Combine(root, ModelCatalog.LegacyTurkishFolder), store.LegacyTurkishInUse("tr"));
        Assert.Null(store.LegacyTurkishInUse("ar"));
    }

    [Fact]
    public void EskiKlasorEksikseKuruluSayilmaz()
    {
        var root = MakeRoot(legacyOnnx: false);
        var store = new FreeModelStore(root, new ModelDownloader(new HttpClient()), keepLegacyTurkish: true);
        Assert.False(store.IsInstalled("tr"));
    }
}
