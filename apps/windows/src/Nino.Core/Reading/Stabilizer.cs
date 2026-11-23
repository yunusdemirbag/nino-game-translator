// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;

namespace Nino.Core.Reading;

/// <summary>Sabitleyicinin bir beslemeye tepkisinin türü.</summary>
public enum StabilizerAction
{
    /// <summary>Bir şey yapılmaz.</summary>
    None,

    /// <summary>Altyazı kararlı: <see cref="StabilizerReaction.Text"/> çevrilmeli.</summary>
    Translate,

    /// <summary>Ekrandaki satır kalktı.</summary>
    Clear,

    /// <summary>Az önce kalkan satır geri geldi (<see cref="StabilizerReaction.Text"/> ilk gönderilen hali).</summary>
    Restore,
}

/// <summary>Sabitleyicinin tepkisi.</summary>
public readonly record struct StabilizerReaction(StabilizerAction Action, string? Text = null)
{
    /// <summary>Hiçbir şey.</summary>
    public static StabilizerReaction Nothing => default;
}

/// <summary>Sabitleyicinin günlük için bıraktığı notun türü.</summary>
public enum StabilizerNoteKind
{
    /// <summary>Gönderilmiş satırın kötü bir yeniden okuması yok sayıldı.</summary>
    BadReread,

    /// <summary>Çöp okuma kararlaşmadan ekrandan gitti; yollanmadı.</summary>
    GarbageDropped,
}

/// <summary>Sabitleyicinin notu.</summary>
public readonly record struct StabilizerNote(StabilizerNoteKind Kind, string Reading);

/// <summary>
/// Sabitleyici: kare kare gelen metni izler; altyazı kararlı olunca "çevir", ekrandan kalkınca "temizle", az önce kalkan
/// satır geri gelince "geri getir" der. Bir satırı ikinci kez göndermez. Kararlar geçen süreyle verilir. Kilitsizdir.
/// </summary>
public sealed class Stabilizer(IMsClock clock)
{
    /// <summary>Aday benzerlik eşiği.</summary>
    public const double CandidateThreshold = 0.85;

    /// <summary>Kararlı sayılmak için okuma sayısı.</summary>
    public const int StableCount = 2;

    /// <summary>Yeri değişen satırın boşlukta silinme süresi.</summary>
    public const long GoneMs = 800;

    /// <summary>Yeri değişmeyen satırı boşlukta en çok tutma süresi.</summary>
    public const long HoldMs = 4000;

    /// <summary>Geri gelme penceresi.</summary>
    public const long RestoreWindowMs = 1500;

    /// <summary>Başarısız çeviriyi yeniden deneme beklemesi.</summary>
    public const long RetryMs = 1000;

    /// <summary>Çöp gibi okumanın kararlı sayılmak için en az süresi.</summary>
    public const long GarbageStableMs = 700;

    /// <summary>Kalkan satır geçmişi.</summary>
    public const int HistorySize = 5;

    /// <summary>"Zaten hedef dilde" eşiği.</summary>
    public const double SameLanguageThreshold = 0.90;

    sealed record Shown(string Lines, string Raw, long RemovedAt);

    string? _candidateKey;
    string? _candidateRaw;
    int _count;
    long _candidateStart;
    string? _sentLines;
    string? _sentRaw;
    long? _gapStart;
    long? _goneAt;
    byte[]? _seenSignature;
    Box? _seenBox;
    readonly List<Shown> _history = [];
    string? _forgotten;
    long _retryAt;
    string? _pendingGarbage;

    /// <summary>
    /// Temiz hızlı yol kipi (çevirmen önceden çeviriyi destekliyorsa): noktalamayla biten satır ilk karede yalnız temiz
    /// okunduysa gider ve satır ilk okunan haliyle gönderilir.
    /// </summary>
    public bool FastPath { get; set; }

    /// <summary>Son beslemenin notu (her beslemede silinir).</summary>
    public StabilizerNote? LastNote { get; private set; }

    /// <summary>Ekrandaki (gönderilmiş) satırın ham hali.</summary>
    public string? SentText => _sentRaw;

