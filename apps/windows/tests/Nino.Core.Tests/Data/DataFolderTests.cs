// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;

namespace Nino.Core.Tests.Data;

public sealed class DataFolderTests : IDisposable
{
    readonly TempFolder _tmp = new();

    sealed class Probe(RunningCopies? result) : IRunningCopyProbe
    {
        public int Calls { get; private set; }

        public RunningCopies? Find()
        {
            Calls++;
            return result;
        }
    }

    string Old => _tmp.File(LegacyNames.DataFolder);
    string New => _tmp.File("Nino");

    DataFolderResolver Resolver(IRunningCopyProbe? probe = null, bool windows = true) =>
        new(_tmp.Path, windows, probe, new FakeClock(new DateTimeOffset(2026, 11, 22, 10, 0, 0, TimeSpan.Zero)));

    void MakeOld()
    {
        Directory.CreateDirectory(Path.Combine(Old, "pool"));
        File.WriteAllText(Path.Combine(Old, "settings.json"), "{}");
        File.WriteAllText(Path.Combine(Old, "pool", "state.json"), "{\"install\":\"x\"}");
    }

    public void Dispose() => _tmp.Dispose();

    [Fact]
    public void YalnizEskiVarsaTasinir()
    {
        MakeOld();
        var choice = Resolver().Prepare();
        Assert.Equal(New, choice.Path);
        Assert.Equal("Nino", choice.FolderName);
        Assert.Null(choice.Error);
        Assert.False(choice.Copied);
        Assert.False(Directory.Exists(Old));
        Assert.True(File.Exists(Path.Combine(New, "pool", "state.json")));
    }

    [Fact]
    public void TasimaHatasindaEskiKullanilirYeniOlusmaz()
    {
        MakeOld();
        var r = Resolver();
        r.MoveDirectory = (_, _) => throw new IOException("kilitli");
        var choice = r.Prepare();
        Assert.Equal(Old, choice.Path);
        Assert.True(choice.IsLegacy);
        Assert.Equal("kilitli", choice.Error);
        Assert.False(Directory.Exists(New));
        Assert.True(File.Exists(Path.Combine(Old, "settings.json")));
    }

    [Fact]
    public void IzinHatasindaDaEskiKullanilir()
    {
        MakeOld();
        var r = Resolver();
        r.MoveDirectory = (_, _) => throw new UnauthorizedAccessException("izin yok");
        Assert.Equal(Old, r.Prepare().Path);
        Assert.False(Directory.Exists(New));
    }

    [Fact]
    public void TasimaBasarisizAmaYeniBelirdiyseYeniKullanilir()
    {
        MakeOld();
        var r = Resolver();
        r.MoveDirectory = (_, to) =>
        {
            Directory.CreateDirectory(to);
            File.WriteAllText(Path.Combine(to, "settings.json"), "{}");
            throw new IOException("başka kopya taşıdı");
        };
        var choice = r.Prepare();
        Assert.Equal(New, choice.Path);
        Assert.Null(choice.Error);
    }

    [Fact]
    public void TasimaBasarisizVeYeniBosKaldiysaEskiKullanilir()
    {
        MakeOld();
        Directory.CreateDirectory(New);
        var r = Resolver();
        r.MoveDirectory = (_, to) =>
        {
            Directory.CreateDirectory(to);
            throw new IOException("taşınamadı");
        };
        var choice = r.Prepare();
        Assert.Equal(Old, choice.Path);
        Assert.NotNull(choice.Error);
    }

    [Fact]
    public void IkisiDeVarsaYeniKullanilirDokunulmaz()
    {
        MakeOld();
        Directory.CreateDirectory(New);
        File.WriteAllText(Path.Combine(New, "x.txt"), "1");
        var probe = new Probe(new RunningCopies(@"C:\a\Nino.exe", []));
        var choice = Resolver(probe).Prepare();
        Assert.Equal(New, choice.Path);
        Assert.True(File.Exists(Path.Combine(Old, "settings.json")));
        Assert.False(File.Exists(Path.Combine(New, "settings.json")));
        Assert.Equal(0, probe.Calls);
    }

    [Fact]
    public void HicbiriYoksaYeniOlusturulurSurecListesineBakilmaz()
    {
        var probe = new Probe(null);
        var choice = Resolver(probe).Prepare();
        Assert.Equal(New, choice.Path);
        Assert.True(Directory.Exists(New));
        Assert.Equal(0, probe.Calls);
    }

