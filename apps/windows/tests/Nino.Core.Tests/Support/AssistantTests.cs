// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using System.Text;
using System.Text.Json;
using Nino.Core.Support;

namespace Nino.Core.Tests.Support;

public sealed class AssistantPayloadTests
{
    static readonly AssistantContext Context = new() { Install = "install-1234", App = "1.0", Language = "en" };

    static byte[] Photo(int size = 10) => Enumerable.Repeat((byte)7, size).ToArray();

    static JsonElement[] Messages(byte[] json) =>
        JsonDocument.Parse(json).RootElement.GetProperty("messages").EnumerateArray().ToArray();

    [Fact]
    public void Last24_StartsWithUser()
    {
        var list = new List<AssistantMessage>();
        for (var i = 0; i < 20; i++)
        {
            list.Add(AssistantMessage.User("soru " + i));
            list.Add(AssistantMessage.Nino("cevap " + i));
        }
        list.Add(AssistantMessage.User("son soru"));
        var messages = Messages(AssistantPayload.Build(Context, list)!);
        Assert.Equal(23, messages.Length);
        Assert.Equal("user", messages[0].GetProperty("role").GetString());
        Assert.Equal("son soru", messages[^1].GetProperty("text").GetString());
        Assert.All(messages, m => Assert.False(m.TryGetProperty("images", out _)));
    }

    [Fact]
    public void Text_TrimmedAndCut()
    {
        var m = Messages(AssistantPayload.Build(Context, [AssistantMessage.User("  " + new string('a', 3000))])!);
        Assert.Equal(2000, m[0].GetProperty("text").GetString()!.Length);
    }

    [Fact]
    public void Invalid_ReturnsNull()
    {
        Assert.Null(AssistantPayload.Build(Context, []));
        Assert.Null(AssistantPayload.Build(Context, [AssistantMessage.User("  ")]));
        Assert.Null(AssistantPayload.Build(Context, [AssistantMessage.User("a"), AssistantMessage.Nino("b")]));
        var only = Messages(AssistantPayload.Build(Context, [AssistantMessage.User("", Photo())])!);
        Assert.Equal("", only[0].GetProperty("text").GetString());
        Assert.Equal(1, only[0].GetProperty("images").GetArrayLength());
    }

    [Fact]
    public void PhotosOnNewestTwo()
    {
        AssistantMessage[] list =
        [
            AssistantMessage.User("ilk", Photo(), Photo()),
            AssistantMessage.Nino("a"),
            AssistantMessage.User("", Photo()),
            AssistantMessage.Nino("b"),
            AssistantMessage.User("üçüncü", Photo()),
            AssistantMessage.Nino("c"),
            AssistantMessage.User("dördüncü", Photo(), Photo(), Photo(), Photo(), Photo()),
        ];
        var m = Messages(AssistantPayload.Build(Context, list)!);
        Assert.Equal(7, m.Length);
        Assert.Equal("ilk [screenshot]", m[0].GetProperty("text").GetString());
        Assert.False(m[0].TryGetProperty("images", out _));
        Assert.Equal("[screenshot]", m[2].GetProperty("text").GetString());
        Assert.False(m[2].TryGetProperty("images", out _));
        Assert.Equal(1, m[4].GetProperty("images").GetArrayLength());
        Assert.Equal(3, m[6].GetProperty("images").GetArrayLength());
        Assert.False(m[1].TryGetProperty("images", out _));
    }

    [Fact]
    public void SizeLimit_DowngradesOldestFirst()
    {
        AssistantMessage[] list =
        [
            AssistantMessage.User("eski", Photo(4000), Photo(4000), Photo(4000)),
            AssistantMessage.Nino("tamam"),
            AssistantMessage.User("yeni", Photo(4000), Photo(4000), Photo(4000)),
        ];
        var m = Messages(AssistantPayload.Build(Context, list, 24_000)!);
        Assert.Equal("eski [screenshot]", m[0].GetProperty("text").GetString());
        Assert.False(m[0].TryGetProperty("images", out _));
        Assert.Equal(3, m[2].GetProperty("images").GetArrayLength());

        m = Messages(AssistantPayload.Build(Context, list, 2000)!);
        Assert.All(m, x => Assert.False(x.TryGetProperty("images", out _)));
        Assert.Equal("yeni [screenshot]", m[2].GetProperty("text").GetString());
    }

