// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Shell;

// Salon sahnesindeki fiş balonu (prizin üstündeki ipucu) ve ana ekranda Enter kısayolu. Mac'in ana ekranıyla aynı kurallar;
// hepsi saf (saat dışarıdan), testleri Nino.Shell.Tests/HomeHintTests.cs'te.

/// <summary>
/// Fiş balonunun görünürlüğü. Kullanıcı fişi hiç kullanmadıysa (ilk kurulumdan sonraki ilk açılış) balon hep görünür.
/// Sonra normalde soluktur; fare prize, fişe ya da balona gelince görünür, çıkınca 1 sn daha görünür kalır. Fiş takılıp
/// çıkarılınca (tık, sürükleme, Enter) 2 sn görünür.
/// </summary>
public sealed class PlugHintVisibility
{
    /// <summary>Soluk hâlin opaklığı (neredeyse görünmez, yine de sıfır değil).</summary>
    public const double FadedOpacity = 0.06;

    /// <summary>Fare çıktıktan sonra görünür kalma süresi.</summary>
    public static readonly TimeSpan HoverLinger = TimeSpan.FromSeconds(1);

    /// <summary>Fiş kullanılınca görünür kalma süresi.</summary>
    public static readonly TimeSpan UseFlash = TimeSpan.FromSeconds(2);

    /// <summary>Görünür olma geçişi.</summary>
    public static readonly TimeSpan FadeIn = TimeSpan.FromSeconds(0.2);

    /// <summary>Solma geçişi (biraz daha yavaş).</summary>
    public static readonly TimeSpan FadeOut = TimeSpan.FromSeconds(0.5);

    /// <param name="learned">Fiş en az bir kez kullanıldı mı (kalıcı bayrak).</param>
    public PlugHintVisibility(bool learned) => Learned = learned;

    /// <summary>Fiş en az bir kez kullanıldı mı.</summary>
    public bool Learned { get; private set; }

    /// <summary>Fare prizin, fişin ya da balonun üstünde mi.</summary>
    public bool Hovering { get; private set; }

    /// <summary>Bu ana kadar görünür (fare çıkışı ya da fiş kullanımı).</summary>
    public DateTimeOffset? VisibleUntil { get; private set; }

    /// <summary>Fare girdi/çıktı.</summary>
    public void HoverChanged(bool inside, DateTimeOffset now)
    {
        if (inside == Hovering) return;
        Hovering = inside;
        if (!inside) Extend(now + HoverLinger);
    }

    /// <summary>Fiş kullanıldı (takıldı ya da çıkarıldı; yalnız kurulumu açsa da).</summary>
    public void PlugUsed(DateTimeOffset now)
    {
        Learned = true;
        Extend(now + UseFlash);
    }

    /// <summary>Şu an görünür mü.</summary>
    public bool IsVisible(DateTimeOffset now)
    {
        if (!Learned || Hovering) return true;
        return VisibleUntil is { } until && now < until;
    }

    /// <summary>Görünürlüğün kendiliğinden değişeceği an (zamanlayıcı için); yoksa null.</summary>
    public DateTimeOffset? NextChange(DateTimeOffset now) =>
        Learned && !Hovering && VisibleUntil is { } until && until > now ? until : null;

    /// <summary>Opaklık: görünürse 1, değilse <see cref="FadedOpacity"/>.</summary>
    public double Opacity(DateTimeOffset now) => IsVisible(now) ? 1 : FadedOpacity;

    void Extend(DateTimeOffset until)
    {
        if (VisibleUntil is { } current && current > until) return;
        VisibleUntil = until;
    }
}

/// <summary>"Fiş bir kez kullanıldı" bayrağı: veri klasöründe küçük bir dosya (ayar dosyasına girmez).</summary>
public static class PlugHintFlag
{
    /// <summary>Bayrak dosyasının adı.</summary>
    public const string FileName = "plug-hint-learned";

