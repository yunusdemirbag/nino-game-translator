// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;
using Nino.Shell.Platform;

namespace Nino.Shell;

/// <summary>Ekrandaki bir dikdörtgen (WPF birimi ya da piksel).</summary>
public readonly record struct ScreenRect(double X, double Y, double Width, double Height)
{
    /// <summary>Sağ kenar.</summary>
    public double Right => X + Width;

    /// <summary>Alt kenar.</summary>
    public double Bottom => Y + Height;
}

/// <summary>Bilgisayardaki altyazı penceresinin yeri (saf hesap, tarif §14.1).</summary>
public static class OverlayLayout
{
    /// <summary>En dar pencere.</summary>
    public const double MinWidth = 320;

    /// <summary>Varsayılan yazı boyu.</summary>
    public const int DefaultFontSize = 46;

    /// <summary>Ölçek = birincil ekran yüksekliği / 1080, 0,5–4 arası; okunamazsa 1.</summary>
    public static double Scale(double primaryHeight) =>
        double.IsFinite(primaryHeight) && primaryHeight > 0 ? Math.Clamp(primaryHeight / 1080, 0.5, 4) : 1;

    /// <summary>Yazı boyu: ≤0 ise 46, değilse 12–200.</summary>
    public static int FontSize(int size) => size <= 0 ? DefaultFontSize : Math.Clamp(size, 12, 200);

    /// <summary>Pencere yüksekliği (üç satır ve kayma payı).</summary>
    public static double Height(int fontSize, double scale) =>
        Math.Round(FontSize(fontSize) * scale * 8.1 + 140 * scale, MidpointRounding.AwayFromZero);

    static double TotalWidth(IReadOnlyList<ScreenRect> screens) =>
        screens.Count == 0 ? double.PositiveInfinity : screens.Max(s => s.Right) - screens.Min(s => s.X);

    /// <summary>Pencerenin yeri ve genişliği.</summary>
    /// <param name="saved">Kayıtlı yer (yoksa null).</param>
    /// <param name="height">Pencere yüksekliği (bozuksa varsayılan yazı boyuyla hesaplanır).</param>
    /// <param name="screens">Bütün ekranlar.</param>
    /// <param name="workArea">Birincil ekranın çalışma alanı (okunamazsa null).</param>
    /// <param name="scale">Ölçek (bozuk yükseklik için).</param>
    public static ScreenRect Place(OverlayPlacement? saved, double height, IReadOnlyList<ScreenRect> screens,
        ScreenRect? workArea, double scale = 1)
    {
        if (!double.IsFinite(height) || height <= 0) height = Height(DefaultFontSize, scale);
        if (saved is { } s && double.IsFinite(s.Left) && double.IsFinite(s.Top) && double.IsFinite(s.Width) && s.Width > 0)
        {
            var width = Math.Clamp(s.Width, MinWidth, Math.Max(MinWidth, TotalWidth(screens)));
            foreach (var screen in screens)
            {
                var horizontal = Math.Min(s.Left + width, screen.Right) - Math.Max(s.Left, screen.X);
                var vertical = Math.Min(s.Top + height, screen.Bottom) - Math.Max(s.Top, screen.Y);
                if (horizontal >= Math.Min(80, width) && vertical >= Math.Min(80, height))
                    return new ScreenRect(s.Left, s.Top, width, height);
            }
        }
        var area = workArea ?? (screens.Count > 0
            ? new ScreenRect(screens.Min(x => x.X), screens.Min(x => x.Y), TotalWidth(screens),
                screens.Max(x => x.Bottom) - screens.Min(x => x.Y))
            : new ScreenRect(0, 0, 1280, 720));
        var w = Math.Max(MinWidth, Math.Round(area.Width * 0.7, MidpointRounding.AwayFromZero));
        return new ScreenRect(area.X + (area.Width - w) / 2, area.Bottom - area.Height * 0.04 - height, w, height);
    }

    /// <summary>Genişletirken: 320 ile bütün ekranlar genişliği arası; bozuk genişlik 320.</summary>
    public static double ResizeWidth(double width, IReadOnlyList<ScreenRect> screens) =>
        !double.IsFinite(width) || width <= 0 ? MinWidth : Math.Clamp(width, MinWidth, Math.Max(MinWidth, TotalWidth(screens)));