    [Fact]
    public void SixHundredKbPhotos_Fit()
    {
        var big = new byte[600 * 1024];
        var list = new[]
        {
            AssistantMessage.User("a", big, big, big), AssistantMessage.Nino("b"), AssistantMessage.User("c", big, big, big),
        };
        var json = AssistantPayload.Build(Context, list)!;
        Assert.True(json.Length <= SupportLimits.AssistantBodyBytes);
        Assert.Equal(6, Messages(json).Sum(x => x.TryGetProperty("images", out var i) ? i.GetArrayLength() : 0));
    }

    [Fact]
    public void Fields()
    {
        var json = Encoding.UTF8.GetString(AssistantPayload.Build(Context with { Device = " app: 1 " },
            [AssistantMessage.User("Televizyonum LG")])!);
        Assert.Contains("\"platform\":\"windows\"", json);
        Assert.Contains("\"language\":\"en\"", json);
        Assert.Contains("\"device\":\"app: 1\"", json);
        Assert.Contains("Televizyonum LG", json);
        Assert.DoesNotContain("\"device\"", Encoding.UTF8.GetString(AssistantPayload.Build(Context, [AssistantMessage.User("x")])!));
    }
}

public sealed class AssistantClientTests
{
    static readonly Uri Root = new("https://pool.example");
    static readonly AssistantContext Context = new() { Install = "install-1234", App = "1.0", Language = "tr" };

    static async Task<AssistantResult> Ask(int status, string body, TimeSpan? retry = null)
    {
        var handler = new StubHandler((_, _) =>
        {
            var r = new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(body) };
            if (retry is { } t) r.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(t);
            return r;
        });
        return await new AssistantClient(new HttpClient(handler), Root).AskAsync(Context, [AssistantMessage.User("selam")]);
    }

    [Fact]
    public async Task Reply_TrimmedWithReport()
    {
        var r = await Ask(200, """{"ok":true,"reply":"  Merhaba!  ","report":"r-42"}""");
        Assert.Equal(AssistantOutcome.Reply, r.Outcome);
        Assert.Equal("Merhaba!", r.Reply);
        Assert.Equal("r-42", r.ReportId);
        Assert.Null((await Ask(200, """{"reply":"x","report":null}""")).ReportId);
    }

    [Theory]
    [InlineData(200, """{"ok":true}""", AssistantOutcome.Failed)]
    [InlineData(200, "<html>", AssistantOutcome.Failed)]
    [InlineData(503, """{"error":"assistant_disabled"}""", AssistantOutcome.Disabled)]
    [InlineData(503, """{"error":"other"}""", AssistantOutcome.Failed)]
    [InlineData(429, """{"error":"busy"}""", AssistantOutcome.Busy)]
    [InlineData(429, """{"error":"daily_limit"}""", AssistantOutcome.Limited)]
    [InlineData(400, "{}", AssistantOutcome.Rejected)]
    [InlineData(413, "", AssistantOutcome.Rejected)]
    [InlineData(502, """{"error":"model_failed"}""", AssistantOutcome.Failed)]
    [InlineData(500, "<html>", AssistantOutcome.Failed)]
    public async Task Mapping(int status, string body, AssistantOutcome expected) =>
        Assert.Equal(expected, (await Ask(status, body)).Outcome);

    [Fact]
    public async Task RetryAfter_Read()
    {
        Assert.Equal(TimeSpan.FromSeconds(30), (await Ask(429, """{"error":"busy"}""", TimeSpan.FromSeconds(30))).RetryAfter);
    }

    [Fact]
    public async Task Request_UrlAndHeaders()
    {
        var handler = StubHandler.Json(HttpStatusCode.OK, """{"reply":"ok"}""");
        await new AssistantClient(new HttpClient(handler), Root).AskAsync(Context, [AssistantMessage.User("selam")]);
        var (request, body) = handler.Requests.Single();
        Assert.Equal("https://pool.example/v1/assistant", request.RequestUri!.ToString());
        Assert.Equal("application/json; charset=utf-8", request.Content!.Headers.ContentType!.ToString());
        Assert.Empty(request.Headers.UserAgent);
        Assert.Contains("\"role\":\"user\"", body);
    }

    [Fact]
    public async Task Offline_NoRoot_Invalid_Fail()
    {
        Assert.Equal(AssistantOutcome.Failed, (await new AssistantClient(new HttpClient(new OfflineHandler()), Root)
            .AskAsync(Context, [AssistantMessage.User("a")])).Outcome);
        Assert.Equal(AssistantOutcome.Failed, (await new AssistantClient(new HttpClient(new OfflineHandler()), null)
            .AskAsync(Context, [AssistantMessage.User("a")])).Outcome);
        var handler = StubHandler.Json(HttpStatusCode.OK, """{"reply":"ok"}""");
        Assert.Equal(AssistantOutcome.Failed, (await new AssistantClient(new HttpClient(handler), Root)
            .AskAsync(Context, [AssistantMessage.Nino("a")])).Outcome);
        Assert.Empty(handler.Requests);
    }
}

