// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using Nino.Core.Health;

namespace Nino.Core.Support;

/// <summary>
/// Bildirim metni ("Nino'nun tespitleri"); sorun bildirme ve otomatik bildirim aynısını kurar. Sabit Türkçe öbekler
/// sunucu ve ekip içindir, çevrilmez; muhtemel sebebin başlığı ekran dilindedir.
/// </summary>
public static class ReportText
{
    public const string AutoHeader = "[Otomatik] Bu bildirimi Nino kendisi gönderdi; kullanıcının notu yok.";
    public const string SendProblemsHeader = "[Hata gönderimi] Kullanıcı not eklemedi; Nino'nun bulduklarını aşağıda bulabilirsiniz.";
    public const string FindingsTitle = "— Nino'nun bulguları —";

    /// <summary>Metne giren son sorunların yaşı.</summary>
    public static readonly TimeSpan RecentWindow = TimeSpan.FromDays(3);

    /// <summary>Metne giren en çok sorun.</summary>
    public const int MaxProblems = 12;

    /// <summary>Metni kurar (en çok 4000 UTF-16 birimi).</summary>
    /// <param name="automatic">Otomatik bildirim mi.</param>
    /// <param name="userText">Kullanıcının yazdığı (otomatikte yok sayılır).</param>
    /// <param name="causeTitle">Muhtemel sebebin ekran dilindeki başlığı.</param>
    /// <param name="problems">Kayıtlı sorunlar (eskiden yeniye); son 3 günün en çok son 12'si alınır.</param>
    /// <param name="summary">Sağlık özeti (<see cref="HealthSummary.Lines"/>).</param>
    /// <param name="now">Şimdi.</param>
    /// <param name="zone">Destek satırlarındaki yerel saat dilimi.</param>
    public static string Build(bool automatic, string? userText, string? causeTitle,
        IEnumerable<ProblemRecord> problems, IReadOnlyList<string> summary, DateTimeOffset now, TimeZoneInfo zone)
    {
        var written = (userText ?? "").Trim();
        var head = automatic ? AutoHeader : written.Length == 0 ? SendProblemsHeader : written;

        var findings = new StringBuilder(FindingsTitle);
        if (!string.IsNullOrWhiteSpace(causeTitle)) findings.Append("\nMuhtemel sebep: ").Append(causeTitle.Trim());
        var recent = problems.Where(p => p.Date >= now - RecentWindow).OrderBy(p => p.Date).ToList();
        if (recent.Count > MaxProblems) recent = recent[^MaxProblems..];
        if (recent.Count > 0)
        {
            findings.Append("\nYakın zamandaki sorunlar:\n");
            findings.AppendJoin('\n', recent.Select(p => "• " + p.SupportLine(zone)));
        }
        if (summary.Count > 0) findings.Append('\n').AppendJoin('\n', summary);

        return SupportLimits.Head(head + "\n\n" + findings, SupportLimits.Text);
    }
}
