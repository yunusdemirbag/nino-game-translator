// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Data;
using Nino.Core.Settings;

namespace Nino.Core.Translation;

/// <summary>Havuz önceliği katmanının sunucu tarafı (çeviri havuzu bunu uygular).</summary>
public interface IPoolFirstSource
{
    /// <summary>Oyun havuz öncelikli mi (sunucunun listesi, hedef dil; "Ortak havuz" ayarından bağımsız).</summary>
    bool IsPoolFirst(string? game);

    /// <summary>Süreli soru: süre dolunca null döner ama istek sürer.</summary>
    Task<string?> AskWithDeadlineAsync(string line, IReadOnlyList<string> context, string? game,
        CancellationToken cancellationToken);
}

/// <summary>Havuz önceliği katmanının ayarları.</summary>
/// <param name="Pool">Çeviri havuzu.</param>
/// <param name="SourceIsEnglish">Kaynak dil <c>en</c> mi (değilse katman hiç devreye girmez).</param>
/// <param name="Game">Havuz öncelikli soru için oyun adı (her satırda okunur).</param>
/// <param name="ContextBefore">Bağlam listesinden "satırdan öncekiler".</param>
/// <param name="Log">Günlük (altyazı günlüğüne yazılır).</param>
public sealed record PoolFirstOptions(IPoolFirstSource Pool, bool SourceIsEnglish, Func<string?> Game,
    Func<string, IReadOnlyList<string>> ContextBefore, Action<string>? Log = null);

/// <summary>
/// Havuz önceliği (çeviri tarifi §1.2): havuz öncelikli oyunda satır sunucuya süreli sorulur; gelmezse yalnız
/// ücretsiz çevirmen çevirir (kullanıcının anahtarlı motoru çağrılmaz).
/// </summary>
public sealed class PoolFirstTranslator(ITranslator inner, ITranslator free, PoolFirstOptions options) : ITranslator
{
    /// <summary>İçteki temel çevirmen.</summary>
    public ITranslator Inner => inner;

    bool PoolFirstNow() => options.SourceIsEnglish && options.Pool.IsPoolFirst(options.Game());

    /// <inheritdoc />
    public string EngineName => inner.EngineName;

    /// <inheritdoc />
    public bool SupportsPretranslation => inner.SupportsPretranslation;

    /// <inheritdoc />
    public bool SupportsBatch => !PoolFirstNow() && inner.SupportsBatch;

    /// <inheritdoc />
    public async Task<TranslationResult> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        var game = options.Game();
        if (!(options.SourceIsEnglish && options.Pool.IsPoolFirst(game)))
        {
            var r = await inner.TranslateAsync(text, cancellationToken).ConfigureAwait(false);
            return r with { Origin = r.Origin == TranslationOrigin.AlreadyTarget ? r.Origin : TranslationOrigin.Engine };
        }
        string? pooled = null;
        try
        {
            pooled = await options.Pool.AskWithDeadlineAsync(text, options.ContextBefore(text), game, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            pooled = null;
        }
        if (!string.IsNullOrWhiteSpace(pooled)) return new TranslationResult(pooled, TranslationOrigin.Pool);
        options.Log?.Invoke("havuzu öncelikli oyunda sunucu çeviri vermedi; yerine ücretsiz çeviri kondu");
        try
        {
            var local = await free.TranslateAsync(text, cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(local.Text) || ReferenceEquals(free, inner))
                return new TranslationResult(local.Text, TranslationOrigin.Free);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception) when (!ReferenceEquals(free, inner))
        {
            // Ücretsiz model kurulu değil ya da açılamadı: satır boş kalmasın, kullanıcının kendi motoru denenir.
        }
        options.Log?.Invoke("ücretsiz çeviri de olmadı; kullanıcının çeviri motoru denendi");
        var own = await inner.TranslateAsync(text, cancellationToken).ConfigureAwait(false);
        return own with { Origin = own.Origin == TranslationOrigin.AlreadyTarget ? own.Origin : TranslationOrigin.Engine };
    }