public sealed class AssistantChatTests
{
    [Fact]
    public async Task Flow_ReplyFailRetry()
    {
        var sent = new List<string[]>();
        var answers = new Queue<AssistantResult>([
            new AssistantResult(AssistantOutcome.Reply, "Merhaba!", "r-1"),
            AssistantResult.Failed,
            new AssistantResult(AssistantOutcome.Reply, "Tamam."),
        ]);
        var chat = new AssistantChat((messages, _) =>
        {
            lock (sent) sent.Add(messages.Select(m => m.Text).ToArray());
            return Task.FromResult(answers.Dequeue());
        });
        var changes = 0;
        chat.Changed += () => Interlocked.Increment(ref changes);
        Assert.True(chat.IsEmpty);
        Assert.True(chat.Send("selam"));
        await chat.LastRun;
        Assert.Equal(new NinoChatEntry("Merhaba!", "r-1"), chat.Entries[1]);
        Assert.True(chat.Send(" Televizyonum LG "));
        await chat.LastRun;
        Assert.IsType<AlertChatEntry>(chat.Entries[^1]);
        Assert.True(chat.CanRetry);
        Assert.True(chat.Retry());
        await chat.LastRun;
        Assert.Equal(["selam", "Merhaba!", "Televizyonum LG"], sent[2]);
        Assert.DoesNotContain(chat.Entries, e => e is AlertChatEntry);
        Assert.Equal("Tamam.", ((NinoChatEntry)chat.Entries[^1]).Text);
        Assert.False(chat.IsWaiting);
        Assert.True(changes >= 6);
    }

    [Fact]
    public async Task Disabled_NotRetriable()
    {
        var chat = new AssistantChat((_, _) => Task.FromResult(new AssistantResult(AssistantOutcome.Disabled)));
        chat.Send("selam");
        await chat.LastRun;
        var alert = Assert.IsType<AlertChatEntry>(chat.Entries[^1]);
        Assert.False(alert.Retriable);
        Assert.True(alert.OffersReport);
        Assert.Equal("ask.alert.disabled", alert.TextKey);
        Assert.False(chat.Retry());
        Assert.Single(chat.OutgoingMessages());
    }

    [Fact]
    public async Task Waiting_BlocksSecondSend_NewChatIgnoresLateReply()
    {
        var gate = new TaskCompletionSource<AssistantResult>();
        var chat = new AssistantChat((_, _) => gate.Task);
        Assert.True(chat.Send("bir"));
        Assert.True(chat.IsWaiting);
        Assert.False(chat.Send("iki"));
        Assert.False(chat.CanSend("iki", 0));
        chat.NewChat();
        gate.SetResult(new AssistantResult(AssistantOutcome.Reply, "geç"));
        await chat.LastRun;
        Assert.Empty(chat.Entries);
        Assert.False(chat.IsWaiting);
    }

    [Fact]
    public async Task EmptyNotSent_FourPhotosKeepThree()
    {
        var chat = new AssistantChat((_, _) => Task.FromResult(new AssistantResult(AssistantOutcome.Reply, "ok")));
        Assert.False(chat.Send("   "));
        Assert.False(chat.Send(null, []));
        Assert.True(chat.Send("", [[1], [2], [3], [4]]));
        await chat.LastRun;
        Assert.Equal(3, ((UserChatEntry)chat.Entries[0]).Images.Count);
    }

