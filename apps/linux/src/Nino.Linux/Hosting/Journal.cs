// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Linux.Hosting;

/// <summary>
/// Sunucu günlüğü: her satır konsola gider (Docker'da <c>docker logs</c>) ve panelin "Günlük" bölümü için son
/// <see cref="Capacity"/> satır bellekte tutulur.
/// </summary>
public sealed class Journal
{
    public const int Capacity = 400;

    private readonly LinkedList<string> kept = new();
    private readonly object sync = new();
    private readonly TextWriter? console;
    private readonly Func<DateTime> clock;

    public Journal(TextWriter? console = null, Func<DateTime>? clock = null)
    {
        this.console = console;
        this.clock = clock ?? (() => DateTime.Now);
    }

    /// <summary>Uygulamanın her yerinden yazılan ortak günlük.</summary>
    public static Journal Shared { get; } = new(Console.Out);

    public void Write(string source, string message)
    {
        var line = $"[{clock():HH:mm:ss}] [{source}] {message}";
        console?.WriteLine(line);
        lock (sync)
        {
            kept.AddLast(line);
            if (kept.Count > Capacity) kept.RemoveFirst();
        }
    }

    public string[] Recent()
    {
        lock (sync) return [.. kept];
    }
}
