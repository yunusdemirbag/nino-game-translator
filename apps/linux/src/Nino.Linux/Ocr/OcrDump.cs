// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.Linux.Ocr;

/// <summary>
/// Tanı: <c>NINO_OCR_DUMP</c> bir klasör gösteriyorsa Tesseract'a giden her gri görüntü oraya PGM olarak, bulunan
/// sözcükler de güvenleriyle yanına metin olarak yazılır. Bir oyunda okuma bozuksa sebep buradan görülür.
/// </summary>
internal sealed class OcrDump
{
    private readonly string folder;
    private int counter;

    public OcrDump(string folder) => this.folder = folder;

    public static OcrDump? FromEnvironment() =>
        Environment.GetEnvironmentVariable("NINO_OCR_DUMP") is { Length: > 0 } folder ? new OcrDump(folder) : null;

    public void Save(byte[] gray, int width, int height, List<List<OcrWord>> lines, WordFilter filter)
    {
        try
        {
            Directory.CreateDirectory(folder);
            var stem = Path.Combine(folder, $"ocr-{Interlocked.Increment(ref counter):D4}");
            using (var image = File.Create(stem + ".pgm"))
            {
                image.Write(Encoding.ASCII.GetBytes(string.Join('\n', "P5", $"{width} {height}", "255", "")));
                image.Write(gray);
            }
            var report = lines.Select(line =>
                (filter.Keep(line).Count > 0 ? "+ " : "- ") + string.Join(' ', line.Select(word => $"{word.Text}[{word.Confidence:0}]")));
            File.WriteAllLines(stem + ".txt", report);
        }
        catch (IOException) { /* döküm isteğe bağlı; okuma sürsün */ }
        catch (UnauthorizedAccessException) { /* klasöre yazılamıyor */ }
    }
}
