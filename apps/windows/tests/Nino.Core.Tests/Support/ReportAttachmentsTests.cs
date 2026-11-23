// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;
using Nino.Core.Support;

namespace Nino.Core.Tests.Support;

public sealed class ReportAttachmentsTests
{
    [Theory]
    [InlineData("a.txt", true, true)]
    [InlineData("A.LOG", true, true)]
    [InlineData("x.text", true, true)]
    [InlineData("p.PNG", false, true)]
    [InlineData("doc.pdf", false, false)]
    [InlineData("noext", false, false)]
    public void FileKinds(string name, bool text, bool accepted)
    {
        Assert.Equal(text, ReportAttachments.IsTextFile(name));
        Assert.Equal(accepted, ReportAttachments.IsAccepted(name));
    }

    [Fact]
    public void FilterHasImagesAndText()
    {
        Assert.Contains("*.png", ReportAttachments.FilterPattern);
        Assert.EndsWith("*.txt;*.log;*.text", ReportAttachments.FilterPattern);
    }

    [Fact]
    public void Decode()
    {
        Assert.Equal("çay", ReportAttachments.Decode(Encoding.UTF8.GetBytes("çay")));
        Assert.Equal("çay", ReportAttachments.Decode([0xEF, 0xBB, 0xBF, .. Encoding.UTF8.GetBytes("çay")]));
        Assert.Equal("hi", ReportAttachments.Decode([0xFF, 0xFE, .. Encoding.Unicode.GetBytes("hi")]));
        Assert.Equal("hi", ReportAttachments.Decode([0xFE, 0xFF, .. Encoding.BigEndianUnicode.GetBytes("hi")]));
        Assert.Equal("é", ReportAttachments.Decode([0xE9])); // geçersiz UTF-8 → Latin-1
        Assert.Null(ReportAttachments.Decode([0x41, 0x00, 0x42])); // ikili
    }

    [Fact]
    public void MergeLimits()
    {
        var existing = new List<ReportAttachment> { ReportAttachment.Image("1.jpg", [1]), ReportAttachment.Image("2.jpg", [1]) };
        var (list, limited) = ReportAttachments.Merge(existing,
            [ReportAttachment.Image("3.jpg", [1]), ReportAttachment.Image("4.jpg", [1]), ReportAttachment.TextFile("a.txt", "a")]);
        Assert.True(limited);
        Assert.Equal(["1.jpg", "2.jpg", "3.jpg", "a.txt"], list.Select(a => a.Name));

        var big = ReportAttachment.TextFile("big.txt", new string('x', ReportAttachments.MaxTotalBytes));
        Assert.True(ReportAttachments.Merge([ReportAttachment.TextFile("s.txt", "s")], [big]).Limited);
        Assert.True(ReportAttachments.Merge([], [ReportAttachment.Image("huge.jpg", new byte[ReportAttachments.MaxImageBytes + 1])]).Limited);

        var six = Enumerable.Range(0, 6).Select(i => ReportAttachment.TextFile($"{i}.txt", "t")).ToList();
        var merged = ReportAttachments.Merge([], six);
        Assert.Equal(ReportAttachments.MaxFiles, merged.Attachments.Count);
        Assert.True(merged.Limited);
    }

    [Fact]
    public void TextBlockAndLog()
    {
        Assert.Equal("", ReportAttachments.TextBlock([ReportAttachment.Image("a.jpg", [1])]));
        var block = ReportAttachments.TextBlock([ReportAttachment.TextFile("a.txt", "bir"), ReportAttachment.TextFile("b.log", "iki")]);
        Assert.Equal("— ek: a.txt —\nbir\n\n— ek: b.log —\niki", block);

        var longText = new string('a', 20_000) + "SON";
        var one = ReportAttachments.TextBlock([ReportAttachment.TextFile("l.txt", longText)]);
        Assert.EndsWith("SON", one);
        Assert.Equal("— ek: l.txt —\n".Length + ReportAttachments.MaxTextUnitsPerFile, one.Length);

        var three = ReportAttachments.TextBlock(Enumerable.Range(0, 3).Select(i => ReportAttachment.TextFile($"{i}.txt", longText)));
        Assert.Equal(ReportAttachments.MaxTextUnitsTotal, three.Length);

        Assert.Equal("log", ReportAttachments.AppendToLog("log", ""));
        Assert.Equal("blok", ReportAttachments.AppendToLog(null, "blok"));
        Assert.Equal("log\n\nblok", ReportAttachments.AppendToLog("log", "blok"));
    }

    [Fact]
    public void SecretsAreRemoved()
    {
        Assert.Equal("anahtar [gizlendi] burada", ReportAttachments.WithoutSecrets("anahtar abcd-1234 burada", ["abcd-1234", null, "ab"]));
        Assert.Equal("ab kısa", ReportAttachments.WithoutSecrets("ab kısa", ["ab"]));
    }
}
