// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using Nino.Core.Translation;

namespace Nino.Translation.Local;

/// <summary>
/// Işın araması (çeviri tarifi §8.8). Adım işlevi verilen girdi belirteçleriyle (ışın başına bir) çalışıp
/// [ışın × sözlük] logit dizisi döndürür; <c>reorder</c> öz dikkat önbelleklerini yeni ışınların kaynaklarına göre dizer.
/// </summary>
public static class BeamSearch
{
    /// <summary>Aramayı yapar; seçilen belirteç dizisini (bitiş olmadan) döndürür.</summary>
    public static IReadOnlyList<int> Run(int beams, int maxSteps, int vocab, int pad, int eos,
        Func<int[], int, float[]> step, Action<int[]> reorder)
    {
        var tokens = Enumerable.Range(0, beams).Select(_ => new List<int>()).ToList();
        var scores = Enumerable.Range(0, beams).Select(b => b == 0 ? 0.0 : double.NegativeInfinity).ToArray();
        var next = Enumerable.Repeat(pad, beams).ToArray();
        var finished = new List<(double Score, List<int> Tokens)>();

        for (var s = 0; s < maxSteps; s++)
        {
            var logits = step(next, s);
            var keep = 2 * beams;
            var candidates = new List<(double Score, int Beam, int Token, long Order)>();
            for (var b = 0; b < beams; b++)
            {
                if (double.IsNegativeInfinity(scores[b])) continue;
                var row = logits.AsSpan(b * vocab, vocab);
                var max = float.NegativeInfinity;
                for (var j = 0; j < vocab; j++)
                    if (j != pad && row[j] > max) max = row[j];
                double sum = 0;
                for (var j = 0; j < vocab; j++)
                    if (j != pad) sum += Math.Exp(row[j] - max);
                var lse = max + Math.Log(sum);
                // Işının en iyi 2B adayı yeter: genel en iyi 2B bunların içindedir.
                var best = new List<(double Score, int Token)>(keep + 1);
                for (var j = 0; j < vocab; j++)
                {
                    if (j == pad) continue;
                    var score = scores[b] + (row[j] - lse);
                    if (best.Count == keep && score <= best[^1].Score) continue;
                    var at = best.Count;
                    while (at > 0 && best[at - 1].Score < score) at--;
                    best.Insert(at, (score, j));
                    if (best.Count > keep) best.RemoveAt(keep);
                }
                foreach (var (score, token) in best) candidates.Add((score, b, token, (long)b * vocab + token));
            }
            var top = candidates.OrderByDescending(c => c.Score).ThenBy(c => c.Order).Take(keep).ToList();

            var newTokens = new List<List<int>>();
            var newScores = new List<double>();
            var newNext = new List<int>();
            var sources = new List<int>();
            for (var r = 0; r < top.Count && newTokens.Count < beams; r++)
            {
                var c = top[r];
                if (double.IsNegativeInfinity(c.Score)) break;
                if (c.Token == eos)
                {
                    if (r < beams)
                    {
                        finished.Add((c.Score / (tokens[c.Beam].Count + 1), [.. tokens[c.Beam]]));
                        finished = finished.OrderByDescending(f => f.Score).Take(beams).ToList();
                    }
                    continue;
                }
                newTokens.Add([.. tokens[c.Beam], c.Token]);
                newScores.Add(c.Score);
                newNext.Add(c.Token);
                sources.Add(c.Beam);
            }
            if (newTokens.Count == 0) break;
            while (newTokens.Count < beams)
            {
                newTokens.Add([.. newTokens[0]]);
                newScores.Add(double.NegativeInfinity);
                newNext.Add(newNext[0]);
                sources.Add(sources[0]);
            }
            tokens = newTokens;
            scores = newScores.ToArray();
            next = newNext.ToArray();
            reorder(sources.ToArray());

            if (finished.Count >= beams && scores.Max() / (s + 1) <= finished.Min(f => f.Score)) break;
        }
        return finished.Count > 0 ? finished[0].Tokens : tokens[0];
    }
}

/// <summary>
/// Türkçe dışındaki ücretsiz diller için ONNX Runtime Marian motoru (Xenova int8 kodlayıcı + birleşik kod çözücü).
/// </summary>
public sealed class OnnxMarianEngine : ISentenceEngine
{
    /// <summary>Işın sayısı.</summary>
    public const int Beams = 4;

    readonly InferenceSession _encoder;
    readonly InferenceSession _decoder;
    readonly MarianTokenizer _tokenizer;
    readonly string[] _pastNames;
    readonly int _heads;
    readonly int _headSize;

    OnnxMarianEngine(InferenceSession encoder, InferenceSession decoder, MarianTokenizer tokenizer)
    {
        _encoder = encoder;
        _decoder = decoder;
        _tokenizer = tokenizer;
        _pastNames = decoder.InputMetadata.Keys.Where(n => n.StartsWith("past_key_values.", StringComparison.Ordinal))
            .ToArray();
        var dims = _pastNames.Length > 0 ? decoder.InputMetadata[_pastNames[0]].Dimensions : [];
        _heads = dims.Length == 4 && dims[1] > 0 ? dims[1] : 16;
        _headSize = dims.Length == 4 && dims[3] > 0 ? dims[3] : 64;
    }

