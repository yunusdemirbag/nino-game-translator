// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Threading.Channels;
using Nino.Core.Data;

namespace Nino.Core.Logging;

/// <summary>Günlük dosya adları ve sınırları.</summary>
public static class LogNames
{
    public const string Error = "hata.log";
    public const string RemotePlay = "remoteplay.log";
    public const string Subtitle = "altyazi.log";
    public const string SubtitleRotated = "altyazi.log.1";
    public const string TvInstall = "tvinstall.log";

    /// <summary>Döndürme/yarılama sınırı: 1 MiB.</summary>
    public const long MaxBytes = 1_048_576;

    /// <summary>Arka plan kuyruklarının en çok satırı (dolarsa satır atılır).</summary>
    public const int QueueLimit = 2000;

    internal static string Stamp(DateTimeOffset t) =>
        t.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);

    internal static string StampMs(DateTimeOffset t) =>
        t.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture);
}

/// <summary>
/// <c>hata.log</c>: <c>[yyyy-AA-gg SS:dd:ss] ileti</c> + satır sonu + hatanın tam metni (yoksa boş) + boş satır.
/// Sınırsız; yazımlar kilitle sıralanır; yazılamazsa sessizce geçilir.
/// </summary>
public sealed class ErrorLog(string path, TimeProvider? clock = null)
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;
    readonly object _gate = new();

    /// <summary>Dosyanın yolu.</summary>
    public string FilePath => path;

    /// <summary>Bir hata kaydı ekler.</summary>
    public void Write(string message, Exception? error = null)
    {
        var nl = Environment.NewLine;
        var text = $"[{LogNames.Stamp(_clock.GetLocalNow())}] {message}{nl}{error?.ToString() ?? ""}{nl}{nl}";
        lock (_gate)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
                File.AppendAllText(path, text, FileIo.Utf8);
            }
            catch { }
        }
    }
}

/// <summary>
/// Satırları arka planda sırayla yazan günlük. Kuyruk en çok <see cref="LogNames.QueueLimit"/> satır; dolarsa yeni
/// satır atılır. Yazma hatası sessizce yutulur.
/// </summary>
public abstract class QueuedLogFile : IDisposable
{
    readonly Channel<string> _queue = Channel.CreateBounded<string>(new BoundedChannelOptions(LogNames.QueueLimit)
    {
        FullMode = BoundedChannelFullMode.DropWrite,
        SingleReader = true,
    });
    readonly Task _worker;
    int _pending;

    protected QueuedLogFile(string path, TimeProvider? clock)
    {
        FilePath = path;
        Clock = clock ?? TimeProvider.System;
        _worker = Task.Run(RunAsync);
    }

    /// <summary>Dosyanın yolu.</summary>
    public string FilePath { get; }

    protected TimeProvider Clock { get; }

    /// <summary>Hazır satırı kuyruğa koyar.</summary>
    protected void Enqueue(string line)
    {
        Interlocked.Increment(ref _pending);
        if (!_queue.Writer.TryWrite(line)) Interlocked.Decrement(ref _pending);
    }

    /// <summary>Bekleyen satırları yazar; en çok <paramref name="timeout"/> (varsayılan 2 sn) bekler.</summary>
    public bool Flush(TimeSpan? timeout = null)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromSeconds(2));
        while (Volatile.Read(ref _pending) > 0)
        {
            if (DateTime.UtcNow >= deadline) return false;
            Thread.Sleep(5);
        }
        return true;
    }

    /// <summary>Tek satırı diske ekler (alt sınıf döndürme/yarılama kuralını uygular).</summary>
    protected abstract void Append(string line);

    async Task RunAsync()
    {
        await foreach (var line in _queue.Reader.ReadAllAsync().ConfigureAwait(false))
        {
            try { Append(line); }
            catch { }
            finally { Interlocked.Decrement(ref _pending); }
        }
    }

    /// <inheritdoc />
    public void Dispose()
    {
        _queue.Writer.TryComplete();
        try { _worker.Wait(TimeSpan.FromSeconds(2)); }
        catch { }
        GC.SuppressFinalize(this);
    }

    internal static void EnsureFolder(string path) =>
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);

    /// <summary>Dosya sınırı aştıysa ilk yarısını siler (karakter ortasından ya da satır başından).</summary>
    internal static void HalveIfLarge(string path, bool atLineStart)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length <= LogNames.MaxBytes) return;
        var text = File.ReadAllText(path, FileIo.Utf8);
        var cut = text.Length / 2;
        if (atLineStart)
        {
            var nl = text.IndexOf('\n', cut);
            cut = nl < 0 ? text.Length : nl + 1;
        }
        else if (cut > 0 && cut < text.Length && char.IsLowSurrogate(text[cut])) cut++;
        File.WriteAllText(path, text[cut..], FileIo.Utf8);
    }
}

/// <summary>
/// <c>altyazi.log</c>: <c>[yyyy-AA-gg SS:dd:ss.fff] satır</c>. Eklenecek satırla 1 MiB'ı geçecekse dosya
/// <c>altyazi.log.1</c> olur ve yeni dosya başlar. Başta kapalıdır; açılışta <see cref="Enabled"/> yapılır.
/// </summary>
public sealed class SubtitleLog(string path, TimeProvider? clock = null) : QueuedLogFile(path, clock)
{
    /// <summary>Kapalıyken satırlar atılır (testlerde kapalı).</summary>
    public bool Enabled { get; set; }

    /// <summary>Bir satır ekler.</summary>
    public void Write(string line)
    {
        if (Enabled) Enqueue($"[{LogNames.StampMs(Clock.GetLocalNow())}] {line}");
    }

    /// <inheritdoc />
    protected override void Append(string line)
    {
        EnsureFolder(FilePath);
        var text = line + Environment.NewLine;
        var info = new FileInfo(FilePath);
        if (info.Exists && info.Length + FileIo.Utf8.GetByteCount(text) > LogNames.MaxBytes)
            File.Move(FilePath, FilePath + ".1", overwrite: true);
        File.AppendAllText(FilePath, text, FileIo.Utf8);
    }
}

/// <summary>
/// <c>tvinstall.log</c>: <c>[zaman] ileti</c> (sondaki boşluklar kırpılır). 1 MiB'ı geçince eski yarı silinir, kalan
/// satır başından başlar. Samsung jetonu ve parolalar buraya yazılmamalı (çağıranın sorumluluğu).
/// </summary>
public sealed class TvInstallLog(string path, TimeProvider? clock = null)
{
    readonly TimeProvider _clock = clock ?? TimeProvider.System;
    readonly object _gate = new();

    /// <summary>Dosyanın yolu.</summary>
    public string FilePath => path;

    /// <summary>Bir ileti ekler; yazılamazsa sessizce geçer.</summary>
    public void Write(string message)
    {
        var line = $"[{LogNames.Stamp(_clock.GetLocalNow())}] {message.TrimEnd()}{Environment.NewLine}";
        lock (_gate)
        {
            try
            {
                QueuedLogFile.EnsureFolder(path);
                QueuedLogFile.HalveIfLarge(path, atLineStart: true);
                File.AppendAllText(path, line, FileIo.Utf8);
            }
            catch { }
        }
    }
}
