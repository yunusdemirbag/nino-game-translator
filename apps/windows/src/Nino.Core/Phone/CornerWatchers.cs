// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Reading;

namespace Nino.Core.Phone;

/// <summary>Köşe izleyicilerinin bir okumadaki kararı.</summary>
abstract record CornerStep
{
    /// <summary>Görüldü, henüz çevrilmedi (eski öğe durur).</summary>
    public sealed record Wait : CornerStep;

    /// <summary>Bu okumada yok (histerezis).</summary>
    public sealed record Missing : CornerStep;

    /// <summary>Hemen kalksın.</summary>
    public sealed record Drop : CornerStep;

    /// <summary>Çevrilsin: <see cref="Text"/> çevrilecek yazı; sonuç <see cref="Key"/> ile geri verilir.</summary>
    public sealed record Translate(string Key, string Text) : CornerStep;

    /// <summary>Bilinen çeviri gösterilsin (mesaj kartında hazır öğe, köşelerde çeviri).</summary>
    public sealed record Show(string Source, string Translation, ScreenItem? Item = null) : CornerStep;

    public static readonly CornerStep Waiting = new Wait();
    public static readonly CornerStep Gone = new Missing();
    public static readonly CornerStep Dropped = new Drop();
}

/// <summary>
/// Mesaj kartının gösterimi: kart iki okuma aynıysa çevrilir; çevirisi bilinen kart her okumada hafızadan yeniden
/// gösterilir. Telefon açıkken ya da kart sağ altta değilse hemen kalkar.
/// </summary>
sealed class MessageCardWatcher(int memorySize = 40)
{
    readonly object _lock = new();
    string? _last;
    string? _translating;
    ScreenItem? _shown;
    readonly List<KeyValuePair<string, string>> _memory = [];

    public CornerStep Observe(GameCards.Card? card, bool phoneActive)
    {
        lock (_lock)
        {
            if (card is null) return CornerStep.Gone;
            if (phoneActive || card.Box is not { } b || b.Left < 0.55 || b.Top < 0.72)
            {
                _last = null;
                _shown = null;
                return CornerStep.Dropped;
            }
            var body = Body(card.Body);
            for (var i = _memory.Count - 1; i >= 0; i--)
                if (GameWords.Ratio(_memory[i].Key, body) >= 0.85) return ShowLocked(card, _memory[i].Value);
            var stable = _last == body;
            _last = body;
            if (!stable || _translating == body) return CornerStep.Waiting;
            _translating = body;
            return new CornerStep.Translate(body, GameWords.WithoutIcons(body));
        }
    }

    /// <summary>Çeviri geldi: öğe döner (kart kutusu yoksa null).</summary>
    public ScreenItem? Translated(GameCards.Card card, string key, string translation)
    {
        lock (_lock)
        {
            if (_translating == key) _translating = null;
            _memory.RemoveAll(kv => kv.Key == key);
            _memory.Add(new(key, translation));
            while (_memory.Count > memorySize) _memory.RemoveAt(0);
            return (ShowLocked(card with { Body = key }, translation) as CornerStep.Show)?.Item;
        }
    }

    public void Failed(string key)
    {
        lock (_lock) if (_translating == key) _translating = null;
    }

    public void Reset()
    {
        lock (_lock)
        {
            _last = null;
            _translating = null;
            _shown = null;
        }
    }

    CornerStep ShowLocked(GameCards.Card card, string translation)
    {
        if (GameCards.Layout(card, translation) is not { } e) return CornerStep.Waiting;
        var keep = GameWords.Near(e, _shown) ? _shown! : e;
        _shown = keep;
        return new CornerStep.Show(card.Body, translation, keep);
    }

    /// <summary>Gövdenin başındaki tek harfli simge kırıntısı (<c>b Bucked You…</c>) atılır.</summary>
    static string Body(string raw)
    {
        var w = GameWords.Words(raw);
        return w.Length > 1 && w[0].Length == 1 && w[0] is not ("a" or "A" or "I")
            ? string.Join(" ", w.Skip(1))
            : GameWords.Squeeze(raw);
    }
}