    /// <summary>Bayrak okunur. Klasör yoksa (ekran dökümü, testler) kullanılmış sayılır: balon soluk başlar.</summary>
    public static bool Read(string? folder)
    {
        if (string.IsNullOrEmpty(folder)) return true;
        try { return File.Exists(Path.Combine(folder, FileName)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { return true; }
    }

    /// <summary>Bayrak yazılır (yazılamazsa sessizce geçer; bu açılışta bellekte kalır).</summary>
    public static void Write(string? folder)
    {
        if (string.IsNullOrEmpty(folder)) return;
        try
        {
            Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, FileName), "1");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { }
    }
}

/// <summary>Fiş balonunun metni (ilk uyan).</summary>
public static class PlugHintText
{
    /// <summary>
    /// Çeviri açık (ya da açılıyor) ve fiş takılıysa "kapatmak için çıkarın"; açık ama fiş henüz oturmadıysa balon yok;
    /// başlatılabiliyorsa "başlatmak için takın"; TV eksikse (Xbox ya da yakalama kartı TV'ye gönderiyorsa) önce TV'yi
    /// kurmaya; değilse önce PS5'i bağlamaya çağırır.
    /// </summary>
    /// <param name="active">Çeviri açık ya da açılıyor.</param>
    /// <param name="plugged">Fiş takılı görünüyor.</param>
    /// <param name="canStart">Çeviri başlatılabilir mi.</param>
    /// <param name="needsTvFirst">Eksik olan TV mi (Xbox ya da TV'ye giden yakalama kartı).</param>
    public static string? Key(bool active, bool plugged, bool canStart, bool needsTvFirst) =>
        active ? (plugged ? "home.plug.unplugToStop" : null)
        : canStart ? "home.plug.plugInToStart"
        : needsTvFirst ? "home.hint.connectTVFirst"
        : "home.hint.connectPS5First";
}

/// <summary>Fiş balonunun yeri: ok ucu ve balonun sığacağı kutu (sahneye ayrılan alanın biriminde).</summary>
/// <param name="ArrowTip">Okun ucu (prizi gösterir).</param>
/// <param name="Box">Balonun sığabileceği kutu; balon kutunun alt-sağ köşesine yaslanır.</param>
public readonly record struct PlugHintPlacement(ScenePoint ArrowTip, ScreenRect Box)
{
    /// <summary>Balonun en geniş hâli.</summary>
    public const double MaxWidth = 220;

    /// <summary>Okun boyu.</summary>
    public const double ArrowLength = 18;

    /// <summary>
    /// Sahne yalnız küçülür, ayrılan alanda ortalanır (genişliğe sehpayı ortalayan sola kaydırma eklenir). Ok ucu prizin
    /// kapağının hemen üstünde (54 sahne pikseli); balon okun üstünde, TV çerçevesinin sağ kenarını ve alanı aşmaz.
    /// Balonun yazısı ölçeklenmez; yalnız ok ucu sahneye bağlıdır.
    /// </summary>
    public static PlugHintPlacement Compute(LivingRoomScene scene, double width, double height,
        double maxWidth = MaxWidth, double arrowLength = ArrowLength)
    {
        var view = SceneView.Of(scene, width, height);
        var s = view.Scale;
        var socket = view.Point(scene.Socket);
        var tip = new ScenePoint(socket.X, socket.Y - 54 * s);
        var bottom = tip.Y - arrowLength - 2;
        var leftBound = Math.Max(4, view.Point(new ScenePoint(scene.Frame.Right, 0)).X + 10);
        var right = Math.Min(width - 4, Math.Max(socket.X + 70 * s + 24, leftBound + 60));
        var boxWidth = Math.Max(60, Math.Min(maxWidth, right - leftBound));
        var top = Math.Max(0, view.Point(new ScenePoint(0, scene.Frame.Y)).Y);
        return new PlugHintPlacement(tip, new ScreenRect(right - boxWidth, top, boxWidth, Math.Max(0, bottom - top)));
    }
}

/// <summary>Salon tuvalinin ayrılan alana yerleşimi (yalnız küçülür, ortalanır).</summary>
/// <param name="Scale">Ölçek (en çok 1).</param>
/// <param name="OriginX">Tuvalin sol kenarı.</param>
/// <param name="OriginY">Tuvalin üst kenarı.</param>
/// <param name="Shift">Görselin tuvaldeki sola kaydırması (sahne pikseli).</param>
public readonly record struct SceneView(double Scale, double OriginX, double OriginY, double Shift)
{
    /// <summary>Tuvalin genişliği: görsel + sehpayı ortalayan kaydırma.</summary>
    public static double CanvasWidth(LivingRoomScene scene) => LivingRoomScene.ImageWidth + scene.ShiftLeft;

    /// <summary>Ayrılan alandaki yerleşim.</summary>
    public static SceneView Of(LivingRoomScene scene, double width, double height)
    {
        var canvasWidth = CanvasWidth(scene);
        var scale = width <= 0 || height <= 0 ? 0
            : Math.Min(1, Math.Min(width / canvasWidth, height / LivingRoomScene.ImageHeight));
        return new SceneView(scale, (width - canvasWidth * scale) / 2, (height - LivingRoomScene.ImageHeight * scale) / 2,
            scene.ShiftLeft);
    }

    /// <summary>Sahne noktasının ayrılan alandaki yeri.</summary>
    public ScenePoint Point(ScenePoint scenePoint) =>
        new(OriginX + (Shift + scenePoint.X) * Scale, OriginY + scenePoint.Y * Scale);
}

/// <summary>
/// Ana ekranda Enter (ya da sayısal tuş takımındaki Enter) fişe tıklamakla aynıdır. Yalnız ana pencere öndeyken, ana ekran
/// görünürken (kurulum bitti), bir yazı alanı odakta değilken; değiştirici tuş yoksa ve basılı tutma tekrarı değilse.
/// Tuş başka işe gitmez. Ekranda Enter'dan söz eden bir yazı yoktur.
/// </summary>
public static class HomeReturnKey
{
    /// <summary>Tuş fişe gitmeli mi.</summary>
    /// <param name="isEnter">Basılan tuş Enter/Return.</param>
    /// <param name="hasModifiers">Ctrl, Alt, Shift ya da Windows tuşu basılı.</param>
    /// <param name="isRepeat">Basılı tutma tekrarı.</param>
    /// <param name="windowActive">Ana pencere öndeki pencere.</param>
    /// <param name="homeShowing">Ana ekran görünür (kurulum bitti).</param>
    /// <param name="textInputFocused">Odakta yazı alanı var.</param>
    /// <param name="alreadyHandled">Tuşu odaktaki öğe (ör. düğme) zaten işledi.</param>
    public static bool ShouldHandle(bool isEnter, bool hasModifiers, bool isRepeat, bool windowActive, bool homeShowing,
        bool textInputFocused, bool alreadyHandled) =>
        isEnter && !hasModifiers && !isRepeat && windowActive && homeShowing && !textInputFocused && !alreadyHandled;
}

/// <summary>
/// Oyun odası tabelasının yeri. Tabela açıkken sahnenin üstünde <see cref="TopSpace"/> kadar yer ayrılır, sahne kalan
/// alanda ortalanır; tabela TV çerçevesinin hemen üstünde, TV'ye göre ortalı, genişliği TV'nin yaklaşık %40'ı.
/// </summary>
/// <param name="TopSpace">Sahnenin üstünde ayrılan yükseklik.</param>
/// <param name="Box">Tabelanın sığacağı kutu (yazı bu kutuya oranı bozulmadan sığdırılır, alta ve ortaya yaslanır).</param>
public readonly record struct GameRoomSignPlacement(double TopSpace, ScreenRect Box)
{
    /// <summary>Ayrılan yer: alan yüksekliğinin %9'u, 30–96 arası.</summary>
    public static double SpaceFor(double height) => Math.Clamp(height * 0.09, 30, 96);

    /// <summary>TV ile tabela arası.</summary>
    public const double Gap = 6;

    /// <summary>Hesap (alan: sahneye ayrılan tüm genişlik ve yükseklik; tabela payı içinden düşülür).</summary>
    public static GameRoomSignPlacement Compute(LivingRoomScene scene, double width, double height)
    {
        var space = SpaceFor(height);
        var view = SceneView.Of(scene, width, Math.Max(0, height - space));
        var left = view.Point(new ScenePoint(scene.Frame.X, scene.Frame.Y));
        var right = view.Point(new ScenePoint(scene.Frame.Right, scene.Frame.Y));
        var tvTop = left.Y + space;
        var signWidth = (right.X - left.X) * Core.Design.GameRoomSign.WidthOfTv;
        var bottom = tvTop - Gap;
        var top = Math.Max(0, bottom - (space - Gap));
        var center = (left.X + right.X) / 2;
        return new GameRoomSignPlacement(space, new ScreenRect(center - signWidth / 2, top, Math.Max(0, signWidth), Math.Max(0, bottom - top)));
    }
}
