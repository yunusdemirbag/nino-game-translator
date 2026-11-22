// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;

namespace Nino.Core.Tests.Data;

public class TranslationCacheTests : IDisposable
{
    readonly TempFolder _tmp = new();

    public void Dispose() => _tmp.Dispose();

    [Theory]
    [InlineData("opus-mt", "en", "tr", "v1-opus_mt-en-tr.jsonl")]
    [InlineData("opus-mt", "en", "ar", "v1-opus_mt-en-ar.jsonl")]
    [InlineData("deepl", "en", "tr", "v1-deepl-en-tr.jsonl")]
    [InlineData("local:model.a", "en", "tr", "v1h-6b5f11ab62999719865a030d1fb7f93bbcf1184290b58d4d603d1bee6c03249c.jsonl")]
    [InlineData("gemini:gemini-3.5-flash-lite", "en", "tr", "v1h-1aa82a53a8896bbdf8841c6a44e31bc0ec2a382935938bda14071a3444e0ca98.jsonl")]
    public void DosyaAdi(string engine, string source, string target, string expected) =>
        Assert.Equal(expected, TranslationCache.FileName(engine, source, target));

    [Fact]
    public void BenzerMotorlarAyniDosyayiPaylasmaz()
    {
        Assert.NotEqual(TranslationCache.FileName("local:qwen2.5:7b", "en", "tr"), TranslationCache.FileName("local:qwen2-5:7b", "en", "tr"));
        Assert.NotEqual(TranslationCache.FileName("local:model.a", "en", "tr"), TranslationCache.FileName("local:model_a", "en", "tr"));
        Assert.NotEqual(TranslationCache.FileName("opus-mt", "en", "tr"), TranslationCache.FileName("opus_mt", "en", "tr"));
    }

    [Fact]
    public void YenidenAcilistaKalirMotorlarAyri()
    {
        var a = new TranslationCache(_tmp.File("a.jsonl"));
        a.Store("Get down!", "Yere yat!");
        var b = new TranslationCache(_tmp.File("b.jsonl"));
        Assert.False(b.TryGet("Get down!", out _));
        var again = new TranslationCache(_tmp.File("a.jsonl"));
        Assert.True(again.TryGet("Get down!", out var tr));
        Assert.Equal("Yere yat!", tr);
    }

    [Fact]
    public void TirnakVeSatirSonuGidipGelirKacisliYazilir()
    {
        var path = _tmp.File("c.jsonl");
        new TranslationCache(path).Store("Say \"hi\" <b>&\nnow", "Işığı söndür.");
        var line = File.ReadAllText(path);
        Assert.Equal("[\"Say \\u0022hi\\u0022 \\u003Cb\\u003E\\u0026\\nnow\",\"I\\u015F\\u0131\\u011F\\u0131 s\\u00F6nd\\u00FCr.\"]\n", line);
        Assert.True(new TranslationCache(path).TryGet("Say \"hi\" <b>&\nnow", out var tr));
        Assert.Equal("Işığı söndür.", tr);
    }

    [Fact]
    public void MacinKacissizSatiriOkunurBozuklarAtlanir()
    {
        var path = _tmp.File("d.jsonl");
        File.WriteAllText(path, "[\"Run!\",\"Koş!\"]\nnot json\n[\"only one\"]\n\n[\"\",\"x\"]\n");
        var c = new TranslationCache(path);
        Assert.Equal(1, c.Count);
        Assert.True(c.TryGet("Run!", out var tr));
        Assert.Equal("Koş!", tr);
    }

    [Fact]
    public void SonuncuGecerli()
    {
        var path = _tmp.File("e.jsonl");
        File.WriteAllText(path, "[\"a\",\"1\"]\n[\"a\",\"2\"]\n");
        Assert.True(new TranslationCache(path).TryGet("a", out var v));
        Assert.Equal("2", v);
    }

    [Fact]
    public void SinirdaEnUzunSuredirKullanilmayanAtilir()
    {
        var c = new TranslationCache(_tmp.File("f.jsonl"), capacity: 10);
        for (var i = 0; i < 10; i++) c.Store("s" + i, "t" + i);
        Assert.True(c.TryGet("s0", out _));
        c.Store("s10", "t10");
        Assert.False(c.TryGet("s1", out _));
        Assert.True(c.TryGet("s0", out _));
        Assert.True(c.TryGet("s10", out _));
    }

    [Fact]
    public void DosyaSiniriAsmaz()
    {
        var path = _tmp.File("g.jsonl");
        var c = new TranslationCache(path, capacity: 5);
        for (var round = 0; round < 6; round++)
            for (var i = 0; i < 5; i++)
                c.Store($"r{round}-{i}", $"v{round}-{i}");
        Assert.True(File.ReadAllLines(path).Length <= 10);
        Assert.True(new TranslationCache(path, capacity: 5).TryGet("r5-4", out var v));
        Assert.Equal("v5-4", v);
    }

    [Fact]
    public void BosDegerSaklanmazDosyaOlusmaz()
    {
        var path = _tmp.File("h.jsonl");
        var c = new TranslationCache(path);
        c.Store("a", "");
        c.Store("", "b");
        Assert.False(File.Exists(path));
    }

    [Fact]
    public void AyniDegerDosyayaYazilmaz()
    {
        var path = _tmp.File("i.jsonl");
        var c = new TranslationCache(path);
        c.Store("a", "b");
        c.Store("a", "b");
        Assert.Single(File.ReadAllLines(path));
    }

    [Fact]
    public void AyniDosyaIcinTekNesne() =>
        Assert.Same(TranslationCache.ForFile(_tmp.File("j.jsonl")), TranslationCache.ForFile(_tmp.File("J.JSONL")));

    [Fact]
    public void DosyasizCalisir()
    {
        var c = new TranslationCache(null);
        c.Store("a", "b");
        Assert.True(c.TryGet("a", out _));
    }
}
