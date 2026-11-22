// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;

namespace Nino.Translation.Local;

/// <summary>İndirilecek bir dosya: ad (klasördeki), adres, boy ve SHA-256.</summary>
public sealed record ModelFile(string Name, string Url, long Size, string Sha256);

/// <summary>Bir hedef dilin ücretsiz modeli.</summary>
/// <param name="Target">Hedef dil kodu.</param>
/// <param name="Folder">Model klasörünün adı (<c>models\…</c> altında).</param>
/// <param name="UsesCt2">Türkçe CTranslate2 modeli mi (değilse ONNX).</param>
/// <param name="TargetToken">Çok hedefli modellerde girdinin başına konan belirteç (yoksa null).</param>
/// <param name="Files">ONNX dosyaları ya da Türkçe için yalnız belirteç dosyaları.</param>
public sealed record FreeModel(string Target, string Folder, bool UsesCt2, string? TargetToken,
    IReadOnlyList<ModelFile> Files);

/// <summary>
/// Ücretsiz modellerin dosya listeleri (çeviri tarifi §8.1–§8.5). Boylar ve özetler indirmede birebir denetlenir.
/// </summary>
public static class ModelCatalog
{
    /// <summary>ONNX motorunun dört dosyası.</summary>
    public static readonly IReadOnlyList<string> OnnxFileNames =
        ["encoder_model_int8.onnx", "decoder_model_merged_int8.onnx", "source.spm", "vocab.json"];

    const string Hub = "https://huggingface.co/";

    // Biçim: çift, sürüm; sonra her dosya için çift, ad, boy, özet.
    const string OnnxTable = """
        en-ar 034a684356c19021a187cda4d7f823298b913921
        en-hi 7aad72006a1588a9c3485ed6203aed99eebbc872
        en-id b3b41f654c2fb3286d007dee1da7b0f47fd27d82
        en-vi 30bcd461c0d7338ad106b36314d3eedc2d4e998c
        en-nl c3a0541231a7329b4492809fc2bd7ab7d2ceb0bc
        en-ar encoder_model_int8.onnx 51600664 045dce89bd4b5bd5d8f546b9e3f9b506a9dbae70c551e8744eac67564050ddfd
        en-ar decoder_model_merged_int8.onnx 58878333 f2cd3894f105e5859d60cd66ad5f83356a3343e68f60c1997627a6e2d156f549
        en-ar source.spm 801074 81ac8f4d4ee271f4109eac67560a31f9c2d555463ba5eb95c32c6deee8ae819d
        en-ar vocab.json 2243581 8b74af9e4c1ec122b8d06362db6c38795e10ca2b0156b2110cf08d4716744b76
        en-hi encoder_model_int8.onnx 51164441 8b53ce50ba917cf4b77d6713a01cb767d16a6a92fe4a56bec4d3576fb9d1e4e2
        en-hi decoder_model_merged_int8.onnx 58438702 7c21712321e7a02aa1f0f676b4beeef8cdccd0c295cdc642eea97991ce59b180
        en-hi source.spm 812240 fd4e951487aed00bae6a6c2ee4ef5d8d1db05fd098b19b608046c9334b58d24d
        en-hi vocab.json 2221738 be02f5dfb85054d4f25089f6b347b69d32e98ed4c3d181ed0c789904eb1e3d3b
        en-id encoder_model_int8.onnx 47501593 577591fb62f86b82b9cddd799bae274b8e9b489a7439bb13ea2d5c4510f34f08
        en-id decoder_model_merged_int8.onnx 54747238 c36b784308b4983be64f076e237332709af48f7e575a9a535fd138d9fbdd468c
        en-id source.spm 795925 e88300911c2c573ec5526777a1e84bae698d20925b82dcef9c7248bb0e537ed0
        en-id vocab.json 1366984 cda834905a5d478c54a73abc98cc9155dc58217baa130cdf165411265b760d6b
        en-vi encoder_model_int8.onnx 46932760 0aa4c958dc2171312b15d70e2fb1a036feca9ff5e098609ee0ea31ebd21b3c98
        en-vi decoder_model_merged_int8.onnx 54173961 c1ec8c85d68119cb419518d30a504ebf625f8e36d62f588c4e0a1466cd6d6e28
        en-vi source.spm 808612 fdd9ab486ca8ea060967105e30db7d8928729c78a67448711d2dd7c3153b37cd
        en-vi vocab.json 1299764 bcc8bbafeb0b6b58fecf244f8da996da9aa45dbea7871164f9c8ce480507f9fe
        en-nl encoder_model_int8.onnx 53764376 3857b90ec2dd0d5f2f4bb637dbe6f6f9e80d9cbed55391d1aa943cffa0cc628f
        en-nl decoder_model_merged_int8.onnx 61058949 3c6bf76b6711dfc3e73d7bf85b3964bd40f425b35d6b721118233b71b9a1ccd4
        en-nl source.spm 789525 d05781fde84b8793191528a7a176e1b17f96265388f602379ee6ae3139f59141
        en-nl vocab.json 1794274 b1fba91c620564d90848c5f77b03f13d17949790f8e7c7741e4a8ea13b8b0d91
        """;

    const string TurkishTokenizerTable = """
        source.spm 796953 180d3f94ddfee5585d78b702290ded0f4f9bd40f299349c8383b32a579fefad4
        vocab.json 1501287 01ef522455d2bf22b0716416ee34688cc2b3f5fa257f742665d21b6acc450ac1
        """;

    /// <summary>Türkçe belirteç dosyalarının revizyonu.</summary>
    public const string TurkishTokenizerRevision = "ce128ea834a090aca240e4e113e7756e06cc78e0";

