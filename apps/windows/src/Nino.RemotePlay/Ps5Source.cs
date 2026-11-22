// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.RemotePlay.Bridge;

namespace Nino.RemotePlay;

/// <summary>PS5 kaynağının kurulumu.</summary>
public sealed class Ps5SourceOptions
{
    public required Ps5Console Console { get; init; }
    public required byte[] AccountId { get; init; }
    public string? LoginPasscode { get; init; }
    public IRemotePlayBridge Bridge { get; init; } = NativeBridge.Shared;
    public RemotePlayLog Log { get; init; } = RemotePlayLog.Silent();
    public TimeProvider Time { get; init; } = TimeProvider.System;

    /// <summary>Taşınma aramasının hedefleri (varsayılan: yerel ağın bütün adresleri).</summary>
    public Func<IReadOnlyList<string>> MoveSearchTargets { get; init; } = Ps5Finder.LocalTargets;
}

/// <summary>
/// PS5 Remote Play kaynağı (doğrudan, ikinci hesapla). Bütün bağlantı işleri tek iş parçacıklı bir kuyrukta koşar;
/// her başlat/durdur/hemen-yeniden-bağlan kuşak numarasını artırır ve eski kuşağın işleri, olayları, gecikmeli
/// denemeleri hiçbir şey yapmaz.
/// </summary>
public sealed class Ps5Source : IVideoSource
{
    public const int MaxFps = 20;
    public static readonly TimeSpan SearchTimeout = TimeSpan.FromSeconds(2);
    public static readonly TimeSpan WakeDeadline = TimeSpan.FromSeconds(20);
    public static readonly TimeSpan WakePoll = TimeSpan.FromSeconds(2);
    public static readonly TimeSpan MoveSearchInterval = TimeSpan.FromSeconds(30);
    public static readonly TimeSpan MoveSearchTimeout = TimeSpan.FromSeconds(3);

    readonly IRemotePlayBridge bridge;
    readonly RemotePlayLog log;
    readonly TimeProvider time;
    readonly long origin;
    readonly Func<IReadOnlyList<string>> moveTargets;
    readonly byte[] accountId;
    readonly string? passcode;
    readonly SerialQueue queue;
    readonly FrameDispatcher dispatcher;
    readonly RetryBackoff backoff = new();
    readonly PictureWatchdog watchdog = new();

    readonly object gate = new();
    Ps5Console console;
    bool running;
    long generation;
    bool disposed;

    // Yalnız kuyruğun iş parçacığında:
    SessionBox? box;
    bool lastSearchAnswered = true;
    long? lastMoveSearchMs;
    ITimer? watchdogTimer;

    public event Action<VideoFrame>? FrameArrived;
    public event Action<SourceStatus>? StatusChanged;
    public event Action<Ps5Console>? ConsoleMoved;

    public Ps5Source(Ps5SourceOptions options)
    {
        ArgumentNullException.ThrowIfNull(options.AccountId);
        if (options.AccountId.Length != 8)
            throw new ArgumentException("accountId needs exactly 8 bytes.", nameof(options));
        bridge = options.Bridge;
        log = options.Log;
        time = options.Time;
        origin = time.GetTimestamp();
        moveTargets = options.MoveSearchTargets;
        accountId = (byte[])options.AccountId.Clone();
        passcode = LoginPasscode.Normalize(options.LoginPasscode);
        console = options.Console;
        queue = new SerialQueue("Nino PS5 session", time, e => log.Nino($"PS5 oturum kuyruğu hatası: {e.Message}"));
        dispatcher = new FrameDispatcher(f => FrameArrived?.Invoke(f), e => log.Nino($"kare işleyicisi hatası: {e.Message}"));
    }

    /// <summary>Şu anki kayıt (taşınınca yeni adresle).</summary>
    public Ps5Console Console
    {
        get
        {
            lock (gate)
                return console;
        }
    }

    long NowMs() => (long)time.GetElapsedTime(origin).TotalMilliseconds;

    bool Valid(long gen)
    {
        lock (gate)
            return running && generation == gen && !disposed;
    }

    // ---------------- Komutlar ----------------

