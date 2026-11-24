// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Nino.Core.Translation;
using Nino.Translation.Local;

namespace Nino.Translation.Tests.Local;

/// <summary>Boşluktan bölen sahte belirteçleyici.</summary>
internal sealed class SpaceTokenizer : IPieceTokenizer
{
    public string[] EncodeToPieces(string text) => [.. text.Split(' ').Select(w => "▁" + w), "</s>"];

    public string DecodePieces(IEnumerable<string> pieces) =>
        string.Concat(pieces.Where(p => p != "</s>")).Replace('▁', ' ').Trim();
}

/// <summary>Sahte işçi: verilen işlevle her istek satırına yanıt verir.</summary>
internal sealed class ScriptedWorker : IWorkerProcess
{
    readonly Queue<string?> _lines = new();
    readonly Func<string, string?> _answer;

    public ScriptedWorker(string? firstLine, Func<string, string?> answer)
    {
        _lines.Enqueue(firstLine);
        _answer = answer;
        Input = new CallbackWriter(line => _lines.Enqueue(_answer(line)));
        Output = new QueueReader(_lines);
    }

    public TextWriter Input { get; }
    public TextReader Output { get; }
    public List<string> Sent => ((CallbackWriter)Input).Lines;
    public bool Killed { get; private set; }
    public string Device { get; init; } = "cpu";

    public void Kill(TimeSpan wait) => Killed = true;

    public void Dispose() => Killed = true;

    sealed class CallbackWriter(Action<string> onLine) : StringWriter
    {
        public List<string> Lines { get; } = [];

        public override void WriteLine(string? value)
        {
            Lines.Add(value ?? "");
            onLine(value ?? "");
        }
    }

    sealed class QueueReader(Queue<string?> lines) : TextReader
    {
        public override string? ReadLine() => lines.Count == 0 ? null : lines.Dequeue();
    }
}

public class EngineTests
{
    static string Echo(string request)
    {
        using var doc = JsonDocument.Parse(request);
        var tokens = doc.RootElement.GetProperty("tokens").EnumerateArray().Select(t => t.GetString()!.ToUpperInvariant());
        return JsonSerializer.Serialize(new { tokens = tokens.Where(t => t != "</S>") });
    }

    [Fact]
    public void IsciProtokolu()
    {
        var worker = new ScriptedWorker("{\"ready\": true}", Echo);
        using var engine = Ct2WorkerEngine.Attach(worker, new SpaceTokenizer());
        Assert.Equal("WE GO.", engine.Translate("We go.", default));
        using var doc = JsonDocument.Parse(worker.Sent[0]);
        Assert.Equal(["▁We", "▁go.", "</s>"], doc.RootElement.GetProperty("tokens").EnumerateArray().Select(t => t.GetString()));
        Assert.Equal(4, doc.RootElement.GetProperty("beams").GetInt32());
        Assert.Equal(22, doc.RootElement.GetProperty("max_output").GetInt32());
        Assert.StartsWith("{\"tokens\":[", worker.Sent[0]);
    }

    [Fact]
    public void UzunIstekKirpilir()
    {
        var tokens = Enumerable.Range(0, 300).Select(i => "▁w" + i).ToList();
        using var doc = JsonDocument.Parse(Ct2WorkerEngine.Request(tokens));
        var sent = doc.RootElement.GetProperty("tokens").EnumerateArray().Select(t => t.GetString()).ToList();
        Assert.Equal(256, sent.Count);
        Assert.Equal("</s>", sent[^1]);
        Assert.Equal(128, doc.RootElement.GetProperty("max_output").GetInt32());
        Assert.Equal(128, Ct2WorkerEngine.MaxOutput(100));
        Assert.Equal(24, Ct2WorkerEngine.MaxOutput(4));
    }

    [Fact]
    public void AcilisHatalari()
    {
        var notReady = new ScriptedWorker("{\"ready\": false, \"error\": \"cuda yok\"}", Echo);
        var e = Assert.Throws<IOException>(() => Ct2WorkerEngine.Attach(notReady, new SpaceTokenizer()));
        Assert.Equal("cuda yok", e.Message);
        Assert.True(notReady.Killed);

        var closed = new ScriptedWorker(null, Echo);
        Assert.Throws<IOException>(() => Ct2WorkerEngine.Attach(closed, new SpaceTokenizer()));
        Assert.True(closed.Killed);
    }

