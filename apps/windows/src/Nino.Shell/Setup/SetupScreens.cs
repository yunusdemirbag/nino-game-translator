// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Text;
using Nino.Core.Tv;

namespace Nino.Shell.Setup;

// Kurulum sihirbazının ekranlarındaki saf hesaplar (kurulum.md §1, §8, §12; tv-kurulum.md §3.5, §5.8, §10.3).
// Windows (WPF) ve Linux paneli aynı kuralları kullanır; metinler katalogdan gelir, burada platform yok.

/// <summary>Sol listedeki bir adım satırının işareti.</summary>
public enum StepMark
{
    /// <summary>Tamamlandı (sırası şimdikinden küçük): success daire, onay simgesi.</summary>
    Done,

    /// <summary>Şimdiki adım: accent daire, numara, yarı kalın ad, surface2 zemin.</summary>
    Current,

    /// <summary>Sıradaki: border daire, numara, textSecondary.</summary>
    Upcoming,
}

/// <summary>Sol listedeki bir satır.</summary>
/// <param name="Step">Adım.</param>
/// <param name="Number">Gösterilen numara (1'den).</param>
/// <param name="Name">Adın metni.</param>
/// <param name="Mark">İşaret.</param>
/// <param name="AccessibleName">Ekran okuyucu adı ("numara. ad").</param>
public sealed record SetupStepRow(SetupStep Step, int Number, string Name, StepMark Mark, string AccessibleName);

/// <summary>Sihirbazın sol adım listesi (kurulum.md §1.1–§1.2).</summary>
public static class SetupSidebar
{
    static readonly SetupStep[] All =
    [
        SetupStep.Welcome, SetupStep.SecondAccount, SetupStep.PsnSignIn, SetupStep.Console, SetupStep.Tv,
        SetupStep.Model, SetupStep.Test, SetupStep.BetterTranslation,
    ];

    /// <summary>Listedeki adımlar, sırasıyla (Xbox'ta İkinci hesap yok).</summary>
    public static IReadOnlyList<SetupStep> Steps(bool xbox) =>
        xbox ? All.Where(s => s != SetupStep.SecondAccount).ToArray() : All;

    /// <summary>Adımın listedeki adının anahtarı (Xbox'ta giriş ve konsol adları farklı).</summary>
    public static string NameKey(SetupStep step, bool xbox) => step switch
    {
        SetupStep.Welcome => "setup.welcome.title",
        SetupStep.SecondAccount => "setup.psnAccount.title",
        SetupStep.PsnSignIn => xbox ? "setup.steps.signInXbox" : "setup.psnSignIn.title",
        SetupStep.Console => xbox ? "setup.steps.consoleXbox" : "home.toggle.connectPs5",
        SetupStep.Tv => "setup.tv.title",
        SetupStep.Model => "setup.model.title",
        SetupStep.Test => "setup.try.title",
        _ => "setup.better.title",
    };

    /// <summary>Satırlar: şimdikinden küçük sıradakiler tamamlanmış, şimdiki, sonrakiler sıradaki.</summary>
    public static IReadOnlyList<SetupStepRow> Rows(SetupStep current, bool xbox, ITextSource text)
    {
        var steps = Steps(xbox);
        var rows = new List<SetupStepRow>(steps.Count);
        for (var i = 0; i < steps.Count; i++)
        {
            var step = steps[i];
            var mark = step < current ? StepMark.Done : step == current ? StepMark.Current : StepMark.Upcoming;
            var name = text.Get(NameKey(step, xbox));
            rows.Add(new SetupStepRow(step, i + 1, name, mark, text.Format("setup.stepRow.accessibility", i + 1, name)));
        }
        return rows;
    }

    /// <summary>Sayaç: "Adım X / Y".</summary>
    public static string Counter(int number, int count, ITextSource text) => text.Format("setup.stepCounter", number, count);
}

