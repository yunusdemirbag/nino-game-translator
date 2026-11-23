// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Collections.Concurrent;
using System.Runtime.InteropServices;

namespace Nino.Linux.Ocr;

/// <summary>
/// Tesseract motorlarından oluşan küçük bir havuz. Bir motor aynı anda tek görüntü okur; okuma hattı iki okumayı
/// aynı anda yapabildiğinden işlemci sayısına göre 2–4 motor tutulur. Boşta kalan motor sonraki okumada
/// yeniden kullanılır.
/// </summary>
internal sealed class TesseractEngine : IWordRecognizer
{
    /// <summary>1080p'deki altyazı boyu için uygun çözünürlük; verilmezse Tesseract her karede uyarır.</summary>
    private const int AssumedPpi = 150;

    private readonly ConcurrentStack<nint> spare = new();
    private readonly SemaphoreSlim slots;
    private volatile bool closed;

    private TesseractEngine(string dataName, nint first, int size)
    {
        DataName = dataName;
        slots = new SemaphoreSlim(size, size);
        spare.Push(first);
    }

    public string DataName { get; }

    public static int PoolSize => Math.Clamp(Environment.ProcessorCount, 2, 4);

    /// <summary>Kütüphane ya da dil verisi yoksa null.</summary>
    public static TesseractEngine? Open(string dataName) =>
        Start(dataName) is { } handle ? new TesseractEngine(dataName, handle, PoolSize) : null;

    public static bool CanOpen(string dataName)
    {
        if (Start(dataName) is not { } handle) return false;
        TesseractApi.TessBaseAPIDelete(handle);
        return true;
    }

    private static nint? Start(string dataName)
    {
        try
        {
            var handle = TesseractApi.TessBaseAPICreate();
            if (handle == 0) return null;
            if (TesseractApi.TessBaseAPIInit3(handle, null, dataName) != 0)
            {
                TesseractApi.TessBaseAPIDelete(handle);
                return null;
            }
            // Bölge tek bir yazı bloğudur; sayfa düzeni çözümlemesi oyun görüntüsünde yanılır.
            TesseractApi.TessBaseAPISetPageSegMode(handle, TesseractApi.SingleBlock);
            TesseractApi.TessBaseAPISetVariable(handle, "debug_file", "/dev/null");
            return handle;
        }
        catch (DllNotFoundException) { return null; }      // kütüphane kurulu değil
        catch (EntryPointNotFoundException) { return null; } // beklenmeyen sürüm
        catch (BadImageFormatException) { return null; }     // başka mimari
    }

    /// <summary>Gri görüntüyü okur; sözcükler Tesseract'ın satırlarına göre gruplanmış döner.</summary>
    public unsafe List<List<OcrWord>> Recognize(byte[] gray, int width, int height)
    {
        var lines = new List<List<OcrWord>>();
        if (closed) return lines;
        slots.Wait();
        nint handle = 0;
        try
        {
            if (!spare.TryPop(out handle)) handle = Start(DataName) ?? 0;
            if (handle == 0) return lines;
            fixed (byte* pixels = gray) TesseractApi.TessBaseAPISetImage(handle, pixels, width, height, 1, width);
            TesseractApi.TessBaseAPISetSourceResolution(handle, AssumedPpi);
            if (TesseractApi.TessBaseAPIRecognize(handle, 0) != 0) return lines;
            Collect(handle, lines);
            return lines;
        }
        finally
        {
            if (handle != 0)
            {
                TesseractApi.TessBaseAPIClear(handle);
                if (closed) TesseractApi.TessBaseAPIDelete(handle); else spare.Push(handle);
            }
            slots.Release();
        }
    }

    private static void Collect(nint handle, List<List<OcrWord>> lines)
    {
        var results = TesseractApi.TessBaseAPIGetIterator(handle);
        if (results == 0) return;
        try
        {
            var page = TesseractApi.TessResultIteratorGetPageIterator(results);
            List<OcrWord>? current = null;
            do
            {
                if (current is null || TesseractApi.TessPageIteratorIsAtBeginningOf(page, TesseractApi.TextLineLevel) != 0)
                {
                    current = [];
                    lines.Add(current);
                }
                var raw = TesseractApi.TessResultIteratorGetUTF8Text(results, TesseractApi.WordLevel);
                if (raw == 0) continue;
                string text;
                try { text = (Marshal.PtrToStringUTF8(raw) ?? "").Trim(); }
                finally { TesseractApi.TessDeleteText(raw); }
                if (text is "") continue;
                if (TesseractApi.TessPageIteratorBoundingBox(page, TesseractApi.WordLevel, out var l, out var t, out var r, out var b) == 0) continue;
                var confidence = TesseractApi.TessResultIteratorConfidence(results, TesseractApi.WordLevel);
                current.Add(new OcrWord(WordFilter.RepairCapitalI(text), confidence, l, t, r, b));
            }
            while (TesseractApi.TessResultIteratorNext(results, TesseractApi.WordLevel) != 0);
        }
        finally
        {
            TesseractApi.TessResultIteratorDelete(results);
        }
        lines.RemoveAll(static words => words.Count is 0);
    }

    public void Dispose()
    {
        closed = true;
        while (spare.TryPop(out var handle)) TesseractApi.TessBaseAPIDelete(handle);
    }
}
