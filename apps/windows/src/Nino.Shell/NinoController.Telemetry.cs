// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Library;
using Nino.Core.Link;
using Nino.Core.Reading;
using Nino.Core.Settings;
using Nino.Core.Telemetry;
using Nino.Core.Translation;
using Nino.RemotePlay;
using TvKind = Nino.Core.Tv.TvBrand;
using TmBrand = Nino.Core.Telemetry.TvBrand;

namespace Nino.Shell;

// Ölçüm (olcum.md): oturum sonu, süre histogramları, PS5 ve TV bağlantısı, hata kodları. Yalnız kod ve sayı gider;
// altyazı metni, ad, adres, istisna iletisi asla. Bütün yöntemler arayüz iş parçacığında çağrılır.
public sealed partial class NinoController
{
    ShellTelemetry? _telemetry;
    SessionTimings? _timings;
    DateTimeOffset? _tmSessionStart;
    SessionSource _tmSource;
    long _tmLines;
    bool _tmFirstSubtitle;
    bool _tmFirstFrame;
    DateTimeOffset? _tmPs5Attempt;
    DateTimeOffset? _tmPs5Since;
    DateTimeOffset? _tmTvAttempt;
    bool _tmTvFailSent;
    readonly Dictionary<long, (DateTimeOffset Since, TmBrand Brand)> _tmTvLinks = [];
    readonly Dictionary<string, DateTimeOffset> _tmErrorAt = new(StringComparer.Ordinal);

    /// <summary>Aynı koddaki sık hatalar (kare başına olanlar) en çok bu aralıkta bir kaydedilir.</summary>
    static readonly TimeSpan ErrorGap = TimeSpan.FromSeconds(10);

    /// <summary>Ölçüm (kurulmadıysa ya da gönderici yoksa null). Platform çökme ve ani çıkışları buraya bildirir.</summary>
    [NotObserved]
    public ShellTelemetry? Telemetry => _telemetry;

    void OpenTelemetry(TelemetrySetup? setup)
    {
        if (setup is null) return;
        _telemetry = ShellTelemetry.Open(setup, _services, () => Brand(_tv?.Brand));
        if (_telemetry is { } opened) OpenDiagnostics(opened, setup);
        if (_telemetry is not { } telemetry || _services.Pool is not { } pool) return;
        Action<string> onConfig = json =>
        {
            try { telemetry.Client.ApplyRemoteConfigJson(json); } catch (Exception) { }
        };
        pool.ConfigReceived += onConfig;
        _subscriptions.Add(new Unsubscribe(() => pool.ConfigReceived -= onConfig));
    }

    static TmBrand Brand(TvKind? brand) => brand switch
    {
        TvKind.Lg => TmBrand.Lg,
        TvKind.Samsung => TmBrand.Samsung,
        TvKind.AndroidTv => TmBrand.AndroidTv,
        _ => TmBrand.None,
    };

    void Record(TelemetryEvent e)
    {
        try { _telemetry?.Client.Record(e); } catch (Exception) { }
    }

    /// <summary>Yakalanan hata (yalnız kod). Aynı kod <see cref="ErrorGap"/> içinde yinelenirse atlanır.</summary>
    void RecordErrorCode(string code, int? http = null)
    {
        if (_telemetry is null) return;
        var now = _timers.Now;
        lock (_tmErrorAt)
        {
            if (_tmErrorAt.TryGetValue(code, out var last) && now - last < ErrorGap) return;
            _tmErrorAt[code] = now;
        }
        Record(TelemetryEvent.Error(now, code, http));
        if (code == "ps5.stream.decoder") _diag?.DecoderFailed();
        else _diag?.Note(code, http);
    }

    long MsSince(DateTimeOffset start) => Math.Max(0, (long)(_timers.Now - start).TotalMilliseconds);

    long SecondsSince(DateTimeOffset start) => Math.Max(0, (long)(_timers.Now - start).TotalSeconds);

    // ---- Oturum ----

    void TmSessionStarted()
    {
        DgSessionStarted();
        _timings = new SessionTimings();
        _tmSessionStart = _timers.Now;
        _tmLines = 0;
        _tmFirstSubtitle = false;
        _tmFirstFrame = false;
        _tmPs5Since = null;
        // Yayın oturumu "bağlanıyor" ile başlar (ilk evre bildirilmez): deneme şimdi başlar.
        _tmPs5Attempt = IsPs5OrXboxStream ? _timers.Now : null;
        _tmSource = UsesCaptureCard ? SessionSource.Capture
            : IsXbox ? SessionSource.Xbox
            : UsesGameWindow || _settings.FrameSource != FrameSource.Ps5 ? SessionSource.Screen
            : SessionSource.RemotePlay;
    }

    void TmSessionEnded()
    {
        DgSessionEnded();
        if (_tmSessionStart is not { } start) return;
        _tmSessionStart = null;
        var timings = _timings;
        _timings = null;
        _tmPs5Attempt = null;
        _tmPs5Since = null;
        Record(TelemetryEvent.Session(_timers.Now, SecondsSince(start), GameIds.FromName(_game.Current?.Name), _tmSource,
            _tmLines, timings is { IsEmpty: false } ? timings : null));
    }

