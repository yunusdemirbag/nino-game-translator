// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Json;
using Microsoft.ML.Tokenizers;

namespace Nino.Translation.Local;

/// <summary>CTranslate2 işçisinin kullandığı belirteç dizgisi dönüşümü.</summary>
public interface IPieceTokenizer
{
    /// <summary>Metin → belirteç dizgileri (bitiş dahil).</summary>
    string[] EncodeToPieces(string text);

    /// <summary>Belirteç dizgileri → metin.</summary>
    string DecodePieces(IEnumerable<string> pieces);
}

/// <summary>
/// Marian (OPUS-MT) belirteçleyicisi (çeviri tarifi §8.7): SentencePiece metni parçalar, kimlikler modelin
/// <c>vocab.json</c>'undan gelir (Hugging Face Marian belirteçleyicisiyle aynı).
/// </summary>
public sealed class MarianTokenizer : IPieceTokenizer
{
    /// <summary>Kelime başı işareti.</summary>
    public const char WordStart = '▁';

    readonly SentencePieceTokenizer _spm;
    readonly Dictionary<string, int> _vocab;
    readonly string?[] _pieces;
    readonly int? _targetId;

    MarianTokenizer(SentencePieceTokenizer spm, Dictionary<string, int> vocab, string? targetToken)
    {
        _spm = spm;
        _vocab = vocab;
        Eos = vocab.TryGetValue("</s>", out var eos) ? eos : 43741;
        Unknown = vocab.TryGetValue("<unk>", out var unk) ? unk : 52508;
        Pad = vocab.TryGetValue("<pad>", out var pad) ? pad : 57059;
        VocabSize = vocab.Values.Max() + 1;
        _pieces = new string?[VocabSize];
        foreach (var (piece, id) in vocab)
            if (id >= 0) _pieces[id] = piece;
        if (targetToken is not null)
        {
            if (!vocab.TryGetValue(targetToken, out var t))
                throw new InvalidDataException($"hedef belirteci sözlükte yok: {targetToken}");
            _targetId = t;
        }
    }

    /// <summary>Bitiş kimliği.</summary>
    public int Eos { get; }

    /// <summary>Bilinmeyen kimliği.</summary>
    public int Unknown { get; }

    /// <summary>Dolgu kimliği (kod çözücünün başlangıç belirteci).</summary>
    public int Pad { get; }

    /// <summary>Sözlük boyu (en büyük kimlik + 1).</summary>
    public int VocabSize { get; }

    /// <summary><c>source.spm</c> ve <c>vocab.json</c>'dan açar.</summary>
    public static MarianTokenizer Load(string spmPath, string vocabPath, string? targetToken = null)
    {
        SentencePieceTokenizer spm;
        using (var stream = File.OpenRead(spmPath))
            spm = SentencePieceTokenizer.Create(stream, addBeginningOfSentence: false, addEndOfSentence: false);
        var vocab = JsonSerializer.Deserialize<Dictionary<string, int>>(File.ReadAllBytes(vocabPath));
        if (vocab is null || vocab.Count == 0) throw new InvalidDataException("vocab.json boş");
        return new MarianTokenizer(spm, vocab, targetToken);
    }

    /// <summary>SentencePiece parçaları; art arda bilinmeyenler tek parçada birleşir.</summary>
    List<(string Piece, bool Unknown)> Pieces(string text)
    {
        var tokens = _spm.EncodeToTokens(text, out var normalized, addBeginningOfSentence: false,
            addEndOfSentence: false, considerPreTokenization: true, considerNormalization: true);
        var result = new List<(string, bool)>(tokens.Count);
        foreach (var token in tokens)
        {
            var unknown = token.Id == _spm.UnknownId;
            var piece = token.Value;
            if (unknown)
            {
                // Bilinmeyen parçanın yüzey metni (özgün SentencePiece bunu kullanır).
                var surface = normalized ?? text;
                var start = token.Offset.Start.GetOffset(surface.Length);
                var end = token.Offset.End.GetOffset(surface.Length);
                if (start >= 0 && end > start && end <= surface.Length) piece = surface[start..end];
            }
            if (unknown && result.Count > 0 && result[^1].Item2) result[^1] = (result[^1].Item1 + piece, true);
            else result.Add((piece, unknown));
        }
        return result;
    }

    /// <summary>Metni kimliklere çevirir: hedef belirteci (varsa), parçalar, bitiş.</summary>
    public int[] Encode(string text)
    {
        var ids = new List<int>();
        if (_targetId is { } t) ids.Add(t);
        foreach (var (piece, _) in Pieces(text)) ids.Add(_vocab.TryGetValue(piece, out var id) ? id : Unknown);
        ids.Add(Eos);
        return ids.ToArray();
    }

    /// <summary>Kimliğin parçası (yoksa null).</summary>
    public string? PieceOf(int id) => id >= 0 && id < _pieces.Length ? _pieces[id] : null;

    /// <summary>CTranslate2 için belirteç dizgileri.</summary>
    public string[] EncodeToPieces(string text) =>
        Encode(text).Select(id => PieceOf(id) ?? PieceOf(Unknown) ?? "<unk>").ToArray();

    /// <summary>Kimlikleri metne çevirir (bitiş, bilinmeyen, dolgu ve aralık dışı atlanır).</summary>
    public string
        Decode(IEnumerable<int> ids)
    {
        var sb = new StringBuilder();
        foreach (var id in ids)
        {
            if (id == Eos || id == Unknown || id == Pad || id < 0 || id >= VocabSize) continue;
            sb.Append(_pieces[id]);
        }
        return sb.Replace(WordStart, ' ').ToString().Trim();
    }

    /// <summary>Belirteç dizgilerini metne çevirir.</summary>
    public string DecodePieces(IEnumerable<string> pieces) =>
        Decode(pieces.Select(p => _vocab.TryGetValue(p, out var id) ? id : Unknown));
}