    [Fact]
    public void SatirHatasiVeKapanma()
    {
        var worker = new ScriptedWorker("{\"ready\":true}", r => r.Contains("Bad") ? "{\"error\":\"satır\"}" : null);
        using var engine = Ct2WorkerEngine.Attach(worker, new SpaceTokenizer());
        Assert.Throws<Ct2LineException>(() => engine.Translate("Bad line", default));
        Assert.Throws<IOException>(() => engine.Translate("Good line", default));
    }

    [Fact]
    public void IsinAramasi()
    {
        const int vocab = 6, pad = 5, eos = 0;
        // Her adımda 1, 2, 3 sonra bitiş en olası.
        float[] Step(int[] next, int step)
        {
            var logits = new float[4 * vocab];
            for (var b = 0; b < 4; b++)
            {
                var best = step < 3 ? step + 1 : eos;
                for (var j = 0; j < vocab; j++) logits[b * vocab + j] = j == best ? 5f : 0f;
                logits[b * vocab + pad] = 50f;
            }
            return logits;
        }
        var reorders = 0;
        var result = BeamSearch.Run(4, 20, vocab, pad, eos, Step, _ => reorders++);
        Assert.Equal([1, 2, 3], result);
        Assert.True(reorders > 0);

        var neverEnds = BeamSearch.Run(4, 5, vocab, pad, eos, (_, _) =>
        {
            var l = new float[4 * vocab];
            for (var b = 0; b < 4; b++)
            {
                l[b * vocab + 4] = 9f;
                l[b * vocab + eos] = -100f;
            }
            return l;
        }, _ => { });
        Assert.Equal([4, 4, 4, 4, 4], neverEnds);
    }

    sealed class CountingStarter
    {
        public List<Ct2Device> Started { get; } = [];
        public Func<Ct2Device, bool> CudaWorks { get; set; } = _ => true;
        public Func<Ct2Device, string, bool> Fails { get; set; } = (_, _) => false;

        public IWorkerProcess Start(string folder, Ct2Device device, int threads, string? cuda)
        {
            Started.Add(device);
            if (device == Ct2Device.Cuda && !CudaWorks(device))
                return new ScriptedWorker("{\"ready\":false,\"error\":\"cuda\"}", Echo);
            return new ScriptedWorker("{\"ready\":true}", r => Fails(device, r) ? "{\"error\":\"x\"}"
                : JsonSerializer.Serialize(new { tokens = new[] { "▁" + device } }));
        }
    }

