// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;

namespace Nino.Core.Library;

/// <summary>
/// Paketteki bulanık dizin (havuz/paket tarifi §3.3) ve en yakın anahtar araması (§3.5). Kayıtlar önce uzunluğa,
/// sonra anahtara göre sıralı; Bloom sözcükleri tek dizide ardışık.
/// </summary>
public sealed class FuzzyIndex
{
    readonly int[] _lengths;
    readonly ulong[] _keys;
    readonly int[] _offsets;
    readonly int[] _popCounts;
    readonly ulong[] _words;
    readonly int[] _firstOfLength = new int[258];

    FuzzyIndex(List<(int Length, ulong Key, ulong[] Words)> records)
    {
        records.Sort((a, b) => a.Length != b.Length ? a.Length.CompareTo(b.Length) : a.Key.CompareTo(b.Key));
        _lengths = new int[records.Count];
        _keys = new ulong[records.Count];
        _offsets = new int[records.Count];
        _popCounts = new int[records.Count];
        _words = new ulong[records.Sum(r => r.Words.Length)];
        var at = 0;
        for (var i = 0; i < records.Count; i++)
        {
            _lengths[i] = records[i].Length;
            _keys[i] = records[i].Key;
            _offsets[i] = at;
            records[i].Words.CopyTo(_words, at);
            at += records[i].Words.Length;
            _popCounts[i] = FuzzySignature.PopCount(records[i].Words);
        }
        var r = 0;
        for (var n = 0; n <= 257; n++)
        {
            while (r < _lengths.Length && _lengths[r] < n) r++;
            _firstOfLength[n] = r;
        }
    }

    /// <summary>İmzalı kayıt sayısı.</summary>
    public int Count => _keys.Length;

    /// <summary>Kayıtlardan dizin kurar (testler ve paket betiğiyle aynı imza).</summary>
    public static FuzzyIndex FromRecords(IEnumerable<(int Length, ulong Key, ulong[] Words)> records) => new(records.ToList());

    /// <summary>
    /// Paketin <c>fuzzy</c> nesnesini okur. <paramref name="sortedKeys"/> paketin bütün geçerli anahtarları (küçükten
    /// büyüğe). Tutarsızsa null.
    /// </summary>
    public static FuzzyIndex? Parse(JsonElement fuzzy, IReadOnlyList<ulong> sortedKeys)
    {
        try
        {
            if (fuzzy.ValueKind != JsonValueKind.Object) return null;
            if (!fuzzy.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.Number
                || version.GetDouble() != 1) return null;
            if (!fuzzy.TryGetProperty("count", out var count) || count.ValueKind != JsonValueKind.Number
                || count.GetDouble() != sortedKeys.Count) return null;
            var mask = Base64(fuzzy, "mask");
            var lengths = Base64(fuzzy, "lengths");
            var blooms = Base64(fuzzy, "blooms");
            if (mask is null || lengths is null || blooms is null) return null;
            if (mask.Length != (sortedKeys.Count + 7) / 8) return null;

            var records = new List<(int, ulong, ulong[])>();
            var signed = 0;
            var offset = 0;
            for (var i = 0; i < sortedKeys.Count; i++)
            {
                if ((mask[i >> 3] & (1 << (i & 7))) == 0) continue;
                if (signed >= lengths.Length) return null;
                int length = lengths[signed++];
                var size = FuzzySignature.BitsFor(length) / 8;
                if (offset + size > blooms.Length) return null;
                var words = new ulong[size / 8];
                for (var w = 0; w < words.Length; w++)
                    words[w] = System.Buffers.Binary.BinaryPrimitives.ReadUInt64LittleEndian(
                        blooms.AsSpan(offset + w * 8, 8));
                offset += size;
                records.Add((length, sortedKeys[i], words));
            }
            if (signed != lengths.Length || offset != blooms.Length) return null;
            return new FuzzyIndex(records);
        }
        catch (Exception e) when (e is FormatException or InvalidOperationException or JsonException)
        {
            return null;
        }
    }