/// <summary>Adım alanının altındaki Geri/Devam düğmelerinin durumu (kurulum.md §1.3).</summary>
/// <param name="BackVisible">Geri görünür mü (gizliyken yeri korunur).</param>
/// <param name="ContinueVisible">Devam görünür mü (gizliyken yeri korunur).</param>
/// <param name="ContinueKey">Devam düğmesinin metin anahtarı.</param>
/// <param name="ContinuePrimary">Birincil görünüm mü (değilse ikincil).</param>
/// <param name="ContinueIsDefault">Varsayılan düğme mi (Enter basar).</param>
public sealed record WizardButtons(bool BackVisible, bool ContinueVisible, string ContinueKey, bool ContinuePrimary,
    bool ContinueIsDefault)
{
    /// <summary>Adıma ve "ücretsiz Gemini kullanılıyor mu"ya göre.</summary>
    public static WizardButtons For(SetupStep step, bool usingFreeGemini)
    {
        var back = step != SetupStep.Welcome;
        var visible = step != SetupStep.Test;
        if (step == SetupStep.BetterTranslation && !usingFreeGemini)
            return new WizardButtons(back, visible, "setup.skipForNow", false, false);
        return new WizardButtons(back, visible, "common.continue", true, true);
    }
}

/// <summary>Microsoft cihaz kodu bağlantısının yazısı (kurulum.md §5).</summary>
public static class MicrosoftLink
{
    /// <summary>Ana makine ("www." atılmış) + yol (sondaki "/" atılmış); ör. "microsoft.com/link".</summary>
    public static string Display(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return "";
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri)) return url.Trim();
        var host = uri.Host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? uri.Host[4..] : uri.Host;
        var path = uri.AbsolutePath.TrimEnd('/');
        return host + path;
    }
}

/// <summary>TV eşleşmesinin hata metni (tv-kurulum.md §3.5).</summary>
public static class TvPairText
{
    /// <summary>
    /// Denenen TV'nin markası ve denetleyicinin hata metninden (<c>TvPairError</c>: TV'nin kısa sebebi ya da hata türü)
    /// kullanıcı metni. <paramref name="timedOut"/>: eşleşme iptalle bitti (Samsung'un 60 saniyelik beklemesi).
    /// </summary>
    public static string Describe(TvBrand brand, string? error, bool timedOut, ITextSource text)
    {
        var reason = error?.Trim() ?? "";
        var noResponse = text.Get("tv.pair.error.noResponse");
        switch (brand)
        {
            case TvBrand.Samsung:
                if (reason.Equals("rejected", StringComparison.OrdinalIgnoreCase)) return text.Get("tv.pair.error.samsungRejected");
                if (timedOut || reason.Equals("cannot connect", StringComparison.OrdinalIgnoreCase)
                    || reason.Equals("timeout", StringComparison.OrdinalIgnoreCase))
                    return text.Get("tv.pair.error.samsungTimeout");
                return noResponse;
            case TvBrand.Lg:
                if (reason.Length > 0 && !reason.Equals("cannot connect", StringComparison.OrdinalIgnoreCase))
                    return $"{noResponse} ({reason})";
                return noResponse;
            default:
                return noResponse;
        }
    }
}