    static (FreeEngineOptions Options, CountingStarter Starter, CudaRuntimeStore Cuda, string Root) GpuSetup(bool useGpu)
    {
        var root = Path.Combine(Path.GetTempPath(), "nino-gpu-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "en-tr-ct2");
        Directory.CreateDirectory(folder);
        foreach (var f in new[] { "model.bin", "config.json", "source.spm", "vocab.json", "shared_vocabulary.json" })
            File.WriteAllText(Path.Combine(folder, f), "x");
        var starter = new CountingStarter();
        var downloader = new ModelDownloader(new HttpClient(new FileServer()));
        var cuda = new CudaRuntimeStore(Path.Combine(root, "cuda-12.8"), downloader, () => true);
        var options = new FreeEngineOptions
        {
            Store = new FreeModelStore(root, downloader),
            Cuda = cuda,
            UseGpu = useGpu,
            StartWorker = starter.Start,
            LoadTokenizer = _ => new SpaceTokenizer(),
        };
        return (options, starter, cuda, root);
    }

    [Fact]
    public void CpuIsci()
    {
        var (options, starter, _, _) = GpuSetup(useGpu: false);
        var source = new FreeEngineSource("tr", options);
        Assert.True(source.IsInstalled);
        using var engine = source.Open(default);
        Assert.Equal("Cpu", engine.Translate("hi", default));
        Assert.Equal([Ct2Device.Cpu], starter.Started);
    }

    [Fact]
    public void GpuAcilamazsaCpu()
    {
        var (options, starter, _, _) = GpuSetup(useGpu: true);
        var fellBack = 0;
        starter.CudaWorks = _ => false;
        using var engine = new FreeEngineSource("tr", options with { GpuFellBack = () => fellBack++ }).Open(default);
        Assert.Equal("Cpu", engine.Translate("hi", default));
        Assert.Equal(1, fellBack);
        Assert.Equal([Ct2Device.Cuda, Ct2Device.Cpu], starter.Started);
    }

    [Fact]
    public void GpuHatasindaCpuyaDuserAyniCumle()
    {
        var (options, starter, _, _) = GpuSetup(useGpu: true);
        var fellBack = 0;
        starter.Fails = (device, _) => device == Ct2Device.Cuda;
        using var engine = new FreeEngineSource("tr", options with { GpuFellBack = () => fellBack++ }).Open(default);
        Assert.Equal("Cpu", engine.Translate("hi", default));
        Assert.Equal(1, fellBack);
        Assert.Equal("Cpu", engine.Translate("again", default));
        Assert.Equal(1, fellBack);
    }

    [Fact]
    public async Task CudaIndirmesiSurerkenCpuSonraCuda()
    {
        var (options, starter, cuda, _) = GpuSetup(useGpu: true);
        var gate = new TaskCompletionSource();
        var running = gate.Task;
        cuda.UseTask(running);
        using var engine = new FreeEngineSource("tr", options).Open(default);
        Assert.Equal("Cpu", engine.Translate("hi", default));
        gate.SetResult();
        await running;
        Assert.Equal("Cuda", engine.Translate("hi", default));
        Assert.Equal([Ct2Device.Cpu, Ct2Device.Cuda], starter.Started);
    }

    static string Here([CallerFilePath] string path = "") => path;

    [PythonFact]
    public void GercekIsciBetigiSahteKutuphaneyle()
    {
        var python = PythonFactAttribute.Python ?? throw new Xunit.Sdk.XunitException("macOS'ta python3 bekleniyordu");
        var runtime = Path.Combine(Path.GetTempPath(), "nino-ct2-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(runtime);
        var script = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(Here())!, "..", "..", "..", "src", "Nino.Translation", "ct2", "worker.py"));
        File.Copy(script, Path.Combine(runtime, "worker.py"));
        File.CreateSymbolicLink(Path.Combine(runtime, "python3"), python);
        File.WriteAllText(Path.Combine(runtime, "ctranslate2.py"), """
            class _Result:
                def __init__(self, tokens):
                    self.hypotheses = [tokens]

            class Translator:
                def __init__(self, model, device, compute_type, inter_threads, intra_threads):
                    if device == "cuda":
                        raise RuntimeError("cublas64_12.dll yok")
                    self.kind = compute_type

                def translate_batch(self, batch, beam_size=1, max_decoding_length=256):
                    tokens = batch[0]
                    if tokens and tokens[0] == "▁Bad":
                        raise ValueError("bozuk satır")
                    return [_Result([t.upper() for t in tokens if t != "</s>"] + [self.kind, "ş"])]
            """);
        var rt = new Ct2Runtime(runtime);
        using (var engine = Ct2WorkerEngine.Attach(rt.Start(runtime, Ct2Device.Cpu, 2, null), new SpaceTokenizer()))
        {
            Assert.Equal("WE GO.int8ş", engine.Translate("We go.", default));
            Assert.Throws<Ct2LineException>(() => engine.Translate("Bad one", default));
            Assert.Equal("STILL ALIVEint8ş", engine.Translate("still alive", default));
        }
        var e = Assert.Throws<IOException>(() =>
            Ct2WorkerEngine.Attach(rt.Start(runtime, Ct2Device.Cuda, 2, runtime), new SpaceTokenizer()));
        Assert.Contains("cublas", e.Message);
        Assert.Throws<FileNotFoundException>(() => new Ct2Runtime(Path.Combine(runtime, "yok")).Start(runtime, Ct2Device.Cpu, 1, null));
    }

    // Model sözlüğünden alınmış kimlikler: yalnız gerçek modelle doğrulanabilir, cümle içermeyen durumlar.
    static readonly (string Text, int[] Ids)[] TurkishReference =
    [
        // Kimlikler gerçek dosyalarla (sabit revizyon, SHA doğrulamalı) bu belirteçleyiciden alındı; aynı dosyalarla
        // Hugging Face çıktısından gelen başvuru tablosuyla da (13 satır) birebir tuttuğu denetlendi (22 Kasım 2026).
        ("Hold on!", [24658, 37652, 21, 43741]),
        ("I see…", [25182, 44984, 34, 43741]),
        ("Torvan.", [51048, 53319, 33, 43741]),
        ("First line\nSecond line", [19943, 32272, 44925, 32272, 43741]),
        ("Ásgeir", [90, 52508, 43740, 21001, 26995, 43741]),
        ("", [43741]),
        ("ðð x", [90, 52508, 54951, 43741]),
        ("😀😀 test", [90, 52508, 50281, 43741]),
        ("ç,¥:l", [90, 9560, 14, 52508, 18, 31140, 43741]),
    ];