    void TmMetrics(SubtitleMetrics m)
    {
        DgLine(m);
        if (_timings is not { } timings) return;
        if (m.OcrMs is { } ocr) timings.Add(SessionTimings.Ocr, ocr);
        if (m.TranslationMs is { } tr)
        {
            switch (m.Origin)
            {
                case ShownOrigin.Pack:
                    timings.Add(SessionTimings.Pack, tr);
                    break;
                case ShownOrigin.Pool:
                    timings.Add(SessionTimings.Pool, tr);
                    break;
                default:
                    timings.Add(SessionTimings.Provider, tr);
                    timings.Add(SessionTimings.ProviderNamed(ProviderName()), tr);
                    break;
            }
        }
        if (m.TotalMs is { } total) timings.Add(SessionTimings.Total, total);
    }

    /// <summary>Satırı çeviren motorun ölçüm adı.</summary>
    string ProviderName() =>
        _chain?.OnlineEnabled != true ? "free"
        : _settings.OnlineEngine switch
        {
            OnlineEngine.DeepL => "deepl",
            OnlineEngine.Gemini => "gemini",
            OnlineEngine.OpenAi => "openai",
            OnlineEngine.Claude => "claude",
            OnlineEngine.Local => "local",
            _ => "free",
        };

    void TmLineShown()
    {
        _diag?.OcrText();
        if (_tmSessionStart is not { } start) return;
        _tmLines++;
        if (_tmFirstSubtitle) return;
        _tmFirstSubtitle = true;
        _timings?.Add(SessionTimings.FirstSubtitle, MsSince(start));
    }

    void TmOnlineFailure(OnlineFailure? failure)
    {
        if (failure is not { } f) return;
        RecordErrorCode(f switch
        {
            OnlineFailure.InvalidKey => "tr.provider.auth",
            OnlineFailure.QuotaExhausted => "tr.provider.quota",
            OnlineFailure.ModelRejected => "tr.provider.rejected",
            _ => "tr.provider.offline",
        });
    }

    // ---- PS5 / Xbox yayını ----

    /// <summary>Görüntü gerçek bir PS5 ya da Xbox yayınından mı (pencere/kart okuma bağlantı sayılmaz).</summary>
    bool IsPs5OrXboxStream => !UsesGameWindow && !UsesCaptureCard && (IsXbox || _settings.FrameSource == FrameSource.Ps5);

    /// <summary>Evre değişimi (yalnız PS5 ya da Xbox yayınında; pencere okuma bağlantı sayılmaz).</summary>
    void TmSourceStatus(SourceStatus old, SourceStatus status)
    {
        if (_telemetry is null || !IsPs5OrXboxStream) return;
        DgSourceStatus(old, status);
        var via = IsXbox ? Ps5Route.Xbox : Ps5Route.Lan;
        switch (status.Phase)
        {
            case SourcePhase.Connecting:
                _tmPs5Attempt ??= _timers.Now;
                break;
            case SourcePhase.Streaming:
                if (_tmPs5Attempt is { } attempt)
                {
                    Record(TelemetryEvent.Ps5Connect(_timers.Now, "ok", MsSince(attempt), via));
                    if (!_tmFirstFrame)
                    {
                        _tmFirstFrame = true;
                        _timings?.Add(SessionTimings.FirstFrame, MsSince(attempt));
                    }
                }
                _tmPs5Attempt = null;
                _tmPs5Since = _timers.Now;
                break;
            default:
                if (status.Reason is not { } reason || reason == DisconnectReason.Stopped) break;
                if (_tmPs5Since is { } since && old.Phase == SourcePhase.Streaming)
                    Record(TelemetryEvent.Ps5Drop(_timers.Now, DropCode(reason), SecondsSince(since)));
                else if (_tmPs5Attempt is { } tried)
                    Record(TelemetryEvent.Ps5Connect(_timers.Now, ConnectCode(reason), MsSince(tried), via));
                _tmPs5Attempt = null;
                _tmPs5Since = null;
                break;
        }
    }

    /// <summary>Bağlanamama sebebi → ölçüm kodu (sabit tablo; ayrıntı metni asla gitmez).</summary>
    internal static string ConnectCode(DisconnectReason reason) => reason switch
    {
        DisconnectReason.ConsoleAsleep => "ps5.session.standby",
        DisconnectReason.InUse => "ps5.session.busy",
        DisconnectReason.Network => "ps5.session.timeout",
        DisconnectReason.NotFound => "ps5.discover.none",
        DisconnectReason.Refused or DisconnectReason.Rejected => "ps5.auth.rejected",
        DisconnectReason.RegistrationInvalid => "ps5.register.failed",
        DisconnectReason.LoginPasscode or DisconnectReason.LoginPasscodeIncorrect => "ps5.auth.passcode",
        DisconnectReason.RemotePlayDisabled => "ps5.remote.disabled",
        _ => "ps5.other",
    };

