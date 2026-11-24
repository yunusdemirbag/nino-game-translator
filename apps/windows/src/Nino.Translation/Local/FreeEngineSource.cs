// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Translation;

namespace Nino.Translation.Local;

/// <summary>Ücretsiz motorun aygıt ayarları (çeviri tarifi §8.5).</summary>
public sealed record FreeEngineOptions
{
    /// <summary>Model deposu.</summary>
    public required FreeModelStore Store { get; init; }

    /// <summary>CTranslate2 çalışma zamanı.</summary>
    public Ct2Runtime Runtime { get; init; } = Ct2Runtime.Default();

    /// <summary>CUDA deposu (GPU yoksa null).</summary>
    public CudaRuntimeStore? Cuda { get; init; }

    /// <summary>GPU (NVIDIA CUDA) seçili mi.</summary>
    public bool UseGpu { get; init; }

    /// <summary>CPU işçisinin iş parçacığı sayısı (1 ile mantıksal işlemci sayısı arasına sıkıştırılır).</summary>
    public int CpuThreads { get; init; } = 2;

    /// <summary>"GPU kullanılamadı, CPU'ya geçildi" olayı.</summary>
    public Action? GpuFellBack { get; init; }

    /// <summary>İşçi başlatıcı (testte sahte); varsayılan <see cref="Runtime"/>.</summary>
    public Func<string, Ct2Device, int, string?, IWorkerProcess>? StartWorker { get; init; }

    /// <summary>
    /// ONNX motorunu ayrı süreçte açan işlev (model klasörü, hedef belirteci); null ise motor bu süreçte açılır. Windows'ta
    /// Nino'nun kendi exe'si işçi kipinde başlar (<see cref="OnnxWorkerRuntime"/>).
    /// </summary>
    public Func<string, string?, IWorkerProcess>? OnnxWorker { get; init; }

    /// <summary>İşçi olayları günlüğü (ör. işçi kapandı, yeniden açıldı).</summary>
    public Action<string>? Log { get; init; }

    /// <summary>Belirteçleyiciyi model klasöründen açan işlev (testte sahte); varsayılan <see cref="MarianTokenizer"/>.</summary>
    public Func<string, IPieceTokenizer>? LoadTokenizer { get; init; }
}

/// <summary>
/// Bir hedefin ücretsiz motoru: klasörde <c>model.bin</c> varsa CTranslate2 işçisi, yoksa ONNX (çeviri tarifi §7).
/// </summary>
public sealed class FreeEngineSource(string target, FreeEngineOptions options) : ISentenceEngineSource
{
    /// <summary>İşçi iş parçacığı sayısı (CUDA'da 2).</summary>
    public const int CudaThreads = 2;

    /// <inheritdoc />
    public bool IsInstalled => options.Store.IsInstalled(target);

    /// <inheritdoc />
    public ISentenceEngine Open(CancellationToken cancellationToken)
    {
        ISentenceEngine OpenOnnx(string onnxFolder, string? token) =>
            options.OnnxWorker is { } worker
                ? OnnxWorkerEngine.Open(() => worker(onnxFolder, token), options.Log)
                : OnnxMarianEngine.Open(onnxFolder, token);

        var model = ModelCatalog.For("en", target) ?? throw new FileNotFoundException("bu dil için ücretsiz model yok");
        var folder = Path.Combine(options.Store.Root, model.Folder);
        if (options.Store.LegacyTurkishInUse(target) is { } legacy) return OpenOnnx(legacy, model.TargetToken);
        if (!File.Exists(Path.Combine(folder, "model.bin"))) return OpenOnnx(folder, model.TargetToken);

        var tokenizer = options.LoadTokenizer?.Invoke(folder)
                        ?? MarianTokenizer.Load(Path.Combine(folder, "source.spm"), Path.Combine(folder, "vocab.json"));
        var cpuThreads = Math.Clamp(options.CpuThreads, 1, Math.Max(1, Environment.ProcessorCount));
        var start = options.StartWorker ?? options.Runtime.Start;
        ISentenceEngine Cpu() => Ct2WorkerEngine.Attach(start(folder, Ct2Device.Cpu, cpuThreads, null), tokenizer);
        ISentenceEngine Cuda() =>
            Ct2WorkerEngine.Attach(start(folder, Ct2Device.Cuda, CudaThreads, options.Cuda!.Folder), tokenizer);

        if (!options.UseGpu || options.Cuda is null) return Cpu();
        var task = options.Cuda.Current;
        if (task is null || task.IsCompletedSuccessfully)
        {
            try { return new GpuEngine(Cuda(), true, null, Cpu, Cuda, options.GpuFellBack); }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                options.GpuFellBack?.Invoke();
                return Cpu();
            }
        }
        if (task.IsCompleted)
        {
            options.GpuFellBack?.Invoke();
            return Cpu();
        }
        return new GpuEngine(Cpu(), false, task, Cpu, Cuda, options.GpuFellBack);
    }

    /// <summary>
    /// CUDA'da çalışan ya da CUDA indirmesi bitince CUDA'ya geçecek motor. CUDA'da hata olursa CPU'ya düşer ve aynı
    /// cümleyi yeniden çevirir.
    /// </summary>
    sealed class GpuEngine(ISentenceEngine current, bool onCuda, Task? pending, Func<ISentenceEngine> openCpu,
        Func<ISentenceEngine> openCuda, Action? fellBack) : ISentenceEngine
    {
        ISentenceEngine _current = current;
        bool _onCuda = onCuda;
        Task? _pending = pending;

        public string Translate(string sentence,
            CancellationToken cancellationToken)
        {
            if (_pending is { IsCompleted: true } done)
            {
                _pending = null;
                if (done.IsCompletedSuccessfully)
                {
                    try
                    {
                        var cuda = openCuda();
                        _current.Dispose();
                        _current = cuda;
                        _onCuda = true;
                    }
                    catch (Exception e) when (e is not OperationCanceledException)
                    {
                        fellBack?.Invoke();
                    }
                }
                else fellBack?.Invoke();
            }
            if (!_onCuda) return _current.Translate(sentence, cancellationToken);
            try
            {
                return _current.Translate(sentence, cancellationToken);
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                _current.Dispose();
                _onCuda = false;
                fellBack?.Invoke();
                _current = openCpu();
                return _current.Translate(sentence, cancellationToken);
            }
        }

        public void Dispose() => _current.Dispose();
    }
}
