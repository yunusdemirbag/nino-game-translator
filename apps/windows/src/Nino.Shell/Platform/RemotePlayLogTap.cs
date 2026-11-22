// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Health;
using Nino.RemotePlay;

namespace Nino.Shell.Platform;

/// <summary>
/// Remote Play günlüğünün dinleyicisi (kaynaklar tarifi §1.9, sağlık tarifi §1): <c>remoteplay.log</c>'a giden her
/// satır sağlık kaydına (yeniden gönderim, taşma, görüntü durması, bozuk kare sayıları) ve altyazı günlüğündeki
/// duraklama izleyicisine (<see cref="PictureStallNotes"/>: "görüntü durdu / sürdü / gelmedi" notları) verilir.
/// Satırlar herhangi bir iş parçacığından gelir; ikisi de kilitlidir. Windows ve Linux açılışı bir kez bağlar.
/// </summary>
public sealed class RemotePlayLogTap : IDisposable
{
    readonly RemotePlayLog _log;
    readonly HealthRecorder _health;
    readonly Action<string> _subtitleLog;
    readonly Func<long> _nowMs;
    readonly PictureStallNotes _stalls = new();
    bool _attached;

    RemotePlayLogTap(RemotePlayLog log, HealthRecorder health, Action<string> subtitleLog, Func<long> nowMs)
    {
        _log = log;
        _health = health;
        _subtitleLog = subtitleLog;
        _nowMs = nowMs;
    }

    /// <summary>Bağlar; <see cref="Dispose"/> çözer.</summary>
    /// <param name="log">Uygulamanın tek Remote Play günlüğü.</param>
    /// <param name="health">Denetleyicinin sağlık kaydı (<c>NinoController.Health</c>).</param>
    /// <param name="subtitleLog">Altyazı günlüğüne satır (<c>IShellLogs.Subtitle</c>).</param>
    /// <param name="nowMs">Milisaniye saati (testler); varsayılan <see cref="Environment.TickCount64"/>.</param>
    public static RemotePlayLogTap Attach(RemotePlayLog log, HealthRecorder health, Action<string> subtitleLog,
        Func<long>? nowMs = null)
    {
        var tap = new RemotePlayLogTap(log, health, subtitleLog, nowMs ?? (() => Environment.TickCount64));
        log.LineAdded += tap.OnLine;
        tap._attached = true;
        return tap;
    }

    void OnLine(string line)
    {
        try { _health.RemotePlayLine(line); }
        catch (Exception) { }
        try
        {
            if (_stalls.Interpret(line, _nowMs()) is { } note) _subtitleLog(note);
        }
        catch (Exception) { }
    }

    /// <inheritdoc />
    public void Dispose()
    {
        if (!_attached) return;
        _attached = false;
        _log.LineAdded -= OnLine;
    }
}
