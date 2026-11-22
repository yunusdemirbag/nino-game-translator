// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay;

/// <summary>
/// Remote Play günlüğü (uygulamada <c>%LOCALAPPDATA%\Nino\remoteplay.log</c>). chiaki satırları
/// "[chiaki &lt;error|warning|info&gt;] …", uygulama satırları "[nino] …". Satırlar dinleyicilere (sağlık kaydı,
/// duraklama izleyicisi) önce verilir; dosyaya arka planda, zaman önekiyle yazılır.
/// </summary>
public sealed class RemotePlayLog : IDisposable
{
    public const string FileName = "remoteplay.log";
    public const int QueueLimit = 2000;
    public const long SizeLimit = 1024 * 1024;

    readonly string? path;
    readonly string? folder;
    readonly TimeProvider time;
    readonly BlockingCollection<string> queue = new(new ConcurrentQueue<string>(), QueueLimit);
    readonly Thread? writer;

    /// <summary>Her satır (önekli, zamansız) yazılınca; dinleyici hatası çağıranı düşürmez.</summary>
    public event Action<string>? LineAdded;

    /// <param name="path">Günlük dosyası; null ise yalnız dinleyicilere verilir.</param>
    public RemotePlayLog(string? path, TimeProvider? time = null)
    {
        this.path = path;
        folder = path is null ? null : Path.GetDirectoryName(Path.GetFullPath(path));
        this.time = time ?? TimeProvider.System;
        if (path is not null)
        {
            writer = new Thread(WriteLoop) { IsBackground = true, Name = "Nino remote play log" };
            writer.Start();
        }
    }

    /// <summary>Günlük dosyasının yolu (yalnız dinleyicilere verilen örnekte null).</summary>
    public string? FilePath => path;

    /// <summary>Günlüğe yazmayan örnek (testler).</summary>
    public static RemotePlayLog Silent() => new(null);

    public void Chiaki(BridgeLogLevel level, string line)
    {
        string tag = level switch
        {
            BridgeLogLevel.Error => "error",
            BridgeLogLevel.Warning => "warning",
            _ => "info",
        };
        Add($"[chiaki {tag}] {line}");
    }

    public void Nino(string line) => Add($"[nino] {line}");

    void Add(string line)
    {
        try
        {
            LineAdded?.Invoke(line);
        }
        catch
        {
        }
        if (writer is null)
            return;
        string stamp = time.GetLocalNow().ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        // Sınırlı kuyruk: doluysa satır atılır.
        try
        {
            queue.TryAdd($"[{stamp}] {line}");
        }
        catch (InvalidOperationException)
        {
            // Kapatıldı (ObjectDisposedException da buraya düşer).
        }
    }

    void WriteLoop()
    {
        try
        {
            foreach (string line in queue.GetConsumingEnumerable())
            {
                var batch = new StringBuilder(line).Append('\n');
                while (queue.TryTake(out string? more))
                    batch.Append(more).Append('\n');
                Append(batch.ToString());
            }
        }
        catch (ObjectDisposedException)
        {
        }
    }

    void Append(string text)
    {
        try
        {
            if (folder is not null)
                Directory.CreateDirectory(folder);
            File.AppendAllText(path!, text, new UTF8Encoding(false));
            var info = new FileInfo(path!);
            if (info.Length > SizeLimit)
                TrimFirstHalf(path!);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    /// <summary>Dosyanın ilk yarısını siler (satır başından keser).</summary>
    internal static void TrimFirstHalf(string file)
    {
        byte[] bytes = File.ReadAllBytes(file);
        int cut = bytes.Length / 2;
        int nl = Array.IndexOf(bytes, (byte)'\n', cut);
        cut = nl < 0 ? cut : nl + 1;
        File.WriteAllBytes(file, bytes[cut..]);
    }

    /// <summary>Kuyruktakileri yazıp bitirir (en çok verilen süre kadar bekler).</summary>
    public void Flush(TimeSpan timeout)
    {
        var until = DateTime.UtcNow + timeout;
        while (queue.Count > 0 && DateTime.UtcNow < until)
            Thread.Sleep(10);
        Thread.Sleep(20);
    }

    public void Dispose()
    {
        queue.CompleteAdding();
        writer?.Join(TimeSpan.FromSeconds(2));
        queue.Dispose();
    }
}

/// <summary>
/// Remote Play satırlarından görüntü duraklaması notları (altyazı günlüğündeki duraklama izleyicisi için):
/// FEC hatası → durdu; IDR geldi → sürdü (boşlukla); bekçi satırı → yeniden kuruluyor.
/// </summary>
public sealed class PictureStallNotes
{
    /// <summary>Bekçi satırının birebir korunan parçası.</summary>
    public const string StalledLineMarker = "sn boyunca kare alınamadı";

    long? pausedAt;

    /// <summary>Satır bir duraklama notu doğuruyorsa notu döner.</summary>
    public string? Interpret(string line, long nowMs)
    {
        lock (this)
        {
            bool fecFailure = line.Contains("FEC failed", StringComparison.Ordinal)
                              || line.Contains("Video FEC failure", StringComparison.Ordinal);
            bool idrArrived = line.Contains("Received IDR frame", StringComparison.Ordinal);
            bool watchdog = line.Contains(StalledLineMarker, StringComparison.Ordinal);
            if (fecFailure)
            {
                if (pausedAt is not null)
                    return null;
                pausedAt = nowMs;
                return "görüntü durdu (FEC hatası), IDR karesi bekleniyor";
            }
            if (idrArrived)
            {
                if (pausedAt is not { } since)
                    return null;
                pausedAt = null;
                return $"görüntü yeniden geldi (IDR karesi), {nowMs - since} ms ara";
            }
            if (watchdog)
            {
                long? since = pausedAt;
                pausedAt = null;
                return "IDR karesi beklenmeyecek; görüntü gelmediği için PS5 oturumu baştan açılıyor"
                       + (since is { } s ? $" ({nowMs - s} ms ara)" : "");
            }
            return null;
        }
    }
}