    /// <summary>Gerçek model dosyaları yalnız <c>NINO_TEST_MODELS</c> (içinde <c>en-tr-ct2</c>) verildiyse sınanır.</summary>
    [TurkishModelFact]
    public void GercekTurkceBelirtecleyici()
    {
        var folder = TurkishModelFactAttribute.Folder!;
        var tok = MarianTokenizer.Load(Path.Combine(folder, "source.spm"), Path.Combine(folder, "vocab.json"));
        Assert.Equal(43741, tok.Eos);
        Assert.Equal(52508, tok.Unknown);
        Assert.Equal(57059, tok.Pad);
        Assert.Equal(57060, tok.VocabSize);
        foreach (var (text, ids) in TurkishReference) Assert.Equal(ids, tok.Encode(text));
        foreach (var text in new[] { "We have no time for that, kid.", "NORA: Captain, the hull is cracking!",
                     "It’s “late” – hurry…", "STOP! LISTEN!", "Meet me at 9 o'clock, Hello Harbor." })
        {
            var ids = tok.Encode(text);
            Assert.Equal(tok.Eos, ids[^1]);
            Assert.DoesNotContain(tok.Unknown, ids);
        }
        // Model sözlüğünde olmayan imler (uzun tire, emoji, Þ) bilinmeyen belirtece düşer.
        foreach (var text in new[] { "9,870.5 m — 20% left!", "🙂 smile check", "Þing hall of Brimvik" })
            Assert.Contains(tok.Unknown, tok.Encode(text));
        Assert.Equal("GO NOW", tok.Decode(tok.Encode("ＧＯ ＮＯＷ")));
        Assert.Equal("Too many gaps here", tok.Decode(tok.Encode("  Too   many\tgaps\there  ")));
        Assert.Equal("The bridge is out.", tok.Decode(tok.Encode("  The bridge   is out. ")));
        Assert.Equal("I see...", tok.Decode(tok.Encode("I see…")));
        Assert.Equal("Hold on!", tok.Decode([tok.Pad, 24658, 37652, 21, tok.Unknown, tok.Eos]));
        foreach (var clean in new[] { "Where is the key? *** Not here.", "Lena, bring the Corvan to Ostrel.",
                     "Ivar, Senna, Doran, Kell and Maro." })
        {
            Assert.DoesNotContain(tok.Unknown, tok.Encode(clean));
            Assert.Equal(clean, tok.Decode(tok.Encode(clean)));
        }
        Assert.Contains(tok.Unknown, tok.Encode("Here? | Not now."));
    }

    [ArabicModelFact]
    public void GercekArapcaOnnx()
    {
        var folder = ArabicModelFactAttribute.Folder!;
        var tok = MarianTokenizer.Load(Path.Combine(folder, "source.spm"), Path.Combine(folder, "vocab.json"), ">>ara<<");
        Assert.Equal(0, tok.Eos);
        Assert.Equal(1, tok.Unknown);
        Assert.Equal(62801, tok.Pad);
        var ids = tok.Encode("Where is the harbor?");
        Assert.Equal(4, ids[0]);
        Assert.Equal(0, ids[^1]);
        var watch = Stopwatch.StartNew();
        using var engine = OnnxMarianEngine.Open(folder, ">>ara<<");
        var text = engine.Translate("Where is the harbor?", default);
        Assert.True(TargetLanguages.IsWrittenInTargetScript(text, "ar"), text);
        Assert.True(watch.Elapsed < TimeSpan.FromMinutes(2));
    }

    sealed class FolderSource(string folder) : ISentenceEngineSource
    {
        public bool IsInstalled => true;

        public ISentenceEngine Open(CancellationToken cancellationToken) => OnnxMarianEngine.Open(folder, ">>ara<<");
    }

    /// <summary>
    /// Kapanma bildiriminde (4.5.2, en→ar) süreç bu satırlar ücretsiz motora gidince kapanmıştı: gerçek model ve tam
    /// ücretsiz çevirmen hattıyla (bölme, metin kuralları, önbellek) çevrilir, süreç ayakta kalır.
    /// </summary>
    [ArabicModelFact]
    public async Task GercekArapcaKapanmaSatirlari()
    {
        using var translator = new FreeTranslator(new FolderSource(ArabicModelFactAttribute.Folder!), "ar",
            new Nino.Core.Data.TranslationCache(null));
        foreach (var line in new[]
                 {
                     "Y up... already know frow it go with them.",
                     "Yup. Saw him walk out with it next day. Just a bag full of butt.",
                     "And allegedly... he caught her ass cheatin' with one of them Sanfo / niggas.",
                     "Said since he paid for her BBL, he could take it away...",
                     "PHOTO STUDIO (3",
                 })
        {
            var r = await translator.TranslateAsync(line);
            Assert.False(string.IsNullOrWhiteSpace(r.Text), line);
        }
    }
}
