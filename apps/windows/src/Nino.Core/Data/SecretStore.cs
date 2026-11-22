// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Nino.Core.Data;

/// <summary>
/// Gizli değerler deposu: anahtar → JSON değer. Hesap, PS5, TV ve çeviri anahtarları burada durur.
/// Değerler varsayılan JSON yazımıyla saklanır (alan adları olduğu gibi, enum'lar sayı, baytlar base64).
/// </summary>
public interface ISecretStore
{
    /// <summary>Değeri yazar (dosya baştan yazılır).</summary>
    void Set<T>(string name, T value);

    /// <summary>Anahtar yoksa ya da değer istenen tipe çevrilemezse false.</summary>
    bool TryGet<T>(string name, out T? value);

    /// <summary>Anahtar varsa siler (yoksa dosyaya dokunmaz).</summary>
    void Remove(string key);

    /// <summary>Anahtar var mı.</summary>
    bool Contains(string key);
}

/// <summary>Depo yardımcıları.</summary>
public static class SecretStoreExtensions
{
    /// <summary>Değer ya da yoksa null/varsayılan.</summary>
    public static T? Get<T>(this ISecretStore store, string name) =>
        store.TryGet<T>(name, out var value) ? value : default;
}

/// <summary>Dosya içeriğini koruyan/çözen platform hizmeti (Windows'ta DPAPI, geçerli kullanıcı).</summary>
public interface ISecretProtector
{
    /// <summary>Düz baytları ek anahtarla korur.</summary>
    byte[] Protect(byte[] plain, byte[] entropy);

    /// <summary>Çözer; çözülemezse hata fırlatır.</summary>
    byte[] Unprotect(byte[] protectedBytes, byte[] entropy);
}

/// <summary>Şifresiz koruyucu: içerik düz JSON kalır (Linux'ta 0600 izinli <c>secure.json</c> için).</summary>
public sealed class PlainSecretProtector : ISecretProtector
{
    /// <inheritdoc />
    public byte[] Protect(byte[] plain, byte[] entropy) => plain;

    /// <inheritdoc />
    public byte[] Unprotect(byte[] protectedBytes, byte[] entropy) => protectedBytes;
}

/// <summary>
/// Bütün anahtarları tek bir JSON nesnesinde tutan dosya deposu (Windows'ta <c>secure.dat</c>, Linux'ta
/// <c>secure.json</c>). Her kayıt/silme dosyayı yeniden okur, değiştirir, korur ve <c>.tmp</c> üzerinden yazar.
/// Eski ek anahtarla korunmuş dosya bir kez yeni anahtarla yeniden yazılır. Çözülemeyen ya da bozuk dosya, üstüne
/// yazılmadan önce <c>&lt;ad&gt;.bozuk-&lt;zaman&gt;</c> olarak kenara alınır.
/// </summary>
public sealed class FileSecretStore : ISecretStore
{
    /// <summary>Windows dosya adı.</summary>
    public const string WindowsFileName = "secure.dat";

    /// <summary>Linux dosya adı.</summary>
    public const string LinuxFileName = "secure.json";

    /// <summary>Yeni ek anahtar.</summary>
    public static byte[] CurrentEntropy => Encoding.UTF8.GetBytes("nino-secure-store");

    static readonly JsonSerializerOptions ValueOptions = new();

    readonly string _path;
    readonly ISecretProtector _protector;
    readonly byte[] _entropy;
    readonly byte[][] _legacyEntropies;
    readonly bool _ownerOnly;
    readonly TimeProvider _clock;
    readonly object _gate = new();

