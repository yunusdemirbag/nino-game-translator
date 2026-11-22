// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using System.Text.Json.Nodes;
using Nino.Core.Data;

namespace Nino.Core.Telemetry;

/// <summary>
/// Çalışma işareti (<c>telemetry/running.json</c>): açılışta yazılır, düzgün kapanışta silinir. Bir sonraki açılışta
/// duruyorsa önceki çalışma çökmüştür. Çökme anında yalnız istisna sınıfı ve uygulama içi sembol yazılır.
/// </summary>
public sealed class CrashMarker(string path, TimeProvider? clock = null)
{
    /// <summary>Dosya adı.</summary>
    public const string FileName = "running.json";

    readonly TimeProvider _clock = clock ?? TimeProvider.System;
    readonly object _gate = new();
    JsonObject? _current;

    /// <summary>Önceki çalışmanın işareti (çökme bilgisi); yoksa null.</summary>
    public sealed record Previous(string Version, string? Code, string? Where, long? UptimeSeconds);

    /// <summary>Önceki işareti okur (silmez).</summary>
    public Previous? ReadPrevious()
    {
        try
        {
            if (!File.Exists(path)) return null;
            if (JsonNode.Parse(File.ReadAllText(path, FileIo.Utf8)) is not JsonObject o) return new("", null, null, null);
            var start = Long(o["start"]);
            var seen = Long(o["seen"]);
            return new Previous(Str(o["ver"]) ?? "", Str(o["code"]), Str(o["where"]),
                start is { } s && seen is { } e && e >= s ? e - s : null);
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { return null; }
        catch (Exception e) when (e is System.Text.Json.JsonException or InvalidOperationException or FormatException)
        {
            return new("", null, null, null);
        }
    }

    /// <summary>Bu çalışmanın işaretini yazar.</summary>
    public void Start(string version)
    {
        var now = _clock.GetUtcNow().ToUnixTimeSeconds();
        lock (_gate)
        {
            _current = new JsonObject { ["ver"] = version, ["start"] = now, ["seen"] = now };
            Save();
        }
    }

    /// <summary>Çalışma süresi için "hâlâ açık" zamanını günceller.</summary>
    public void Touch()
    {
        lock (_gate)
        {
            if (_current is null) return;
            _current["seen"] = _clock.GetUtcNow().ToUnixTimeSeconds();
            Save();
        }
    }

    /// <summary>Çökme anında: istisnanın sınıf adı ve uygulama içindeki en üst sembol (ileti asla yazılmaz).</summary>
    public void RecordCrash(Exception error)
    {
        lock (_gate)
        {
            if (_current is null) return;
            _current["code"] = TelemetryText.Code(error.GetType().FullName) ?? TelemetryCodes.UncleanExit;
            if (WhereOf(error) is { } where) _current["where"] = where;
            _current["seen"] = _clock.GetUtcNow().ToUnixTimeSeconds();
            Save();
        }
    }

    /// <summary>Düzgün kapanış: işaret silinir.</summary>
    public void Stop()
    {
        lock (_gate)
        {
            _current = null;
            try { File.Delete(path); }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
        }
    }

    /// <summary>Yığındaki Nino koduna ait ilk çerçeve: <c>Tür.Yöntem</c> (yol ya da satır yok).</summary>
    public static string? WhereOf(Exception error)
    {
        var trace = new StackTrace(error, fNeedFileInfo: false);
        foreach (var frame in trace.GetFrames())
        {
            var method = frame.GetMethod();
            var type = method?.DeclaringType;
            if (type?.Namespace is not { } ns || !ns.StartsWith("Nino", StringComparison.Ordinal)) continue;
            return TelemetryText.Where($"{type.Name}.{method!.Name}");
        }
        return null;
    }

    void Save()
    {
        try { FileIo.WriteAtomic(path, _current!.ToJsonString()); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }

    static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    static long? Long(JsonNode? n) => n is JsonValue v && v.TryGetValue<long>(out var l) ? l : null;
}