    /// <summary>Kaydedilecek yer: üçü sonlu ve genişlik &gt; 0 ise yuvarlanmış; değilse null.</summary>
    public static OverlayPlacement? ToSave(double left, double top, double width) =>
        double.IsFinite(left) && double.IsFinite(top) && double.IsFinite(width) && width > 0
            ? new OverlayPlacement
            {
                Left = Math.Round(left, MidpointRounding.AwayFromZero),
                Top = Math.Round(top, MidpointRounding.AwayFromZero),
                Width = Math.Round(width, MidpointRounding.AwayFromZero),
            }
            : null;
}

/// <summary>Görünür bir pencerenin içerik alanı. <paramref name="ClassName"/>: pencere sınıfı (bilinmiyorsa boş).</summary>
public sealed record WindowCandidate(string ProcessName, string Title, int Width, int Height, string ClassName = "");

/// <summary>Oyunun penceresi kuralları (saf, tarif §14.2).</summary>
public static class GameWindowRules
{
    static readonly string[] Ps5Parts = ["remoteplay", "remote play", "chiaki"];
    static readonly string[] Browsers = ["chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc"];

    // Windows'taki Xbox uygulamasının süreç adları (boşluksuz, küçük harf). "xbox" alt dizgesi aranmaz: Game Bar ve
    // Xbox hizmetleri de "xbox" içerir.
    static readonly HashSet<string> XboxProcesses = new(StringComparer.Ordinal)
    {
        "xboxpcapp", "xboxapp", "xbox", "gamingapp", "microsoftgamingapp", "xboxapplication",
    };

    /// <summary>UWP uygulamalarını barındıran süreç ve çerçeve penceresinin sınıfı.</summary>
    public const string FrameHostProcess = "ApplicationFrameHost", FrameWindowClass = "ApplicationFrameWindow";

    // Xbox uygulamasındaki uzaktan oynatma penceresinin başlıkları, birkaç dilde (aksansız, küçük harf, tire boşluk).
    static readonly string[] RemotePlayTitles =
    [
        "remote play", "remoteplay", "uzaktan oynat", "uzaktan oyna", "lecture a distance", "jeu a distance",
        "reproduccion remota", "juego remoto", "juego a distancia", "riproduzione remota", "gioco remoto", "remotespiel",
        "remote spiel", "jogo remoto", "reproducao remota", "op afstand spelen", "extern spelen", "zdalne granie",
        "gra zdalna", "удаленная игра", "дистанционная игра", "التشغيل عن بعد", "اللعب عن بعد", "リモートプレイ",
        "원격 플레이", "远程游玩", "远程游戏", "遠端遊玩", "bermain jarak jauh", "permainan jauh", "choi tu xa",
        "เล่นระยะไกล", "दूरस्थ खेल", "রিমোট প্লে",
    ];

    /// <summary>Pencere en az bu kadar olmalı.</summary>
    public const int MinWidth = 320, MinHeight = 180;

    /// <summary>Aksansız, küçük harf, tire ve alt çizgi boşluk; Türkçe ı → i.</summary>
    public static string Fold(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var lower = text.ToLowerInvariant().Replace('ı', 'i').Replace('-', ' ').Replace('_', ' ');
        var decomposed = lower.Normalize(System.Text.NormalizationForm.FormD);
        var sb = new System.Text.StringBuilder(decomposed.Length);
        foreach (var ch in decomposed)
            if (System.Globalization.CharUnicodeInfo.GetUnicodeCategory(ch) != System.Globalization.UnicodeCategory.NonSpacingMark)
                sb.Append(ch);
        return sb.ToString().Normalize(System.Text.NormalizationForm.FormC);
    }

    static string ProcessKey(string process) => Fold(process).Replace(" ", "").Replace(".exe", "");

    /// <summary>Süreç Xbox uygulamasının kendisi mi (Game Bar değil).</summary>
    public static bool IsXboxProcess(string process)
    {
        var key = ProcessKey(process);
        return !key.Contains("gamebar") && XboxProcesses.Contains(key);
    }

    /// <summary>Başlık "uzaktan oynatma" anlamına gelen bir söz içeriyor mu (birkaç dilde).</summary>
    public static bool HasRemotePlayTitle(string title)
    {
        var t = Fold(title);
        return RemotePlayTitles.Any(t.Contains);
    }

    static bool IsGameBar(string process, string title) =>
        ProcessKey(process).Contains("gamebar") || Fold(title).Contains("game bar");