    /// <param name="path">Dosyanın tam yolu.</param>
    /// <param name="protector">Koruyucu (DPAPI ya da <see cref="PlainSecretProtector"/>).</param>
    /// <param name="ownerOnly">Doğruysa dosya yalnız sahibinin okuyabileceği izinle (0600) yazılır.</param>
    /// <param name="entropy">Ek anahtar; verilmezse <see cref="CurrentEntropy"/>.</param>
    /// <param name="legacyEntropies">Çözülemezse denenecek eski ek anahtarlar; verilmezse LegacyNames'teki.</param>
    /// <param name="clock">Kenara alma adındaki zaman.</param>
    public FileSecretStore(string path, ISecretProtector protector, bool ownerOnly = false, byte[]? entropy = null,
        IEnumerable<byte[]>? legacyEntropies = null, TimeProvider? clock = null)
    {
        _path = path;
        _protector = protector;
        _ownerOnly = ownerOnly;
        _entropy = entropy ?? CurrentEntropy;
        _legacyEntropies = (legacyEntropies ?? [LegacyNames.SecretsEntropy]).ToArray();
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>Windows deposu: veri klasöründe <c>secure.dat</c>.</summary>
    public static FileSecretStore ForWindows(string dataFolder, ISecretProtector dpapi) =>
        new(Path.Combine(dataFolder, WindowsFileName), dpapi);

    /// <summary>Linux deposu: veri klasöründe 0600 izinli düz <c>secure.json</c> (ad değiştirilebilir).</summary>
    public static FileSecretStore ForLinux(string dataFolder, string fileName = LinuxFileName) =>
        new(Path.Combine(dataFolder, fileName), new PlainSecretProtector(), ownerOnly: true);

    /// <summary>Dosyanın yolu.</summary>
    public string FilePath => _path;

    /// <inheritdoc />
    public void Set<T>(string name, T value)
    {
        lock (_gate)
        {
            var state = Read();
            if (state.Kind == ReadKind.IoError)
                throw new IOException($"{Path.GetFileName(_path)} okunamadı; üstüne yazılmadı.", state.Error);
            if (state.Kind == ReadKind.Unreadable) FileIo.SetAside(_path, _clock.GetUtcNow());
            state.Root[name] = JsonSerializer.SerializeToNode(value, ValueOptions);
            Write(state.Root);
        }
    }

    /// <inheritdoc />
    public bool TryGet<T>(string name, out T? value)
    {
        value = default;
        JsonNode? node;
        lock (_gate)
        {
            var root = Read().Root;
            if (!root.TryGetPropertyValue(name, out node)) return false;
        }
        try
        {
            value = node is null ? default : node.Deserialize<T>(ValueOptions);
            return node is null ? default(T) is null : true;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException
                                      or NotSupportedException)
        {
            value = default;
            return false;
        }
    }

    /// <inheritdoc />
    public void Remove(string key)
    {
        lock (_gate)
        {
            var state = Read();
            if (!state.Root.ContainsKey(key)) return;
            state.Root.Remove(key);
            Write(state.Root);
        }
    }

    /// <inheritdoc />
    public bool Contains(string key)
    {
        lock (_gate) return Read().Root.ContainsKey(key);
    }

    enum ReadKind { Missing, Ok, IoError, Unreadable }

    readonly record struct ReadState(ReadKind Kind, JsonObject Root, Exception? Error = null);

    ReadState Read()
    {
        byte[] blob;
        try
        {
            if (!File.Exists(_path)) return new(ReadKind.Missing, new JsonObject());
            blob = File.ReadAllBytes(_path);
        }
        catch (Exception e) when (FileIo.IsIoError(e))
        {
            return new(ReadKind.IoError, new JsonObject(), e);
        }

        if (TryOpen(blob, _entropy, out var root)) return new(ReadKind.Ok, root);
        foreach (var legacy in _legacyEntropies)
        {
            if (!TryOpen(blob, legacy, out root)) continue;
            try { Write(root); } // bir kezlik geçiş: yeni ek anahtarla yeniden yaz
            catch (Exception e) when (FileIo.IsIoError(e)) { }
            return new(ReadKind.Ok, root);
        }
        return new(ReadKind.Unreadable, new JsonObject());
    }

    bool TryOpen(byte[] blob, byte[] entropy, out JsonObject root)
    {
        root = null!;
        byte[] plain;
        try { plain = _protector.Unprotect(blob, entropy); }
        catch { return false; }
        try
        {
            if (JsonNode.Parse(plain) is not JsonObject obj) return false;
            root = obj;
            return true;
        }
        catch (JsonException) { return false; }
    }

    void Write(JsonObject root)
    {
        var plain = FileIo.Utf8.GetBytes(root.ToJsonString());
        FileIo.WriteAtomic(_path, _protector.Protect(plain, _entropy), _ownerOnly);
    }
}

/// <summary>Bellekte duran depo (testler ve dosyasız kullanım).</summary>
public sealed class MemorySecretStore : ISecretStore
{
    readonly Dictionary<string, JsonNode?> _values = new(StringComparer.Ordinal);
    readonly object _gate = new();

    /// <inheritdoc />
    public void Set<T>(string name, T value)
    {
        lock (_gate) _values[name] = JsonSerializer.SerializeToNode(value);
    }

    /// <inheritdoc />
    public bool TryGet<T>(string name, out T? value)
    {
        value = default;
        JsonNode? node;
        lock (_gate)
            if (!_values.TryGetValue(name, out node)) return false;
        try
        {
            value = node is null ? default : node.Deserialize<T>();
            return node is not null || default(T) is null;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException
                                      or NotSupportedException)
        {
            return false;
        }
    }

    /// <inheritdoc />
    public void Remove(string key)
    {
        lock (_gate) _values.Remove(key);
    }

    /// <inheritdoc />
    public bool Contains(string key)
    {
        lock (_gate) return _values.ContainsKey(key);
    }
}