    /// <inheritdoc />
    public Task PretranslateAsync(string text, CancellationToken cancellationToken = default) =>
        PoolFirstNow() ? Task.CompletedTask : inner.PretranslateAsync(text, cancellationToken);

    /// <inheritdoc />
    public async Task<IReadOnlyList<string>> TranslateBatchAsync(IReadOnlyList<string> texts,
        CancellationToken
            cancellationToken = default)
    {
        if (!PoolFirstNow()) return await inner.TranslateBatchAsync(texts, cancellationToken).ConfigureAwait(false);
        return await this.TranslateOneByOneAsync(texts, cancellationToken).ConfigureAwait(false);
    }
}

/// <summary>Zincirin parçalarını kuran platform fabrikası (Nino.Translation uygular).</summary>
public interface ITranslatorFactory
{
    /// <summary>
    /// Ücretsiz çevirmen: hedef desteklenmiyorsa "desteklenmiyor", model kurulu değilse "indirme gerekli", motor
    /// daha önce açılamadıysa "motor açılamadı" durumlu <see cref="UnavailableTranslator"/>; değilse
    /// <see cref="FreeTranslator"/>.
    /// </summary>
    ITranslator CreateFree(string target);

    /// <summary>DeepL çevirmeni.</summary>
    ITranslator CreateDeepL(string apiKey, string target, ITranslator? fallback);

    /// <summary>Yapay zekâ çevirmeni (bulut ya da yerel model).</summary>
    ITranslator CreateAi(AiService service, string model, string apiKey, string target, LocalServer? local,
        ITranslator? fallback, Func<string?> gameName);
}

/// <summary>Kurulan zincir.</summary>
/// <param name="Translator">En dıştaki çevirmen (yazı denetimi → havuz önceliği → temel).</param>
/// <param name="Base">Temel çevirmen.</param>
/// <param name="Free">Ücretsiz çevirmen (ya da "kullanılamaz").</param>
/// <param name="OnlineEnabled">Çevrimiçi motor etkin mi.</param>
public sealed record TranslatorChain(ITranslator Translator, ITranslator Base, ITranslator Free, bool OnlineEnabled)
{
    /// <summary>Çevrimiçi motorun durumu (etkin değilse null).</summary>
    public IOnlineEngineStatus? OnlineStatus => OnlineEnabled ? Base as IOnlineEngineStatus : null;
}

/// <summary>Çevirmen zincirinin kurulması (çeviri tarifi §1.1, §1.3).</summary>
public static class TranslationChain
{
    /// <summary>Seçili motorun şifreli depodaki anahtar adı.</summary>
    public static string? SecretKeyFor(OnlineEngine engine) => engine switch
    {
        OnlineEngine.DeepL => SecretKeys.DeepLKey,
        OnlineEngine.Gemini => SecretKeys.GeminiKey,
        OnlineEngine.OpenAi => SecretKeys.OpenAIKey,
        OnlineEngine.Claude => SecretKeys.ClaudeKey,
        OnlineEngine.Local => SecretKeys.LocalAIKey,
        _ => null,
    };

    /// <summary>
    /// Depodaki anahtar (kırpılmış); yoksa ya da boşsa null. <paramref name="secrets"/> şifreli depodan ada göre metin
    /// okur (ör. <c>name =&gt; store.Get&lt;string&gt;(name)</c>).
    /// </summary>
    public static string? StoredKey(Func<string, string?> secrets, OnlineEngine engine) =>
        SecretKeyFor(engine) is { } name && secrets(name)?.Trim() is { Length: > 0 } k ? k : null;

    /// <summary>Ayardaki yerel sunucu (geçersizse null).</summary>
    public static LocalServer? LocalServerOf(AppSettings s) => LocalServer.Create(s.LocalAiBaseUrl, s.LocalAiModel);