/// <summary>
/// Arama kartı: "Ad aranıyor…" gibi durum yazısı; konuşma sürerken (sayaç) öğe yoktur. Öğenin kimliği ad ve
/// durumdur, sayaç girmez.
/// </summary>
sealed class CallWatcher
{
    readonly object _lock = new();
    ScreenItem? _shown;

    /// <summary><paramref name="status"/>: durumun hedef dildeki yazısı; henüz yoksa null (çeviri bekleniyor).</summary>
    public CornerStep Observe(GameCards.Call? call, Func<GameCards.CallState, string?> status)
    {
        lock (_lock)
        {
            if (call is null) return CornerStep.Gone;
            if (call.State == GameCards.CallState.Talking)
            {
                _shown = null;
                return CornerStep.Dropped;
            }
            if (status(call.State) is not { } text || GameCards.Layout(call, text) is not { } e) return CornerStep.Waiting;
            var keep = GameWords.Near(e, _shown) ? _shown! : e;
            _shown = keep;
            return new CornerStep.Show(call.Name, text, keep);
        }
    }

    public void Reset()
    {
        lock (_lock) _shown = null;
    }
}

/// <summary>
/// Köşe yazısının kararlılığı ve hafızası. <paramref name="stable"/> açıkken yazı ancak iki okuma aynıysa çevrilir
/// (sol üst ipucu); kapalıyken ilk görülüşte (sağ üst bildirim). Hafızadaki çeviri her kararlı okumada yeniden
/// verilir. Hedef dilde görülen yazıdan sonra 15 sn susar.
/// </summary>
sealed class StripWatcher(bool stable = true, Func<string, bool>? isTarget = null, int memorySize = 40)
{
    /// <summary>Hedef dilde yazı görüldükten sonraki susma.</summary>
    public const long SilenceMs = 15_000;

    readonly object _lock = new();
    readonly Func<string, bool> _isTarget = isTarget ?? (_ => false);
    string? _previous;
    string? _translating;
    long _silentUntil = long.MinValue;
    readonly List<KeyValuePair<string, string>> _memory = [];

    public CornerStep Observe(string? text, long nowMs)
    {
        lock (_lock)
        {
            var t = GameWords.Squeeze(text);
            if (t.Length == 0)
            {
                _previous = null;
                return CornerStep.Gone;
            }
            var ok = !stable || (_previous is { } p && Close(p, t));
            _previous = t;
            if (!ok) return CornerStep.Waiting;
            if ((text ?? t).Split('\n').Any(l => _isTarget(l.Trim())) || _isTarget(t))
            {
                _silentUntil = nowMs + SilenceMs;
                return CornerStep.Waiting;
            }
            if (nowMs < _silentUntil)
            {
                _previous = null;
                return CornerStep.Waiting;
            }
            for (var i = _memory.Count - 1; i >= 0; i--)
                if (Close(_memory[i].Key, t)) return new CornerStep.Show(t, _memory[i].Value);
            if (_translating == t) return CornerStep.Waiting;
            _translating = t;
            return new CornerStep.Translate(t, t);
        }
    }

    public void Translated(string source, string translation)
    {
        lock (_lock)
        {
            if (_translating == source) _translating = null;
            _memory.Add(new(source, translation));
            while (_memory.Count > memorySize) _memory.RemoveAt(0);
        }
    }

    public void Failed(string source)
    {
        lock (_lock) if (_translating == source) _translating = null;
    }

    public void Reset()
    {
        lock (_lock)
        {
            _previous = null;
            _translating = null;
        }
    }

    public static bool Close(string a, string b) =>
        TextKey.Of(a) == TextKey.Of(b) || (a.Length >= 30 && GameWords.Ratio(a, b) >= 0.8);
}
