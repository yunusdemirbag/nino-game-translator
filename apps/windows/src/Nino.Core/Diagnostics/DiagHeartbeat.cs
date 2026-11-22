// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text.Json.Nodes;
using Nino.Core.Data;

namespace Nino.Core.Diagnostics;

/// <summary>
/// Askıda kalma damgası (<c>telemetry/diag-alive.json</c>): izleyici iş parçacığı birkaç saniyede bir "süreç hâlâ
/// çalışıyor" (<c>alive</c>) ve "ana iş parçacığı en son şu an yanıt verdi" (<c>ui</c>) zamanlarını yazar; düzgün
/// kapanışta silinir. Bir sonraki açılışta dosya duruyor ve ana iş parçacığı son 60 sn'den uzun süredir yanıtsızken
/// çalışma bittiyse önceki çalışma askıda kalmıştır (<c>app.hang</c>; çökmeden ayrı).
/// </summary>
public sealed class DiagHeartbeat(string path)
{
    /// <summary>Dosya adı.</summary>
    public const string FileName = "diag-alive.json";

    /// <summary>Önceki çalışmanın askıda kalmış sayılması için en az yanıtsızlık.</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromSeconds(60);

    /// <summary>Önceki çalışma askıda bittiyse ana iş parçacığının yanıtsız kaldığı süre (sn); değilse null. Dosyayı siler.</summary>
    public double? TakePrevious()
    {
        try
        {
            if (!File.Exists(path)) return null;
            var root = JsonNode.Parse(File.ReadAllText(path, FileIo.Utf8)) as JsonObject;
            File.Delete(path);
            if (root?["alive"] is not JsonValue a || !a.TryGetValue<long>(out var alive)) return null;
            if (root["ui"] is not JsonValue u || !u.TryGetValue<long>(out var ui)) return null;
            // Aynı askı canlıyken zaten bildirildiyse yeniden bildirilmez.
            if (root["reported"] is JsonValue r && r.TryGetValue<bool>(out var reported) && reported) return null;
            var blocked = alive - ui;
            return blocked > StaleAfter.TotalSeconds ? blocked : null;
        }
        catch (Exception e) when (FileIo.IsIoError(e) || e is System.Text.Json.JsonException or InvalidOperationException
                                      or FormatException)
        {
            return null;
        }
    }

    /// <summary>Damgayı yazar. <paramref name="reported"/>: süren askı canlı olarak bildirildi.</summary>
    public void Beat(DateTimeOffset alive, DateTimeOffset uiResponded, bool reported = false)
    {
        try
        {
            var o = new JsonObject
            {
                ["alive"] = alive.ToUnixTimeSeconds(),
                ["ui"] = uiResponded.ToUnixTimeSeconds(),
            };
            if (reported) o["reported"] = true;
            FileIo.WriteAtomic(path, o.ToJsonString());
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }

    /// <summary>Düzgün kapanış: damga silinir.</summary>
    public void Stop()
    {
        try { File.Delete(path); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }
}