    /// <summary>Motor hazır mı: bulutta anahtar kayıtlı, yerel modelde adres ve model geçerli.</summary>
    public static bool EngineReady(AppSettings s, Func<string, string?> secrets) => s.OnlineEngine switch
    {
        OnlineEngine.Local => LocalServerOf(s) is not null,
        OnlineEngine.Free => false,
        _ => StoredKey(secrets, s.OnlineEngine) is not null,
    };

    /// <summary>
    /// Çevrimiçi etkin: ayar açık, kaynak <c>en</c>, hedef seçilebilir, (DeepL ise hedef DeepL'in dillerinden) ve motor
    /// hazır.
    /// </summary>
    public static bool OnlineEnabled(AppSettings s, Func<string, string?> secrets) =>
        s.OnlineTranslation && s.OnlineEngine != OnlineEngine.Free
        && TargetLanguages.Code(s.SourceLanguage) == "en" && TargetLanguages.IsSupported(s.TargetLanguage)
        && (s.OnlineEngine != OnlineEngine.DeepL || TargetLanguages.DeepLSupports(s.TargetLanguage))
        && EngineReady(s, secrets);

    /// <summary>Ayardaki bulut modeli (listede yoksa varsayılan).</summary>
    public static string CloudModel(AppSettings s, AiService service, AiModelCatalog? catalog = null)
    {
        var saved = service switch
        {
            AiService.Gemini => s.GeminiModel,
            AiService.OpenAi => s.OpenAiModel,
            _ => s.ClaudeModel,
        };
        return (catalog ?? AiModelCatalog.Default).Resolve(service, saved)?.Id ?? saved;
    }

    /// <summary>Zinciri kurar.</summary>
    /// <param name="s">Ayarlar.</param>
    /// <param name="secrets">Şifreli depo.</param>
    /// <param name="factory">Platform fabrikası.</param>
    /// <param name="gameName">Yapay zekâya giden "kararlı oyun" adı (her istekte okunur).</param>
    /// <param name="poolFirst">Havuz önceliği (çeviri havuzu yoksa null).</param>
    public static TranslatorChain Build(AppSettings s, Func<string, string?> secrets, ITranslatorFactory factory,
        Func<string?> gameName, PoolFirstOptions? poolFirst)
    {
        var target = TargetLanguages.Code(s.TargetLanguage);
        var free = factory.CreateFree(target);
        var fallback = free is UnavailableTranslator ? null
            : free is FreeTranslator { State: FreeTranslatorState.EngineFailed } ? null
            : free;

        var online = OnlineEnabled(s, secrets);
        var baseTranslator = free;
        if (online)
        {
            var key = StoredKey(secrets, s.OnlineEngine) ?? "";
            baseTranslator = s.OnlineEngine switch
            {
                OnlineEngine.DeepL => factory.CreateDeepL(key, target, fallback),
                OnlineEngine.Local => factory.CreateAi(AiService.Local, LocalServerOf(s)!.Model, key, target,
                    LocalServerOf(s), fallback, gameName),
                OnlineEngine.Gemini => factory.CreateAi(AiService.Gemini, CloudModel(s, AiService.Gemini), key, target,
                    null, fallback, gameName),
                OnlineEngine.OpenAi => factory.CreateAi(AiService.OpenAi, CloudModel(s, AiService.OpenAi), key, target,
                    null, fallback, gameName),
                _ => factory.CreateAi(AiService.Claude, CloudModel(s, AiService.Claude), key, target, null, fallback,
                    gameName),
            };
        }

        ITranslator chain = baseTranslator;
        if (poolFirst is not null) chain = new PoolFirstTranslator(chain, free, poolFirst);
        chain = new ScriptGuardTranslator(chain, target);
        return new TranslatorChain(chain, baseTranslator, free, online);
    }
}