    /// <summary>Klasördeki modeli açar.</summary>
    public static OnnxMarianEngine Open(string folder, string? targetToken)
    {
        var tokenizer = MarianTokenizer.Load(Path.Combine(folder, "source.spm"), Path.Combine(folder, "vocab.json"),
            targetToken);
        using var options = new SessionOptions
        {
            GraphOptimizationLevel =
                GraphOptimizationLevel.ORT_ENABLE_ALL,
            ExecutionMode =
                ExecutionMode.ORT_SEQUENTIAL,
            IntraOpNumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 2),
            InterOpNumThreads = 1,
        };
        var encoder = new InferenceSession(Path.Combine(folder, "encoder_model_int8.onnx"), options);
        try
        {
            var decoder = new InferenceSession(Path.Combine(folder, "decoder_model_merged_int8.onnx"), options);
            return new OnnxMarianEngine(encoder, decoder, tokenizer);
        }
        catch
        {
            encoder.Dispose();
            throw;
        }
    }

    static bool IsSelfAttention(string name) =>
        name.EndsWith(".decoder.key", StringComparison.Ordinal) || name.EndsWith(".decoder.value", StringComparison.Ordinal);

    /// <inheritdoc />
    public string Translate(string sentence,
        CancellationToken cancellationToken)
    {
        var ids = _tokenizer.Encode(sentence);
        if (ids.Length > 256)
        {
            ids = ids[..256];
            ids[^1] = _tokenizer.Eos;
        }
        var n = ids.Length;

        float[] hidden;
        int width;
        using (var encoded = _encoder.Run(
               [
                   NamedOnnxValue.CreateFromTensor("input_ids", new DenseTensor<long>(ids.Select(i => (long)i).ToArray(), [1, n])),
                   NamedOnnxValue.CreateFromTensor("attention_mask", new DenseTensor<long>(Enumerable.Repeat(1L, n).ToArray(), [1, n])),
               ]))
        {
            var state = encoded.First(r => r.Name == "last_hidden_state").AsTensor<float>();
            width = state.Dimensions[2];
            hidden = state.ToArray();
        }

        var batchHidden = new float[Beams * n * width];
        for (var b = 0; b < Beams; b++) hidden.CopyTo(batchHidden, b * n * width);
        var hiddenTensor = new DenseTensor<float>(batchHidden, [Beams, n, width]);
        var mask = new DenseTensor<long>(Enumerable.Repeat(1L, Beams * n).ToArray(), [Beams, n]);
        var caches = _pastNames.ToDictionary(p => p, _ => (Data: Array.Empty<float>(), Length: 0));
        var vocab = _tokenizer.VocabSize;

        float[] Step(int[] next, int step)
        {
            cancellationToken
                .ThrowIfCancellationRequested();
            var inputs = new List<NamedOnnxValue>
            {
                NamedOnnxValue.CreateFromTensor("input_ids", new DenseTensor<long>(next.Select(i => (long)i).ToArray(), [Beams, 1])),
                NamedOnnxValue.CreateFromTensor("encoder_attention_mask", mask),
                NamedOnnxValue.CreateFromTensor("encoder_hidden_states", hiddenTensor),
                NamedOnnxValue.CreateFromTensor("use_cache_branch", new DenseTensor<bool>(new[] { step > 0 }, [1])),
            };
            foreach (var name in _pastNames)
            {
                var (data, length) = caches[name];
                inputs.Add(NamedOnnxValue.CreateFromTensor(name,
                    new DenseTensor<float>(data, [Beams, _heads, length, _headSize])));
            }
            using var results = _decoder.Run(inputs);
            float[] logits = [];
            foreach (var r in results)
            {
                if (r.Name == "logits")
                {
                    var t = r.AsTensor<float>();
                    var v = t.Dimensions[^1];
                    var all = t.ToArray();
                    var seq = t.Dimensions[1];
                    logits = new float[Beams * vocab];
                    for (var b = 0; b < Beams; b++)
                        Array.Copy(all, (b * seq + seq - 1) * v, logits, b * vocab, Math.Min(v, vocab));
                    continue;
                }
                if (!r.Name.StartsWith("present.", StringComparison.Ordinal)) continue;
                var past = "past_key_values." + r.Name["present.".Length..];
                if (!caches.ContainsKey(past)) continue;
                if (!IsSelfAttention(past) && step > 0) continue;
                var tensor = r.AsTensor<float>();
                caches[past] = (tensor.ToArray(), tensor.Dimensions[2]);
            }
            return logits;
        }

        void Reorder(int[] sources)
        {
            if (sources.Select((s, i) => s == i).All(x => x)) return;
            foreach (var name in _pastNames.Where(IsSelfAttention))
            {
                var (data, length) = caches[name];
                var row = data.Length / Beams;
                var copy = new float[data.Length];
                for (var b = 0; b < Beams; b++) Array.Copy(data, sources[b] * row, copy, b * row, row);
                caches[name] = (copy, length);
            }
        }

        var output = BeamSearch.Run(Beams, Math.Min(128, 2 * n + 16), vocab, _tokenizer.Pad, _tokenizer.Eos, Step, Reorder);
        return _tokenizer.Decode(output);
    }

    /// <inheritdoc />
    public void Dispose()
    {
        _decoder.Dispose();
        _encoder.Dispose();
    }
}