    /// <summary>Başlatır. Yerel kütüphane yoksa ya da başlatılamazsa hata çağırana gider.</summary>
    public void Start()
    {
        bridge.EnsureInitialized();
        long gen;
        lock (gate)
        {
            if (disposed)
                throw new ObjectDisposedException(nameof(Ps5Source));
            running = true;
            gen = ++generation;
        }
        queue.Post(() =>
        {
            if (!Valid(gen))
                return;
            backoff.Reset();
            Connect(gen);
        });
    }

    public void Stop()
    {
        lock (gate)
        {
            running = false;
            generation++;
        }
        queue.Post(CloseBox);
    }

    public void ReconnectNow()
    {
        long gen;
        lock (gate)
        {
            if (!running || disposed)
                return;
            gen = ++generation;
        }
        queue.Post(() =>
        {
            CloseBox();
            if (!Valid(gen))
                return;
            backoff.Reset();
            Connect(gen);
        });
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed)
                return;
        }
        Stop();
        lock (gate)
            disposed = true;
        queue.Post(() =>
        {
            StopWatchdogTimer();
            dispatcher.Dispose();
            queue.Dispose();
        });
    }

    // ---------------- Bağlanma (kuyrukta) ----------------

    void Connect(long gen)
    {
        if (!Valid(gen) || box is not null)
            return;
        try
        {
            Emit(SourceStatus.Connecting);
            Ps5Console c = Console;
            FoundPs5? found = SearchOne(c.Host);
            if (found is null && MoveSearch(c) is { } moved)
            {
                found = moved;
                c = Console;
            }
            if (!Valid(gen))
                return;

            lastSearchAnswered = found is not null;
            if (found is null)
                log.Nino($"PS5 oturumu: {c.Host} keşif isteğine cevap vermedi; bağlantı yine de deneniyor");
            else
                log.Nino($"PS5 oturumu: {found.Name} {c.Host} " + (found.Awake ? "uyanık" : "dinlenmede, uyandırılıyor"));

            if (found is { Awake: false } && !WakeAndWait(gen, c))
                return;
            OpenSession(gen, c);
        }
        catch (Exception e)
        {
            log.Nino($"PS5 oturumu kurulamadı: {e.Message}");
            if (Valid(gen))
                ScheduleRetry(gen, new ReasonHint(DisconnectReason.Other, e.Message));
        }
    }

    FoundPs5? SearchOne(string host)
    {
        var replies = Ps5Finder.Collapse(bridge.Discover([host], (int)SearchTimeout.TotalMilliseconds));
        return replies.FirstOrDefault(r => r.Host == host) ?? replies.FirstOrDefault();
    }

    /// <summary>Uyandırır ve uyanmayı bekler; olmazsa yeniden deneme sırasına sokar ve false döner.</summary>
    bool WakeAndWait(long gen, Ps5Console c)
    {
        try
        {
            ulong credential = c.WakeCredential
                ?? throw new RemotePlayException("the regist key is not a wake-up credential");
            bridge.Wake(c.Host, credential);
        }
        catch (Exception e)
        {
            log.Nino($"wake: {e.Message}");
        }

        long deadline = NowMs() + (long)WakeDeadline.TotalMilliseconds;
        while (true)
        {
            Task.Delay(WakePoll, time).Wait();
            if (!Valid(gen))
                return false;
            if (SearchOne(c.Host) is { Awake: true })
            {
                lastSearchAnswered = true;
                return true;
            }
            if (NowMs() >= deadline)
            {
                ScheduleRetry(gen, new ReasonHint(DisconnectReason.ConsoleAsleep));
                return false;
            }
        }
    }

    /// <summary>Kayıtlı adreste yanıt yoksa bütün ağda kayıtlı adla PS5 aranır (en çok 30 sn'de bir).</summary>
    FoundPs5? MoveSearch(Ps5Console c)
    {
        long now = NowMs();
        if (lastMoveSearchMs is { } last && now - last < (long)MoveSearchInterval.TotalMilliseconds)
            return null;
        lastMoveSearchMs = now;

        var all = Ps5Finder.Collapse(bridge.Discover(moveTargets(), (int)MoveSearchTimeout.TotalMilliseconds));
        FoundPs5? pick = Ps5Finder.PickMoved(all, c.Name);
        if (pick is null || pick.Host == c.Host)
            return null;

        log.Nino($"PS5 yeni adreste: {c.Host} -> {pick.Host}");
        Ps5Console updated = c.WithHost(pick.Host);
        lock (gate)
            console = updated;
        try
        {
            ConsoleMoved?.Invoke(updated);
        }
        catch (Exception e)
        {
            log.Nino($"PS5 taşındı işleyicisi hatası: {e.Message}");
        }
        return pick;
    }

    void OpenSession(long gen, Ps5Console c)
    {
        var b = new SessionBox(this, gen, new PasscodeResponder(passcode));
        var request = new BridgeSessionRequest(c.Host, KeyBytes.Fit(c.RegistKey, 16), KeyBytes.Fit(c.Morning, 16),
                                               accountId, MaxFps);
        IBridgeSession? session = bridge.StartSession(request, b);
        if (session is null)
        {
            string reason = b.LastError ?? "the session failed to start";
            log.Nino($"PS5 oturumu açılamadı ({c.Host}): {reason}");
            ScheduleRetry(gen, new ReasonHint(DisconnectReason.Other, reason));
            return;
        }
        b.Attach(session);
        box = b;
    }

    /// <summary>Kutuyu kapatır: bekçiye "bitti", kutu boşaltılır, durdurma arka planda (join kuyruğu bekletmez).</summary>
    void CloseBox()
    {
        StopWatchdogTimer();
        watchdog.Finish();
        SessionBox? b = box;
        box = null;
        if (b is not null)
            Task.Run(b.Close);
    }

    void ScheduleRetry(long gen, ReasonHint reason)
    {
        ReasonHint classified = SessionRules.Classify(reason, lastSearchAnswered, Console.Host);
        Emit(SourceStatus.Down(classified.Reason, classified.Detail));
        if (!Valid(gen))
            return;
        TimeSpan delay = backoff.Next();
        queue.PostDelayed(delay, () =>
        {
            if (Valid(gen))
                Connect(gen);
        });
    }

    void GiveUp(DisconnectReason reason, string? detail = null)
    {
        lock (gate)
        {
            running = false;
            generation++;
        }
        CloseBox();
        Emit(SourceStatus.Down(reason, detail));
    }

    void Emit(SourceStatus status)
    {
        if (status.Phase != SourcePhase.Connecting)
            log.Nino("PS5 oturumu: " + status);
        try
        {
            StatusChanged?.Invoke(status);
        }
        catch (Exception e)
        {
            log.Nino($"durum işleyicisi hatası: {e.Message}");
        }
    }

    // ---------------- Oturum olayları (kuyrukta) ----------------

    bool Current(SessionBox b) => box == b && Valid(b.Generation);

    void OnConnected(SessionBox b)
    {
        if (!Current(b))
            return;
        backoff.Reset();
        watchdog.Connected(NowMs());
        Emit(SourceStatus.Streaming);
        StartWatchdogTimer(b);
    }

    void OnPasscodeRequest(SessionBox b, byte[]? reply, DisconnectReason ifMissing)
    {
        if (!Current(b))
            return;
        if (reply is not null)
        {
            log.Nino("PS5 oturum şifresi sordu; Ayarlar'da kayıtlı şifre yollanıyor");
            int r = b.SendPasscode(reply);
            if (r != 0)
                log.Nino($"giriş şifresi gönderilemedi ({r})");
            return;
        }
        GiveUp(ifMissing);
    }

    void OnQuit(SessionBox b, ReasonHint reason)
    {
        if (!Current(b))
            return;
        CloseBox();
        if (SessionRules.GivesUp(reason.Reason))
        {
            lock (gate)
            {
                running = false;
                generation++;
            }
            Emit(SourceStatus.Down(reason.Reason, reason.Detail));
            return;
        }
        ScheduleRetry(b.Generation, reason);
    }

    void StartWatchdogTimer(SessionBox b)
    {
        StopWatchdogTimer();
        watchdogTimer = time.CreateTimer(_ => queue.Post(() => CheckPicture(b)), null,
                                         TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
    }

    void StopWatchdogTimer()
    {
        watchdogTimer?.Dispose();
        watchdogTimer = null;
    }

    void CheckPicture(SessionBox b)
    {
        if (!Current(b))
            return;
        if (watchdog.Stalled(NowMs()) is not { } gap)
            return;
        log.Nino($"PS5'ten {gap / 1000} {PictureStallNotes.StalledLineMarker}; bağlantı açık, oturum yeniden kuruluyor");
        CloseBox();
        ScheduleRetry(b.Generation, new ReasonHint(DisconnectReason.Other, "the PS5 stopped sending video"));
    }

    // ---------------- Geri çağrılar (köprünün iş parçacığında) ----------------

    unsafe void OnFrame(SessionBox b, byte* bgra, int width, int height, int stride)
    {
        if (b.Closed)
            return;
        watchdog.Picture(NowMs());
        dispatcher.Offer(bgra, width, height, stride);
    }

    /// <summary>Testler için: kuyruk ve sahte kutu.</summary>
    internal SerialQueue Queue => queue;

    internal long CurrentGeneration
    {
        get
        {
            lock (gate)
                return generation;
        }
    }

    internal IBridgeSessionCallbacks InstallBoxForTest(long gen, IBridgeSession session)
    {
        var b = new SessionBox(this, gen, new PasscodeResponder(passcode));
        b.Attach(session);
        box = b;
        return b;
    }

    /// <summary>Tek bir yerel oturumun sahibi; yerel oturum durup iş parçacıkları bitene dek canlı kalır.</summary>
    sealed class SessionBox(Ps5Source owner, long generation, PasscodeResponder responder) : IBridgeSessionCallbacks
    {
        readonly object sessionGate = new();
        IBridgeSession? session;
        volatile bool closed;
        ReasonHint? lastHint;
        string? lastError;

        public long Generation { get; } = generation;
        public bool Closed => closed;

        public string? LastError
        {
            get
            {
                lock (this)
                    return lastError;
            }
        }

        public void Attach(IBridgeSession s)
        {
            lock (sessionGate)
                session = s;
        }

        /// <summary>Durdurma ve şifre gönderme aynı kilitte; durmuş kutuya şifre gönderilmez.</summary>
        public int SendPasscode(byte[] pin)
        {
            lock (sessionGate)
                return closed || session is null ? -1 : session.SendLoginPasscode(pin);
        }

        public void Close()
        {
            lock (sessionGate)
            {
                if (closed)
                    return;
                closed = true;
                try
                {
                    session?.Stop();
                }
                catch (Exception e)
                {
                    owner.log.Nino($"PS5 oturumu durdurulamadı: {e.Message}");
                }
            }
        }

        public unsafe void OnFrame(byte* bgra, int width, int height, int stride) =>
            owner.OnFrame(this, bgra, width, height, stride);

        public void OnLog(BridgeLogLevel level, string line)
        {
            owner.log.Chiaki(level, line);
            if (level != BridgeLogLevel.Error)
                return;
            lock (this)
            {
                lastError = line;
                if (SessionRules.HintFromLine(line) is { } hint)
                    lastHint = hint;
            }
        }

        public void OnEvent(int code, int quitReason, string? reasonText)
        {
            switch (code)
            {
                case BridgeEvent.Connected:
                    owner.queue.Post(() => owner.OnConnected(this));
                    break;
                case BridgeEvent.LoginPasscode:
                {
                    // Yanıt hemen hesaplanır; gönderme olay geri çağrısından değil kuyruktan yapılır.
                    byte[]? reply = responder.Respond(quitReason == 1, out DisconnectReason missing);
                    owner.queue.Post(() => owner.OnPasscodeRequest(this, reply, missing));
                    break;
                }
                case BridgeEvent.Quit:
                {
                    ReasonHint? hint;
                    lock (this)
                        hint = lastHint;
                    ReasonHint merged = SessionRules.Merge(quitReason, reasonText, hint);
                    owner.log.Nino($"Oturum kapandı: neden {quitReason} ({merged.Reason}) {reasonText}".TrimEnd());
                    owner.queue.Post(() => owner.OnQuit(this, merged));
                    break;
                }
            }
        }
    }
}