    static readonly HashSet<string> ShortWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "a", "i", "o", "an", "am", "as", "at", "be", "by", "do", "go", "ha", "he", "hi", "if", "in", "is", "it", "me",
        "mr", "ms", "mrs", "dr", "st", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "tv", "uh", "um", "up",
        "us", "we", "ya", "ye",
    };

    const string CleanTrim = ".,!?…:;\"'“”‘’()";

    /// <summary>Temiz okuma mı (her sözcük harf/rakam/kesme/tire; 1–2 harfli sözcükler bilinen listeden).</summary>
    public static bool IsCleanRead(string? text)
    {
        var words = TextKey.Words(text);
        if (words.Length == 0) return false;
        foreach (var raw in words)
        {
            var w = raw.Trim(CleanTrim.ToCharArray());
            if (w.Length == 0) return false;
            if (!w.All(c => char.IsLetterOrDigit(c) || c is '\'' or '’' or '-')) return false;
            if (w.Length <= 2 && w.All(char.IsLetter) && !ShortWords.Contains(w)) return false;
        }
        return true;
    }

    /// <summary>Çeviri gösterilmeli mi: kaynak ile çevirinin sadeleştirilmişleri 0,90 ile benzer değilse.</summary>
    public static bool ShouldSend(string? source, string? translation) =>
        !TextKey.Similar(TextKey.Of(source), TextKey.Of(translation), SameLanguageThreshold);

    void MarkSeen(byte[]? signature, Box? box)
    {
        if (signature is not null && box is not null)
        {
            _seenSignature = signature;
            _seenBox = box;
        }
        else
        {
            _seenSignature = null;
            _seenBox = null;
        }
    }

    void PushShown(long now)
    {
        if (_sentLines is null) return;
        _history.Add(new Shown(_sentLines, _sentRaw ?? "", now));
        if (_history.Count > HistorySize) _history.RemoveAt(0);
        _sentLines = null;
        _sentRaw = null;
        _seenSignature = null;
        _seenBox = null;
    }

    bool LooksUnmoved(byte[]? signature) =>
        signature is not null && _seenSignature is not null && _seenBox is { } box
        && !RegionSignature.Changed(_seenSignature, signature, RegionSignature.DefaultThreshold, box);

    /// <summary>
    /// Bir kareyi besler: okunan metin, alanın izi ve okumanın alana göre kutusu (ikisi de isteğe bağlı).
    /// </summary>
    public StabilizerReaction Feed(string? text, byte[]? signature = null, Box? box = null)
    {
        LastNote = null;
        var now = clock.NowMs;
        var raw = text ?? "";
        var key = TextKey.Of(raw);

        if (key.Length < 3)
        {
            if (_pendingGarbage is not null)
            {
                LastNote = new(StabilizerNoteKind.GarbageDropped, _pendingGarbage);
                _pendingGarbage = null;
            }
            _candidateKey = null;
            _candidateRaw = null;
            _count = 0;
            _gapStart ??= now;
            if (_sentLines is null) return StabilizerReaction.Nothing;
            if (_goneAt is null && !LooksUnmoved(signature)) _goneAt = now;
            if ((_goneAt is { } gone && now - gone >= GoneMs) || now - _gapStart.Value >= HoldMs)
            {
                PushShown(now);
                return new(StabilizerAction.Clear);
            }
            return StabilizerReaction.Nothing;
        }

        _gapStart = null;
        _goneAt = null;

        if (_candidateKey is not null && TextKey.Similar(key, _candidateKey, CandidateThreshold))
        {
            _count++;
            if (FastPath && TextCompare.AddsMeaningMarker(raw, _candidateRaw))
            {
                _candidateKey = key;
                _candidateRaw = raw;
            }
        }
        else
        {
            if (_pendingGarbage is not null) LastNote = new(StabilizerNoteKind.GarbageDropped, _pendingGarbage);
            _pendingGarbage = null;
            _candidateKey = key;
            _candidateRaw = raw;
            _count = 1;
            _candidateStart = now;
        }

        var garbage = OcrJunk.LooksLikeGarbage(raw);
        var ready = garbage
            ? _count >= StableCount && now - _candidateStart >= GarbageStableMs
            : _count >= StableCount || (TextKey.EndsSentence(raw) && (!FastPath || IsCleanRead(raw)));

        if (_sentLines is not null && TextCompare.SameSubtitle(key, _sentLines))
        {
            MarkSeen(signature, box);
            return StabilizerReaction.Nothing;
        }

        if (!ready)
        {
            if (garbage) _pendingGarbage = raw;
            return StabilizerReaction.Nothing;
        }
        _pendingGarbage = null;

        if (_sentRaw is not null && TextCompare.IsWorseReread(raw, _sentRaw))
        {
            LastNote = new(StabilizerNoteKind.BadReread, raw);
            MarkSeen(signature, box);
            return StabilizerReaction.Nothing;
        }

        for (var i = _history.Count - 1; i >= 0; i--)
        {
            var h = _history[i];
            if (now - h.RemovedAt > RestoreWindowMs || !TextCompare.SameSubtitle(key, h.Lines)) continue;
            _history.RemoveAt(i);
            PushShown(now);
            _sentLines = h.Lines;
            _sentRaw = h.Raw;
            MarkSeen(signature, box);
            return new(StabilizerAction.Restore, h.Raw);
        }

        if (_forgotten is not null && now < _retryAt && TextCompare.SameSubtitle(key, _forgotten))
            return StabilizerReaction.Nothing;

        PushShown(now);
        _forgotten = null;
        _sentRaw = FastPath ? _candidateRaw ?? raw.Trim() : raw.Trim();
        _sentLines = TextKey.OfLines(_sentRaw);
        MarkSeen(signature, box);
        return new(StabilizerAction.Translate, _sentRaw);
    }

    /// <summary>
    /// Gönderileni unut (çeviri başarısız): satır ekranda kaldıkça yeniden kararlı olup çevrilir, ama saniyede en çok
    /// bir kez.
    /// </summary>
    public void ForgetSent()
    {
        if (_sentLines is not null)
        {
            _forgotten = _sentLines;
            _retryAt = clock.NowMs + RetryMs;
        }
        _sentLines = null;
        _sentRaw = null;
        _seenSignature = null;
        _seenBox = null;
        _candidateKey = null;
        _candidateRaw = null;
        _count = 0;
        _pendingGarbage = null;
    }

    /// <summary>Her şeyi siler; ekranda satır varsa "temizle" döner.</summary>
    public StabilizerReaction Reset()
    {
        _candidateKey = null;
        _candidateRaw = null;
        _count = 0;
        _pendingGarbage = null;
        LastNote = null;
        _gapStart = null;
        _goneAt = null;
        _seenSignature = null;
        _seenBox = null;
        _history.Clear();
        _forgotten = null;
        if (_sentLines is null) return StabilizerReaction.Nothing;
        _sentLines = null;
        _sentRaw = null;
        return new(StabilizerAction.Clear);
    }
}