    // UWP çerçevesi (ApplicationFrameHost'un penceresi; süreç adı çerçeve ya da çözülmüş içerik süreci olabilir).
    static bool IsFramedXbox(string process, string title, string className) =>
        string.Equals(className, FrameWindowClass, StringComparison.OrdinalIgnoreCase) && Fold(title).Contains("xbox")
        && !IsGameBar(process, title);

    /// <summary>PS5 penceresi mi (Xbox uygulamasının "Remote Play" başlıklı penceresi sayılmaz).</summary>
    public static bool IsPs5Window(string process, string title, string className = "")
    {
        if (IsXboxProcess(process) || IsFramedXbox(process, title, className)) return false;
        var text = (process + " " + title).ToLowerInvariant();
        return Ps5Parts.Any(text.Contains);
    }

    static bool IsBrowser(string process) => Browsers.Contains(process.Trim().ToLowerInvariant());

    /// <summary>
    /// Xbox penceresi mi: Xbox uygulaması (XboxPcApp, Xbox, Gaming App…; başlıktan bağımsız), Greenlight, UWP çerçevesinde
    /// barındırılan Xbox penceresi (sınıf ApplicationFrameWindow, başlıkta Xbox) ya da başlığında "xbox" geçen tarayıcı
    /// (xbox.com/play). Xbox Game Bar sayılmaz.
    /// </summary>
    public static bool IsXboxWindow(string process, string title, string className = "")
    {
        if (IsGameBar(process, title)) return false;
        var p = process.ToLowerInvariant();
        return IsXboxProcess(process) || p.Contains("greenlight") || IsFramedXbox(process, title, className)
            || (IsBrowser(process) && title.Contains("xbox", StringComparison.OrdinalIgnoreCase));
    }

    static bool Matches(WindowCandidate w, GameConsole console) => console == GameConsole.Xbox
        ? IsXboxWindow(w.ProcessName, w.Title, w.ClassName)
        : IsPs5Window(w.ProcessName, w.Title, w.ClassName);

    /// <summary>
    /// Konsola uyan en büyük pencere. Xbox'ta başlığı "uzaktan oynatma" diyen Xbox uygulaması penceresi öne alınır
    /// (kütüphane penceresi de açıksa).
    /// </summary>
    public static WindowCandidate? Pick(IEnumerable<WindowCandidate> windows, GameConsole console) =>
        windows.Where(w => w.Width >= MinWidth && w.Height >= MinHeight)
            .Where(w => Matches(w, console))
            .OrderByDescending(w => console == GameConsole.Xbox && !IsBrowser(w.ProcessName) && HasRemotePlayTitle(w.Title))
            .ThenByDescending(w => (long)w.Width * w.Height)
            .FirstOrDefault();

    /// <summary>Gösterilen uygulama adı.</summary>
    public static string DisplayName(string process, string title, string className = "")
    {
        var p = process.ToLowerInvariant();
        if (p.Contains("chiaki")) return "chiaki-ng";
        if (p.Contains("greenlight")) return "Greenlight";
        if (IsXboxProcess(process) || IsFramedXbox(process, title, className)) return "Xbox";
        if (IsBrowser(process)) return "xbox.com/play";
        return "PS Remote Play";
    }

    /// <summary>İçerik alanında ortalanmış 16:9 oyun alanı.</summary>
    public static PixelRect GameArea(int width, int height)
    {
        if (width <= 0 || height <= 0) return new PixelRect(0, 0, Math.Max(0, width), Math.Max(0, height));
        double w = width, h = width * 9.0 / 16;
        if (h > height)
        {
            h = height;
            w = height * 16.0 / 9;
        }
        var x = (width - w) / 2;
        var y = (height - h) / 2;
        return new PixelRect((int)Math.Round(x), (int)Math.Round(y), (int)Math.Round(w), (int)Math.Round(h));
    }

    /// <summary>Altyazı penceresi oyun alanının üstünde: genişlik %90, alt kenar oyunun altından yüksekliğin %3'ü yukarıda.</summary>
    public static ScreenRect OverlayOverGame(ScreenRect game, double overlayHeight) =>
        new(game.X + game.Width * 0.05, game.Bottom - game.Height * 0.03 - overlayHeight, game.Width * 0.9, overlayHeight);
}

/// <summary>2B nokta.</summary>
public readonly record struct ScenePoint(double X, double Y);

