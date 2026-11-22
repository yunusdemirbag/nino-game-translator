// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;

namespace Nino.Linux.Core;

/// <summary>
/// Paneldeki tek "çevrimiçi anahtar" alanı: Anthropic anahtarı (<c>sk-ant-</c>) Claude'a, gerisi DeepL'e gider.
/// Anahtarın kendisi panele hiç dönmez; yalnız motorun adı.
/// </summary>
public static class OnlineKeys
{
    public const string ClaudePrefix = "sk-ant-";

    public static bool IsClaude(string key) => key.Trim().StartsWith(ClaudePrefix, StringComparison.Ordinal);

    public static OnlineEngine EngineFor(string key) => IsClaude(key) ? OnlineEngine.Claude : OnlineEngine.DeepL;

    public static string SecretNameFor(OnlineEngine engine) => engine == OnlineEngine.Claude ? SecretKeys.ClaudeKey : SecretKeys.DeepLKey;

    /// <summary>Kayıtlı anahtarın motoru ("Claude" ya da "DeepL"); anahtar yoksa null.</summary>
    public static string? SavedEngine(ISecretStore secrets, AppSettings settings)
    {
        var engine = settings.OnlineEngine == OnlineEngine.Claude ? OnlineEngine.Claude : OnlineEngine.DeepL;
        return secrets.Get<string>(SecretNameFor(engine)) is { Length: > 0 } ? engine.ToString() : null;
    }
}
