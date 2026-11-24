// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Design;
using Nino.Core.Settings;
using Nino.RemotePlay;
using Nino.Shell.Platform;

namespace Nino.Shell;

// Ekranlara verilen durum metinleri ve noktalar (§19). Metinler Nino.Core.Text kataloğundan.
public sealed partial class NinoController
{
    /// <summary>Konsol başlığı.</summary>
    public string ConsoleTitle => _text.Get(IsXbox ? "status.console.titleXbox"
        : OnStreamPath && _settings.FrameSource == FrameSource.ChosenWindow ? "status.console.titleSelectedWindow"
        : "status.console.titlePs5");

    /// <summary>Konsol/görüntü kaynağının tek satırlık durum metni.</summary>
    public string ConsoleStatusText
    {
        get
        {
            if (UsesGameWindow) return GameWindowText();
            if (UsesCaptureCard) return CardText();
            if (IsXbox) return XboxText();
            return _settings.FrameSource switch
            {
                FrameSource.RemotePlayWindow => RemotePlayWindowText(),
                FrameSource.ChosenWindow => ChosenWindowText(),
                _ => Ps5Text(),
            };
        }
    }

    string Ps5Text()
    {
        var s = _status;
        if (_translating && s.Phase == SourcePhase.Streaming) return _text.Get("status.common.connected");
        if (_translating && s.Phase == SourcePhase.Connecting) return _text.Get("status.common.connecting");
        if (!_translating)
            return _console is null ? _text.Get("status.common.notConnected")
                : _text.Format("status.ps5.pairedIdle", _console.Name is { Length: > 0 } n ? n : "PS5");
        var detail = s.Detail?.Trim();
        return s.Reason switch
        {
            DisconnectReason.ConsoleAsleep => _text.Get("status.ps5.asleep"),
            DisconnectReason.InUse => _text.Get("status.ps5.inUseElsewhere"),
            DisconnectReason.Refused => _text.Get("status.ps5.refused"),
            DisconnectReason.LoginPasscode => _text.Get("status.ps5.passcodeRequired"),
            DisconnectReason.LoginPasscodeIncorrect => _text.Get("status.ps5.passcodeWrong"),
            DisconnectReason.RegistrationInvalid => _text.Get("status.ps5.pairingInvalid"),
            DisconnectReason.RemotePlayDisabled => _text.Get("status.ps5.remotePlayOff"),
            DisconnectReason.NotFound => _text.Format("status.ps5.notFound", detail is { Length: > 0 } ? detail : _console?.Host ?? "?"),
            DisconnectReason.Network => _text.Get("status.ps5.unreachable"),
            DisconnectReason.Rejected => detail is { Length: > 0 }
                ? _text.Format("status.ps5.sessionRejectedCode", detail)
                : _text.Get("status.ps5.sessionRejected"),
            DisconnectReason.Other when detail is { Length: > 0 } => _text.Format("status.common.reconnectingDetail", detail),
            _ => _text.Get("status.common.reconnecting"),
        };
    }

    string XboxText()
    {
        var s = _status;
        if (_translating && s.Phase == SourcePhase.Streaming) return _text.Get("status.common.connected");
        if (_translating && s.Phase == SourcePhase.Connecting) return _text.Get("status.common.connecting");
        if (!_translating)
            return _xboxConsole is null ? _text.Get("status.common.notConnected")
                : _text.Format("status.xbox.readyIdle", _xboxConsole.Name);
        var detail = s.Detail?.Trim();
        if (s.Reason == DisconnectReason.Refused && detail is { Length: > 0 }) return detail;
        return detail is { Length: > 0 } ? _text.Format("status.xbox.retryingDetail", detail) : _text.Get("status.xbox.retrying");
    }

    string RemotePlayWindowText()
    {
        var streaming = _translating && _status.Phase == SourcePhase.Streaming;
        if (!streaming && !_services.IsRemotePlayAppInstalled(_settings.RemotePlayApp))
            return _text.Get("status.remotePlayWindow.notInstalled");
        if (streaming) return _text.Get("status.remotePlayWindow.reading");
        if (!_translating) return _text.Get("status.remotePlayWindow.idle");
        if (_status.Phase == SourcePhase.Connecting) return _text.Get("status.remotePlayWindow.waiting");
        return _status.Detail is { Length: > 0 } d ? d : _text.Get("status.remotePlayWindow.waiting");
    }

    string ChosenWindowText()
    {
        if (_settings.CaptureWindow is not { ProcessName.Length: > 0, Title.Length: > 0 } window)
            return _text.Get("status.selectedWindow.notChosen");
        if (_translating && _status.Phase == SourcePhase.Streaming) return _text.Get("status.selectedWindow.reading");
        if (!_translating) return _text.Format("status.selectedWindow.idle", window.Title);
        return _status.Detail is { Length: > 0 } d ? d : _text.Format("status.selectedWindow.waiting", window.Title);
    }

    string GameWindowText()
    {
        var xbox = UsesXboxGameWindow;
        if (_windowState == WindowCaptureState.Capturing)
            return _text.Format("status.common.reading", _windowApp is { Length: > 0 } app ? app : xbox ? "Xbox" : "PS Remote Play");
        if (_windowState == WindowCaptureState.LookingForWindow || _translating)
            return _text.Get(xbox ? "status.gameWindow.xbox.startPlaying" : "status.gameWindow.ps5.startPlaying");
        return _text.Get(xbox ? "status.gameWindow.xbox.idle" : "status.gameWindow.ps5.idle");
    }

    string CardText() => _card.State switch
    {
        CardCaptureState.NeedsPermission => _text.Get("status.card.noPermission"),
        CardCaptureState.NoCard => _text.Get("status.card.notPlugged"),
        CardCaptureState.InUse => _text.Get("status.card.inUse"),
        CardCaptureState.BlackPicture => _text.Get("status.card.black"),
        CardCaptureState.Capturing => _text.Format("status.common.reading",
            _card.DeviceName is { Length: > 0 } n ? n : _text.Get("status.card.defaultName")),
        _ => _text.Get("status.card.idle"),
    };

    /// <summary>Konsol noktası.</summary>
    public StatusTone ConsoleTone =>
        UsesCaptureCard && _card.State == CardCaptureState.BlackPicture ? StatusTone.Warning
        : _translating && _status.Phase == SourcePhase.Streaming ? StatusTone.Good
        : _translating ? StatusTone.Warning
        : StatusTone.Idle;

    /// <summary>TV noktası.</summary>
    public StatusTone TvTone =>
        !TvPaired ? StatusTone.Idle
        : _tvCount > 0 ? StatusTone.Good
        : _translating ? StatusTone.Warning
        : StatusTone.Idle;

    /// <summary>TV metni.</summary>
    public string TvStatusText =>
        !TvPaired ? _text.Get("status.tv.notSetUp")
        : _tvCount > 0 ? _text.Get("status.common.connected")
        : _text.Get("status.tv.waitingForApp");
}
