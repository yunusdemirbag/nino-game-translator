// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Nino.Core.Translation;

namespace Nino.Translation.Local;

/// <summary>
/// ONNX motorunun ayrı süreçteki işçisi. ONNX Runtime uygulamanın kendi sürecinde çalışırken yerel bir hata (ör. bellek
/// erişim hatası) bütün uygulamayı kapatıyordu; işçide yalnız işçi kapanır, uygulama ayakta kalır ve işçiyi yeniden açar.
/// Satır protokolü: ilk satır <c>{"ready":true}</c> (ya da <c>{"ready":false,"error":…}</c>), sonra istek başına
/// <c>{"text":…}</c> → <c>{"text":…}</c> ya da <c>{"error":…}</c>.
/// </summary>
public static class OnnxWorkerHost
{
    static readonly JsonSerializerOptions Json = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    /// <summary>İşçiyi çalıştırır: girdi kapanınca 0, motor açılamazsa 2 ile biter.</summary>
    public static int Serve(TextReader input, TextWriter output, Func<ISentenceEngine> open)
    {
        ISentenceEngine engine;
        try
        {
            engine = open();
        }
        catch (Exception e)
        {
            Write(output, new Dictionary<string, object> { ["ready"] = false, ["error"] = e.GetType().Name + ": " + e.Message });
            return 2;
        }
        using (engine)
        {
            Write(output, new Dictionary<string, object> { ["ready"] = true });
            while (input.ReadLine() is { } line)
            {
                string? text = null;
                try
                {
                    using var doc = JsonDocument.Parse(line);
                    if (doc.RootElement.TryGetProperty("text", out var t) && t.ValueKind == JsonValueKind.String)
                        text = t.GetString();
                }
                catch (JsonException) { }
                if (text is null)
                {
                    Write(output, new Dictionary<string, object> { ["error"] = "istek anlaşılmadı" });
                    continue;
                }
                try
                {
                    Write(output, new Dictionary<string, object> { ["text"] = engine.Translate(text, CancellationToken.None) });
                }
                catch (Exception e)
                {
                    Write(output, new Dictionary<string, object> { ["error"] = e.GetType().Name + ": " + e.Message });
                }
            }
        }
        return 0;
    }

    static void Write(TextWriter output, Dictionary<string, object> body)
    {
        output.WriteLine(JsonSerializer.Serialize(body, Json));
        output.Flush();
    }

    /// <summary>İstek satırı.</summary>
    internal static string Request(string text) =>
        JsonSerializer.Serialize(new Dictionary<string, string> { ["text"] = text }, Json);
}

/// <summary>Çıkış kodunu bildiren işçi süreci.</summary>
public interface IWorkerExit
{
    /// <summary>Süreç bittiyse çıkış kodu; bitmediyse null.</summary>
    int? ExitCode { get; }
}

/// <summary>
/// ONNX işçisini başlatır: Nino'nun kendi exe'si <c>--free-worker &lt;model klasörü&gt; [hedef belirteci]</c> ile.
/// </summary>
public static class OnnxWorkerRuntime
{
    /// <summary>İşçi kipinin argümanı.</summary>
    public const string Argument = "--free-worker";

    /// <summary>İşçiyi başlatır.</summary>
    public static IWorkerProcess Start(string exe, string modelFolder, string? targetToken)
    {
        var info = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = false,
            StandardInputEncoding =
                new UTF8Encoding(false),
            StandardOutputEncoding = Encoding.UTF8,
        };
        info.ArgumentList.Add(Argument);
        info.ArgumentList.Add(modelFolder);
        if (!string.IsNullOrEmpty(targetToken)) info.ArgumentList.Add(targetToken);
        var process = Process.Start(info) ?? throw new IOException("ücretsiz motor işçisi başlatılamadı");
        try { process.PriorityClass = ProcessPriorityClass.BelowNormal; }
        catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
        return new Worker(process);
    }

    sealed class Worker(Process process) : IWorkerProcess, IWorkerExit
    {
        public TextWriter Input => process.StandardInput;

        public TextReader Output => process.StandardOutput;

        public int? ExitCode
        {
            get
            {
                try { return process.HasExited ? process.ExitCode : null; }
                catch (InvalidOperationException) { return null; }
            }
        }

        public void Kill(TimeSpan wait)
        {
            try
            {
                if (process.HasExited is false) process.Kill(true);
                process.WaitForExit(wait);
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
        }

        public void Dispose()
        {
            try { process.StandardInput.Close(); }
            catch (Exception e) when (e is IOException or InvalidOperationException) { }
            try
            {
                if (!process.WaitForExit(1500)) Kill(TimeSpan.FromSeconds(2));
            }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
            process.Dispose();
        }
    }
}

/// <summary>
/// Ayrı süreçteki ONNX işçisinin istemcisi. İşçi bir satırda kapanırsa o satır düşer (<see cref="Ct2LineException"/>),
/// işçi bir sonraki satırda yeniden açılır; o satır bir daha işçiye gönderilmez. Oturumda <see cref="MaxDeaths"/>
/// kapanmadan sonra motor kalıcı olarak düşer (<see cref="IOException"/>). Yanıt <see cref="ReplyTimeout"/> içinde
/// gelmezse işçi öldürülür ve kapanmış sayılır.
/// </summary>
public sealed class OnnxWorkerEngine : ISentenceEngine
{
    /// <summary>Kalıcı düşmeden önce en çok işçi kapanması.</summary>
    public const int MaxDeaths = 3;

