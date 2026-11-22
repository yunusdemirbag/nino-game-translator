// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>Telefonda okunan bir mesaj ya da uygulama satırı (kutu kareye göre).</summary>
/// <param name="Text">Metin.</param>
/// <param name="Box">Kutu.</param>
/// <param name="LineHeight">Satır boyu.</param>
public sealed record PhoneMessage(string Text, Box Box, double LineHeight);

/// <summary>Bir telefon okumasından çıkan ekran: mesajlar, sohbet mi, başlık.</summary>
/// <param name="Messages">Çevrilecek mesajlar/satırlar (boşsa çevrilecek bir şey yok).</param>
/// <param name="IsChat">Sohbet ekranı mı (değilse uygulama satırları).</param>
/// <param name="Title">Sohbet başlığı (kırpılmış satır metni); yoksa null.</param>
public sealed record PhoneScreenContent(IReadOnlyList<PhoneMessage> Messages, bool IsChat, string? Title);

/// <summary>Telefon ekranının türü ve okumadan mesajların çıkarılması (sohbet, liste, uygulama).</summary>
public static class PhoneScreen
{
    static readonly HashSet<string> NavButtons = new(StringComparer.Ordinal)
    {
        "back", "geri", "done", "close", "cancel", "edit",
    };

    static readonly HashSet<string> LabelTexts = new(StringComparer.Ordinal)
    {
        "new message", "new messages", "typing", "delivered", "read", "today", "yesterday", "messages encrypted",
    };

    static readonly HashSet<string> AppNames = new(StringComparer.Ordinal) { "ryde", "rydeme", "buckme" };

    static readonly HashSet<string> SmallWords = new(StringComparer.Ordinal) { "del", "de", "la", "of", "the", "&" };

    /// <summary>Okumadan ekranın içeriği (§5.2 sırası).</summary>
    public static PhoneScreenContent Read(OcrReading reading, PhoneShape phone)
    {
        var isChatList = IsChatList(reading);
        var title = isChatList ? null : ChatTitle(reading, phone);
        var messages = title is { } t ? ChatMessages(reading, phone, t.Box) : [];
        messages = messages.Where(m => !PhoneText.IsSenderName(m.Text)).ToList();
        var chat = messages.Any(m => PhoneText.IsSentence(m.Text));
        if (chat) return new PhoneScreenContent(messages, true, title?.Text);
        if (IsMessageList(reading)) return new PhoneScreenContent([], false, null);
        return new PhoneScreenContent(AppLines(reading, phone), false, null);
    }

    static double ScreenHeight(PhoneShape phone) => phone.Box.Height;

    static double HeaderBottom(PhoneShape phone) => phone.Box.Top + ScreenHeight(phone) * 0.07;

    static double Indent(Box b, PhoneShape phone) => b.Left - phone.LeftAt(b.CenterY);

    static bool IsNavButton(string text) =>
        NavButtons.Contains(text.ToLowerInvariant().Trim('<', '‹', ' '));

    /// <summary>Sohbet başlığı (şartları sağlayan ilk satır); yoksa null.</summary>
    public static (string Text, Box Box)? ChatTitle(OcrReading reading, PhoneShape phone)
    {
        var boxed = reading.Lines.Where(l => l.Box is not null).ToArray();
        if (boxed.Length == 0) return null;
        var topmost = boxed.Min(l => l.Box!.Value.Top);
        foreach (var line in boxed)
        {
            var b = line.Box!.Value;
            if (!(b.Top < HeaderBottom(phone) || b.Top <= topmost + 0.002)) continue;
            var text = PhoneText.TrimSpaces(line.Text);
            if (!PhoneText.IsTitleLike(text) || IsNavButton(text)) continue;
            if (Math.Abs(b.CenterX - phone.CenterAt(b.CenterY)) >= phone.Width * 0.12) continue;
            var indent = Indent(b, phone);
            var hasPreview = boxed.Any(o => !ReferenceEquals(o, line)
                && o.Box!.Value.Top - b.Top > 0.008 && o.Box.Value.Top - b.Top < 0.05
                && Math.Abs(Indent(o.Box.Value, phone) - indent) < 0.015);
            if (hasPreview) continue;
            return (text, b);
        }
        return null;
    }

