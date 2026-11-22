// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;

namespace Nino.RemotePlay.Tests;

public class PsnTests
{
    const string Prefix = PsnSignIn.RedirectPrefix;

    [Fact]
    public void SignInUrl()
    {
        string url = PsnSignIn.SignInUrl();
        string[] expected =
        [
            "redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect",
            "scope=psn:clientapp%20referenceDataService",
            "client_id=ba495a24-818c-472b-b12d-ff231c1b5745",
        ];
        Assert.True(url.StartsWith("https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?", StringComparison.Ordinal));
        foreach (string part in expected)
            Assert.Contains(part, url);
        Assert.Contains("?service_entity=urn:service-entity:psn&response_type=code&", url);
        Assert.EndsWith("&prompt=always&PlatformPrivacyWs1=minimal", url);
    }

    [Fact]
    public void QueryEncoding()
    {
        Assert.Equal("a%20b", PsnSignIn.Encode("a b"));
        Assert.Equal("-._~:/?@!$'()*,;", PsnSignIn.Encode("-._~:/?@!$'()*,;"));
        Assert.Equal("%26%3D%2B%C3%BC", PsnSignIn.Encode("&=+ü"));
        Assert.StartsWith("grant_type=authorization_code&code=the-code&scope=psn:clientapp%20", PsnSignIn.TokenRequestBody("the-code"));
    }

    [Fact]
    public void CodeFromRedirect()
    {
        Assert.Equal("AbC123", PsnSignIn.Code(Prefix + "?code=AbC123&cid=x"));
        Assert.Null(PsnSignIn.Code("https://example.com/redirect?code=AbC123"));
        Assert.Null(PsnSignIn.Code(Prefix + "?cid=x"));
    }

    [Fact]
    public void SonyErrorFromRedirect()
    {
        Assert.Equal("access_denied: Access denied (4002)",
                     PsnSignIn.SonyError(Prefix + "?error=access_denied&error_description=Access+denied&error_code=4002"));
        Assert.Equal("access_denied", PsnSignIn.SonyError(Prefix + "?error=access_denied"));
        Assert.Null(PsnSignIn.SonyError(Prefix + "?code=x"));
    }

    [Theory]
    [InlineData(Prefix + "?code=AbC123")]
    [InlineData("  \n" + Prefix + "?code=AbC123 \r\n")]
    [InlineData("\"" + Prefix + "?code=AbC123\"")]
    [InlineData("redirect " + Prefix + "?code=AbC123 copied")]
    [InlineData("HTTPS://REMOTEPLAY.DL.PLAYSTATION.NET/REMOTEPLAY/REDIRECT?code=AbC123")]
    public void PastedRedirectIsAccepted(string text)
    {
        string? url = PsnSignIn.RedirectFromText(text);
        Assert.NotNull(url);
        Assert.Equal("AbC123", PsnSignIn.Code(url));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("https://my.account.sony.com/central/signin/")]
    [InlineData(Prefix)]
    [InlineData(Prefix + "?cid=1")]
    [InlineData("https://example.com/?u=https://remoteplay.dl.playstation.net/remoteplay/redirectx")]
    public void PastedTextIsRejected(string? text) => Assert.Null(PsnSignIn.RedirectFromText(text));

    [Fact]
    public void PastedErrorRedirectIsAccepted()
    {
        string? url = PsnSignIn.RedirectFromText(Prefix + "?error=access_denied&error_description=denied");
        Assert.NotNull(url);
        Assert.StartsWith("access_denied", PsnSignIn.SonyError(url));
    }

    [Theory]
    [InlineData("Can't connect to the server.", true)]
    [InlineData("Can’t connect to the server right now.", true)]
    [InlineData("Sign In\nCANNOT CONNECT TO THE SERVER", true)]
    [InlineData("unable to connect to the server, sorry", true)]
    [InlineData("Could not connect to the server", true)]
    [InlineData(null, false)]
    [InlineData("Sign In\nSign-In ID (Email Address)\nNext", false)]
    [InlineData("Connect to the server first", false)]
    public void CannotConnectPage(string? text, bool expected) => Assert.Equal(expected, PsnSignIn.IsCannotConnectPage(text));