/// <summary>Salon sahnesinin bir düzeni (görsel 1672×941).</summary>
public sealed record LivingRoomScene(
    string Image, ScreenRect Screen, ScreenRect Frame, ScreenRect Table, ScenePoint Socket, ScenePoint CableHead,
    IReadOnlyList<ScenePoint> CablePath, ScenePoint Exit, ScenePoint PlugRest)
{
    /// <summary>Görsel boyu.</summary>
    public const double ImageWidth = 1672, ImageHeight = 941;

    /// <summary>Mantıksal TV ekranının genişliği.</summary>
    public const double LogicalScreenWidth = 588;

    /// <summary>Fiş prize bu kadar kala tam döner.</summary>
    public const double FullTurnDistance = 120;

    /// <summary>Kablonun serbest boyu ve kalınlığı; priz kenarı.</summary>
    public const double CableLength = 330, CableThickness = 8, SocketSize = 86;

    /// <summary>PS5 sahnesi.</summary>
    public static LivingRoomScene Ps5 { get; } = new("living-room.png",
        new(149, 40, 1151, 595), new(139, 27, 1171, 621), new(49, 713, 1502, 160), new(1564, 378), new(1550, 734),
        [new(1490, 706), new(1522, 706), new(1535, 709), new(1545, 716), new(1552, 727)], new(0.5, 0.87), new(1600, 885));

    /// <summary>Xbox sahnesi.</summary>
    public static LivingRoomScene Xbox { get; } = new("living-room-xbox.png",
        new(136, 40, 1185, 596), new(121, 26, 1214, 630), new(43, 733, 1580, 167), new(1561, 381), new(1572, 722),
        [], new(1, 0.1), new(1646, 912));

    /// <summary>Sola kaydırma.</summary>
    public double ShiftLeft => Math.Max(0, 2 * (ImageWidth / 2 - (Table.X + Table.Width / 2)));

    /// <summary>Ekran büyütmesi.</summary>
    public double ScreenScale => Screen.Width / LogicalScreenWidth;

    static double Distance(ScenePoint a, ScenePoint b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));

    /// <summary>Fişin dönüşü (radyan; 0 aşağı).</summary>
    public double PlugRotation(ScenePoint plug)
    {
        var rest = Distance(PlugRest, Socket);
        var at = Distance(plug, Socket);
        if (rest <= FullTurnDistance || at <= 1) return 0;
        var t = Math.Clamp((rest - at) / (rest - FullTurnDistance), 0, 1);
        var smooth = t * t * (3 - 2 * t);
        var target = Math.Atan2(-(Socket.X - plug.X), Socket.Y - plug.Y);
        return smooth * target;
    }

    /// <summary>Kablonun eğrisi: başlangıç, iki denetim noktası, uç.</summary>
    public (ScenePoint Start, ScenePoint Control1, ScenePoint Control2, ScenePoint End) Cable(ScenePoint plug, bool plugged)
    {
        var start = CablePath.Count > 0 ? CablePath[^1] : CableHead;
        if (plugged)
        {
            var end = new ScenePoint(plug.X, plug.Y + 30);
            return (start, new(start.X + Exit.X * 90, start.Y + Exit.Y * 90), new(end.X + 10, end.Y + 170), end);
        }
        var theta = PlugRotation(plug);
        var tip = new ScenePoint(-Math.Sin(theta), Math.Cos(theta));
        var back = new ScenePoint(plug.X - tip.X * 40, plug.Y - tip.Y * 40);
        var sag = Math.Max(0, CableLength - Distance(back, start)) * 0.45;
        return (start, new(start.X + Exit.X * 70, start.Y + Exit.Y * 70 + sag),
            new(back.X - tip.X * 80, back.Y - tip.Y * 80 + sag), back);
    }
}

/// <summary>Yayıncı penceresinin zemin rengi.</summary>
public static class StreamBackgroundColors
{
    /// <summary>RGB (0xRRGGBB).</summary>
    public static int Rgb(StreamBackground background) => background switch
    {
        StreamBackground.Black => 0x000000,
        StreamBackground.Magenta => 0xFF00FF,
        _ => 0x00FF00,
    };

    /// <summary>Düz zeminde kutu ya tam koyu ya hiç: arka plan yüzdesi &gt; 0 ise 1, değilse 0.</summary>
    public static double BoxOpacity(int backgroundPercent) => backgroundPercent > 0 ? 1 : 0;
}