    [Fact]
    public async Task Throwing_BecomesFailed()
    {
        var chat = new AssistantChat((_, _) => throw new IOException("dosya"));
        chat.Send("a");
        await chat.LastRun;
        Assert.True(chat.CanRetry);
    }
}

public sealed class AssistantOptionsTests
{
    static readonly Uri Root = new("https://pool.example");
    static readonly AssistantContext Context = new() { Install = "install-1234", App = "1.0", Language = "tr" };

    const string Question = "Nino'yu hangi TV'de kullanıyorsun?\n\n1. Samsung TV\n2. LG TV\n3. Android TV";

    static Task<AssistantResult> Ask(string body) =>
        new AssistantClient(new HttpClient(StubHandler.Json(HttpStatusCode.OK, body)), Root)
            .AskAsync(Context, [AssistantMessage.User("selam")]);

    static IReadOnlyList<string> Read(string json) => AssistantOptions.Read(JsonDocument.Parse(json).RootElement);

    [Fact]
    public async Task Options_Read_ReplyUntouched()
    {
        var body = JsonSerializer.Serialize(new { ok = true, reply = Question, report = (string?)null,
            options = new[] { "Samsung TV", "LG TV", "Android TV" } });
        var r = await Ask(body);
        Assert.Equal(AssistantOutcome.Reply, r.Outcome);
        Assert.Equal(Question, r.Reply);
        Assert.Equal(["Samsung TV", "LG TV", "Android TV"], r.Options);
    }

    [Theory]
    [InlineData("""{"reply":"x"}""")]
    [InlineData("""{"reply":"x","options":null}""")]
    [InlineData("""{"reply":"x","options":"Samsung TV"}""")]
    [InlineData("""{"reply":"x","options":{"a":"b"}}""")]
    [InlineData("""{"reply":"x","options":[1,true,null,"  ",""]}""")]
    public async Task Options_MissingOrBroken_Empty(string body)
    {
        var r = await Ask(body);
        Assert.Equal(AssistantOutcome.Reply, r.Outcome);
        Assert.Empty(r.Options);
    }

    [Fact]
    public async Task Options_OnlyOnReply()
    {
        var r = await new AssistantClient(new HttpClient(StubHandler.Json(HttpStatusCode.TooManyRequests,
            """{"error":"busy","options":["a"]}""")), Root).AskAsync(Context, [AssistantMessage.User("selam")]);
        Assert.Equal(AssistantOutcome.Busy, r.Outcome);
        Assert.Empty(r.Options);
    }

    [Fact]
    public void Limits_CountLengthEmptyDuplicates()
    {
        var many = JsonSerializer.Serialize(Enumerable.Range(1, 12).Select(i => "Seçenek " + i));
        Assert.Equal(AssistantOptions.MaxCount, Read(many).Count);
        Assert.Equal("Seçenek 8", Read(many)[^1]);
        var mixed = JsonSerializer.Serialize(new object[]
            { "  LG TV  ", "", "   ", new string('a', AssistantOptions.MaxLength + 1), new string('b', AssistantOptions.MaxLength), "LG TV", 5, "تلفاز سامسونج" });
        Assert.Equal(["LG TV", new string('b', AssistantOptions.MaxLength), "تلفاز سامسونج"], Read(mixed));
        Assert.Same(AssistantOptions.None, Read("[]"));
    }

    static AssistantChat Chat(Queue<AssistantResult> answers, List<AssistantMessage[]> sent, SemaphoreSlim? gate = null) =>
        new(async (messages, _) =>
        {
            lock (sent) sent.Add(messages.ToArray());
            // Kapı verilirse cevap, test izin verene kadar bekler (gönderim hemen biterse iddialarla yarışır).
            if (gate is not null) await gate.WaitAsync();
            lock (answers) return answers.Dequeue();
        });

    static AssistantResult WithOptions(string reply, params string[] options) =>
        new(AssistantOutcome.Reply, reply) { Options = options };