    [Fact]
    public void SonyHosts()
    {
        Assert.True(PsnSignIn.IsSonyHost("my.account.sony.com"));
        Assert.True(PsnSignIn.IsSonyHost("auth.api.sonyentertainmentnetwork.com"));
        Assert.True(PsnSignIn.IsSonyHost("www.playstation.com"));
        Assert.True(PsnSignIn.IsSonyHost("remoteplay.dl.playstation.net"));
        Assert.False(PsnSignIn.IsSonyHost("notsony.com"));
        Assert.False(PsnSignIn.IsSonyHost("example.com"));
    }

    [Fact]
    public void AccountIdFromUserId()
    {
        Assert.Equal("AQAAAAAAAAA=", Convert.ToBase64String(PsnAccountId.FromUserId("1")!));
        Assert.Equal(new byte[] { 2, 1, 0, 0, 0, 0, 0, 0 }, PsnAccountId.FromUserId("258"));
        Assert.Equal(new byte[] { 255, 255, 255, 255, 255, 255, 255, 255 }, PsnAccountId.FromUserId("18446744073709551615"));
        Assert.Null(PsnAccountId.FromUserId("abc"));
        Assert.Null(PsnAccountId.FromUserId(""));
        Assert.Null(PsnAccountId.FromUserId("-1"));
        Assert.Null(PsnAccountId.FromUserId("18446744073709551616"));
    }

    [Fact]
    public void ManualAccountId()
    {
        Assert.Equal(new byte[] { 1, 2, 3, 4, 5, 6, 7, 8 }, PsnAccountId.FromManualText(" AQID BAUG Bwg= "));
        Assert.Null(PsnAccountId.FromManualText("AQIDBAUGBw=="));      // 7 bayt
        Assert.Null(PsnAccountId.FromManualText("AQIDBAUGBwgJ"));      // 9 bayt
        Assert.Null(PsnAccountId.FromManualText("not base64!!"));
        Assert.Null(PsnAccountId.FromManualText(null));
    }

    // ---------------- Jeton değişimi (sahte işleyici; ağ yok) ----------------

