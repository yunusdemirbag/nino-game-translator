// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Nino.Core.Translation;

namespace Nino.Translation.Local;

/// <summary>İşçi sürecinin akışları (testte sahte).</summary>
public interface IWorkerProcess : IDisposable
{
    /// <summary>İşçinin girdisi (UTF-8).</summary>
    TextWriter Input { get; }

    /// <summary>İşçinin çıktısı (UTF-8).</summary>
    TextReader Output { get; }

    /// <summary>Süreci ağacıyla öldürür ve en çok verilen süre bekler.</summary>
    void Kill(TimeSpan wait);
}

/// <summary>Aygıt.</summary>
public enum Ct2Device { Cpu, Cuda }

/// <summary>
/// CTranslate2 çalışma zamanı (uygulama klasöründe <c>ct2\</c>, ya da <c>NINO_CT2_RUNTIME</c>): gömülü Python ve
/// <c>worker.py</c>. Süreci başlatır (çeviri tarifi §8.6).
/// </summary>
public sealed class Ct2Runtime(string folder)
{
    /// <summary>Ortam değişkeni.</summary>
    public const string RuntimeVariable = "NINO_CT2_RUNTIME";

    /// <summary>Çalışma zamanı klasörü.</summary>
    public string Folder => folder;

    /// <summary>Varsayılan klasör: ortam değişkeni ya da uygulama klasöründe <c>ct2</c>.</summary>
    public static Ct2Runtime Default() =>
        new(Environment.GetEnvironmentVariable(RuntimeVariable) is { Length: > 0 } custom
            ? custom
            : Path.Combine(AppContext.BaseDirectory, "ct2"));

    /// <summary>Python yorumlayıcısı (Windows'ta <c>python.exe</c>).</summary>
    public string Python => Path.Combine(folder, OperatingSystem.IsWindows() ? "python.exe" : "python3");

    /// <summary>İşçi betiği.</summary>
    public string Script => Path.Combine(folder, "worker.py");

    /// <summary>Süreci başlatır; çalışma zamanı eksikse <see cref="FileNotFoundException"/>.</summary>
    public IWorkerProcess Start(string modelFolder, Ct2Device device, int threads, string? cudaFolder)
    {
        if (!File.Exists(Python)) throw new FileNotFoundException("CTranslate2 çalışma zamanı eksik", Python);
        if (!File.Exists(Script)) throw new FileNotFoundException("CTranslate2 çalışma zamanı eksik", Script);
        var info = new ProcessStartInfo(Python)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardInputEncoding =
                new UTF8Encoding(false),
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = folder,
        };
        foreach (var arg in new[] { "-u", Script, modelFolder, device == Ct2Device.Cuda ? "cuda" : "cpu",
                     threads.ToString(System.Globalization.CultureInfo.InvariantCulture) })
            info.ArgumentList.Add(arg);
        info.Environment["PYTHONIOENCODING"]
            = "utf-8";
        if (device == Ct2Device.Cuda && cudaFolder is not null)
        {
            info.Environment["NINO_CUDA_DIR"] = cudaFolder;
            info.Environment["PATH"] = cudaFolder + Path.PathSeparator + (info.Environment["PATH"] ?? "");
        }
        var process = Process.Start(info) ?? throw new IOException("işçi başlatılamadı");
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null) Debug.WriteLine("[ct2] " + e.Data);
        };
        process.BeginErrorReadLine();
        return new RealWorkerProcess(process);
    }

    sealed class RealWorkerProcess(Process process) : IWorkerProcess
    {
        public TextWriter Input => process.StandardInput;

        public TextReader Output => process.StandardOutput;

        public void Kill(TimeSpan wait)
        {
            try
            {
                if (!process.HasExited)
                    process.Kill(entireProcessTree: true);
                process.WaitForExit(wait);
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
        }

        public void Dispose()
        {
            Kill(TimeSpan.FromSeconds(2));
            process.Dispose();
        }
    }
}

/// <summary>Bir satırın işçide çevrilemediği hata (işçi ayakta; yalnız o satır düşer).</summary>
public sealed class Ct2LineException(string message) : Exception(message);

/// <summary>
/// CTranslate2 işçisinin satır protokolü istemcisi: ilk satır hazır bilgisi, sonra istek başına bir satır. Yanıt
/// gelmezse <see cref="IOException"/> (kalıcı motor hatası).
/// </summary>
public sealed class Ct2WorkerEngine : ISentenceEngine
{
    /// <summary>Işın sayısı.</summary>
    public const int Beams = 4;

    static readonly JsonSerializerOptions Json = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    readonly IWorkerProcess _process;
    readonly IPieceTokenizer _tokenizer;

    Ct2WorkerEngine(IWorkerProcess process, IPieceTokenizer tokenizer)
    {
        _process = process;
        _tokenizer = tokenizer;
    }

    /// <summary>İşçinin hazır olmasını bekler; değilse süreci öldürüp hata fırlatır.</summary>
    public static Ct2WorkerEngine Attach(IWorkerProcess process, IPieceTokenizer tokenizer)
    {
        try
        {
            var first = process.Output.ReadLine() ?? throw new IOException("işçi açılışta kapandı");
            using var doc = JsonDocument.Parse(first);
            var root = doc.RootElement;
            if (!(root.TryGetProperty("ready", out var ready) && ready.ValueKind == JsonValueKind.True))
            {
                var error = root.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String
                    ? e.GetString()
                    : "işçi hazır değil";
                throw new IOException(error);
            }
            return new Ct2WorkerEngine(process, tokenizer);
        }
        catch (Exception e)
        {
            process.Dispose();
            throw e is JsonException ? new IOException("işçinin ilk satırı anlaşılmadı", e) : e;
        }
    }

    /// <summary>Çıktı sınırı: min(128, 2 × belirteç + 16).</summary>
    public static int MaxOutput(int tokens) => Math.Min(128, 2 * tokens + 16);

    /// <summary>İstek satırı.</summary>
    internal static string Request(IReadOnlyList<string> tokens)
    {
        var list = tokens.Count > 256 ? [.. tokens.Take(255), "</s>"] : tokens.ToList();
        return JsonSerializer.Serialize(new Ct2Request(list, Beams, MaxOutput(list.Count)), Json);
    }

    sealed record Ct2Request(
        [property: System.Text.Json.Serialization.JsonPropertyName("tokens")] List<string> Tokens,
        [property: System.Text.Json.Serialization.JsonPropertyName("beams")] int BeamCount,
        [property: System.Text.Json.Serialization.JsonPropertyName("max_output")] int Limit);

    /// <inheritdoc />
    public string Translate(string sentence,
        CancellationToken cancellationToken)
    {
        cancellationToken
            .ThrowIfCancellationRequested();
        var pieces = _tokenizer.EncodeToPieces(sentence);
        _process.Input.WriteLine(Request(pieces));
        _process.Input.Flush();
        var line = _process.Output.ReadLine() ?? throw new IOException("işçi çeviri sırasında kapandı");
        using var doc = JsonDocument.Parse(line);
        var root = doc.RootElement;
        if (root.TryGetProperty("error", out var error))
            throw new Ct2LineException(error.ValueKind == JsonValueKind.String ? error.GetString()! : "çevrilemedi");
        if (!root.TryGetProperty("tokens", out var tokens) || tokens.ValueKind != JsonValueKind.Array)
            throw new Ct2LineException("işçinin yanıtı anlaşılmadı");
        return _tokenizer.DecodePieces(tokens.EnumerateArray().Select(t => t.GetString() ?? ""));
    }

    /// <inheritdoc />
    public void Dispose() => _process.Dispose();
}
