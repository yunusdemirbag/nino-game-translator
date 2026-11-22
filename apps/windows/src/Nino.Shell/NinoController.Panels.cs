// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Health;
using Nino.Core.Settings;
using Nino.Core.Support;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Shell;

// Ayarlar penceresi ve yan pencerelerin (Sağlık, sorun bildirme, Nino'ya Sor, Görüntünün kaynağı, HDMI yakalama kartı
// önizlemesi) denetleyiciden istedikleri. Hepsi arayüz iş parçacığından çağrılır.
public sealed partial class NinoController
{
    static readonly HttpClient PanelHttp = new() { Timeout = TimeSpan.FromSeconds(60) };
    AssistantChat? _assistant;

    /// <summary>Veri klasörü (günlükler, paketler, sorun kaydı); yoksa (testler, bazı Linux kurulumları) null.</summary>
    [NotObserved]
    public string? DataFolder => _services.HealthFolder;

    /// <summary>Nino'nun sürümü (Hakkında, bildirimler).</summary>
    [NotObserved]
    public string AppVersion => _services.AppVersion;

    /// <summary>Kullanıcının paket klasörü (<c>…\packs</c>); veri klasörü yoksa null.</summary>
    [NotObserved]
    public string? UserPacksFolder => DataFolder is { } folder ? Path.Combine(folder, "packs") : null;

    /// <summary>Seçilebilecek görünür pencereler (OBS projektörü / oyun penceresi). Hata boş liste.</summary>
    public IReadOnlyList<VisibleWindow> VisibleWindows()
    {
        try { return _services.VisibleWindows(); }
        catch (Exception e)
        {
            _logs.Error("Pencere listesi alınamadı", e);
            return [];
        }
    }

    /// <summary>PS Remote Play bu makinede yüklü görünüyorsa true; emin olunamıyorsa da true.</summary>
    public bool IsRemotePlayAppInstalled(RemotePlayApp app)
    {
        try { return _services.IsRemotePlayAppInstalled(app); }
        catch (Exception) { return true; }
    }

    /// <summary>Oyun dili <paramref name="source"/>'tan şu anki çeviri diline çevrilebilir mi (İngilizce her zaman).</summary>
    public bool CanTranslateFrom(string source)
    {
        var src = TargetLanguages.Code(source);
        if (src == "en") return true;
        try { return _services.FreeModel.Supports(src, TargetLanguages.Code(_settings.TargetLanguage)); }
        catch (Exception) { return false; }
    }

    // ---- Sağlık ve sorunlar ----

    /// <summary>Bilgisayarın ağ türü (sorun bekçisinin son okuduğu).</summary>
    [NotObserved]
    public NetworkKind Network => _problems?.Network ?? NetworkKind.Unknown;

    /// <summary>Kayıtlı sorunlar (eskiden yeniye; dosyadan yeniden okunur). Klasör yoksa boş.</summary>
    public IReadOnlyList<ProblemRecord> ProblemRecords()
    {
        try { return ProblemLog.InFolder(_services.HealthFolder).All; }
        catch (Exception) { return []; }
    }

    /// <summary>Sağlık denetimleri kartının girdisi (o anki durumla).</summary>
    public HealthCheckInput HealthInput(NetworkKind? network) => new(_health.Snapshot(), network, _translating, ShowsOnTv,
        _tvCount, OnlineEnabledNow || _settings.OnlineEngine == OnlineEngine.Local);

    /// <summary>"Nino'nun tespitleri" metni (sorun bildirme; otomatik değil).</summary>
    public string ProblemFindings(string? userText)
    {
        if (_problems is { } watcher) return watcher.Findings(automatic: false, userText);
        var snapshot = _health.Snapshot();
        return ReportText.Build(false, userText, HealthCauses.FirstTitle(snapshot, NetworkKind.Unknown, _text),
            ProblemRecords(), HealthSummary.Lines(snapshot, NetworkKind.Unknown), _timers.Now, TimeZoneInfo.Local);
    }

