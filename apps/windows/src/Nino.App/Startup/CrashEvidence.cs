// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics.Eventing.Reader;
using System.Globalization;
using System.IO;
using Nino.Core.Data;
using Nino.Core.Logging;

namespace Nino.App.Startup;

/// <summary>
/// Yerel çökmelerin izi. Süreç yerel bir hatayla (ör. bellek erişim hatası, yığın taşması) kapanınca .NET'in hata
/// kancası çalışmaz; Windows olayı Uygulama günlüğüne yazar ("Application Error" 1000, ".NET Runtime" 1026). Açılışta
/// son 3 günün Nino.exe olayları okunur; daha önce görülmeyenler <c>hata.log</c>'a (sorun bildirimine eklenir) ve
/// ölçüme yalnız kod olarak (<c>crash.native.&lt;modül&gt;.&lt;kod&gt;</c>) gider.
/// </summary>
public static class CrashEvidence
{
    const string SeenFile = "crash-events.txt";
    const int MaxEvents = 10;

    /// <summary>Bulunan bir çökme.</summary>
    public sealed record Found(long RecordId, DateTime When, string Provider, string? Module, string? Code, string? Offset, string Text);

    /// <summary>Arka planda okur ve yazar; hiçbir hata bırakmaz.</summary>
    public static void ReportInBackground(string dataFolder, ErrorLog errors, Action<string>? recordCode) =>
        _ = Task.Run(() =>
        {
            try { Report(dataFolder, errors, recordCode); }
            catch (Exception) { }
        });

    static void Report(string dataFolder, ErrorLog errors, Action<string>? recordCode)
    {
        var seenPath = Path.Combine(dataFolder, SeenFile);
        long seen = 0;
        try
        {
            if (File.Exists(seenPath))
                long.TryParse(File.ReadAllText(seenPath).Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out seen);
        }
        catch (Exception e) when (FileIo.IsIoError(e)) { }

        var found = Read(seen);
        if (found.Count == 0) return;
        foreach (var f in found)
        {
            errors.Write($"Önceki çalışma Windows'ta kapandı ({f.When.ToLocalTime():yyyy-MM-dd HH:mm:ss}, {f.Provider}): "
                         + $"modül {f.Module ?? "?"}, kod {f.Code ?? "?"}, ofset {f.Offset ?? "?"}\n{Trim(f.Text, 3000)}");
            if (CodeFor(f) is { } code) recordCode?.Invoke(code);
        }
        try { FileIo.WriteAtomic(seenPath, found.Max(f => f.RecordId).ToString(CultureInfo.InvariantCulture)); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }

    /// <summary>Ölçüm kodu: <c>crash.native.onnxruntime.dll.c0000005</c> (kurala uymayan karakterler atılır).</summary>
    public static string? CodeFor(Found f)
    {
        var module = Clean(f.Module ?? (f.Provider == ".NET Runtime" ? "dotnet" : "unknown"));
        var code = Clean((f.Code ?? "").Replace("0x", "", StringComparison.OrdinalIgnoreCase));
        var text = "crash.native." + module + (code.Length > 0 ? "." + code : "");
        return text.Length > 64 ? text[..64] : text;
    }

    static string Clean(string s) =>
        new(s.ToLowerInvariant().Where(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-').ToArray());

    static string Trim(string s, int n) => s.Length <= n ? s : s[..n] + "…";

    static List<Found> Read(long afterRecord)
    {
        var result = new List<Found>();
        var query = new EventLogQuery("Application", PathType.LogName,
            "*[System[(Provider[@Name='Application Error'] and EventID=1000) or (Provider[@Name='.NET Runtime'] and EventID=1026)]"
            + " and System[TimeCreated[timediff(@SystemTime) <= 259200000]]]")
        { ReverseDirection = true };
        using var reader = new EventLogReader(query);
        for (var i = 0; i < 200 && result.Count < MaxEvents; i++)
        {
            using var record = reader.ReadEvent();
            if (record is null) break;
            if (record.RecordId is not { } id || id <= afterRecord) continue;
            string text;
            try { text = record.FormatDescription() ?? ""; }
            catch (EventLogException) { text = ""; }
            var props = record.Properties.Select(p => p.Value?.ToString() ?? "").ToList();
            if (record.ProviderName == "Application Error")
            {
                if (props.Count < 1 || !props[0].Equals("Nino.exe", StringComparison.OrdinalIgnoreCase)) continue;
                result.Add(new Found(id, record.TimeCreated ?? DateTime.Now, "Application Error",
                    props.ElementAtOrDefault(3), props.ElementAtOrDefault(6), props.ElementAtOrDefault(7), text));
            }
            else
            {
                if (!text.Contains("Nino.exe", StringComparison.OrdinalIgnoreCase)) continue;
                result.Add(new Found(id, record.TimeCreated ?? DateTime.Now, ".NET Runtime", null, null, null, text));
            }
        }
        return result;
    }
}
