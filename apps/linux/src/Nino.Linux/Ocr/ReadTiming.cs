// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Diagnostics;
using Nino.Linux.Hosting;

namespace Nino.Linux.Ocr;

/// <summary>
/// Gecikmenin nereden geldiği panel günlüğünden görülsün diye okuma süresini yazar; her kare değil, yalnız okunan
/// metin değiştiğinde bir satır.
/// </summary>
public sealed class ReadTiming
{
    private readonly Journal journal;
    private string previous = "";

    public ReadTiming(Journal journal) => this.journal = journal;

    public OcrReading Measure(Func<OcrReading> read, bool deep)
    {
        var clock = Stopwatch.StartNew();
        var reading = read();
        var flat = reading.Text.ReplaceLineEndings(" ").Trim();
        if (flat != previous)
        {
            previous = flat;
            journal.Write("okuma", $"{clock.ElapsedMilliseconds} ms{(deep ? ", derin" : "")} → {(flat.Length == 0 ? "—" : flat)}");
        }
        return reading;
    }
}
