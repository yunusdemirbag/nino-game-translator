// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Nino.Core.Support;

/// <summary>Cevap bloğunun türü.</summary>
public enum ReplyBlockKind
{
    Paragraph,
    Step,
    Bullet,
}

/// <summary>Satır içi parça: düz yazı ya da bağlantı (<see cref="Link"/> doluysa).</summary>
public sealed record ReplyInline(string Text, Uri? Link = null);

/// <summary>Cevabın bir bloğu: paragraf, numaralı adım ya da madde.</summary>
public sealed record ReplyBlock(ReplyBlockKind Kind, string Text, int Number = 0)
{
    /// <summary>Yazının düz yazı ve bağlantı parçaları.</summary>
    public IReadOnlyList<ReplyInline> Inlines => ReplyBlocks.SplitLinks(Text);
}

/// <summary>
/// Nino'nun cevabını bloklara ayırır (Mac, iPhone ve Android ile aynı kurallar): boş satır bloğu kapatır; 1–2 rakam +
/// <c>.</c>/<c>)</c> + boşluk adım; <c>-</c>/<c>•</c>/<c>*</c> + boşluk madde; diğer satırlar paragrafa ya da (girintiliyse)
/// açık bloğa eklenir. Yalnız http/https mutlak adresler bağlantı olur.
/// </summary>
public static partial class ReplyBlocks
{
    [GeneratedRegex(@"^\s*(\d{1,2})[.)]\s+(\S.*)$")]
    private static partial Regex StepLine();

    [GeneratedRegex(@"^\s*[-•*]\s+(\S.*)$")]
    private static partial Regex BulletLine();

    [GeneratedRegex(@"https?://[^\s<>""')\]]+", RegexOptions.IgnoreCase)]
    private static partial Regex LinkPattern();

    /// <summary>Bloklar.</summary>
    public static IReadOnlyList<ReplyBlock> Parse(string? text)
    {
        var builder = new Builder();
        foreach (var row in (text ?? "").Split(LineEnds, StringSplitOptions.None)) builder.Feed(row);
        return builder.Finish();
    }

    // "\r\n" önce denenir; tek "\r" de satır sonudur.
    static readonly string[] LineEnds = ["\r\n", "\r", "\n"];

    /// <summary>Açık bloğu tutan küçük durum makinesi.</summary>
    sealed class Builder
    {
        readonly List<ReplyBlock> _done = [];
        readonly StringBuilder _text = new();
        ReplyBlockKind? _open;
        int _number;

        public void Feed(string row)
        {
            var content = row.Trim();
            if (content.Length == 0)
            {
                Flush();
                return;
            }

            var step = StepLine().Match(row);
            if (step.Success)
            {
                Start(ReplyBlockKind.Step, step.Groups[2].Value.Trim(),
                    int.Parse(step.Groups[1].Value, CultureInfo.InvariantCulture));
                return;
            }

            var bullet = BulletLine().Match(row);
            if (bullet.Success)
            {
                Start(ReplyBlockKind.Bullet, bullet.Groups[1].Value.Trim(), 0);
                return;
            }

            if (Continues(row)) _text.Append('\n').Append(content);
            else Start(ReplyBlockKind.Paragraph, content, 0);
        }

        // Paragraf her düz satırı alır; adım ve madde yalnız girintili satırı.
        bool Continues(string row)
        {
            if (_open is null) return false;
            return _open == ReplyBlockKind.Paragraph || row.StartsWith(' ') || row.StartsWith('\t');
        }

        void Start(ReplyBlockKind kind, string first, int number)
        {
            Flush();
            _open = kind;
            _number = number;
            _text.Append(first);
        }

        void Flush()
        {
            if (_open.HasValue) _done.Add(new ReplyBlock(_open.Value, _text.ToString(), _number));
            _open = null;
            _number = 0;
            _text.Clear();
        }

        public List<ReplyBlock> Finish()
        {
            Flush();
            return _done;
        }
    }

    /// <summary>Yazıyı düz yazı ve bağlantı parçalarına ayırır; sondaki <c>. , ; : ! ?</c> bağlantıya girmez.</summary>
    public static IReadOnlyList<ReplyInline> SplitLinks(string text)
    {
        var result = new List<ReplyInline>();
        var plainFrom = 0;
        foreach (Match candidate in LinkPattern().Matches(text))
        {
            var address = candidate.Value.TrimEnd(TrailingPunctuation);
            var link = WebAddress(address);
            if (link is null) continue;

            if (candidate.Index > plainFrom) result.Add(new ReplyInline(text[plainFrom..candidate.Index]));
            result.Add(new ReplyInline(address, link));
            plainFrom = candidate.Index + address.Length;
        }
        if (plainFrom < text.Length) result.Add(new ReplyInline(text[plainFrom..]));
        return result;
    }

    static readonly char[] TrailingPunctuation = ['.', ',', ';', ':', '!', '?'];

    // Yalnız sunucusu olan mutlak http/https adresi.
    static Uri? WebAddress(string address)
    {
        if (!Uri.TryCreate(address, UriKind.Absolute, out var parsed)) return null;
        var web = parsed.Scheme == Uri.UriSchemeHttps || parsed.Scheme == Uri.UriSchemeHttp;
        return web && parsed.Host.Length > 0 ? parsed : null;
    }
}