    [Fact]
    public async Task Choose_SendsLabelVerbatim_HistoryKeepsRawReply()
    {
        var sent = new List<AssistantMessage[]>();
        var chat = Chat(new([WithOptions(Question, "Samsung TV", "LG TV", "Android TV"), new(AssistantOutcome.Reply, "Tamam.")]), sent);
        chat.Send("altyazı çıkmıyor");
        await chat.LastRun;
        Assert.Equal(["Samsung TV", "LG TV", "Android TV"], chat.ActiveOptions);
        Assert.Equal(Question, ((NinoChatEntry)chat.Entries[^1]).Text);

        Assert.False(chat.Choose("Philips TV"));
        Assert.False(chat.Choose("lg tv"));
        Assert.True(chat.Choose("LG TV"));
        Assert.Empty(chat.ActiveOptions);
        Assert.False(chat.Choose("LG TV"));
        await chat.LastRun;

        var last = sent[^1];
        Assert.Equal(["altyazı çıkmıyor", Question, "LG TV"], last.Select(m => m.Text));
        Assert.Equal([AssistantRole.User, AssistantRole.Assistant, AssistantRole.User], last.Select(m => m.Role));
        Assert.Empty(((UserChatEntry)chat.Entries[2]).Images);
        // Sunucuya giden gövdede de reply birebir.
        var json = JsonDocument.Parse(AssistantPayload.Build(Context, last)!);
        Assert.Equal(Question, json.RootElement.GetProperty("messages")[1].GetProperty("text").GetString());
        Assert.Empty(chat.ActiveOptions);
        Assert.All(chat.Entries.OfType<NinoChatEntry>(), n => Assert.Empty(n.Options));
    }

    [Fact]
    public async Task OptionsCleared_WhenUserTypes_AndOnlyLastBalloonHolds()
    {
        var sent = new List<AssistantMessage[]>();
        using var gate = new SemaphoreSlim(0);
        var chat = Chat(new([
            WithOptions(Question, "Samsung TV", "LG TV"),
            WithOptions("Altyazı nerede görünüyor?\n\n1. TV'de\n2. Bilgisayarda", "TV'de", "Bilgisayarda"),
            AssistantResult.Failed,
            new(AssistantOutcome.Reply, "Tamam."),
        ]), sent, gate);
        chat.Send("yardım");
        gate.Release();
        await chat.LastRun;
        Assert.True(chat.Send("Samsung"));
        Assert.Empty(chat.ActiveOptions);
        Assert.Empty(((NinoChatEntry)chat.Entries[1]).Options);
        Assert.False(chat.Choose("LG TV"));
        gate.Release(3);
        await chat.LastRun;
        Assert.Equal(["TV'de", "Bilgisayarda"], chat.ActiveOptions);
        Assert.Single(chat.Entries.OfType<NinoChatEntry>(), n => n.Options.Count > 0);

        // Gönderim başarısız: uyarı son girdi, seçenek yok; tekrar denemede eski seçenekler geri gelmez.
        Assert.True(chat.Choose("TV'de"));
        await chat.LastRun;
        Assert.Empty(chat.ActiveOptions);
        Assert.True(chat.Retry());
        await chat.LastRun;
        Assert.Empty(chat.ActiveOptions);
        Assert.Equal("TV'de", sent[^1][^1].Text);
        Assert.Equal(sent[^2].Select(m => m.Text), sent[^1].Select(m => m.Text));
    }

    [Fact]
    public async Task NewReplyWithoutOptions_ClearsThem()
    {
        var chat = Chat(new([WithOptions(Question, "Samsung TV"), new(AssistantOutcome.Reply, "Oldu mu?")]), []);
        chat.Send("a");
        await chat.LastRun;
        chat.Choose("Samsung TV");
        await chat.LastRun;
        Assert.Empty(chat.ActiveOptions);
        Assert.Equal("Oldu mu?", ((NinoChatEntry)chat.Entries[^1]).Text);
    }

    [Fact]
    public async Task Waiting_ChooseRefused()
    {
        var gate = new TaskCompletionSource<AssistantResult>();
        var calls = 0;
        var chat = new AssistantChat((_, _) => ++calls == 1 ? Task.FromResult(WithOptions(Question, "LG TV")) : gate.Task);
        chat.Send("a");
        await chat.LastRun;
        Assert.True(chat.Choose("LG TV"));
        Assert.True(chat.IsWaiting);
        Assert.False(chat.Choose("LG TV"));
        gate.SetResult(new AssistantResult(AssistantOutcome.Reply, "ok"));
        await chat.LastRun;
        Assert.Equal(2, calls);
    }
}

