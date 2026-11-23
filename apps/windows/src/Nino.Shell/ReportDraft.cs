// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Support;

namespace Nino.Shell;

/// <summary>Hata bildirimi taslağının aşaması.</summary>
public enum ReportPhase
{
    /// <summary>Yazılıyor.</summary>
    Editing,

    /// <summary>Gönderiliyor.</summary>
    Sending,

    /// <summary>Gönderildi ("Teşekkürler"; ekran kısa süre sonra <see cref="ReportDraft.Reset"/> çağırır).</summary>
    Sent,
}

/// <summary>
/// Hata bildirimi taslağı: yazı, ekler (en çok 5 dosya; <see cref="ReportAttachments"/>), aşama ve hatalar. Uygulama açık
/// kaldıkça denetleyicide durur (pencere kapanıp açılınca kaybolmaz); diske yazılmaz. Yalnız arayüz iş parçacığında
/// değiştirilir; her değişiklikte <see cref="Changed"/>.
/// </summary>
public sealed class ReportDraft
{
    string _description = "";
    IReadOnlyList<ReportAttachment> _attachments = [];

    /// <summary>Kullanıcının yazdığı.</summary>
    public string Description
    {
        get => _description;
        set
        {
            var text = value ?? "";
            if (text == _description) return;
            _description = text;
            Error = null;
            Changed?.Invoke();
        }
    }

    /// <summary>Resim ve yazı ekleri.</summary>
    public IReadOnlyList<ReportAttachment> Attachments => _attachments;

    /// <summary>Hazırlanmakta olan ekleme sayısı (resim sığdırma, dosya okuma).</summary>
    public int Preparing { get; private set; }

    /// <summary>Son eklemede okunamayan ya da sınıra takılan dosya.</summary>
    public ReportAttachmentFailure? AttachError { get; private set; }

    /// <summary>Aşama.</summary>
    public ReportPhase Phase { get; private set; } = ReportPhase.Editing;

    /// <summary>Son gönderimin hatası (gönderildiyse ya da yazı değişince null).</summary>
    public ReportStatus? Error { get; private set; }

    /// <summary>Gönderilebilir mi.</summary>
    public bool CanSend => Phase == ReportPhase.Editing && Preparing == 0;

    /// <summary>Yeni ek alınabilir mi.</summary>
    public bool CanAdd => Phase == ReportPhase.Editing && _attachments.Count < ReportAttachments.MaxFiles;

    /// <summary>Resim ekleri (JPEG).</summary>
    public IReadOnlyList<byte[]> Photos => _attachments.Where(a => a.Jpeg is not null).Select(a => a.Jpeg!).ToList();

    /// <summary>Değişti.</summary>
    public event Action? Changed;

    /// <summary>Bir ekleme hazırlanmaya başladı.</summary>
    public void BeginPreparing()
    {
        Preparing++;
        Changed?.Invoke();
    }

    /// <summary>Hazırlanan ekleri ekler; sığmayan ya da okunamayan varsa <see cref="AttachError"/>.</summary>
    /// <param name="added">Hazırlananlar.</param>
    /// <param name="failed">Hazırlanamayan dosya oldu mu.</param>
    /// <param name="endPreparing">Bir <see cref="BeginPreparing"/>'i kapatır.</param>
    public void Add(IEnumerable<ReportAttachment> added, bool failed = false, bool endPreparing = false)
    {
        if (endPreparing && Preparing > 0) Preparing--;
        var (list, limited) = ReportAttachments.Merge(_attachments, added);
        _attachments = list;
        AttachError = limited ? ReportAttachmentFailure.Limit : failed ? ReportAttachmentFailure.Unreadable : null;
        Error = null;
        Changed?.Invoke();
    }

    /// <summary>Sınıra takıldı (ör. dolu alana bırakıldı).</summary>
    public void MarkLimit()
    {
        AttachError = ReportAttachmentFailure.Limit;
        Changed?.Invoke();
    }

    /// <summary>Eki çıkarır.</summary>
    public void Remove(Guid id)
    {
        if (Phase != ReportPhase.Editing) return;
        _attachments = _attachments.Where(a => a.Id != id).ToList();
        AttachError = null;
        Error = null;
        Changed?.Invoke();
    }

