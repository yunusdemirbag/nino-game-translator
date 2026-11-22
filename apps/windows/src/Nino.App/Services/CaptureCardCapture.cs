// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows.Threading;
using Nino.RemotePlay;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;
using Windows.Devices.Enumeration;
using Windows.Graphics.Imaging;
using Windows.Media.Audio;
using Windows.Media.Capture;
using Windows.Media.Capture.Frames;
using Windows.Media.MediaProperties;
using Windows.Media.Render;

namespace Nino.App.Services;

/// <summary>Kart kaynağının kurulumu.</summary>
public sealed record CaptureCardOptions
{
    /// <summary>Oyun bu bilgisayarda gösterilsin mi (oyun penceresi + ses).</summary>
    public bool ShowGameHere { get; init; }

    /// <summary>Kullanıcının seçtiği aygıt (yoksa kendiliğinden).</summary>
    public string? PreferredDeviceId { get; init; }

    /// <summary>Arayüz iş parçacığı (oyun penceresi orada kurulur).</summary>
    public required Dispatcher Dispatcher { get; init; }

    /// <summary>Altyazı günlüğü satırları.</summary>
    public Action<string>? Log { get; init; }

    /// <summary>Oyunun penceresi gösterilirken ekranı açık tut.</summary>
    public Action<bool>? HoldDisplay { get; init; }
}

/// <summary>
/// HDMI yakalama kartı (kaynaklar §3): kartlar Windows'ta kamera gibi görünür; Windows.Media.Capture ile yalnız
/// görüntü, işlemci belleği, özel denetim; kare okuyucusu BGRA8 1920×1080 gerçek zamanlı. Okuma hattına saniyede 10
/// kare 1920×1080; oyun bu bilgisayarda gösteriliyorsa her kare oyun penceresine ve kartın sesi hoparlöre.
/// </summary>
public sealed class CaptureCardCapture : ICaptureCardSource
{
    const string ContainerProperty = "System.Devices.ContainerId";

    readonly CaptureCardOptions _o;
    readonly Action<string> _log;
    readonly object _gate = new();
    readonly SemaphoreSlim _connecting = new(1, 1);
    readonly Stopwatch _clock = Stopwatch.StartNew();
    readonly BlackPictureWatch _blackWatch = new();
    readonly CardStallWatch _stall = new();
    int _generation;
    bool _running;
    CardStatus? _cardStatus;
    SourceStatus? _status;
    DeviceWatcher? _watcher;
    Timer? _stallTimer;
    Timer? _debounce;
    Timer? _retry;
    MediaCapture? _capture;
    MediaFrameReader? _reader;
    AudioGraph? _audio;
    CaptureDevice? _card;
    CardPlayerWindow? _player;
    double _lastFrame;
    double _lastRead = double.NegativeInfinity;
    int _processing;
    byte[]? _buffer;

    /// <summary>Kurar.</summary>
    public CaptureCardCapture(CaptureCardOptions options)
    {
        _o = options;
        _log = options.Log ?? (_ => { });
    }

    double Now => _clock.Elapsed.TotalSeconds;

    /// <inheritdoc />
    public event Action<VideoFrame>? FrameArrived;

    /// <inheritdoc />
    public event Action<SourceStatus>? StatusChanged;

    /// <inheritdoc />
    public event Action<Ps5Console>? ConsoleMoved { add { } remove { } }

    /// <inheritdoc />
    public event Action<CardStatus>? CardStatusChanged;

    /// <inheritdoc />
    public event Action<PixelRect?>? GameAreaChanged;

    /// <inheritdoc />
    public event Action? GameWindowClosed;

