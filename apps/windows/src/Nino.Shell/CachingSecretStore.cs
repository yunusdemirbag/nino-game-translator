// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using System.Text.Json.Nodes;
using Nino.Core.Data;

namespace Nino.Shell;

/// <summary>
/// Şifreli deponun önbellekli sarmalayıcısı: <c>FileSecretStore</c> her okumada dosyayı açıp çözdüğü için denetleyici
/// (ekran yenilemesinde birçok "kayıtlı mı" sorusu sorar) okumaları bellekte tutar. Yazmalar ve silmeler hemen alttaki
/// depoya gider. Depoya yalnız denetleyici yazmalıdır (başkası yazarsa önbellek bunu görmez).
/// </summary>
internal sealed class CachingSecretStore(ISecretStore inner) : ISecretStore
{
    readonly Dictionary<string, JsonNode?> _values = new(StringComparer.Ordinal);
    readonly HashSet<string> _missing = new(StringComparer.Ordinal);
    readonly object _gate = new();

    public void Set<T>(string name, T value)
    {
        inner.Set(name, value);
        lock (_gate)
        {
            _values[name] = JsonSerializer.SerializeToNode(value);
            _missing.Remove(name);
        }
    }

    public bool TryGet<T>(string name, out T? value)
    {
        value = default;
        JsonNode? node;
        lock (_gate)
        {
            if (_missing.Contains(name)) return false;
            if (!_values.TryGetValue(name, out node))
            {
                if (!inner.TryGet<JsonNode>(name, out node) && !inner.Contains(name))
                {
                    _missing.Add(name);
                    return false;
                }
                _values[name] = node;
            }
        }
        try
        {
            value = node is null ? default : node.Deserialize<T>();
            return node is not null || default(T) is null;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException or NotSupportedException)
        {
            value = default;
            return false;
        }
    }

    public void Remove(string key)
    {
        inner.Remove(key);
        lock (_gate)
        {
            _values.Remove(key);
            _missing.Add(key);
        }
    }

    public bool Contains(string key)
    {
        lock (_gate)
        {
            if (_values.ContainsKey(key)) return true;
            if (_missing.Contains(key)) return false;
        }
        var has = inner.Contains(key);
        lock (_gate)
            if (!has) _missing.Add(key);
        return has;
    }
}