    /// <summary>Formu boşaltır (gönderildikten sonra).</summary>
    public void Reset()
    {
        _description = "";
        _attachments = [];
        AttachError = null;
        Error = null;
        Phase = ReportPhase.Editing;
        Changed?.Invoke();
    }

    internal void StartSending()
    {
        Error = null;
        Phase = ReportPhase.Sending;
        Changed?.Invoke();
    }

    internal void Finish(ReportResult result)
    {
        if (result.Status == ReportStatus.Sent)
        {
            Phase = ReportPhase.Sent;
            Error = null;
        }
        else
        {
            Phase = ReportPhase.Editing;
            Error = result.Status;
        }
        Changed?.Invoke();
    }
}

// Hata bildirimi'in gönderimi: yazılan + ekler + Nino'nun tespitleri + cihaz özeti + uygulama günlükleri (her zaman).
public sealed partial class NinoController
{
    ReportDraft? _reportDraft;

    /// <summary>Uygulama boyunca tek Hata bildirimi taslağı.</summary>
    [NotObserved]
    public ReportDraft ReportDraft => _reportDraft ??= new ReportDraft();

    /// <summary>
    /// Taslağı gönderir. Metin = yazılan + Nino'nun tespitleri; günlük her zaman eklenir ve yazı ekleri sonuna konur;
    /// kayıtlı çeviri anahtarları yazıdan ve eklerden çıkarılır. Başarıda taslak "gönderildi" olur (ekran kısa süre
    /// teşekkür gösterip <see cref="ReportDraft.Reset"/> çağırır), değilse hata taslakta kalır.
    /// </summary>
    public async Task<ReportResult> SendReportDraftAsync(CancellationToken cancellationToken = default)
    {
        var draft = ReportDraft;
        if (!draft.CanSend) return ReportResult.Failed;
        draft.StartSending();
        ReportResult result;
        try
        {
            result = await SendUserReportAsync(draft.Description, draft.Attachments, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            await OnUi();
            draft.Finish(ReportResult.Failed);
            throw;
        }
        catch (Exception e)
        {
            await OnUi();
            _logs.Error("Bildirim gönderilemedi", e);
            result = ReportResult.Failed;
        }
        await OnUi();
        draft.Finish(result);
        return result;
    }

    /// <summary>Kayıtlı çeviri anahtarları (bildirime girmez).</summary>
    IEnumerable<string?> ReportSecrets() =>
    [
        _secrets.Get<string>(SecretKeys.DeepLKey),
        _secrets.Get<string>(SecretKeys.GeminiKey),
        _secrets.Get<string>(SecretKeys.OpenAIKey),
        _secrets.Get<string>(SecretKeys.ClaudeKey),
        _secrets.Get<string>(SecretKeys.LocalAIKey),
    ];

    async Task<ReportResult> SendUserReportAsync(string? userText, IReadOnlyList<ReportAttachment> attachments,
        CancellationToken cancellationToken)
    {
        if (_services.HealthFolder is not { } folder) return ReportResult.Failed;
        var secrets = ReportSecrets().ToList();
        var text = ReportAttachments.WithoutSecrets(ProblemFindings(userText), secrets);
        var device = DeviceInfo.Summary(DeviceInfoLines());
        var language = _settings.TargetLanguage;
        var poolId = _services.Pool?.InstallId;
        var version = _services.AppVersion;
        var photos = attachments.Where(a => a.Jpeg is { Length: > 0 }).Take(SupportLimits.Images)
            .Select(a => SupportImage.Jpeg(a.Jpeg!)).ToArray();
        var files = attachments.Where(a => a.Text is not null).ToList();
        ReportBody body;
        try
        {
            body = await Task.Run(() =>
            {
                var block = LogRedactor.Redact(ReportAttachments.WithoutSecrets(ReportAttachments.TextBlock(files), secrets));
                var log = ReportAttachments.AppendToLog(LogCollector.Collect(folder), block);
                return new ReportBody
                {
                    Install = InstallIdFile.ReadOrCreateReportId(Path.Combine(folder, InstallIdFile.ReportFileName), poolId),
                    App = version,
                    Language = language,
                    Text = text,
                    Log = log is null ? null : ReportAttachments.WithoutSecrets(log, secrets),
                    Images = photos,
                    Device = device,
                };
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
}