    /// <summary>Mesaj değil, etiket mi (<c>New message</c>, uygulama adı, ek olarak gönderilen yer adı…).</summary>
    public static bool IsLabel(string text)
    {
        var lower = text.ToLowerInvariant();
        if (LabelTexts.Contains(lower.Trim('.', '…', '•', ' '))) return true;
        if (lower.EndsWith("messages encrypted", StringComparison.Ordinal)
            || lower.EndsWith("message encrypted", StringComparison.Ordinal)) return true;
        if (AppNames.Contains(PhoneText.Key(text))) return true;
        var words = PhoneText.Words(text);
        return words.Length >= 2 && !text.Any(".,!?…".Contains)
            && words.All(w => PhoneText.StartsUpper(w) || SmallWords.Contains(w.ToLowerInvariant()));
    }

    /// <summary>Aynı satırdaki parçaları birleştirir (emoji satırı böler).</summary>
    static List<OcrLine> MergeRowFragments(IEnumerable<OcrLine> lines)
    {
        var added = new List<OcrLine>();
        foreach (var line in lines.OrderBy(l => l.Box?.Left ?? 0))
        {
            if (line.Box is not { } b)
            {
                added.Add(line);
                continue;
            }
            var index = added.FindIndex(o => o.Box is { } ob && Joins(ob, b));
            if (index < 0)
            {
                added.Add(line);
                continue;
            }
            var o = added[index];
            added[index] = o with { Text = o.Text + " " + line.Text, Box = o.Box!.Value.Union(b) };
        }
        return added;

        static bool Joins(Box o, Box b)
        {
            var small = Math.Min(o.Height, b.Height);
            if (small <= 0) return false;
            var overlap = Math.Min(o.Bottom, b.Bottom) - Math.Max(o.Top, b.Top);
            return overlap >= small * 0.75 && b.Left - o.Right <= 0.03 && b.Left > o.Right - 0.005;
        }
    }

    /// <summary>Sohbet mesajları (paragraflar; etiketler atılmış).</summary>
    public static List<PhoneMessage> ChatMessages(OcrReading reading, PhoneShape phone, Box? titleBox)
    {
        var bandBottom = Math.Max(HeaderBottom(phone), titleBox?.Bottom ?? 0);
        var rows = MergeRowFragments(reading.Lines)
            .Where(l => l.Box is { } b && PhoneText.LetterCount(PhoneText.TrimSpaces(l.Text)) >= 2
                && b.Top > bandBottom + 0.012 && b.Bottom < phone.Box.Bottom - 0.01)
            .OrderBy(l => l.Box!.Value.Top).ToList();

        var gaps = new List<double>();
        for (var i = 1; i < rows.Count; i++)
        {
            var d = rows[i].Box!.Value.Top - rows[i - 1].Box!.Value.Top;
            if (d >= 0.012 && d <= 0.04) gaps.Add(d);
        }
        var spacing = gaps.Count > 0 ? gaps.Min()
            : (rows.Count > 0 ? rows.Min(l => l.Box!.Value.Height) : 0.025) * 1.2;

        var messages = new List<PhoneMessage>();
        var group = new List<OcrLine>();
        void Flush()
        {
            if (group.Count == 0) return;
            var text = string.Join(" ", group.Select(l => PhoneText.TrimSpaces(l.Text)));
            var box = group.Select(l => l.Box!.Value).Aggregate((a, b) => a.Union(b));
            if (!IsLabel(text)) messages.Add(new PhoneMessage(text, box, spacing * 0.85));
            group.Clear();
        }
        foreach (var line in rows)
        {
            var b = line.Box!.Value;
            if (group.Count > 0)
            {
                var prev = group[^1].Box!.Value;
                var first = group[0].Box!.Value;
                if (!(b.Top - prev.Top < spacing * 1.6 && Math.Abs(Indent(b, phone) - Indent(first, phone)) < 0.02))
                    Flush();
            }
            group.Add(line);
        }
        Flush();
        return messages;
    }