    /// <summary>Türkçe CTranslate2 model klasörü.</summary>
    public const string TurkishFolder = "en-tr-ct2";

    /// <summary>Eski sürümlerin ONNX Türkçe model klasörü (Türkçe model kurulunca silinir).</summary>
    public const string LegacyTurkishFolder = "en-tr";

    /// <summary>Türkçe CTranslate2 arşivi.</summary>
    public static ModelFile TurkishArchive { get; } = new("opus-mt-en-tr.zip",
        Hub + "Unbakedcookie/live-translator-models/resolve/50473df5681764ebdef107dd78f7d21da66c28a7/opus-mt-en-tr.zip",
        474_595_937, "acabcdc3becfbf4d740c3012d6dc4e8a1ba6ed41a62a125c37f6c228667ff9b9");

    /// <summary>Arşivden çıkarılan dosya adları (klasör yolu yok sayılır).</summary>
    public static readonly IReadOnlySet<string> TurkishArchiveEntries = new HashSet<string>(StringComparer.Ordinal)
    {
        "model.bin", "config.json", "shared_vocabulary.json", "source_vocabulary.json", "target_vocabulary.json",
        "source.spm", "target.spm", "opus_mt.json", "LICENCE.txt",
    };

    static readonly Lazy<Dictionary<string, FreeModel>> Models = new(Build);

    static Dictionary<string, FreeModel> Build()
    {
        var revisions = new Dictionary<string, string>(StringComparer.Ordinal);
        var files = new Dictionary<string, List<ModelFile>>(StringComparer.Ordinal);
        foreach (var raw in OnnxTable.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var cells = raw.Split(' ');
            if (cells.Length == 2)
            {
                revisions[cells[0]] = cells[1];
                continue;
            }
            var pair = cells[0];
            var name = cells[1];
            var path = name.EndsWith(".onnx", StringComparison.Ordinal) ? "onnx/" + name : name;
            var url = $"{Hub}Xenova/opus-mt-{pair}/resolve/{revisions[pair]}/{path}";
            if (!files.TryGetValue(pair, out var list)) files[pair] = list = [];
            list.Add(new ModelFile(name, url, long.Parse(cells[2], CultureInfo.InvariantCulture), cells[3]));
        }

        var result = new Dictionary<string, FreeModel>(StringComparer.Ordinal);
        foreach (var (pair, list) in files)
        {
            var target = pair[3..];
            var token = target switch { "ar" => ">>ara<<", "vi" => ">>vie<<", _ => null };
            result[target] = new FreeModel(target, pair, false, token, list);
        }
        result["tr"] = new FreeModel("tr", TurkishFolder, true, null, TurkishTokenizerFiles);
        return result;
    }

    /// <summary>Türkçe belirteç dosyaları (kurulumda yalnız <c>vocab.json</c> indirilir).</summary>
    public static IReadOnlyList<ModelFile> TurkishTokenizerFiles { get; } = TurkishTokenizerTable
        .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(line => line.Split(' '))
        .Select(c => new ModelFile(c[0],
            $"{Hub}onnx-community/opus-mt-tc-big-en-tr/resolve/{TurkishTokenizerRevision}/{c[0]}",
            long.Parse(c[1], CultureInfo.InvariantCulture), c[2]))
        .ToList();

    /// <summary>Hedefin modeli; ücretsiz model yoksa (ya da kaynak <c>en</c> değilse) null.</summary>
    public static FreeModel? For(string? source, string? target)
    {
        if (Nino.Core.Translation.TargetLanguages.Code(source) != "en") return null;
        return Models.Value.TryGetValue(Nino.Core.Translation.TargetLanguages.Code(target), out var m) ? m : null;
    }

    /// <summary>Bütün modeller.</summary>
    public static IReadOnlyCollection<FreeModel> All => Models.Value.Values;
}

/// <summary>CUDA çalışma zamanı dosyaları (çeviri tarifi §8.5).</summary>
public static class CudaCatalog
{
    /// <summary>Klasör adı (<c>%LOCALAPPDATA%\Nino\…</c>).</summary>
    public const string Folder = "cuda-12.8";

    const string Redist = "https://developer.download.nvidia.com/compute/cuda/redist/";

    const string ArchiveTable = """
        libcublas-windows-x86_64-12.8.4.1-archive.zip libcublas/windows-x86_64/ 563660944 57a470112cec7e112c95253dde8b3c7184d795dbd92b0bde77a4cb7f8c94c8aa
        cuda_cudart-windows-x86_64-12.8.90-archive.zip cuda_cudart/windows-x86_64/ 3037735 4a39058fd8519444a81cfc7ae055d136f48d1a31ffa41ae255b35b2edd61e13b
        """;

    /// <summary>İki arşiv (cuBLAS, cudart).</summary>
    public static IReadOnlyList<ModelFile> Archives { get; } = ArchiveTable
        .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(line => line.Split(' '))
        .Select(c => new ModelFile(c[0], Redist + c[1] + c[0], long.Parse(c[2], CultureInfo.InvariantCulture), c[3]))
        .ToList();

    /// <summary>Gerekli DLL'ler ve boyları.</summary>
    public static IReadOnlyDictionary<string, long> Dlls { get; } = new Dictionary<string, long>(StringComparer.Ordinal)
    {
        ["cublas64_12.dll"] = 113_716_224,
        ["cublasLt64_12.dll"] = 674_667_520,
        ["cudart64_12.dll"] = 573_952,
    };

    /// <summary>cuBLAS arşivindeki lisansın yazıldığı ad.</summary>
    public const string LicenseFile = "CUDA-LICENSE.txt";
}
