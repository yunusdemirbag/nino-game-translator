// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Diagnostics.Guards;

/// <summary>
/// <c>tr.errors</c>: son 40 istekte (en az 10) hata oranı eşikten (%30) büyük; her sonuçtan sonra bakılır, koşulun ilk
/// sağlandığı istekte tetiklenir. Sebep: hataların en sık sınıfı (429 kota, 401/403 anahtar, ağ yok, 5xx, zaman aşımı).
/// </summary>
internal sealed class TrErrorsGuard(DiagnosticsWatcher owner) : DiagGuard(owner)
{
    const int Window = 40;
    const int Minimum = 10;
    readonly Queue<(bool Ok, int? Http, string? Class)> _results = new();

    public override void OnSignal(in DiagSignal s)
    {
        switch (s.Code)
        {
            case "session.start" or "session.stop":
                _results.Clear();
                break;
            case "tr.ok":
                Add(true, null, null, s.At);
                break;
            case "tr.error":
                var http = s.Number is { } h ? (int)h : (int?)null;
                Add(false, http, Classify(http, s.Reason), s.At);
                break;
        }
    }

    string? Classify(int? http, string? reason) => http switch
    {
        429 => "quota",
        401 or 403 => "auth",
        >= 500 and <= 599 => "server",
        0 => "offline",
        408 or 504 => "timeout",
        _ when reason == "timeout" => W.NetDown ? "offline" : "timeout",
        _ when W.NetDown => "offline",
        _ => null,
    };

    void Add(bool ok, int? http, string? cls, DateTimeOffset at)
    {
        _results.Enqueue((ok, http, cls));
        while (_results.Count > Window) _results.Dequeue();
        if (_results.Count < Minimum) return;
        var errors = _results.Count(r => !r.Ok);
        if (errors <= W.Limit(DiagLimitKeys.TrErrorRate) * _results.Count || W.IsQuiet(at)) return;
        var failed = _results.Where(r => !r.Ok).ToList();
        var cause = failed.Where(r => r.Class is not null).GroupBy(r => r.Class!)
            .OrderByDescending(g => g.Count()).FirstOrDefault()?.Key;
        var topHttp = failed.Where(r => r.Http is > 0).GroupBy(r => r.Http!.Value)
            .OrderByDescending(g => g.Count()).FirstOrDefault()?.Key;
        var state = new List<KeyValuePair<string, object?>>
        {
            F("errors", errors),
            F("requests", _results.Count),
            F("provider", W.Host().Provider),
            F("http", topHttp),
        };
        _results.Clear();
        W.Fire(DiagRules.TrErrors, cause, at, state);
    }
}