    sealed class Responder(Func<HttpRequestMessage, string?, HttpResponseMessage> answer) : HttpMessageHandler
    {
        public List<(HttpMethod Method, string Url, string? Auth, string? Body)> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancel)
        {
            string? body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancel);
            Requests.Add((request.Method, request.RequestUri!.ToString(), request.Headers.Authorization?.ToString(), body));
            return answer(request, body);
        }
    }

    static HttpResponseMessage Json(HttpStatusCode status, string body) =>
        new(status) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    [Fact]
    public async Task RedirectCodeBecomesAccountId()
    {
        var handler = new Responder((req, _) => req.Method == HttpMethod.Post
            ? Json(HttpStatusCode.OK, "{\"access_token\":\"tok123\"}")
            : Json(HttpStatusCode.OK, "{\"user_id\":\"258\"}"));
        using var client = new PsnAccountClient(handler);
        byte[] id = await client.AccountIdAsync(Prefix + "?code=the-code");
        Assert.True(id.SequenceEqual(new byte[] { 2, 1, 0, 0, 0, 0, 0, 0 }));

        Assert.Equal(2, handler.Requests.Count);
        string basic = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(PsnSignIn.ClientId + ":" + PsnSignIn.ClientSecret));
        Assert.Equal(HttpMethod.Post, handler.Requests[0].Method);
        Assert.Equal(PsnSignIn.TokenUrl, handler.Requests[0].Url);
        Assert.Equal(basic, handler.Requests[0].Auth);
        Assert.StartsWith("grant_type=authorization_code&code=the-code&scope=psn:clientapp%20", handler.Requests[0].Body);
        Assert.EndsWith("redirect_uri=https://remoteplay.dl.playstation.net/remoteplay/redirect", handler.Requests[0].Body);
        Assert.Equal(PsnSignIn.TokenUrl + "/tok123", handler.Requests[1].Url);
        Assert.Equal(basic, handler.Requests[1].Auth);
    }

    [Fact]
    public async Task NumericUserIdIsAccepted()
    {
        var handler = new Responder((req, _) => req.Method == HttpMethod.Post
            ? Json(HttpStatusCode.OK, "{\"access_token\":\"t\"}")
            : Json(HttpStatusCode.OK, "{\"user_id\":1}"));
        using var client = new PsnAccountClient(handler);
        Assert.Equal("AQAAAAAAAAA=", Convert.ToBase64String(await client.AccountIdAsync(Prefix + "?code=c")));
    }

    static async Task<PsnSignInException> Fails(HttpStatusCode status, string body, string redirect = Prefix + "?code=c")
    {
        var handler = new Responder((_, _) => Json(status, body));
        using var client = new PsnAccountClient(handler);
        return await Assert.ThrowsAsync<PsnSignInException>(() => client.AccountIdAsync(redirect));
    }

    [Fact]
    public async Task FailuresAreClassified()
    {
        var e = await Fails(HttpStatusCode.BadRequest, "{}");
        Assert.Equal((PsnSignInFailure.Refused, 400), (e.Kind, e.HttpStatus));

        e = await Fails(HttpStatusCode.BadRequest,
                        "{\"error\":\"invalid_grant\",\"error_description\":\"Invalid authorization code\",\"error_code\":4165}");
        Assert.Equal(PsnSignInFailure.Refused, e.Kind);
        Assert.Equal("invalid_grant: Invalid authorization code (4165)", e.Detail);

        e = await Fails(HttpStatusCode.TooManyRequests, "Too Many Requests");
        Assert.Equal(PsnSignInFailure.RateLimited, e.Kind);
        Assert.Equal("Too Many Requests", e.Detail);

        e = await Fails(HttpStatusCode.ServiceUnavailable, "");
        Assert.Equal((PsnSignInFailure.Http, 503, (string?)null), (e.Kind, e.HttpStatus, e.Detail));

        e = await Fails(HttpStatusCode.OK, "{\"error\":\"invalid_grant\"}");
        Assert.Equal((PsnSignInFailure.Refused, (int?)null, "invalid_grant"), (e.Kind, e.HttpStatus, e.Detail));

        e = await Fails(HttpStatusCode.OK, "{}");
        Assert.Equal(PsnSignInFailure.BadResponse, e.Kind);
        Assert.Null(e.HttpStatus);

        e = await Fails(HttpStatusCode.OK, "[1,2]");
        Assert.Equal(PsnSignInFailure.BadResponse, e.Kind);
    }

    [Fact]
    public async Task NetworkFailure()
    {
        var handler = new Responder((_, _) => throw new HttpRequestException("No such host is known."));
        using var client = new PsnAccountClient(handler);
        var e = await Assert.ThrowsAsync<PsnSignInException>(() => client.AccountIdAsync(Prefix + "?code=c"));
        Assert.Equal(PsnSignInFailure.Network, e.Kind);
        Assert.Contains("No such host is known.", e.Detail);
        Assert.Equal("Network HTTP - No such host is known.", e.LogText);
    }

    [Fact]
    public async Task RedirectWithoutCodeMakesNoRequest()
    {
        var handler = new Responder((_, _) => throw new InvalidOperationException("no request expected"));
        using var client = new PsnAccountClient(handler);
        var e = await Assert.ThrowsAsync<PsnSignInException>(
            () => client.AccountIdAsync(Prefix + "?error=temporarily_unavailable&error_description=Too+many+requests"));
        Assert.Equal(PsnSignInFailure.RateLimited, e.Kind);
        e = await Assert.ThrowsAsync<PsnSignInException>(() => client.AccountIdAsync(Prefix + "?cid=x"));
        Assert.Equal(PsnSignInFailure.NoCode, e.Kind);
        e = await Assert.ThrowsAsync<PsnSignInException>(() => client.AccountIdAsync(Prefix + "?error=access_denied"));
        Assert.Equal((PsnSignInFailure.Refused, "access_denied"), (e.Kind, e.Detail));
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task CallerCancellationIsNotANetworkFailure()
    {
        var handler = new Responder((_, _) => throw new TaskCanceledException());
        using var client = new PsnAccountClient(handler);
        using var cancel = new CancellationTokenSource();
        cancel.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => client.AccountIdAsync(Prefix + "?code=c", cancel.Token));
    }
}