    [Fact]
    public void HazirlikYokkenHicbirSeyYapilmaz()
    {
        MakeOld();
        Directory.CreateDirectory(New); // boş
        var r = Resolver();
        Assert.Equal(New, r.Current.Path);
        Assert.True(Directory.Exists(Old));
        // Karar verildikten sonra hazırlık bir şey yapmaz.
        Assert.Equal(New, r.Prepare().Path);
        Assert.True(Directory.Exists(Old));
    }

    [Fact]
    public void HazirlikYokkenYalnizEskiVarsaEskiSecilir()
    {
        MakeOld();
        var choice = Resolver().Current;
        Assert.Equal(Old, choice.Path);
        Assert.False(Directory.Exists(New));
    }

    [Fact]
    public void BosYeniKlasorEskiVerininOnuneGecmez()
    {
        MakeOld();
        Directory.CreateDirectory(New);
        var choice = Resolver().Prepare();
        Assert.Equal(New, choice.Path);
        Assert.True(File.Exists(Path.Combine(New, "settings.json")));
        Assert.False(Directory.Exists(Old));
    }

    [Fact]
    public void BaskaKopyaAcikkenErtelenirBosYeniyeDokunulmaz()
    {
        MakeOld();
        Directory.CreateDirectory(New);
        var probe = new Probe(new RunningCopies(@"C:\K\current\Nino.exe", [@"C:\K\current\Nino.exe"]));
        var choice = Resolver(probe).Prepare();
        Assert.Equal(Old, choice.Path);
        Assert.NotNull(choice.Error);
        Assert.True(Directory.Exists(New));
        Assert.Equal(1, probe.Calls);
    }

    [Fact]
    public void BaskaKopyaAcikkenOrtakKlasorDeErtelenir()
    {
        MakeOld();
        File.WriteAllText(Path.Combine(Old, "Update.exe"), "");
        var probe = new Probe(new RunningCopies(@"C:\K\current\Nino.exe", [null]));
        var choice = Resolver(probe).Prepare();
        Assert.Equal(Old, choice.Path);
        Assert.False(Directory.Exists(New));
    }

    [Theory]
    [InlineData("file:Update.exe")]
    [InlineData("dir:current")]
    [InlineData("dir:packages")]
    [InlineData("sibling")]
    [InlineData("process")]
    public void OrtaklikIsaretiKopyayaYolAcar(string sign)
    {
        MakeOld();
        IRunningCopyProbe? probe = null;
        switch (sign)
        {
            case "file:Update.exe": File.WriteAllText(Path.Combine(Old, "Update.exe"), "x"); break;
            case "dir:current": Directory.CreateDirectory(Path.Combine(Old, "current")); break;
            case "dir:packages": Directory.CreateDirectory(Path.Combine(Old, "packages")); break;
            case "sibling": Directory.CreateDirectory(_tmp.File(LegacyNames.InstallFolder)); break;
            case "process":
                probe = new Probe(new RunningCopies(@"C:\K\current\Nino.exe", [@"C:\Asil\current\Old.exe"]));
                break;
        }
        var choice = Resolver(probe).Prepare();
        Assert.Equal(New, choice.Path);
        Assert.True(choice.Copied);
        Assert.True(Directory.Exists(Old));
        Assert.True(File.Exists(Path.Combine(New, "settings.json")));
        Assert.True(File.Exists(Path.Combine(New, DataFolderResolver.CopyNoteFile)));
        Assert.False(File.Exists(Path.Combine(New, "Update.exe")));
        Assert.False(Directory.Exists(Path.Combine(New, "current")));
        Assert.False(Directory.Exists(Path.Combine(New, "packages")));
        Assert.Empty(Directory.GetDirectories(_tmp.Path, "Nino.kopya-*"));
    }

