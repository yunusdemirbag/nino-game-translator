// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using Nino.Translation.Local;

namespace Nino.Translation.Tests.Local;

/// <summary>Bellekten dosya veren, aralık destekleyebilen sahte sunucu.</summary>
internal sealed class FileServer : HttpMessageHandler
{
    public Dictionary<string,
        byte[]> Files { get; } = new();
    public List<(string Url, string? Range)> Requests { get; } = [];
    public bool SupportsRange
        { get; set; } = true;
    public Func<string, long, Task>? BeforeChunk { get; set; }

    protected override Task<HttpResponseMessage>
        SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var url = request.RequestUri!.ToString();
        var range =
            request.Headers.Range?.Ranges.FirstOrDefault();
        lock (Requests) Requests.Add((url, request.Headers.Range?.ToString()));
        if (!Files.TryGetValue(url, out var bytes)) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        var from = SupportsRange && range?.From is { } f ? f : 0;
        var response = new HttpResponseMessage(from > 0 ? HttpStatusCode.PartialContent : HttpStatusCode.OK)
        {
            Content = new StreamContent(new ChunkStream(bytes, (int)from, this, url)),
        };
        if (from > 0) response.Content.Headers.ContentRange = new ContentRangeHeaderValue(from, bytes.Length - 1, bytes.Length);
        return Task.FromResult(response);
    }

    sealed class ChunkStream(byte[] data, int start, FileServer server, string url) : Stream
    {
        int _at = start;
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => data.Length;
        public override long Position { get => _at; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override int Read(byte[] buffer, int offset, int count) => ReadAsync(buffer, offset, count).GetAwaiter().GetResult();

        public override async Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken ct)
        {
            if (server.BeforeChunk is { } hook) await hook(url, _at).WaitAsync(ct);
            var n = Math.Min(Math.Min(count, 10_000), data.Length - _at);
            if (n <= 0) return 0;
            Array.Copy(data, _at, buffer, offset, n);
            _at += n;
            return n;
        }

        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken ct = default)
        {
            var array = new byte[buffer.Length];
            return new ValueTask<int>(ReadAsync(array, 0, array.Length, ct).ContinueWith(t =>
            {
                array.AsSpan(0, t.Result).CopyTo(buffer.Span);
                return t.Result;
            }, ct));
        }

        public override long Seek(long offset, SeekOrigin
            origin) => throw new NotSupportedException();
        public override void SetLength(long value)
            => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset,
            int count) => throw new NotSupportedException();
    }
}

internal sealed class ListProgress : IProgress<double>
{
    public List<double> Values { get; } = [];
    public void Report(double value)
    {
        lock (Values) Values.Add(value);
    }
}