    static byte[]? Base64(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String) return null;
        try { return Convert.FromBase64String(value.GetString()!); }
        catch (FormatException) { return null; }
    }

    ReadOnlySpan<ulong> WordsOf(int i) => _words.AsSpan(_offsets[i], FuzzySignature.BitsFor(_lengths[i]) / 64);

    /// <summary>
    /// En yakın anahtar. <paramref name="turkishOf"/> adayın Türkçesini verir (belirsizlik kararı için).
    /// Bulunamazsa ya da belirsizse null.
    /// </summary>
    public ulong? Nearest(string query, Func<ulong, string?> turkishOf)
    {
        if (_keys.Length == 0) return null;
        var folded = FuzzySignature.Fold(query);
        if (folded.Length < FuzzySignature.MinLength) return null;
        var length = FuzzySignature.LengthOf(folded);
        var threshold = FuzzySignature.Threshold(length, FuzzySignature.LooksDamaged(query));
        var floor = threshold - FuzzySignature.Margin;
        var trigrams = FuzzySignature.Trigrams(folded);
        var blooms = new Dictionary<int, (ulong[] Words, int Bits)>();
        foreach (var bits in new[] { 64, 128, 256 })
        {
            var w = FuzzySignature.Bloom(trigrams, bits);
            blooms[bits] = (w, FuzzySignature.PopCount(w));
        }

        var scored = new List<(int Index, double Score)>();
        var near = (Low: length - length / 4, High: Math.Min(255, length + length / 4));
        for (var i = _firstOfLength[Math.Max(0, near.Low)]; i < _firstOfLength[near.High + 1]; i++)
        {
            var bits = FuzzySignature.BitsFor(_lengths[i]);
            var (qWords, qCount) = blooms[bits];
            var cand = WordsOf(i);
            var (q, c) = FuzzySignature.Coverage(FuzzySignature.CommonBits(qWords, cand), qCount, _popCounts[i], bits);
            var sim = Math.Min(q, c);
            if (sim >= floor) scored.Add((i, sim));
        }

        var (pick, ambiguous) = Select(scored, threshold, turkishOf);
        if (pick is not null) return pick;
        if (ambiguous || length < 22) return null;

        List<List<ulong[]>>? clauses = null;
        var clausesReady = false;
        var oneWay = new List<(int, double)>();
        var low = Math.Max(22, length * 11 / 20);
        var high = Math.Min(255, length * 5 / 2);
        if (low <= high)
            for (var i = _firstOfLength[low]; i < _firstOfLength[high + 1]; i++)
            {
                var candLength = _lengths[i];
                if (candLength < 22 || candLength == length) continue;
                var bits = FuzzySignature.BitsFor(candLength);
                var (qWords, qCount) = blooms[bits];
                var cand = WordsOf(i);
                var common = FuzzySignature.CommonBits(qWords, cand);
                var longer = candLength > length;
                var shortCount = longer ? qCount : _popCounts[i];
                if (common * 10 < 9 * shortCount) continue;
                var (q, c) = FuzzySignature.Coverage(common, qCount, _popCounts[i], bits);
                var inner = longer ? q : c;
                var outer = longer ? c : q;
                var lowerBound = longer ? 25 : 55;
                if (inner < 90 || outer < lowerBound || inner - 10 < floor) continue;
                if (!longer)
                {
                    if (!clausesReady)
                    {
                        clauses = FuzzyClauses.CheckList(query);
                        clausesReady = true;
                    }
                    if (clauses is not null && !FuzzyClauses.Passes(clauses, cand)) continue;
                }
                oneWay.Add((i, inner - 10));
            }
        if (oneWay.Count == 0) return null;
        scored.AddRange(oneWay);
        (pick, _) = Select(scored, threshold, turkishOf);
        return pick;
    }

    (ulong? Pick, bool Ambiguous) Select(List<(int Index, double Score)> scored, double threshold,
        Func<ulong, string?> turkishOf)
    {
        if (scored.Count == 0) return (null, false);
        var best = scored[0];
        foreach (var s in scored)
            if (s.Score > best.Score || (s.Score == best.Score && _keys[s.Index] > _keys[best.Index]))
                best = s;
        if (best.Score < threshold) return (null, false);
        var bestKey = _keys[best.Index];
        var bestTurkish = turkishOf(bestKey);
        foreach (var s in scored)
        {
            var key = _keys[s.Index];
            if (key == bestKey || s.Score <= best.Score - FuzzySignature.Margin) continue;
            if (!string.Equals(turkishOf(key), bestTurkish, StringComparison.Ordinal)) return (null, true);
        }
        return (bestKey, false);
    }
}
