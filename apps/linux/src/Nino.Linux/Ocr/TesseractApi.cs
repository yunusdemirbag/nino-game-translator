// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Reflection;
using System.Runtime.InteropServices;

namespace Nino.Linux.Ocr;

/// <summary>
/// Sistemdeki libtesseract'ın C arayüzü (tesseract/capi.h; 4.x ve 5.x aynı). Dağıtımlar kütüphaneyi sürüm
/// ekiyle kurduğundan birkaç ad sırayla denenir.
/// </summary>
internal static unsafe partial class TesseractApi
{
    private const string Name = "nino-tesseract";

    internal const int SingleBlock = 6;
    internal const int TextLineLevel = 2;
    internal const int WordLevel = 3;

    public const string PathVariable = "NINO_TESSERACT_LIBRARY";

    internal static readonly string[] Candidates =
        ["libtesseract.so.5", "libtesseract.so.4", "libtesseract.so", "libtesseract.dylib", "tesseract"];

    static TesseractApi() => NativeLibrary.SetDllImportResolver(typeof(TesseractApi).Assembly, Find);

    private static nint Find(string library, Assembly assembly, DllImportSearchPath? search)
    {
        if (library != Name) return 0;
        // Tam yol verilebilir (ör. Mac'te Homebrew'un /opt/homebrew/lib/libtesseract.dylib'i).
        if (Environment.GetEnvironmentVariable(PathVariable) is { Length: > 0 } path && NativeLibrary.TryLoad(path, out var chosen))
            return chosen;
        foreach (var candidate in Candidates)
            if (NativeLibrary.TryLoad(candidate, assembly, search, out var handle)) return handle;
        return 0;
    }

    [LibraryImport(Name)] internal static partial nint TessBaseAPICreate();
    [LibraryImport(Name)] internal static partial void TessBaseAPIDelete(nint api);
    [LibraryImport(Name, StringMarshalling = StringMarshalling.Utf8)] internal static partial int TessBaseAPIInit3(nint api, string? dataPath, string language);
    [LibraryImport(Name)] internal static partial void TessBaseAPISetPageSegMode(nint api, int mode);
    [LibraryImport(Name, StringMarshalling = StringMarshalling.Utf8)] internal static partial int TessBaseAPISetVariable(nint api, string name, string value);
    [LibraryImport(Name)] internal static partial void TessBaseAPISetImage(nint api, byte* pixels, int width, int height, int bytesPerPixel, int bytesPerLine);
    [LibraryImport(Name)] internal static partial void TessBaseAPISetSourceResolution(nint api, int ppi);
    [LibraryImport(Name)] internal static partial int TessBaseAPIRecognize(nint api, nint monitor);
    [LibraryImport(Name)] internal static partial void TessBaseAPIClear(nint api);
    [LibraryImport(Name)] internal static partial nint TessBaseAPIGetIterator(nint api);
    [LibraryImport(Name)] internal static partial void TessResultIteratorDelete(nint iterator);
    [LibraryImport(Name)] internal static partial nint TessResultIteratorGetPageIterator(nint iterator);
    [LibraryImport(Name)] internal static partial int TessResultIteratorNext(nint iterator, int level);
    [LibraryImport(Name)] internal static partial nint TessResultIteratorGetUTF8Text(nint iterator, int level);
    [LibraryImport(Name)] internal static partial float TessResultIteratorConfidence(nint iterator, int level);
    [LibraryImport(Name)] internal static partial int TessPageIteratorBoundingBox(nint iterator, int level, out int left, out int top, out int right, out int bottom);
    [LibraryImport(Name)] internal static partial int TessPageIteratorIsAtBeginningOf(nint iterator, int level);
    [LibraryImport(Name)] internal static partial void TessDeleteText(nint text);
}
