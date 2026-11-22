// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json;
using Nino.Core.Data;

namespace Nino.Core.Settings;

/// <summary>Son yüklemenin sonucu.</summary>
public enum SettingsLoadStatus
{
    /// <summary>Henüz yüklenmedi.</summary>
    NotLoaded,
    /// <summary>Dosya yoktu (ilk açılış): çeviri dili sistem dilinden.</summary>
    Missing,
    /// <summary>Dosya okundu.</summary>
    Loaded,
    /// <summary>Dosya bozuktu: bütün alanlar varsayılan, çeviri dili <c>tr</c>. İlk kayıttan önce kenara alınır.</summary>
    Corrupt,
    /// <summary>Dosya okunamadı (kilit, izin): varsayılanlar; ilk kayıttan önce kenara alınır.</summary>
    Unreadable,
}

/// <summary>Ayar deposu (yükle, kaydet).</summary>
public interface ISettingsStore
{
    /// <summary>Ayarları yükler; hiç hata fırlatmaz (hatada varsayılanlar).</summary>
    AppSettings Load();

    /// <summary>Kaydeder; başarısızsa false döner (ayar bellekte geçerli kalır, sonraki kayıt yeniden dener).</summary>
    bool Save(AppSettings settings);
}

/// <summary>Bellekte duran ayar deposu (testler, Linux'ta dosyasız kullanım).</summary>
public sealed class MemorySettingsStore(AppSettings? initial = null) : ISettingsStore
{
    AppSettings _value = initial?.Clone() ?? new AppSettings();

    /// <summary>Kayıt sayısı.</summary>
    public int SaveCount { get; private set; }

    /// <inheritdoc />
    public AppSettings Load() => _value.Clone();

    /// <inheritdoc />
    public bool Save(AppSettings settings)
    {
        _value = settings.Clone();
        SaveCount++;
        return true;
    }
}

/// <summary>
/// <c>settings.json</c> dosya deposu. Yazma <c>.tmp</c> + yer değiştirme ile yapılır. Bozuk dosya ilk kayıttan
/// hemen önce bir kez <c>settings.json.bozuk-&lt;zaman&gt;</c> olarak kenara alınır (okunamayan dosya da).
/// </summary>
public sealed class JsonFileSettingsStore : ISettingsStore
{
    /// <summary>Dosya adı (Windows ve Linux).</summary>
    public const string FileName = "settings.json";

    readonly string _path;
    readonly Func<string?> _uiLanguage;
    readonly Action<string, Exception>? _onError;
    readonly TimeProvider _clock;
    readonly object _gate = new();
    bool _setAsidePending;

    /// <param name="path">Dosyanın tam yolu.</param>
    /// <param name="uiLanguage">Sistemin arayüz dili (ilk açılışta çeviri dili için), ör. <c>ar-SA</c>.</param>
    /// <param name="onError">Kaydetme hatası (ör. hata günlüğüne "Ayarlar kaydedilemedi").</param>
    /// <param name="clock">Kenara alma adındaki zaman.</param>
    public JsonFileSettingsStore(string path, Func<string?> uiLanguage, Action<string, Exception>? onError = null,
        TimeProvider? clock = null)
    {
        _path = path;
        _uiLanguage = uiLanguage;
        _onError = onError;
        _clock = clock ?? TimeProvider.System;
    }

    /// <summary>Dosyanın yolu.</summary>
    public string FilePath => _path;

    /// <summary>Son yüklemenin sonucu.</summary>
    public SettingsLoadStatus LastLoadStatus { get; private set; }

    /// <inheritdoc />
    public AppSettings Load()
    {
        lock (_gate)
        {
            string json;
            try
            {
                if (!File.Exists(_path))
                {
                    LastLoadStatus = SettingsLoadStatus.Missing;
                    _setAsidePending = false;
                    return new AppSettings { TargetLanguage = SettingsRules.FirstRunTargetLanguage(_uiLanguage()) };
                }
                json = File.ReadAllText(_path, FileIo.Utf8);
            }
            catch (Exception e) when (FileIo.IsIoError(e))
            {
                // Hiç okunamamış dosyanın üstüne varsayılanlar yazılacaksa önce kenara alınır.
                LastLoadStatus = SettingsLoadStatus.Unreadable;
                _setAsidePending = true;
                return new AppSettings();
            }

            try
            {
                var settings = SettingsJson.Deserialize(json);
                LastLoadStatus = SettingsLoadStatus.Loaded;
                _setAsidePending = false;
                return settings;
            }
            catch (Exception e) when (e is JsonException or NotSupportedException or InvalidOperationException
                                          or ArgumentException)
            {
                LastLoadStatus = SettingsLoadStatus.Corrupt;
                _setAsidePending = true;
                return new AppSettings();
            }
        }
    }

    /// <inheritdoc />
    public bool Save(AppSettings settings)
    {
        lock (_gate)
        {
            try
            {
                if (_setAsidePending)
                {
                    FileIo.SetAside(_path, _clock.GetUtcNow());
                    _setAsidePending = false;
                }
                FileIo.WriteAtomic(_path, SettingsJson.Serialize(settings));
                return true;
            }
            catch (Exception e) when (FileIo.IsIoError(e))
            {
                _onError?.Invoke("Ayarlar kaydedilemedi", e);
                return false;
            }
        }
    }
}
