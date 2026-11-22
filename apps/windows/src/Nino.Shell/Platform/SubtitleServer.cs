// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Link;

namespace Nino.Shell.Platform;

/// <summary>
/// Altyazı sunucusu (8787 + 47800 + Android TV bağlantısı). Gerçeği <see cref="TvOutputServer"/>
/// (<see cref="TvOutput"/>'un ince sarmalayıcısı); testlerde sahtesi. Olaylar herhangi bir iş parçacığından gelir.
/// </summary>
public interface ISubtitleServer : IAsyncDisposable
{
    /// <summary>Bağlı TV sayısı değişti.</summary>
    event Action<int>? TvCountChanged;

    /// <summary>TV uygulaması modelini bildirdi.</summary>
    event Action<string>? TvModelReported;

    /// <summary>Gönderilen her olayın yerel özeti (bilgisayar penceresi ve yayın penceresi için).</summary>
    event Action<LocalSubtitleEvent>? LocalEvent;

    /// <summary>Android TV bağlantısı TV'yi yeni bir adreste buldu.</summary>
    event Action<string>? AndroidTvHostFound;

    /// <summary>Bir TV bağlandı (OBS izleyicisi hariç). Varsayılan: hiç gelmez.</summary>
    event Action<TvLinkConnected>? TvConnected { add { } remove { } }

    /// <summary>Bir TV bağlantısı bitti ya da el sıkışma olmadı. Varsayılan: hiç gelmez.</summary>
    event Action<TvLinkDropped>? TvDropped { add { } remove { } }

    /// <summary>Açık mı.</summary>
    bool IsRunning { get; }

    /// <summary>Gerçek port (açılmadıysa 0).</summary>
    int Port { get; }

    /// <summary>Bağlı TV sayısı.</summary>
    int TvCount { get; }

    /// <summary>Altyazı olayları TV'ye gitsin mi (kapalıyken yalnız OBS'e).</summary>
    bool SendToTv { get; set; }

    /// <summary>Açar: 8787 (doluysa 6 deneme, sonra boş port). Açıksa bir şey yapmaz; süren açılış beklenir.</summary>
    Task<int> StartAsync(CancellationToken cancellationToken = default);

    /// <summary>Olayı yollar.</summary>
    void Send(TvEvent e);

    /// <summary>TV'ye verilen 8787 adresi.</summary>
    string ServerAddress(string? localIp);

    /// <summary>LG/Samsung TV uygulamasının açılış parametreleri (JSON metni).</summary>
    string LaunchParameters(string? localIp);

    /// <summary>OBS adresleri.</summary>
    (string Local, string? Network) ObsAddresses(string? lanIp);

    /// <summary>Android TV'ye giden bağlantıyı başlatır.</summary>
    void ConnectAndroidTv(string? savedHost) { }

    /// <summary>Android TV bağlantısını bırakır.</summary>
    void DisconnectAndroidTv() { }
}

/// <summary><see cref="TvOutput"/>'u <see cref="ISubtitleServer"/> olarak sunar.</summary>
public sealed class TvOutputServer : ISubtitleServer
{
    readonly TvOutput _output;

    /// <summary>Sarmalar.</summary>
    public TvOutputServer(TvOutput output)
    {
        _output = output;
        _output.TvCountChanged += n => TvCountChanged?.Invoke(n);
        _output.TvInfoReported += info =>
        {
            if (!string.IsNullOrWhiteSpace(info.Model)) TvModelReported?.Invoke(info.Model!);
        };
        _output.LocalEvent += e => LocalEvent?.Invoke(e);
        _output.AndroidTvHostFound += h => AndroidTvHostFound?.Invoke(h);
        _output.TvConnected += e => TvConnected?.Invoke(e);
        _output.TvDropped += e => TvDropped?.Invoke(e);
    }

    /// <summary>İçteki çıkış.</summary>
    public TvOutput Output => _output;

    /// <inheritdoc />
    public event Action<int>? TvCountChanged;

    /// <inheritdoc />
    public event Action<string>? TvModelReported;

    /// <inheritdoc />
    public event Action<LocalSubtitleEvent>? LocalEvent;

    /// <inheritdoc />
    public event Action<string>? AndroidTvHostFound;

    /// <inheritdoc />
    public event Action<TvLinkConnected>? TvConnected;

    /// <inheritdoc />
    public event Action<TvLinkDropped>? TvDropped;

    /// <inheritdoc />
    public bool IsRunning => _output.Legacy.IsRunning;

    /// <inheritdoc />
    public int Port => _output.LegacyPort;

    /// <inheritdoc />
    public int TvCount => _output.TvCount;

    /// <inheritdoc />
    public bool SendToTv
    {
        get => _output.SubtitlesOnTv;
        set => _output.SubtitlesOnTv = value;
    }

    /// <inheritdoc />
    public Task<int> StartAsync(CancellationToken cancellationToken = default) => _output.EnsureStartedAsync(cancellationToken);

    /// <inheritdoc />
    public void Send(TvEvent e) => _output.Send(e);

    /// <inheritdoc />
    public string ServerAddress(string? localIp) => _output.ServerAddress(localIp);

    /// <inheritdoc />
    public string LaunchParameters(string? localIp) => _output.LaunchParameters(localIp);

    /// <inheritdoc />
    public (string Local, string? Network) ObsAddresses(string? lanIp) => _output.ObsAddresses(lanIp);

    /// <inheritdoc />
    public void ConnectAndroidTv(string? savedHost) => _output.ConnectAndroidTv(savedHost);

    /// <inheritdoc />
    public void DisconnectAndroidTv() => _output.DisconnectAndroidTv();

    /// <inheritdoc />
    public ValueTask DisposeAsync() => _output.DisposeAsync();
}