    /// <summary>Kopma sebebi → ölçüm kodu.</summary>
    internal static string DropCode(DisconnectReason reason) => reason switch
    {
        DisconnectReason.Network => "network_lost",
        DisconnectReason.ConsoleAsleep => "standby",
        DisconnectReason.InUse => "kicked",
        DisconnectReason.Refused or DisconnectReason.Rejected => "ps5_closed",
        _ => "other",
    };

    // ---- TV ----

    void TmTvWatchStarted()
    {
        _tmTvAttempt ??= _timers.Now;
        _tmTvFailSent = false;
    }

    /// <summary>Bekçi durdu (kullanıcı durdurdu ya da altyazı TV'den alındı): deneme süresi artık ölçülmez.</summary>
    void TmTvWatchStopped() => _tmTvAttempt = null;

    /// <summary>
    /// Ölçümdeki marka: bağlantının yolu söylüyorsa o (Android TV bağlantısı), yoksa kayıtlı TV markası (8787'de her
    /// marka olabilir; 47800 girişine yalnız LG/Samsung gelir).
    /// </summary>
    TmBrand LinkBrand(TvLinkKind kind) => kind switch
    {
        TvLinkKind.AndroidTv => TmBrand.AndroidTv,
        TvLinkKind.WebTv => _tv?.Brand is TvKind.Lg or TvKind.Samsung ? Brand(_tv.Brand) : TmBrand.None,
        _ => Brand(_tv?.Brand),
    };

    static TvProtocol LinkProtocol(TvLinkKind kind) => kind == TvLinkKind.Legacy ? TvProtocol.Legacy : TvProtocol.Nino;

    /// <summary>
    /// TV bağlandı (her bağlantı; OBS gelmez). Süre: bekçi bir deneme başlattıysa onun başından, yoksa bağlantının kendi
    /// el sıkışma süresi (8787'de sıfır).
    /// </summary>
    void TmTvConnected(TvLinkConnected e)
    {
        if (_telemetry is null || _closing) return;
        DgTvConnected(e.Kind);
        var brand = LinkBrand(e.Kind);
        var ms = _tmTvAttempt is { } attempt ? MsSince(attempt) : (long)e.Took.TotalMilliseconds;
        _tmTvAttempt = null;
        _tmTvFailSent = false;
        _tmTvLinks[e.Id] = (_timers.Now, brand);
        Record(TelemetryEvent.TvConnect(_timers.Now, "ok", ms, brand, LinkProtocol(e.Kind)));
    }

    /// <summary>
    /// TV bağlantısı bitti. El sıkışma olmadıysa başarısız <c>tv_connect</c> (deneme başına bir kez); bağlıyken çeviri
    /// sürerken koptuysa gerçek nedenle <c>tv_drop</c>. Nino'nun kapattığı bağlantı (<c>stopped</c>) kopma değildir.
    /// </summary>
    void TmTvDropped(TvLinkDropped e)
    {
        if (_telemetry is null) return;
        if (!e.WasConnected)
        {
            if (_tmTvFailSent || _closing || e.Reason != TvLinkEndReason.Handshake) return;
            _tmTvFailSent = true;
            var ms = _tmTvAttempt is { } attempt ? MsSince(attempt) : (long)e.After.TotalMilliseconds;
            Record(TelemetryEvent.TvConnect(_timers.Now, HandshakeCode(e), ms, LinkBrand(e.Kind), LinkProtocol(e.Kind)));
            return;
        }
        if (!_tmTvLinks.Remove(e.Id, out var link)) return;
        if (e.Reason == TvLinkEndReason.Stopped || !_translating || _closing) return;
        Record(TelemetryEvent.TvDrop(_timers.Now, DropCode(e.Reason), link.Brand, SecondsSince(link.Since)));
        _diag?.TvDropped(DropCode(e.Reason), SecondsSince(link.Since));
        if (_tmTvLinks.Count == 0 && _watch is not null) _tmTvAttempt ??= _timers.Now;
    }

    /// <summary>El sıkışma hatası → <c>tv_connect.r</c>: welcome gelmedi zaman aşımı, sürüm yok uyumsuzluk.</summary>
    static string HandshakeCode(TvLinkDropped e) =>
        e.Detail == TvLinkReasons.NoWelcome ? "tv.connect.timeout" : "tv.protocol.mismatch";

    /// <summary>Kopma nedeni → <c>tv_drop.code</c> (olcum.md tablosu; tabloda karşılığı olmayan <c>replaced</c> kendi adıyla).</summary>
    internal static string DropCode(TvLinkEndReason reason) => reason switch
    {
        TvLinkEndReason.Closed => "closed",
        TvLinkEndReason.WriteFailed => "write_error",
        TvLinkEndReason.Silence => "timeout",
        TvLinkEndReason.Replaced => "replaced",
        _ => "other",
    };

    // ---- Kapanış ----

    async Task CloseTelemetryAsync()
    {
        CloseDiagnostics();
        if (_telemetry is not { } telemetry) return;
        telemetry.Exiting();
        await telemetry.FlushOnExitAsync(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
    }
}
