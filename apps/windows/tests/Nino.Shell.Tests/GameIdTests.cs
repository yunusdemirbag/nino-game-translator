// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;

namespace Nino.Shell.Tests;

// Asıl oyun kimliği: paket listesi, oyun seçici, ana ekran kartı, kapsam paketinin kimliği.
public sealed class GameIdTests
{
    static void WritePack(string folder, string file, string id, string title, params string[] lines)
    {
        var entries = string.Join(",", lines.Select(l => $"\"{LineKey.Compute(l)}\":\"TR {l}\""));
        File.WriteAllText(Path.Combine(folder, file), $$$"""{"format":1,"id":"{{{id}}}","title":"{{{title}}}","entries":{{{{entries}}}}}""");
    }

    [Fact]
    public void AyniOyunTekSatir()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            WritePack(folder, "community-grand-theft-auto-vi.json", "community-grand-theft-auto-vi", "Grand Theft Auto VI",
                "Meet me at the docks tonight");
            WritePack(folder, "gta-6.json", "gta-6", "Grand Theft Auto VI", "Meet me at the docks tonight", "Get in the car now");
            WritePack(folder, "red-dead-redemption-2.json", "red-dead-redemption-2", "Red Dead Redemption 2", "Hold the reins tight");
            var w = new World().WithPs5().WithTv();
            w.Services.PackService = new PackLibrary(folder);
            var c = w.Open();
            c.ReloadPacks();

            // Ayarlar'daki liste: yerel + inen GTA 6 paketi tek satır, adı tablodan.
            Assert.Equal(["GTA 6", "Red Dead Redemption 2"], c.Packs.Select(p => p.Title));
            Assert.Equal(2, c.Packs[0].EntryCount);
            // Oyun seçici: GTA 6 bir kez.
            Assert.Single(c.GameSuggestions(null), n => GameIds.FromName(n) == "gta-6");

            // Ana ekran kartı: seçilen yazılış ne olursa olsun okunur ad.
            c.ChooseGame("Grand Theft Auto VI");
            Assert.Equal("GTA 6", c.PlayingGame);
            Assert.Equal("Grand Theft Auto VI", c.LastChosenGame);

            // Takma adla seçilen oyunun paketi bulunur; kapsam kimliği asıl kimlik.
            c.ChooseGame("gtavi");
            var packs = w.Services.PackService;
            Assert.NotNull(packs.SelectedPack);
            Assert.NotNull(packs.FindExact("Get in the car now"));
            Assert.Equal("gta-6", packs.ScopeGameId);
        }
        finally { Directory.Delete(folder, true); }
    }

    [Fact]
    public void IceAktarilanPaketinKimligiBasliktan()
    {
        var folder = Directory.CreateTempSubdirectory().FullName;
        try
        {
            WritePack(folder, "community-grand-theft-auto-vi.json", "community-grand-theft-auto-vi", "Grand Theft Auto VI",
                "Only in the imported pack here");
            var packs = new PackLibrary(folder);
            Assert.NotNull(packs.FindExact("Only in the imported pack here"));
            Assert.Equal("community-grand-theft-auto-vi", packs.ScopeId);
            Assert.Equal("gta-6", packs.ScopeGameId);
        }
        finally { Directory.Delete(folder, true); }
    }
}