    [Fact]
    public void KopyadaAtlananlarVeKopyalananlar()
    {
        MakeOld();
        File.WriteAllText(Path.Combine(Old, "Update.exe"), "");
        foreach (var d in new[] { "current", "packages", "Models", "cuda-12.8", "webview", "xbox-webview", "packs", "adb", "samsung", "translations", "glossary" })
            Directory.CreateDirectory(Path.Combine(Old, d));
        File.WriteAllText(Path.Combine(Old, "packs", "a.json"), "{}");
        File.WriteAllText(Path.Combine(Old, "packs", "x.log"), "alt düzeyde atlanmaz");
        foreach (var f in new[] { "secure.dat", "Nino.exe", "hata.log", "remoteplay.log", "altyazi.log.1", "secure.dat.tmp", "a.nupkg" })
            File.WriteAllText(Path.Combine(Old, f), "");
        Directory.CreateDirectory(_tmp.File("Nino.kopya-eski"));

        var choice = Resolver().Prepare();
        Assert.True(choice.Copied);
        foreach (var kept in new[] { "settings.json", "secure.dat", "packs/a.json", "packs/x.log" })
            Assert.True(File.Exists(Path.Combine(New, kept)), kept);
        foreach (var d in new[] { "packs", "adb", "samsung", "pool", "translations", "glossary" })
            Assert.True(Directory.Exists(Path.Combine(New, d)), d);
        foreach (var d in new[] { "current", "packages", "Models", "cuda-12.8", "webview", "xbox-webview" })
            Assert.False(Directory.Exists(Path.Combine(New, d)), d);
        foreach (var f in new[] { "Update.exe", "Nino.exe", "hata.log", "remoteplay.log", "altyazi.log.1", "secure.dat.tmp", "a.nupkg" })
            Assert.False(File.Exists(Path.Combine(New, f)), f);
        Assert.False(Directory.Exists(_tmp.File("Nino.kopya-eski")));
    }

    [Fact]
    public void KopyaYariKalirsaGeciciKlasorSilinirEskiKullanilir()
    {
        MakeOld();
        File.WriteAllText(Path.Combine(Old, "Update.exe"), "");
        var r = Resolver();
        r.PromoteCopy = (_, _) => throw new IOException("yer değiştirilemedi");
        var choice = r.Prepare();
        Assert.Equal(Old, choice.Path);
        Assert.False(Directory.Exists(New));
        Assert.Empty(Directory.GetDirectories(_tmp.Path, "Nino.kopya-*"));
    }

    [Fact]
    public void WindowsDisindaEskiAdKalirHicbirSeyOlusmaz()
    {
        var r = Resolver(windows: false);
        var choice = r.Prepare();
        Assert.Equal(Old, choice.Path);
        Assert.Equal(LegacyNames.DataFolder, choice.FolderName);
        Assert.False(Directory.Exists(Old));
        Assert.False(Directory.Exists(New));
    }

    [Fact]
    public void GosterilenYol()
    {
        MakeOld();
        Assert.Equal(@"%LOCALAPPDATA%\Nino\hata.log", Resolver().Prepare().DisplayPath("hata.log"));
    }

    const string K = @"C:\Users\u\AppData\Local\NinoGameTranslator";
    const string Asil = @"C:\Users\u\AppData\Local\Other";

    [Fact]
    public void AcikKopyaSiniflandirma()
    {
        var own = K + @"\current\Nino.exe";
        Assert.Equal(OtherCopyKind.None, RunningCopyRules.Classify(own, []));
        Assert.Equal(OtherCopyKind.None, RunningCopyRules.Classify(own, [K + @"\Nino.exe"]));
        Assert.Equal(OtherCopyKind.ThisApp, RunningCopyRules.Classify(own, [K + @"\current\Nino.exe"]));
        Assert.Equal(OtherCopyKind.ThisApp, RunningCopyRules.Classify(own, [Asil + @"\current\Nino.exe", K + @"\current\Nino.exe"]));
        Assert.Equal(OtherCopyKind.OtherApp, RunningCopyRules.Classify(own, [Asil + @"\current\Nino.exe"]));
        Assert.Equal(OtherCopyKind.OtherApp, RunningCopyRules.Classify(own, [K + @"\Nino.exe", Asil + @"\current\Nino.exe"]));
        Assert.Equal(OtherCopyKind.ThisApp, RunningCopyRules.Classify(own, [Asil + @"\current\Nino.exe", null]));
        Assert.Equal(OtherCopyKind.ThisApp, RunningCopyRules.Classify(null, [Asil + @"\current\Nino.exe"]));
        Assert.Equal(OtherCopyKind.None, RunningCopyRules.Classify(null, []));
    }

    [Fact]
    public void BaslaticiYolu()
    {
        Assert.Equal(K + @"\Nino.exe", RunningCopyRules.LauncherPath(K + @"\current\Nino.exe"));
        Assert.Null(RunningCopyRules.LauncherPath("Nino.exe"));
        Assert.Null(RunningCopyRules.LauncherPath(""));
    }
}