/// <summary>TV uygulaması kartının görünüşü (kurulum.md §8.1, tv-kurulum.md §5.8).</summary>
/// <param name="Visible">Kart görünür mü (durum "bilinmiyor" değilse).</param>
/// <param name="Status">Durum yazısı (boş olabilir).</param>
/// <param name="Detail">Ayrıntı ipucu (boşsa gizli).</param>
/// <param name="LgSteps">LG adımları.</param>
/// <param name="SamsungSteps">Samsung adımları.</param>
/// <param name="AndroidSteps">Android adımları.</param>
/// <param name="Passphrase">Parola bölümü.</param>
/// <param name="Reopen">"Sayfayı yeniden aç" bölümü.</param>
/// <param name="Problem">Sorun yazısı (boşsa gizli).</param>
/// <param name="Retry">"Tekrar Dene" görünür mü.</param>
public sealed record TvAppCardView(bool Visible, string Status, string Detail, bool LgSteps, bool SamsungSteps,
    bool AndroidSteps, bool Passphrase, bool Reopen, string Problem, bool Retry)
{
    /// <summary>Kartın görünüşünü kurar.</summary>
    /// <param name="status">Denetleyicinin TV uygulaması durumu.</param>
    /// <param name="brand">Eşli TV'nin markası (yoksa LG verin).</param>
    /// <param name="lgHoursLeft">LG geliştirici modunun kalan saati.</param>
    /// <param name="thisComputer">Yerel bilgisayarın güncel adresi (biliniyorsa).</param>
    /// <param name="tvInstallLog">Kullanıcıya gösterilecek <c>tvinstall.log</c> yolu.</param>
    /// <param name="text">Metinler.</param>
    public static TvAppCardView Build(TvAppStatus status, TvBrand brand, int? lgHoursLeft, string? thisComputer,
        string tvInstallLog, ITextSource text)
    {
        var kind = status.Kind;
        if (kind == TvAppKind.Unknown) return new TvAppCardView(false, "", "", false, false, false, false, false, "", false);
        var devOff = kind == TvAppKind.DevModeOff;
        var lg = brand == TvBrand.Lg;
        var samsung = brand == TvBrand.Samsung;
        var android = brand == TvBrand.AndroidTv;
        var samsungSteps = samsung && (devOff || (kind == TvAppKind.Failed
            && status.Error is TvError.Unreachable or TvError.HostPcMismatch));
        return new TvAppCardView(
            Visible: true,
            Status: StatusText(status, brand, text),
            Detail: DetailText(status, brand, lgHoursLeft, text),
            LgSteps: devOff && lg,
            SamsungSteps: samsungSteps,
            AndroidSteps: devOff && android,
            Passphrase: kind == TvAppKind.PassphraseNeeded || (devOff && lg),
            Reopen: kind == TvAppKind.SamsungSignIn,
            Problem: ProblemText(status, brand, thisComputer, tvInstallLog, text),
            Retry: kind == TvAppKind.Failed);
    }

    /// <summary>Durum yazısı.</summary>
    public static string StatusText(TvAppStatus status, TvBrand brand, ITextSource text) => status.Kind switch
    {
        TvAppKind.Installing => text.Get("tvApp.status.installing"),
        TvAppKind.UpToDate => text.Format("tvApp.status.ready", status.Version is { Length: > 0 } v ? v : "?"),
        TvAppKind.DevModeOff => text.Get(brand switch
        {
            TvBrand.Lg => "tvApp.status.devModeOff.lg",
            TvBrand.Samsung => "tvApp.status.devModeOffSamsung",
            _ => "tvApp.status.devModeOff.android",
        }),
        TvAppKind.PassphraseNeeded => text.Get("tvApp.status.passphraseNeeded"),
        TvAppKind.SamsungSignIn => text.Get("tvApp.status.samsungSignIn"),
        TvAppKind.ConfirmOnTv => text.Get("tvApp.status.approveOnTv"),
        _ => "",
    };

    /// <summary>Ayrıntı ipucu.</summary>
    public static string DetailText(TvAppStatus status, TvBrand brand, int? lgHoursLeft, ITextSource text) => status.Kind switch
    {
        TvAppKind.SamsungSignIn => text.Get("tvApp.detail.samsungSignIn") + " " + text.Get("tvApp.detail.samsungNoAccount"),
        TvAppKind.ConfirmOnTv => text.Get("tvApp.detail.approveOnTv"),
        TvAppKind.UpToDate when brand == TvBrand.Lg => lgHoursLeft is { } h
            ? text.Format("tvApp.detail.lgHoursLeft", h)
            : text.Get("tvApp.detail.lgAutoExtend"),
        TvAppKind.UpToDate when brand == TvBrand.Samsung => text.Get("tvApp.detail.samsungSourceSwitch"),
        _ => "",
    };

    /// <summary>Samsung adımlarının 3. satırı: Host PC IP olarak bu bilgisayarın adresi (yoksa "?").</summary>
    public static string SamsungHostStep(string? thisComputer, ITextSource text) =>
        text.Format("tvApp.samsung.step3", thisComputer is { Length: > 0 } a ? a : "?");

    /// <summary>Sorun yazısı (tv-kurulum.md §10.3); hata yoksa boş. Paragraflar arasında boş satır.</summary>
    public static string ProblemText(TvAppStatus status, TvBrand brand, string? thisComputer, string tvInstallLog,
        ITextSource text)
    {
        if (status.Error is not { } error) return "";
        var samsung = brand == TvBrand.Samsung;
        var computer = status.ThisComputer is { Length: > 0 } c ? c : thisComputer is { Length: > 0 } t ? t : null;
        if (error == TvError.HostPcMismatch)
            return text.Format("tvApp.error.hostPcMismatch", status.TvHostPcIp is { Length: > 0 } tv ? tv : "?", computer ?? "?");

        var parts = new List<string> { text.Get(MainKey(error, samsung)) };
        if (samsung && error == TvError.Unreachable && computer is not null)
            parts.Add(text.Format("tvApp.problem.hostPcIp", computer));
        if (status.Reason?.Trim() is { Length: > 0 } reason)
            parts.Add(text.Format(samsung ? "tvApp.problem.detailsSamsung" : "tvApp.problem.detailsTv", reason));
        if (samsung)
        {
            if (error is TvError.InstallFailed or TvError.CertificateRejected) parts.Add(text.Get("tvApp.problem.serverMaintenance"));
            if (error is TvError.Unreachable or TvError.InstallFailed or TvError.CertificateRejected)
                parts.Add(text.Get("tvApp.problem.restartSamsung"));
            if (error == TvError.ConnectionLost) parts.Add(text.Get("tvApp.detail.anynet"));
            parts.Add(text.Format("status.sendLogFile", tvInstallLog));
        }
        return string.Join("\n\n", parts);
    }

    static string MainKey(TvError error, bool samsung) => error switch
    {
        TvError.Unreachable => samsung ? "tvApp.error.unreachableSamsung" : "tv.pair.error.noResponse",
        TvError.KeyServerClosed => "tvApp.error.keyServerOff",
        TvError.WrongPassphrase => "tvApp.error.wrongPassphrase",
        TvError.KeyRejected => "tvApp.error.keyRejected",
        TvError.ToolMissing => "tvApp.error.toolMissing",
        TvError.TooOld => "tvApp.error.tooOld",
        TvError.LoginFailed => "tvApp.error.signInFailed",
        TvError.CertificateFailed => "tvApp.error.certNotIssued",
        TvError.NotApproved => "tvApp.error.notApproved",
        TvError.NotEnoughSpace => "tvApp.error.noSpace",
        TvError.CertificateMismatch => "tvApp.error.certMismatch",
        TvError.CertificateRejected => "tvApp.error.certRejected",
        TvError.TvClockWrong => "tvApp.error.tvClockBehind",
        TvError.PackageBlocked => "tvApp.error.packageBlocked",
        TvError.ConnectionLost => "tvApp.error.connectionLost",
        _ => "tvApp.error.installFailed",
    };

    /// <summary>
    /// Kart kendiliğinden yeniden denetlenecek mi (bilgi için; zamanlayıcıyı denetleyici kurar): geliştirici modu kapalı
    /// ya da Samsung'da Host PC uyuşmazlığı.
    /// </summary>
    public static bool Polls(TvAppStatus status) =>
        status.Kind == TvAppKind.DevModeOff || (status.Kind == TvAppKind.Failed && status.Error == TvError.HostPcMismatch);
}

/// <summary>HDMI yakalama kartı rehberinin sayfa noktaları ve düğmeleri (kurulum.md §12.1).</summary>
public static class CaptureGuideSteps
{
    /// <summary>Sayfa sayısı.</summary>
    public const int PageCount = 3;

    /// <summary>Nokta: şimdiki mi (24 geniş) ve accent mi (şimdiki ve öncekiler).</summary>
    public static (bool Current, bool Accent) Dot(int dot, int page) => (dot == page, dot <= page);

    /// <summary>Sol (hayalet) düğmenin metin anahtarı: pencerede ilk sayfada "Vazgeç", değilse "Geri".</summary>
    public static string BackKey(int page, bool inWindow) => page == 0 && inWindow ? "common.cancel" : "common.back";

    /// <summary>Sağ (birincil) düğmenin metin anahtarı: sonda "Bitti", değilse "Devam".</summary>
    public static string NextKey(int page) => page >= PageCount - 1 ? "common.done" : "common.continue";
}