    /// <inheritdoc />
    public void Start()
    {
        int gen;
        lock (_gate)
        {
            if (_running) return;
            _running = true;
            gen = ++_generation;
            _cardStatus = null;
            _status = null;
        }
        if (_o.ShowGameHere) OpenPlayer(gen);
        try
        {
            var watcher = DeviceInformation.CreateWatcher(DeviceClass.VideoCapture);
            watcher.Added += (_, _) => DevicesChanged(gen);
            watcher.Removed += (_, _) => DevicesChanged(gen);
            watcher.Start();
            _watcher = watcher;
        }
        catch (Exception e)
        {
            _log("yakalama kartı aygıt izleyicisi açılamadı: " + e.Message);
        }
        _stallTimer = new Timer(_ => StallTick(gen), null, TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
        _ = ConnectAsync(gen, reopen: false);
    }

    /// <inheritdoc />
    public void Stop()
    {
        lock (_gate)
        {
            if (!_running) return;
            SetCard(new CardStatus(CardCaptureState.Stopped));
            _running = false;
            _generation++;
        }
        _stallTimer?.Dispose();
        _debounce?.Dispose();
        _retry?.Dispose();
        try { _watcher?.Stop(); } catch (Exception) { }
        _watcher = null;
        ClosePlayer();
        _ = Task.Run(async () =>
        {
            await _connecting.WaitAsync().ConfigureAwait(false);
            try { await ReleaseAsync().ConfigureAwait(false); }
            finally { _connecting.Release(); }
        });
    }

    /// <inheritdoc />
    public void ReconnectNow() => Refresh();

    /// <inheritdoc />
    public void Dispose() => Stop();

    /// <inheritdoc />
    public void ToggleFullScreen() => _o.Dispatcher.BeginInvoke(() => _player?.ToggleFullScreen());

    /// <summary>Yenile (uykudan uyanma, başka aygıt seçildi, takılma): kart unutulur, yeniden açılır.</summary>
    void Refresh()
    {
        int gen;
        lock (_gate)
        {
            if (!_running) return;
            gen = _generation;
            _card = null;
        }
        _ = ConnectAsync(gen, reopen: true);
    }

    bool Current(int gen)
    {
        lock (_gate) return _running && gen == _generation;
    }

    void SetCard(CardStatus status)
    {
        if (!_running || status == _cardStatus) return;
        _cardStatus = status;
        Safe(() => CardStatusChanged?.Invoke(status));
        var phase = status.State switch
        {
            CardCaptureState.Capturing or CardCaptureState.BlackPicture => SourceStatus.Streaming,
            CardCaptureState.Stopped => SourceStatus.Down(DisconnectReason.Stopped),
            _ => SourceStatus.Connecting,
        };
        if (phase == _status) return;
        _status = phase;
        Safe(() => StatusChanged?.Invoke(phase));
    }

    void SetCard(int gen, CardStatus status)
    {
        lock (_gate)
            if (gen == _generation) SetCard(status);
    }

    static void Safe(Action a)
    {
        try { a(); } catch (Exception) { }
    }

    void DevicesChanged(int gen)
    {
        if (!Current(gen)) return;
        _debounce?.Dispose();
        _debounce = new Timer(_ => _ = ConnectAsync(gen, reopen: false), null, CaptureCardRules.DeviceChangeDelay,
            Timeout.InfiniteTimeSpan);
    }

    void RetryIn(int gen, TimeSpan delay)
    {
        _retry?.Dispose();
        _retry = new Timer(_ => _ = ConnectAsync(gen, reopen: false), null, delay, Timeout.InfiniteTimeSpan);
    }

    async Task ConnectAsync(int gen, bool reopen)
    {
        if (!Current(gen)) return;
        await _connecting.WaitAsync().ConfigureAwait(false);
        try
        {
            if (!Current(gen)) return;
            var devices = await ListAsync(DeviceClass.VideoCapture).ConfigureAwait(false);
            var card = CaptureCardRules.PickVideo(devices, _o.PreferredDeviceId);
            if (card is null)
            {
                await ReleaseAsync().ConfigureAwait(false);
                SetCard(gen, new CardStatus(CardCaptureState.NoCard));
                return;
            }
            if (!reopen && _card?.Id == card.Id && _reader is not null) return;
            await ReleaseAsync().ConfigureAwait(false);
            try
            {
                await OpenAsync(gen, card).ConfigureAwait(false);
            }
            catch (UnauthorizedAccessException)
            {
                await ReleaseAsync().ConfigureAwait(false);
                SetCard(gen, new CardStatus(CardCaptureState.NeedsPermission));
                RetryIn(gen, CaptureCardRules.PermissionRetry);
            }
            catch (Exception e)
            {
                _log($"yakalama kartı açılamadı: {e.GetType().Name}: 0x{e.HResult:X8} {e.Message}");
                await ReleaseAsync().ConfigureAwait(false);
                if (_cardStatus?.State != CardCaptureState.Capturing) SetCard(gen, new CardStatus(CardCaptureState.NoCard));
                RetryIn(gen, CaptureCardRules.OpenRetry);
            }
        }
        catch (Exception e)
        {
            _log("yakalama kartı aygıtları okunamadı: " + e.Message);
        }
        finally
        {
            _connecting.Release();
        }
    }

    Task<IReadOnlyList<CaptureDevice>> ListAsync(DeviceClass kind) => FindDevicesAsync(kind, _log);

    /// <summary>
    /// Etkin yakalama aygıtları (kimlik, ad, kap). Liste hatası günlüğe yazılır, boş liste döner. Ayarlardaki aygıt
    /// listesi de (<see cref="CaptureCardDevices"/>) bunu kullanır.
    /// </summary>
    internal static async Task<IReadOnlyList<CaptureDevice>> FindDevicesAsync(DeviceClass kind, Action<string> log)
    {
        try
        {
            var found = await DeviceInformation.FindAllAsync(DeviceInformation.GetAqsFilterFromDeviceClass(kind), [ContainerProperty]).AsTask().ConfigureAwait(false);
            return found.Where(d => d.IsEnabled).Select(d => new CaptureDevice(d.Id, d.Name ?? "",
                d.Properties.TryGetValue(ContainerProperty, out var c) ? c?.ToString() : null)).ToList();
        }
        catch (Exception e)
        {
            log("aygıt listesi okunamadı: " + e.Message);
            return [];
        }
    }

    async Task OpenAsync(int gen, CaptureDevice card)
    {
        var capture = new MediaCapture();
        _capture = capture;
        var init = new MediaCaptureInitializationSettings { VideoDeviceId = card.Id };
        init.StreamingCaptureMode = StreamingCaptureMode.Video; // yalnız görüntü
        init.MemoryPreference = MediaCaptureMemoryPreference.Cpu; // işlemci belleği
        init.SharingMode = MediaCaptureSharingMode.ExclusiveControl; // özel denetim
        await capture.InitializeAsync(init).AsTask().ConfigureAwait(false);
        capture.Failed += (_, e) =>
        {
            _log($"kart bağlantısı kesildi: 0x{e.Code:X8} {e.Message}");
            lock (_gate) _card = null;
            RetryIn(gen, CaptureCardRules.FailedRetry);
        };
        var colors = capture.FrameSources.Values.Where(s => s.Info.SourceKind == MediaFrameSourceKind.Color).ToList();
        var source = colors.FirstOrDefault(s => s.Info.MediaStreamType == MediaStreamType.VideoRecord) ?? colors.FirstOrDefault()
            ?? throw new InvalidOperationException("kart hiçbir görüntü akışı sunmuyor");
        string described;
        var formats = source.SupportedFormats.Where(f => f.VideoFormat is not null && f.FrameRate is not null).ToList();
        var wanted = CaptureCardRules.PickFormat(formats.Select(Describe));
        var chosen = wanted is null ? null : formats.FirstOrDefault(f => Describe(f) == wanted);
        if (chosen is not null)
        {
            try
            {
                await source.SetFormatAsync(chosen).AsTask().ConfigureAwait(false);
                described = string.Create(CultureInfo.InvariantCulture,
                    $"{wanted!.Width}×{wanted.Height} {wanted.FrameRate:0.##} {wanted.Subtype}");
            }
            catch (Exception e)
            {
                _log("yakalama kartı biçimi ayarlanamadı: " + e.Message);
                described = "varsayılan biçim";
            }
        }
        else described = "varsayılan biçim";
        var reader = await capture.CreateFrameReaderAsync(source, MediaEncodingSubtypes.Bgra8,
            new Windows.Graphics.Imaging.BitmapSize { Width = CaptureCardRules.OutputWidth, Height = CaptureCardRules.OutputHeight })
            .AsTask().ConfigureAwait(false);
        reader.AcquisitionMode = MediaFrameReaderAcquisitionMode.Realtime;
        _reader = reader;
        if (!Current(gen)) return;
        reader.FrameArrived += (r, _) => OnFrame(gen, r);
        var status = await reader.StartAsync().AsTask().ConfigureAwait(false);
        if (status != MediaFrameReaderStartStatus.Success) throw new InvalidOperationException("kart okunamadı: " + status);
        if (!Current(gen)) return;
        lock (_gate) _card = card;
        _blackWatch.Reset();
        _stall.Reset();
        _lastFrame = Now;
        _log($"yakalama kartı kullanımda: {card.Name} ({described})");
        SetCard(gen, new CardStatus(CardCaptureState.Capturing, card.Name));
        if (_o.ShowGameHere && Current(gen)) await StartAudioAsync(gen, card).ConfigureAwait(false);
    }

    static CaptureFormat Describe(MediaFrameFormat f) => new((int)f.VideoFormat.Width, (int)f.VideoFormat.Height,
        f.FrameRate.Denominator == 0 ? 0 : (double)f.FrameRate.Numerator / f.FrameRate.Denominator, f.Subtype ?? "");

    async Task StartAudioAsync(int gen, CaptureDevice card)
    {
        try
        {
            var audio = await ListAsync(DeviceClass.AudioCapture).ConfigureAwait(false);
            if (CaptureCardRules.PickAudio(card, audio) is not { } input)
            {
                _log("ses aygıtı bulunamadı; ses çalınmıyor");
                return;
            }
            var graphSettings = new AudioGraphSettings(AudioRenderCategory.GameMedia);
            graphSettings.QuantumSizeSelectionMode = QuantumSizeSelectionMode.LowestLatency;
            var created = await AudioGraph.CreateAsync(graphSettings).AsTask().ConfigureAwait(false);
            if (created.Status != AudioGraphCreationStatus.Success) throw new InvalidOperationException(created.Status.ToString());
            var graph = created.Graph;
            var output = await graph.CreateDeviceOutputNodeAsync().AsTask().ConfigureAwait(false);
            if (output.Status != AudioDeviceNodeCreationStatus.Success) throw new InvalidOperationException(output.Status.ToString());
            var device = await DeviceInformation.CreateFromIdAsync(input.Id).AsTask().ConfigureAwait(false);
            var inNode = await graph.CreateDeviceInputNodeAsync(Windows.Media.Capture.MediaCategory.Media,
                graph.EncodingProperties, device).AsTask().ConfigureAwait(false);
            if (inNode.Status != AudioDeviceNodeCreationStatus.Success) throw new InvalidOperationException(inNode.Status.ToString());
            inNode.DeviceInputNode.AddOutgoingConnection(output.DeviceOutputNode);
            _audio = graph;
            if (!Current(gen)) return; // durdurma bırakır
            graph.Start();
        }
        catch (Exception e)
        {
            _log("yakalama kartının sesi açılamadı: " + e.Message);
        }
    }

    void OnFrame(int gen, MediaFrameReader reader)
    {
        _lastFrame = Now;
        if (Interlocked.CompareExchange(ref _processing, 1, 0) != 0) return;
        try
        {
            if (!Current(gen)) return;
            var now = Now;
            var player = _player;
            var due = CaptureCardRules.ReadDue(now, _lastRead);
            if (player is null && !due) return;
            using var reference = reader.TryAcquireLatestFrame();
            var bitmap = reference?.VideoMediaFrame?.SoftwareBitmap;
            if (bitmap is null) return;
            using var bgra = bitmap.BitmapPixelFormat == BitmapPixelFormat.Bgra8
                ? null
                : SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore);
            var source = bgra ?? bitmap;
            var w = source.PixelWidth;
            var h = source.PixelHeight;
            if (w <= 0 || h <= 0) return;
            // Ekran için her kare yeni dizi (pencere en son kareyi alır); yalnız okuma hattı için tampon yeniden kullanılır.
            var bytes = player is not null ? new byte[w * h * 4]
                : _buffer is { } b && b.Length == w * h * 4 ? b : _buffer = new byte[w * h * 4];
            source.CopyToBuffer(bytes.AsBuffer());
            player?.Push(bytes, w, h);
            if (!due) return;
            _lastRead = now;
            var black = CaptureCardRules.IsBlack(bytes, w, h, w * 4);
            var name = _card?.Name;
            SetCard(gen, new CardStatus(_blackWatch.Feed(black, now) ? CardCaptureState.BlackPicture : CardCaptureState.Capturing, name));
            var frame = new VideoFrame(CaptureCardRules.ToOutput(bytes, w, h, w * 4), CaptureCardRules.OutputWidth,
                CaptureCardRules.OutputHeight, CaptureCardRules.OutputWidth * 4);
            if (Current(gen)) Safe(() => FrameArrived?.Invoke(frame));
        }
        catch (Exception) { }
        finally
        {
            Interlocked.Exchange(ref _processing, 0);
        }
    }