    /// <summary>Bir satırın en uzun bekleme süresi.</summary>
    public static readonly TimeSpan ReplyTimeout = TimeSpan.FromSeconds(30);

    readonly Func<IWorkerProcess> _start;
    readonly Action<string>? _log;
    readonly TimeSpan _replyTimeout;
    readonly HashSet<string> _poison = new(StringComparer.Ordinal);
    readonly object _gate = new();
    IWorkerProcess? _process;
    int _deaths;
    volatile bool _disposed;

    OnnxWorkerEngine(Func<IWorkerProcess> start, Action<string>? log, TimeSpan replyTimeout)
    {
        _start = start;
        _log = log;
        _replyTimeout = replyTimeout;
    }

    /// <summary>İşçiyi açar ve hazır olmasını bekler; olmazsa <see cref="IOException"/>.</summary>
    public static OnnxWorkerEngine Open(Func<IWorkerProcess> start, Action<string>? log = null, TimeSpan? replyTimeout = null)
    {
        var engine = new OnnxWorkerEngine(start, log, replyTimeout ?? ReplyTimeout);
        engine._process = engine.Launch();
        return engine;
    }

    /// <summary>Bu oturumda işçinin kapanma sayısı.</summary>
    public int Deaths
    {
        get { lock (_gate) return _deaths; }
    }

    IWorkerProcess Launch()
    {
        var process = _start();
        try
        {
            var first = ReadLine(process, _replyTimeout) ?? throw new IOException("ücretsiz motor işçisi açılışta kapandı" + ExitText(process));
            using var doc = JsonDocument.Parse(first);
            var root = doc.RootElement;
            if (!(root.TryGetProperty("ready", out var ready) && ready.ValueKind == JsonValueKind.True))
                throw new IOException(root.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String
                    ? e.GetString()
                    : "ücretsiz motor işçisi hazır değil");
            return process;
        }
        catch (Exception e)
        {
            process.Dispose();
            throw e is JsonException ? new IOException("işçinin ilk satırı anlaşılmadı", e) : e;
        }
    }

    /// <inheritdoc />
    public string Translate(string sentence,
        CancellationToken cancellationToken)
    {
        cancellationToken
            .ThrowIfCancellationRequested();
        lock (_gate)
        {
            if (_disposed) throw new IOException("ücretsiz motor kapandı");
            if (_poison.Contains(sentence)) throw new Ct2LineException("bu satır ücretsiz motoru kapatmıştı");
            if (_process is null)
            {
                if (_deaths >= MaxDeaths) throw new IOException("ücretsiz motor işçisi tekrar tekrar kapandı");
                _process = Launch();
                _log?.Invoke("ücretsiz motor işçisi yeniden açıldı");
            }
            var process = _process;
            string? line;
            try
            {
                process.Input.WriteLine(OnnxWorkerHost.Request(sentence));
                process.Input.Flush();
                line = ReadLine(process, _replyTimeout);
            }
            catch (IOException)
            {
                line = null;
            }
            if (line is null)
            {
                _deaths++;
                _poison.Add(sentence);
                var exit = ExitText(process);
                _process = null;
                process.Dispose();
                _log?.Invoke($"ücretsiz motor işçisi satırı çevirirken kapandı{exit} ({_deaths}/{MaxDeaths}); uygulama ayakta");
                if (_deaths >= MaxDeaths) throw new IOException("ücretsiz motor işçisi tekrar tekrar kapandı" + exit);
                throw new Ct2LineException("ücretsiz motor işçisi bu satırda kapandı");
            }
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;
            if (root.TryGetProperty("text", out var text) && text.ValueKind == JsonValueKind.String) return text.GetString()!;
            throw new Ct2LineException(root.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.String
                ? error.GetString()!
                : "işçinin yanıtı anlaşılmadı");
        }
    }

    /// <summary>Çıkış kodu metni (ör. <c> (çıkış kodu 0xC0000005)</c>); bilinmiyorsa boş.</summary>
    internal static string ExitText(IWorkerProcess process)
    {
        if (process is not IWorkerExit exit) return "";
        int? code = exit.ExitCode;
        if (code is null)
        {
            process.Kill(TimeSpan.FromMilliseconds(500));
            code = exit.ExitCode;
        }
        return code is { } c ? " (çıkış kodu 0x" + ((uint)c).ToString("X8", CultureInfo.InvariantCulture) + ")" : "";
    }

    static string? ReadLine(IWorkerProcess process, TimeSpan timeout)
    {
        var read = Task.Run(process.Output.ReadLine);
        try
        {
            if (read.Wait(timeout)) return read.Result;
        }
        catch (AggregateException)
        {
            return null;
        }
        process.Kill(TimeSpan.FromSeconds(2));
        return null;
    }

    /// <inheritdoc />
    public void Dispose()
    {
        // Süren bir satır kilidi tutuyor olabilir (yanıt beklerken): önce kilitsiz öldürülür ki kapanış beklemesin.
        _disposed = true;
        Volatile.Read(ref _process)?.Kill(TimeSpan.FromMilliseconds(500));
        IWorkerProcess? process;
        lock (_gate)
        {
            process = _process;
            _process = null;
        }
        process?.Dispose();
    }
}
