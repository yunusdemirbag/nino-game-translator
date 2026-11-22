// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Nino.RemotePlay;

/// <summary>PSN girişi hata türleri (adları günlüğe yazılır).</summary>
public enum PsnSignInFailure
{
    NoCode,
    Refused,
    RateLimited,
    Http,
    Network,
    BadResponse,
}

public sealed class PsnSignInException(PsnSignInFailure kind, int? httpStatus, string? detail)
    : RemotePlayException($"PSN sign-in failed: {kind}" + (httpStatus is { } s ? $" HTTP {s}" : "")
                          + (string.IsNullOrEmpty(detail) ? "" : $" {detail}"))
{
    public PsnSignInFailure Kind { get; } = kind;
    public int? HttpStatus { get; } = httpStatus;
    public string? Detail => detail;

    /// <summary>Günlük satırı için: "&lt;tür&gt; HTTP &lt;kod|-&gt; &lt;ayrıntı&gt;".</summary>
    public string LogText => $"{Kind} HTTP {(HttpStatus is { } s ? s.ToString() : "-")} {Detail}".TrimEnd();
}

/// <summary>
/// Yönlendirmedeki kodu 8 baytlık hesap kimliğine çevirir (jeton saklanmaz). HTTP istemcisi çerezsiz, 30 sn zaman aşımlı.
/// </summary>
public sealed class PsnAccountClient : IDisposable
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    readonly HttpClient http;

    public PsnAccountClient() : this(new SocketsHttpHandler { UseCookies = false })
    {
    }

    /// <summary>Testler için: istekleri verilen işleyiciye gönderir.</summary>
    public PsnAccountClient(HttpMessageHandler handler)
    {
        http = new HttpClient(handler, disposeHandler: true) { Timeout = Timeout };
    }

    public void Dispose() => http.Dispose();

    static AuthenticationHeaderValue Basic() =>
        new("Basic", Convert.ToBase64String(Encoding.UTF8.GetBytes($"{PsnSignIn.ClientId}:{PsnSignIn.ClientSecret}")));

    /// <summary>Yönlendirme adresinden hesap kimliği; hata olursa <see cref="PsnSignInException"/>.</summary>
    public async Task<byte[]> AccountIdAsync(string redirectUrl, CancellationToken cancel = default)
    {
        string? code = PsnSignIn.Code(redirectUrl);
        if (code is null)
        {
            string? error = PsnSignIn.SonyError(redirectUrl);
            if (error is null)
                throw new PsnSignInException(PsnSignInFailure.NoCode, null, null);
            throw new PsnSignInException(PsnSignIn.LooksRateLimited(error) ? PsnSignInFailure.RateLimited : PsnSignInFailure.Refused,
                                         null, error);
        }

        var form = new ByteArrayContent(Encoding.UTF8.GetBytes(PsnSignIn.TokenRequestBody(code)));
        form.Headers.ContentType = new MediaTypeHeaderValue("application/x-www-form-urlencoded");
        using var tokenRequest = new HttpRequestMessage(HttpMethod.Post, PsnSignIn.TokenUrl) { Content = form };
        tokenRequest.Headers.Authorization = Basic();
        using JsonDocument token = await SendAsync(tokenRequest, cancel).ConfigureAwait(false);

        if (!token.RootElement.TryGetProperty("access_token", out JsonElement accessToken)
            || accessToken.ValueKind != JsonValueKind.String || string.IsNullOrEmpty(accessToken.GetString()))
        {
            string? error = SonyError(token.RootElement);
            if (error is null)
                throw new PsnSignInException(PsnSignInFailure.BadResponse, null, null);
            throw new PsnSignInException(PsnSignIn.LooksRateLimited(error) ? PsnSignInFailure.RateLimited : PsnSignInFailure.Refused,
                                         null, error);
        }

        using var infoRequest = new HttpRequestMessage(HttpMethod.Get,
            PsnSignIn.TokenUrl + "/" + Uri.EscapeDataString(accessToken.GetString()!));
        infoRequest.Headers.Authorization = Basic();
        using JsonDocument info = await SendAsync(infoRequest, cancel).ConfigureAwait(false);

        string? userId = null;
        if (info.RootElement.TryGetProperty("user_id", out JsonElement id))
            userId = id.ValueKind switch
            {
                JsonValueKind.String => id.GetString(),
                JsonValueKind.Number => id.GetRawText(),
                _ => null,
            };
        return PsnAccountId.FromUserId(userId) ?? throw new PsnSignInException(PsnSignInFailure.BadResponse, null, null);
    }

    async Task<JsonDocument> SendAsync(HttpRequestMessage request, CancellationToken cancel)
    {
        HttpResponseMessage response;
        string body;
        try
        {
            response = await http.SendAsync(request, cancel).ConfigureAwait(false);
            body = await response.Content.ReadAsStringAsync(cancel).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException)
        {
            throw new PsnSignInException(PsnSignInFailure.Network, null, "timeout");
        }
        catch (HttpRequestException e)
        {
            throw new PsnSignInException(PsnSignInFailure.Network, null, e.Message);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
                throw HttpFailure((int)response.StatusCode, body);
            JsonDocument? doc = null;
            try
            {
                doc = JsonDocument.Parse(body);
            }
            catch (JsonException)
            {
            }
            if (doc is null || doc.RootElement.ValueKind != JsonValueKind.Object)
            {
                doc?.Dispose();
                throw new PsnSignInException(PsnSignInFailure.BadResponse, null, null);
            }
            return doc;
        }
    }

    /// <summary>Başarısız HTTP yanıtının sınıflaması.</summary>
    public static PsnSignInException HttpFailure(int status, string? body)
    {
        string? detail = null;
        if (!string.IsNullOrWhiteSpace(body))
        {
            try
            {
                using var doc = JsonDocument.Parse(body);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                    detail = SonyError(doc.RootElement);
            }
            catch (JsonException)
            {
            }
            if (detail is null)
            {
                string trimmed = body.Trim();
                detail = trimmed.Length > 200 ? trimmed[..200] : trimmed;
            }
            if (detail is { Length: 0 })
                detail = null;
        }

        PsnSignInFailure kind = status == (int)HttpStatusCode.TooManyRequests || PsnSignIn.LooksRateLimited(detail)
            ? PsnSignInFailure.RateLimited
            : status is 400 or 401 or 403 ? PsnSignInFailure.Refused : PsnSignInFailure.Http;
        return new PsnSignInException(kind, status, detail);
    }

    static string? SonyError(JsonElement obj)
    {
        if (obj.ValueKind != JsonValueKind.Object)
            return null;
        return PsnSignIn.FormatSonyError(Field(obj, "error"), Field(obj, "error_description"), Field(obj, "error_code"));
    }

    static string? Field(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out JsonElement v)
            ? v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Number => v.GetRawText(),
                _ => null,
            }
            : null;
}