public sealed class ReplyBlocksTests
{
    [Fact]
    public void Example_Steps()
    {
        var blocks = ReplyBlocks.Parse(
            "Şunu dene:\r\n\r\n1. Nino'yu yeniden başlat.\n2) https://nino.example/kurulum sayfasını aç.\n   Sayfa açılmazsa bekle.\n\nHâlâ olmazsa haber ver.\nSonra yine bakarız.");
        Assert.Equal(4, blocks.Count);
        Assert.Equal(new ReplyBlock(ReplyBlockKind.Paragraph, "Şunu dene:"), blocks[0]);
        Assert.Equal(new ReplyBlock(ReplyBlockKind.Step, "Nino'yu yeniden başlat.", 1), blocks[1]);
        Assert.Equal(ReplyBlockKind.Step, blocks[2].Kind);
        Assert.Equal(2, blocks[2].Number);
        Assert.Equal("https://nino.example/kurulum sayfasını aç.\nSayfa açılmazsa bekle.", blocks[2].Text);
        var inl = blocks[2].Inlines;
        Assert.Equal(new Uri("https://nino.example/kurulum"), inl[0].Link);
        Assert.Equal(" sayfasını aç.\nSayfa açılmazsa bekle.", inl[1].Text);
        Assert.Equal(new ReplyBlock(ReplyBlockKind.Paragraph, "Hâlâ olmazsa haber ver.\nSonra yine bakarız."), blocks[3]);
    }

    [Fact]
    public void Steps_SplitInsideParagraph()
    {
        var blocks = ReplyBlocks.Parse("Yap:\n1. bir\n2. iki\n10. not: 2.5 dakika sürebilir.");
        Assert.Equal([ReplyBlockKind.Paragraph, ReplyBlockKind.Step, ReplyBlockKind.Step, ReplyBlockKind.Step],
            blocks.Select(b => b.Kind));
        Assert.Equal(new ReplyBlock(ReplyBlockKind.Step, "not: 2.5 dakika sürebilir.", 10), blocks[3]);
    }

    [Fact]
    public void Bullets()
    {
        var blocks = ReplyBlocks.Parse("Gerekenler:\n- PS5\n• Ücretsiz bir PSN hesabı\n* Ortak ev ağı\n\n2025. yılındaki sürümler de çalışır.");
        Assert.Equal(new ReplyBlock(ReplyBlockKind.Paragraph, "Gerekenler:"), blocks[0]);
        Assert.Equal(["PS5", "Ücretsiz bir PSN hesabı", "Ortak ev ağı"],
            blocks.Where(b => b.Kind == ReplyBlockKind.Bullet).Select(b => b.Text));
        Assert.Equal(new ReplyBlock(ReplyBlockKind.Paragraph, "2025. yılındaki sürümler de çalışır."), blocks[^1]);
    }

    [Fact]
    public void NoSpaceAfterMarker_AndBlank()
    {
        Assert.Equal([new ReplyBlock(ReplyBlockKind.Paragraph, "-yok\n1.yok")], ReplyBlocks.Parse("-yok\n1.yok"));
        Assert.Empty(ReplyBlocks.Parse("   \n \t "));
        Assert.Empty(ReplyBlocks.Parse(null));
    }

    [Fact]
    public void Links()
    {
        var parts = ReplyBlocks.SplitLinks("Bak: https://a.example/x?y=1. Ya da (http://b.example/yol), javascript:alert(1) file:///c");
        var links = parts.Where(p => p.Link is not null).Select(p => p.Text).ToArray();
        Assert.Equal(["https://a.example/x?y=1", "http://b.example/yol"], links);
        Assert.Equal("Bak: https://a.example/x?y=1. Ya da (http://b.example/yol), javascript:alert(1) file:///c",
            string.Concat(parts.Select(p => p.Text)));
        Assert.Single(ReplyBlocks.SplitLinks("düz yazı"));
    }
}
