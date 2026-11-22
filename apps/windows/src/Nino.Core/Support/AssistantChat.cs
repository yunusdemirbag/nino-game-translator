// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

namespace Nino.Core.Support;

/// <summary>Sohbetteki bir girdi.</summary>
public abstract record ChatEntry;

/// <summary>Kullanıcının mesajı (metin kırpılmış, en çok 3 JPEG).</summary>
public sealed record UserChatEntry(string Text, IReadOnlyList<byte[]> Images) : ChatEntry;

/// <summary>Nino'nun cevabı; cevapla bildirim açıldıysa kimliği.</summary>
public sealed record NinoChatEntry(string Text, string? ReportId) : ChatEntry;

/// <summary>Yerel uyarı (sunucuya gitmez).</summary>
public sealed record AlertChatEntry(AssistantOutcome Outcome) : ChatEntry
{
    /// <summary>"Tekrar dene" gösterilir mi (yalnız ulaşılamadıysa).</summary>
    public bool Retriable => Outcome == AssistantOutcome.Failed;

    /// <summary>Uyarının katalog anahtarı.</summary>
    public string TextKey => Outcome switch
    {
        AssistantOutcome.Disabled => "ask.alert.disabled",
        AssistantOutcome.Limited => "ask.alert.dailyLimit",
        AssistantOutcome.Busy => "ask.alert.busy",
        AssistantOutcome.Rejected => "ask.alert.rejected",
        _ => "ask.alert.failed",
    };

    /// <summary>Uyarının altında sorun bildirme düğmesi var mı (yalnız yardımcı kapalıyken).</summary>
    public bool OffersReport => Outcome == AssistantOutcome.Disabled;
}

/// <summary>
/// Uygulama oturumu boyunca tek Nino'ya Sor sohbeti (diske yazılmaz). Yerel selam ve uyarılar sunucuya gitmez.
/// <see cref="Changed"/> herhangi bir iş parçacığından gelebilir; pencere arayüze aktarır.
/// </summary>
public sealed class AssistantChat(Func<IReadOnlyList<AssistantMessage>, CancellationToken, Task<AssistantResult>> ask)
{
    readonly object _gate = new();
    readonly List<ChatEntry> _entries = [];
    int _generation;
    bool _waiting;
    CancellationTokenSource _cancel = new();

    /// <summary>Girdiler, değişti.</summary>
    public event Action? Changed;

    /// <summary>Son yürütmenin görevi (testler bekler).</summary>
    public Task LastRun { get; private set; } = Task.CompletedTask;

    /// <summary>Girdiler (eskiden yeniye).</summary>
    public IReadOnlyList<ChatEntry> Entries
    {
        get { lock (_gate) return _entries.ToArray(); }
    }

    /// <summary>Cevap bekleniyor mu.</summary>
    public bool IsWaiting
    {
        get { lock (_gate) return _waiting; }
    }

    /// <summary>Sohbet boş mu (öneri hapları gösterilir).</summary>
    public bool IsEmpty
    {
        get { lock (_gate) return _entries.Count == 0; }
    }

    /// <summary>"Tekrar dene" yapılabilir mi: beklenmiyor ve son girdi ulaşılamadı uyarısı.</summary>
    public bool CanRetry
    {
        get { lock (_gate) return !_waiting && _entries.Count > 0 && _entries[^1] is AlertChatEntry { Retriable: true }; }
    }

    /// <summary>Gönder düğmesi etkin mi.</summary>
    public bool CanSend(string? text, int imageCount) =>
        !IsWaiting && ((text ?? "").Trim().Length > 0 || imageCount > 0);

    /// <summary>Sunucuya gönderilecek konuşma geçmişi: kullanıcının ve Nino'nun yazdıkları.</summary>
    public IReadOnlyList<AssistantMessage> OutgoingMessages()
    {
        lock (_gate) return Outgoing();
    }

    /// <summary>Kullanıcı mesajı ekler ve gönderir. Beklenirken ya da boşsa false.</summary>
    public bool Send(string? text, IEnumerable<byte[]>? images = null)
    {
        var trimmed = (text ?? "").Trim();
        var photos = (images ?? []).Where(i => i is { Length: > 0 }).Take(SupportLimits.Images).ToArray();
        lock (_gate)
        {
            if (_waiting || (trimmed.Length == 0 && photos.Length == 0)) return false;
            _entries.Add(new UserChatEntry(trimmed, photos));
            StartRun();
        }
        RaiseChanged();
        return true;
    }

    /// <summary>Son uyarıyı kaldırıp aynı sohbeti yeniden gönderir. Yapılamıyorsa false.</summary>
    public bool Retry()
    {
        lock (_gate)
        {
            if (_waiting || _entries.Count == 0 || _entries[^1] is not AlertChatEntry { Retriable: true }) return false;
            _entries.RemoveAt(_entries.Count - 1);
            StartRun();
        }
        RaiseChanged();
        return true;
    }

    /// <summary>Sohbeti sıfırlar; beklenen cevap gelirse yok sayılır.</summary>
    public void NewChat()
    {
        lock (_gate)
        {
            _generation++;
            _entries.Clear();
            _waiting = false;
            _cancel.Cancel();
            _cancel = new CancellationTokenSource();
        }
        RaiseChanged();
    }

    // Kilit tutulurken çağrılır.
    void StartRun()
    {
        var generation = _generation;
        var messages = Outgoing();
        var token = _cancel.Token;
        _waiting = true;
        LastRun = Task.Run(() => RunAsync(generation, messages, token));
    }

    async Task RunAsync(int generation, IReadOnlyList<AssistantMessage> messages, CancellationToken token)
    {
        AssistantResult result;
        try
        {
            result = await ask(messages, token).ConfigureAwait(false);
        }
        catch
        {
            result = AssistantResult.Failed;
        }
        lock (_gate)
        {
            if (generation != _generation) return;
            _waiting = false;
            _entries.Add(result.Outcome == AssistantOutcome.Reply && result.Reply is { Length: > 0 } reply
                ? new NinoChatEntry(reply, result.ReportId)
                : new AlertChatEntry(result.Outcome == AssistantOutcome.Reply ? AssistantOutcome.Failed : result.Outcome));
        }
        RaiseChanged();
    }

    IReadOnlyList<AssistantMessage> Outgoing()
    {
        var list = new List<AssistantMessage>();
        foreach (var entry in _entries)
        {
            switch (entry)
            {
                case UserChatEntry u:
                    list.Add(new AssistantMessage(AssistantRole.User, u.Text, u.Images));
                    break;
                case NinoChatEntry n:
                    list.Add(AssistantMessage.Nino(n.Text));
                    break;
            }
        }
        return list;
    }

    void RaiseChanged()
    {
        try { Changed?.Invoke(); }
        catch { }
    }
}