    void StallTick(int gen)
    {
        if (!Current(gen) || _card is null || _reader is null) return;
        if (_stall.Tick(Now, _lastFrame) is { } seconds)
        {
            _log($"kart {seconds} sn boyunca kare göndermedi; aygıt yeniden başlatılıyor");
            Refresh();
        }
    }

    async Task ReleaseAsync()
    {
        var audio = _audio;
        var reader = _reader;
        var capture = _capture;
        _audio = null;
        _reader = null;
        _capture = null;
        try
        {
            audio?.Stop();
            audio?.Dispose();
        }
        catch (Exception) { }
        try
        {
            if (reader is not null)
            {
                await reader.StopAsync().AsTask().ConfigureAwait(false);
                reader.Dispose();
            }
        }
        catch (Exception) { }
        try { capture?.Dispose(); } catch (Exception) { }
    }

    void OpenPlayer(int gen)
    {
        void Create()
        {
            try
            {
                var player = new CardPlayerWindow();
                player.AreaChanged += area =>
                {
                    if (Current(gen)) Safe(() => GameAreaChanged?.Invoke(area));
                };
                player.UserClosed += () =>
                {
                    _player = null;
                    _o.HoldDisplay?.Invoke(false);
                    if (Current(gen)) Safe(() => GameWindowClosed?.Invoke());
                };
                _player = player;
                _o.HoldDisplay?.Invoke(true);
                player.ShowFullScreen();
            }
            catch (Exception e)
            {
                _log("oyun penceresi açılamadı: " + e.Message);
            }
        }
        if (_o.Dispatcher.CheckAccess()) Create();
        else _o.Dispatcher.Invoke(Create);
    }

    void ClosePlayer()
    {
        var player = _player;
        _player = null;
        if (player is null) return;
        _o.Dispatcher.BeginInvoke(() =>
        {
            try { player.CloseSilently(); } catch (Exception) { }
            _o.HoldDisplay?.Invoke(false);
        });
    }
}