    /// <summary>Sohbet listesi (ad + önizleme çiftleri ≥ 3).</summary>
    public static bool IsChatList(OcrReading reading)
    {
        var boxed = reading.Lines.Where(l => l.Box is not null).ToArray();
        var pairs = 0;
        for (var i = 0; i + 1 < boxed.Length; i++)
        {
            var a = boxed[i].Box!.Value;
            var b = boxed[i + 1].Box!.Value;
            if (PhoneText.IsListName(boxed[i].Text) && b.Top - a.Bottom < a.Height * 1.2
                && Math.Abs(b.Left - a.Left) < 0.03) pairs++;
        }
        return pairs >= 3;
    }

    /// <summary>Mesaj kartı listesi (≥ 3 satır ve ≥ 2 kişi adı ya da ≥ 2 üç noktayla biten satır).</summary>
    public static bool IsMessageCardList(OcrReading reading) =>
        reading.Lines.Count >= 3 && (reading.Lines.Count(l => PhoneText.IsPersonName(l.Text)) >= 2
            || reading.Lines.Count(l => PhoneText.EndsWithEllipsis(l.Text)) >= 2);

    /// <summary>Mesaj listesi (çevrilmez).</summary>
    public static bool IsMessageList(OcrReading reading) =>
        (IsMessageCardList(reading) && reading.Lines.Any(l => PhoneText.EndsWithEllipsis(l.Text))) || IsChatList(reading);

    /// <summary>Uygulama satırları (sohbet olmayan ekran).</summary>
    public static List<PhoneMessage> AppLines(OcrReading reading, PhoneShape phone)
    {
        var lines = new List<PhoneMessage>();
        foreach (var line in reading.Lines)
        {
            if (line.Box is not { } b) continue;
            var text = PhoneText.TrimSpaces(line.Text);
            var cut = 0;
            while (cut < text.Length && !(char.IsLetterOrDigit(text[cut]) || text[cut] is '$' or '€' or '£')) cut++;
            text = PhoneText.TrimSpaces(text[cut..]);
            var lower = text.ToLowerInvariant();
            if (lower.EndsWith("messages encrypted", StringComparison.Ordinal)
                || lower.EndsWith("message encrypted", StringComparison.Ordinal)) continue;
            if (PhoneText.LetterCount(text) < 3) continue;
            if (!(b.Top > HeaderBottom(phone) && b.Bottom < phone.Box.Bottom - 0.01)) continue;
            lines.Add(new PhoneMessage(text, b, b.Height * 0.85));
        }
        lines = lines.OrderBy(l => l.Box.Top).ToList();

        var merged = new List<PhoneMessage>();
        foreach (var line in lines)
        {
            if (merged.Count > 0)
            {
                var prev = merged[^1];
                var gap = line.Box.Top - prev.Box.Bottom;
                if (gap < line.LineHeight * 0.6 && Math.Abs(line.Box.Left - prev.Box.Left) < 0.02 && Continues(prev.Text, line.Text))
                {
                    merged[^1] = prev with { Text = prev.Text + " " + line.Text, Box = prev.Box.Union(line.Box) };
                    continue;
                }
            }
            merged.Add(line);
        }

        if (merged.Count > 0 && merged.All(l => IsCapsLabel(l.Text))) return [];
        return merged;

        static bool Continues(string previous, string next)
        {
            var lower = previous.ToLowerInvariant();
            var words = PhoneText.Words(previous).Count(PhoneText.HasLetter);
            if (lower.StartsWith("by ", StringComparison.Ordinal) && words <= 4) return false;
            if (PhoneText.StartsLower(next)) return true;
            return !PhoneText.EndsWithAny(previous, ".!?:") && words >= 3;
        }

        static bool IsCapsLabel(string text)
        {
            var letters = new string(text.Where(char.IsLetter).ToArray());
            return letters == letters.ToUpperInvariant() && PhoneText.Words(text).Length <= 3;
        }
    }
}
