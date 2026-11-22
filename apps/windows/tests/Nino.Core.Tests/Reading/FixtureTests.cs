// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using Nino.Core.Imaging;
using Nino.Core.Reading;

namespace Nino.Core.Tests.Reading;

/// <summary>
/// Gerçek GTA 6 karelerinden çıkarılmış okumalar (<c>Fixtures/&lt;ad&gt;.lines.txt</c>): her satır dört sayı (sol üst sağ
/// alt; karenin tamamına oran, nokta ondalık), bir sekme ve metin. Sekmesiz satırlar yok sayılır.
/// </summary>
public static class Fixtures
{
    /// <summary>Fixtures klasörü: çıktı klasöründe, yoksa çalışma klasöründen yukarı doğru aranır.</summary>
    public static string Folder
    {
        get
        {
            var output = Path.Combine(AppContext.BaseDirectory, "Fixtures");
            if (File.Exists(Path.Combine(output, "gta6-harita-buckme.lines.txt"))) return output;
            for (var dir = new DirectoryInfo(Directory.GetCurrentDirectory()); dir is not null; dir = dir.Parent)
            {
                var candidate = Path.Combine(dir.FullName, "Nino.Core.Tests", "Fixtures");
                if (File.Exists(Path.Combine(candidate, "gta6-harita-buckme.lines.txt"))) return candidate;
                candidate = Path.Combine(dir.FullName, "Fixtures");
                if (File.Exists(Path.Combine(candidate, "gta6-harita-buckme.lines.txt"))) return candidate;
            }
            throw new DirectoryNotFoundException("Fixtures klasörü bulunamadı");
        }
    }

    /// <summary>Okumayı yükler.</summary>
    public static OcrReading Load(string name)
    {
        var lines = new List<OcrLine>();
        foreach (var raw in File.ReadAllLines(Path.Combine(Folder, name + ".lines.txt")))
        {
            var tab = raw.IndexOf('\t');
            if (tab < 0) continue;
            var n = raw[..tab].Split(' ', StringSplitOptions.RemoveEmptyEntries)
                .Select(v => double.Parse(v, CultureInfo.InvariantCulture)).ToArray();
            lines.Add(new OcrLine(raw[(tab + 1)..], new Box(n[0], n[1], n[2], n[3])));
        }
        return new OcrReading(lines);
    }
}

public class FixtureTests
{
    [Fact]
    public void Loads()
    {
        var r = Fixtures.Load("gta6-harita-buckme");
        Assert.Equal("STORY", r.Lines[0].Text);
        Assert.Equal(0.0160, r.Lines[0].Box!.Value.Left, 9);
        Assert.Equal(7, Directory.GetFiles(Fixtures.Folder, "*.lines.txt").Length);
    }

    [Theory]
    [InlineData("gta6-harita-buckme", true)]
    [InlineData("gta6-altyazi-beyaz", false)]
    [InlineData("gta6-telefon-brian-parlama", false)]
    public void Gta6Signs(string name, bool gta)
    {
        // Harita ekranı kararı ve menü temizliği telefon/harita tarafının gerçek kuralları.
        var lines = Fixtures.Load(name).Lines.Select(l => l.Text).ToArray();
        Assert.Equal(gta, Gta6Markers.Detect(lines, l => Nino.Core.Phone.MapScreen.IsMapScreen(l), Nino.Core.Phone.MapScreen.CleanMenu));
    }

    [Fact]
    public void WhiteSubtitleFrameSelectsCenteredLine()
    {
        // Gerçek kare: sağda telefon mesajı, altta ortalı altyazı. Bölge (0,66–0,97 / 0,14–0,86) okunmuş gibi.
        var area = new Box(0.14, 0.66, 0.86, 0.97);
        var inArea = new OcrReading(Fixtures.Load("gta6-altyazi-beyaz").Lines
            .Where(l => l.Box!.Value.Top >= area.Top && l.Box.Value.Bottom <= area.Bottom)
            .Select(l => l with { Box = l.Box!.Value.RelativeTo(area) }));
        var block = LineLayout.SelectSubtitleBlock(LineLayout.MergeRows(inArea), area);
        Assert.Equal("Yeah, okay. Just wait, you're gonna love it, we're gonna have fun.", block.Text);
    }
}