    /// <summary>
    /// Sorun bildirme penceresinden gönderim: metin = kullanıcının yazdığı + Nino'nun tespitleri; günlük (istenirse) arka planda
    /// toplanıp gizlenir; dil = çeviri dili; platform <c>windows</c>. Veri klasörü yoksa "başarısız".
    /// </summary>
    public async Task<ReportResult> SendProblemReportAsync(string? userText, string? contact, bool includeLog,
        IReadOnlyList<byte[]> images, CancellationToken cancellationToken = default)
    {
        if (_services.HealthFolder is not { } folder) return ReportResult.Failed;
        var text = ProblemFindings(userText);
        var device = DeviceInfo.Summary(DeviceInfoLines());
        var language = _settings.TargetLanguage;
        var poolId = _services.Pool?.InstallId;
        var version = _services.AppVersion;
        var photos = images.Where(i => i is { Length: > 0 }).Take(SupportLimits.Images).Select(SupportImage.Jpeg).ToArray();
        ReportBody body;
        try
        {
            body = await Task.Run(() => new ReportBody
            {
                Install = InstallIdFile.ReadOrCreateReportId(Path.Combine(folder, InstallIdFile.ReportFileName), poolId),
                App = version,
                Language = language,
                Text = text,
                Contact = string.IsNullOrWhiteSpace(contact) ? null : contact.Trim(),
                Log = includeLog ? LogCollector.Collect(folder) : null,
                Images = photos,
                Device = device,
            }, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception e)
        {
            _logs.Error("Bildirim hazırlanamadı", e);
            return ReportResult.Failed;
        }
        ReportResult result;
        try { result = await _services.SendReportAsync(body, cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception) { result = ReportResult.Failed; }
        await OnUi();
        return result;
    }

    // ---- Nino'ya Sor ----

    /// <summary>Uygulama boyunca tek sohbet (diske yazılmaz). <c>Changed</c> herhangi bir iş parçacığından gelir.</summary>
    [NotObserved]
    public AssistantChat Assistant => _assistant ??= new AssistantChat(AskAssistantAsync);

    Task<AssistantResult> AskAssistantAsync(IReadOnlyList<AssistantMessage> messages, CancellationToken cancellationToken)
    {
        // Cihaz özeti her mesajda yeniden alınır (TV sonradan bağlanmış olabilir); arayüz iş parçacığındayız.
        string device;
        try { device = DeviceInfo.Summary(DeviceInfoLines()); }
        catch (Exception) { device = ""; }
        var folder = _services.HealthFolder;
        var poolId = _services.Pool?.InstallId;
        var version = _services.AppVersion;
        var language = _text.Language;
        return Task.Run(async () =>
        {
            if (folder is null) return AssistantResult.Failed;
            var context = new AssistantContext
            {
                Install = InstallIdFile.ReadOrCreateReportId(Path.Combine(folder, InstallIdFile.ReportFileName), poolId),
                App = version,
                Language = language,
                Device = device.Length == 0 ? null : device,
            };
            var client = new AssistantClient(PanelHttp, SupportEndpoints.RootFromDataFolder(folder));
            return await client.AskAsync(context, messages, cancellationToken).ConfigureAwait(false);
        }, cancellationToken);
    }

    // ---- DeepL kullanımı ----

    /// <summary>Kayıtlı DeepL anahtarının bu ayki kullanımı (anahtar yoksa geçersiz).</summary>
    public async Task<DeepLUsageResult> DeepLUsageAsync(CancellationToken cancellationToken = default)
    {
        if (_secrets.Get<string>(SecretKeys.DeepLKey) is not { Length: > 0 } key)
            return new DeepLUsageResult(KeyCheckStatus.InvalidKey, null, null);
        DeepLUsageResult result;
        try { result = await DeepLTranslator.CheckUsageAsync(key, PanelHttp, cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception) { result = new DeepLUsageResult(KeyCheckStatus.Unreachable, null, null); }
        await OnUi();
        return result;
    }

    // ---- HDMI yakalama kartı önizlemesi ----

    /// <summary>
    /// Ayarlar'daki canlı önizleme için kart kaynağı (oyunu göstermez); çeviri sürerken ya da başlarken null (kart
    /// aynı anda tek okuyucuya açılır). Kaynağı çağıran başlatır ve bırakır.
    /// </summary>
    public ICaptureCardSource? CreateCardPreview()
    {
        if (_translating || _starting) return null;
        try { return _services.CreateCaptureCardSource(false, PreferredCardId); }
        catch (Exception e)
        {
            _logs.Error("Kart önizlemesi açılamadı", e);
            return null;
        }
    }
}
