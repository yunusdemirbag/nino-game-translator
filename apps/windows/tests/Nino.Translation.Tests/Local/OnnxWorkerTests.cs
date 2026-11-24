// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Translation;
using Nino.Translation.Local;

namespace Nino.Translation.Tests.Local;

/// <summary>ONNX işçisi: yerel hata yalnız işçiyi kapatır, uygulama ayakta kalır.</summary>
public class OnnxWorkerTests
{
    sealed class UpperEngine : ISentenceEngine
    {
        public bool IsDisposed { get; private set; }

        public string Translate(string sentence, CancellationToken cancellationToken) =>
            sentence == "bad" ? throw new InvalidOperationException("olmadı") : sentence.ToUpperInvariant();

        public void Dispose() { IsDisposed = true; }
    }

    /// <summary>"boom" satırında kapanan (yanıt vermeyen) işçi; çıkış kodu 0xC0000005.</summary>
    sealed class DyingWorker : IWorkerProcess, IWorkerExit
    {
        readonly Queue<string?> _lines = new();
        bool _dead;

        public DyingWorker()
        {
            _lines.Enqueue("{\"ready\":true}");
            Input = new Writer(this);
            Output = new Reader(this);
        }

        public TextWriter Input { get; }
        public TextReader Output { get; }
        public int? ExitCode => _dead ? unchecked((int)0xC0000005) : null;
        public bool IsDisposed { get; private set; }

        public void Kill(TimeSpan wait) => _dead = true;

        public void Dispose() { IsDisposed = true; }

        void OnLine(string line)
        {
            var text = JsonDocument.Parse(line).RootElement.GetProperty("text").GetString()!;
            if (text.StartsWith("boom", StringComparison.Ordinal))
            {
                _dead = true;
                return;
            }
            _lines.Enqueue(JsonSerializer.Serialize(new Dictionary<string, string> { ["text"] = "<" + text + ">" }));
        }

        sealed class Writer(DyingWorker owner) : StringWriter
        {
            public override void WriteLine(string? value) => owner.OnLine(value ?? "");
        }

        sealed class Reader(DyingWorker owner) : TextReader
        {
            public override string? ReadLine() => owner._dead || owner._lines.Count == 0 ? null : owner._lines.Dequeue();
        }
    }

    [Fact]
    public void IsciIstekleriCevirirHataliSatiriBildirir()
    {
        var input = new StringReader("{\"text\":\"hello\"}\n{\"text\":\"bad\"}\nçöp\n");
        var output = new StringWriter();
        var engine = new UpperEngine();

        var code = OnnxWorkerHost.Serve(input, output, () => engine);

        Assert.Equal(0, code);
        Assert.True(engine.IsDisposed);
        var lines = output.ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(l => l.TrimEnd('\r')).ToList();
        Assert.Equal("{\"ready\":true}", lines[0]);
        Assert.Equal("{\"text\":\"HELLO\"}", lines[1]);
        Assert.Contains("olmadı", lines[2]);
        Assert.Contains("anlaşılmadı", lines[3]);
    }

    [Fact]
    public void IsciMotoruAcamazsaHazirDegil()
    {
        var output = new StringWriter();
        var code = OnnxWorkerHost.Serve(new StringReader(""), output, () => throw new FileNotFoundException("model yok"));

        Assert.Equal(2, code);
        Assert.Contains("\"ready\":false", output.ToString());
        Assert.Contains("model yok", output.ToString());
    }

    [Fact]
    public void IsciKapanincaSatirDuserUygulamaAyaktaKalirIsciYenidenAcilir()
    {
        var started = new List<DyingWorker>();
        var log = new List<string>();
        using var engine = OnnxWorkerEngine.Open(() =>
        {
            var w = new DyingWorker();
            started.Add(w);
            return w;
        }, log.Add, TimeSpan.FromSeconds(5));

        Assert.Equal("<hello>", engine.Translate("hello", CancellationToken.None));
        Assert.Throws<Ct2LineException>(() => engine.Translate("boom", CancellationToken.None));
        Assert.True(started[0].IsDisposed);
        Assert.Contains(log, l => l.Contains("0xC0000005") && l.Contains("ayakta"));

        Assert.Equal("<next>", engine.Translate("next", CancellationToken.None));
        Assert.Equal(2, started.Count);

        // Kapatan satır bir daha işçiye gitmez (işçi yeniden kapanmaz).
        Assert.Throws<Ct2LineException>(() => engine.Translate("boom", CancellationToken.None));
        Assert.Equal(2, started.Count);
        Assert.Equal(1, engine.Deaths);
    }

    [Fact]
    public void UcKapanmadanSonraMotorKaliciDuser()
    {
        using var engine = OnnxWorkerEngine.Open(() => new DyingWorker(), null, TimeSpan.FromSeconds(5));

        Assert.Throws<Ct2LineException>(() => engine.Translate("boom 1", CancellationToken.None));
        Assert.Throws<Ct2LineException>(() => engine.Translate("boom 2", CancellationToken.None));
        Assert.Throws<IOException>(() => engine.Translate("boom 3", CancellationToken.None));
        Assert.Equal(OnnxWorkerEngine.MaxDeaths, engine.Deaths);
        Assert.Throws<IOException>(() => engine.Translate("hello", CancellationToken.None));
    }

    [Fact]
    public void YanitGelmezseIsciOldurulur()
    {
        var hung = new HungWorker();
        using var engine = OnnxWorkerEngine.Open(() => hung, null, TimeSpan.FromMilliseconds(300));

        Assert.Throws<Ct2LineException>(() => engine.Translate("hello", CancellationToken.None));
        Assert.True(hung.Killed);
        Assert.Equal(1, engine.Deaths);
    }

    [Fact]
    public void IsciAcilistaKapanirsaMotorAcilamaz()
    {
        Assert.Throws<IOException>(() => OnnxWorkerEngine.Open(() => new HungWorker(ready: null), null, TimeSpan.FromSeconds(2)));
    }

    /// <summary>Hazır der, sonra hiç yanıt vermez.</summary>
    sealed class HungWorker(string? ready = "{\"ready\":true}") : IWorkerProcess
    {
        readonly ManualResetEventSlim _killed = new();
        readonly string? _ready = ready;
        bool _first = true;

        public TextWriter Input { get; } = new StringWriter();
        public TextReader Output => new Reader(this);
        public bool Killed => _killed.IsSet;

        public void Kill(TimeSpan wait) => _killed.Set();

        public void Dispose() => _killed.Set();

        sealed class Reader(HungWorker owner) : TextReader
        {
            public override string? ReadLine()
            {
                if (owner._first)
                {
                    owner._first = false;
                    return owner._ready;
                }
                owner._killed.Wait(TimeSpan.FromSeconds(5));
                return null;
            }
        }
    }
}