public class DownloadTests
{
    static string Temp()
    {
        var dir = Path.Combine(Path.GetTempPath(), "nino-dl-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    static byte[] Data(int size, int seed)
    {
        var bytes = new byte[size];
        new Random(seed).NextBytes(bytes);
        return bytes;
    }

    static ModelFile Serve(FileServer server, string name, byte[] data, string? sha = null, long? size = null)
    {
        var url = "https://models.example.test/" + name;
        server.Files[url] = data;
        return new ModelFile(name, url, size ?? data.Length, sha ?? Convert.ToHexString(SHA256.HashData(data)));
    }

    [Fact]
    public async Task IkiDosyaIner()
    {
        var server = new FileServer();
        var files = new[] { Serve(server, "a.bin", Data(150_000, 1)), Serve(server, "b.bin", Data(90_000, 2)) };
        var dir = Temp();
        var progress = new ListProgress();
        await new ModelDownloader(new HttpClient(server)).DownloadAsync(dir, files, progress);
        Assert.True(ModelDownloader.AllInstalled(dir, files));
        Assert.Empty(Directory.GetFiles(dir, "*.part"));
        Assert.Equal(1, progress.Values[^1]);
        for (var i = 1; i < progress.Values.Count; i++) Assert.True(progress.Values[i] >= progress.Values[i - 1]);
    }

    [Fact]
    public async Task OzetYaDaBoyTutmazsa()
    {
        var server = new FileServer();
        var dir = Temp();
        var bad = Serve(server, "a.bin", Data(1000, 3), sha: new string('0', 64));
        await Assert.ThrowsAsync<ModelDownloadException>(() =>
            new ModelDownloader(new HttpClient(server)).DownloadAsync(dir, [bad]));
        Assert.False(File.Exists(Path.Combine(dir, "a.bin")));
        Assert.False(File.Exists(Path.Combine(dir, "a.bin.part")));

        var wrongSize = Serve(server, "b.bin", Data(1000, 4), size: 999);
        await Assert.ThrowsAsync<ModelDownloadException>(() =>
            new ModelDownloader(new HttpClient(server)).DownloadAsync(dir, [wrongSize]));
    }

    [Fact]
    public void KisaDosyaKuruluSayilmaz()
    {
        var dir = Temp();
        File.WriteAllBytes(Path.Combine(dir, "a.bin"), new byte[10]);
        Assert.False(ModelDownloader.IsInstalled(dir, new ModelFile("a.bin", "x", 11, "")));
        Assert.True(ModelDownloader.IsInstalled(dir, new ModelFile("a.bin", "x", 10, "")));
    }

    [Fact]
    public async Task KaldigiYerdenSurer()
    {
        var server = new FileServer();
        var data = Data(300_000, 5);
        var file = Serve(server, "m.bin", data);
        var dir = Temp();
        File.WriteAllBytes(Path.Combine(dir, "m.bin.part"), data[..120_000]);
        await new ModelDownloader(new HttpClient(server)).DownloadAsync(dir, [file]);
        Assert.Equal("bytes=120000-", server.Requests.Single().Range);
        Assert.Equal(data, File.ReadAllBytes(Path.Combine(dir, "m.bin")));
    }

    [Fact]
    public async Task AralikYoksaBastan()
    {
        var server = new FileServer { SupportsRange = false };
        var data = Data(200_000, 6);
        var file = Serve(server, "m.bin", data);
        var dir = Temp();
        File.WriteAllBytes(Path.Combine(dir, "m.bin.part"), data[..50_000]);
        await new ModelDownloader(new HttpClient(server)).DownloadAsync(dir, [file]);
        Assert.Equal(data, File.ReadAllBytes(Path.Combine(dir, "m.bin")));
    }

    [Fact]
    public async Task BozukParcaOnceHataSonraBasari()
    {
        var server = new FileServer();
        var data = Data(200_000, 7);
        var file = Serve(server, "m.bin", data);
        var dir = Temp();
        File.WriteAllBytes(Path.Combine(dir, "m.bin.part"), new byte[120_000]);
        var downloader = new ModelDownloader(new HttpClient(server));
        await Assert.ThrowsAsync<ModelDownloadException>(() => downloader.DownloadAsync(dir, [file]));
        await downloader.DownloadAsync(dir, [file]);
        Assert.Equal(data, File.ReadAllBytes(Path.Combine(dir, "m.bin")));
    }

    [Fact]
    public async Task KuruluysaIstekYok()
    {
        var server = new FileServer();
        var data = Data(5000, 8);
        var file = Serve(server, "m.bin", data);
        var dir = Temp();
        File.WriteAllBytes(Path.Combine(dir, "m.bin"), data);
        var progress = new ListProgress();
        await new ModelDownloader(new HttpClient(server)).DownloadAsync(dir, [file], progress);
        Assert.Empty(server.Requests);
        Assert.Equal(1, progress.Values[^1]);
    }

    [Fact]
    public async Task IptalSonraTamamlanir()
    {
        var server = new FileServer();
        var data = Data(300_000, 9);
        var file = Serve(server, "m.bin", data);
        var dir = Temp();
        using var cts = new CancellationTokenSource();
        server.BeforeChunk = (_, at) =>
        {
            if (at >= 100_000) cts.Cancel();
            return Task.CompletedTask;
        };
        var downloader = new ModelDownloader(new HttpClient(server));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => downloader.DownloadAsync(dir, [file], null, cts.Token));
        Assert.False(ModelDownloader.IsInstalled(dir, file));
        server.BeforeChunk = null;
        await downloader.DownloadAsync(dir, [file]);
        Assert.Equal(data, File.ReadAllBytes(Path.Combine(dir, "m.bin")));
    }

    [Fact]
    public async Task TakilanIndirme()
    {
        var server = new FileServer();
        var file = Serve(server, "m.bin", Data(50_000, 10));
        server.BeforeChunk = (_, at) => at > 0 ? Task.Delay(Timeout.Infinite) : Task.CompletedTask;
        var dir = Temp();
        var e = await Assert.ThrowsAsync<ModelDownloadException>(() =>
            new ModelDownloader(new HttpClient(server), TimeSpan.FromMilliseconds(200)).DownloadAsync(dir, [file]));
        Assert.Contains("takıldı", e.Message);
    }

    [Fact]
    public void DosyaListeleri()
    {
        var tokenizer = ModelCatalog.TurkishTokenizerFiles;
        Assert.Equal(2, tokenizer.Count);
        Assert.All(tokenizer, f => Assert.Contains("/resolve/ce128ea834a090aca240e4e113e7756e06cc78e0/", f.Url));
        var total = tokenizer.Sum(f => f.Size);
        Assert.InRange(total, 2_000_000, 3_000_000);
        Assert.Null(ModelCatalog.For("en", "th"));
        Assert.Null(ModelCatalog.For("de", "tr"));
        var ar = ModelCatalog.For("en", "ar")!;
        Assert.Equal(">>ara<<", ar.TargetToken);
        Assert.Equal("en-ar", ar.Folder);
        Assert.Equal(ModelCatalog.OnnxFileNames, ar.Files.Select(f => f.Name));
        Assert.Equal("https://huggingface.co/Xenova/opus-mt-en-ar/resolve/034a684356c19021a187cda4d7f823298b913921/onnx/encoder_model_int8.onnx",
            ar.Files[0].Url);
        Assert.EndsWith("/vocab.json", ar.Files[3].Url);
        Assert.Equal(">>vie<<", ModelCatalog.For("en", "vi")!.TargetToken);
        Assert.Null(ModelCatalog.For("en", "nl")!.TargetToken);
        Assert.True(ModelCatalog.For("en", "tr")!.UsesCt2);
        Assert.Equal(474_595_937, ModelCatalog.TurkishArchive.Size);
        Assert.Equal(2, CudaCatalog.Archives.Count);
        Assert.StartsWith("https://developer.download.nvidia.com/compute/cuda/redist/libcublas/windows-x86_64/",
            CudaCatalog.Archives[0].Url);
    }

    [Fact]
    public async Task TurkceArsivKurulumu()
    {
        var zipBytes = new MemoryStream();
        using (var zip = new ZipArchive(zipBytes, ZipArchiveMode.Create, leaveOpen: true))
            foreach (var name in new[] { "model.bin", "config.json", "shared_vocabulary.json", "source.spm", "README.md", "LICENCE.txt" })
            {
                using var w = new StreamWriter(zip.CreateEntry("opus-mt-en-tr/" + name).Open());
                w.Write("içerik " + name);
            }
        var server = new FileServer();
        var archive = Serve(server, "opus-mt-en-tr.zip", zipBytes.ToArray());
        var vocab = Serve(server, "vocab.json", "{\"</s>\":0}"u8.ToArray());
        var root = Temp();
        Directory.CreateDirectory(Path.Combine(root, "en-tr"));
        var store = new FreeModelStore(root, new ModelDownloader(new HttpClient(server)), null, archive, vocab);
        Assert.False(store.IsInstalled("tr"));
        var progress = new ListProgress();
        await store.DownloadAsync("tr", progress);
        Assert.True(store.IsInstalled("tr"));
        var folder = Path.Combine(root, "en-tr-ct2");
        Assert.False(File.Exists(Path.Combine(folder, "opus-mt-en-tr.zip")));
        Assert.False(File.Exists(Path.Combine(folder, "README.md")));
        Assert.True(File.Exists(Path.Combine(folder, "LICENCE.txt")));
        Assert.False(Directory.Exists(Path.Combine(root, "en-tr")));
        Assert.Equal(1, progress.Values[^1]);
        Assert.Equal(1, progress.Values.Count(v => v == 1));

        var requests = server.Requests.Count;
        await store.DownloadAsync("tr");
        Assert.Equal(requests, server.Requests.Count);
    }

    [Fact]
    public async Task ArsivdeModelEksik()
    {
        var zipBytes = new MemoryStream();
        using (var zip = new ZipArchive(zipBytes, ZipArchiveMode.Create, leaveOpen: true))
            zip.CreateEntry("x/config.json");
        var server = new FileServer();
        var archive = Serve(server, "opus-mt-en-tr.zip", zipBytes.ToArray());
        var vocab = Serve(server, "vocab.json", "{}"u8.ToArray());
        var store = new FreeModelStore(Temp(), new ModelDownloader(new HttpClient(server)), null, archive, vocab);
        var e = await Assert.ThrowsAsync<ModelDownloadException>(() => store.DownloadAsync("tr"));
        Assert.Contains("eksik", e.Message);
    }

    [Fact]
    public void CudaKurulumuBoyaBakar()
    {
        var dir = Temp();
        var store = new CudaRuntimeStore(dir, new ModelDownloader(new HttpClient(new FileServer())), () => true);
        Assert.False(store.IsInstalled);
        Assert.Null(store.Current);
        Assert.True(store.DriverPresent);
    }
}
