// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Net;
using Nino.Core.Translation;
using Nino.Translation.Online;

namespace Nino.Translation.Tests.Online;

public class AiProtocolTests
{
    [Theory]
    [InlineData("```json\n[\"Kapıyı aç.\", \"Arkamda kal.\"]\n```", 2, "Kapıyı aç.|Arkamda kal.")]
    [InlineData("“Kapıyı aç.”", 1, "Kapıyı aç.")]
    [InlineData("<think>…</think>Kapıyı aç.", 1, "Kapıyı aç.")]
    [InlineData("[Köprüye ulaşmalıyız.]", 1, "Köprüye ulaşmalıyız.")]
    [InlineData("[Sus, dinle, kımıldama.]", 1, "Sus, dinle, kımıldama.")]
    [InlineData("<think>\nÖnce düşündüm.\n</think>\n[Çek elini oradan!]", 1, "Çek elini oradan!")]
    [InlineData("```json\n[Feneri söndür.]\n```", 1, "Feneri söndür.")]
    [InlineData("[\"Ona \"bekle\" dedim.\"]", 1, "Ona \"bekle\" dedim.")]
    [InlineData("[iç çekiyor] Yine mi sen?", 1, "[iç çekiyor] Yine mi sen?")]
    [InlineData("[\"Eğil!\"]</s>", 1, "Eğil!")]
    [InlineData("[Eğil!]</s>", 1, "Eğil!")]
    [InlineData("Çık dışarı!<|im_end|>", 1, "Çık dışarı!")]
    [InlineData("<s>[\"Bir.\", \"İki.\",]<|eot_id|>", 2, "Bir.|İki.")]
    [InlineData("[\"<i> işareti durur\"]", 1, "<i> işareti durur")]
    [InlineData("[Birinci satır., İkinci satır.]", 2, "Birinci satır.|İkinci satır.")]
    [InlineData("[\n  Kapıyı aç.,\n  Arkamda kal.\n]", 2, "Kapıyı aç.|Arkamda kal.")]
    [InlineData("<think>…</think>[Eğil!, Sus!]", 2, "Eğil!|Sus!")]
    [InlineData("[Evet, kaptan., Hayır, kalıyorum.]", 2, "Evet, kaptan.|Hayır, kalıyorum.")]
    [InlineData("[Sus, dinle, kımıldama!, Peki.]", 2, "Sus, dinle, kımıldama!|Peki.")]
    [InlineData("[Korkma, ortak.\nBen bakarım, dert etme.]", 2, "Korkma, ortak.|Ben bakarım, dert etme.")]
    [InlineData("[Hey, Sen]", 2, "Hey|Sen")]
    [InlineData("Şimdi çıkıyoruz.\nArkamda kal.", 2, "Şimdi çıkıyoruz.|Arkamda kal.")]
    [InlineData("<think>\nThe user wants [\"x\"] translated…\n</think>\n\n[\"Koş!\"]", 1, "Koş!")]
    public void YanitOkuma(string text, int count, string expected) =>
        Assert.Equal(expected.Split('|'), AiProtocol.ParseList(text, count));

    [Theory]
    [InlineData("[\"Tek\"]", 2)]
    [InlineData("Kapıyı aç. Arkamda kal.", 2)]
    [InlineData("[Birinci satır.]", 2)]
    [InlineData("[Sol., Sağ., Orta.]", 2)]
    [InlineData("[Sus, dinle, kımıldama.]", 2)]
    public void YanitOkumaHatasi(string text, int count)
    {
        var e = Assert.Throws<OnlineRequestException>(() => AiProtocol.ParseList(text, count));
        Assert.Equal(OnlineFailure.Unreachable, e.Failure);
    }

    [Fact]
    public void MetinCikarma()
    {
        Assert.Equal("ab", AiProtocol.ExtractText(AiService.Gemini,
            """{"candidates":[{"content":{"parts":[{"text":"düşünce","thought":true},{"text":"a"},{"text":"b"}]}}]}"""));
        Assert.Equal("x", AiProtocol.ExtractText(AiService.Claude,
            """{"content":[{"type":"thinking","thinking":"..."},{"type":"text","text":"x"}]}"""));
        Assert.Equal("y", AiProtocol.ExtractText(AiService.OpenAi, """{"choices":[{"message":{"content":"y"}}]}"""));
        foreach (var bad in new[] { "not json", "{\"promptFeedback\":{\"blockReason\":\"OTHER\"}}",
                     "{\"choices\":[{\"message\":{\"content\":\"   \"}}]}", "{\"choices\":[{\"message\":{\"content\":5}}]}" })
            Assert.Throws<OnlineRequestException>(() => AiProtocol.ExtractText(AiService.Local, bad));
        // Kullanıcı bildirimi: Gemini'nin reddettiği satır "ulaşılamıyor" sayılıyordu. Ret satıra özeldir.
        Assert.Equal("OTHER", Assert.Throws<OnlineLineRefusedException>(() =>
            AiProtocol.ExtractText(AiService.Gemini, "{\"promptFeedback\":{\"blockReason\":\"OTHER\"}}")).Reason);
        Assert.Equal("SAFETY", Assert.Throws<OnlineLineRefusedException>(() =>
            AiProtocol.ExtractText(AiService.Gemini, "{\"candidates\":[{\"finishReason\":\"SAFETY\",\"index\":0}]}")).Reason);
        // Belirsiz bitiş ve boş aday ulaşılamadı kalır.
        Assert.Throws<OnlineRequestException>(() =>
            AiProtocol.ExtractText(AiService.Gemini, "{\"candidates\":[{\"finishReason\":\"OTHER\"}]}"));
        Assert.Throws<OnlineRequestException>(() => AiProtocol.ExtractText(AiService.Gemini, "{\"candidates\":[]}"));
    }

    static string Violation(string quotaId, object value, string delay) => FakeHandler.Encode(new
    {
        error = new
        {
            details = new object[]
            {
                new { violations = new[] { new { quotaId, quotaValue = value } } },
                new { retryDelay = delay },
            },
        },
    });

    [Fact]
    public void DakikalikSinir()
    {
        var a = AiProtocol.ParseMinuteLimit((HttpStatusCode)429, Violation("GenerateRequestsPerMinutePerProjectPerModel-FreeTier", "10", "37.5s"));
        Assert.Equal(new MinuteLimit(TimeSpan.FromSeconds(37.5), 10), a);
        var b = AiProtocol.ParseMinuteLimit((HttpStatusCode)429, Violation("GenerateContentInputTokensPerModelPerMinute-FreeTier", 250000, "3s"));
        Assert.Equal(new MinuteLimit(TimeSpan.FromSeconds(3), null), b);
        Assert.Null(AiProtocol.ParseMinuteLimit((HttpStatusCode)429, Violation("GenerateRequestsPerDayPerProjectPerModel-FreeTier", 10, "1s")));
        Assert.Null(AiProtocol.ParseMinuteLimit((HttpStatusCode)429, """{"error":{"message":"quota"}}"""));
        Assert.Null(AiProtocol.ParseMinuteLimit(HttpStatusCode.BadRequest, Violation("RequestsPerMinute", 10, "1s")));
        Assert.Null(AiProtocol.ParseMinuteLimit((HttpStatusCode)429, ""));
        Assert.Equal(OnlineFailure.QuotaExhausted, AiProtocol.Failure((HttpStatusCode)429, "").Failure);
        Assert.Null(AiProtocol.Failure((HttpStatusCode)429, "").MinuteLimit);
    }

    [Theory]
    [InlineData(401, "", OnlineFailure.InvalidKey)]
    [InlineData(403, "", OnlineFailure.InvalidKey)]
    [InlineData(402, "", OnlineFailure.QuotaExhausted)]
    [InlineData(429, "insufficient_quota", OnlineFailure.QuotaExhausted)]
    [InlineData(400, """{"error":{"message":"API key not valid. Please pass a valid API key.","details":[{"reason":"API_KEY_INVALID"}]}}""", OnlineFailure.InvalidKey)]
    [InlineData(400, "Your credit balance is too low", OnlineFailure.QuotaExhausted)]
    [InlineData(404, "", OnlineFailure.ModelRejected)]
    [InlineData(400, "the model gpt-x does not exist", OnlineFailure.ModelRejected)]
    [InlineData(529, "", OnlineFailure.Unreachable)]
    [InlineData(500, "", OnlineFailure.Unreachable)]
    public void HataEslemesi(int status, string body, OnlineFailure expected) =>
        Assert.Equal(expected, AiProtocol.MapFailure((HttpStatusCode)status, body));

    [Fact]
    public void Yonergeler()
    {
        Assert.Contains("into Thai", AiPrompts.Instruction("th"));
        Assert.DoesNotContain("Arabic", AiPrompts.Instruction("vi"));
        Assert.Contains("Modern Standard Arabic", AiPrompts.Instruction("ar"));
        Assert.DoesNotContain("Turkish", AiPrompts.Instruction("ar"));
        Assert.Contains("Turkish", AiPrompts.Instruction("tr"));
        var msg = AiPrompts.UserMessage(["Hi"], "ar", null, [new ContextLine("Marco?", "ماركو؟")]);
        Assert.Contains("into Arabic", msg);
        Assert.Contains("Arabic: ماركو؟", msg);
        Assert.DoesNotContain("Turkish", msg);
    }

    [Fact]
    public void CeviriModeliKaliplari()
    {
        var messages = AiPrompts.TranslationModelMessages("translategemma:12b", "tr", ["Open the hatch.", "Keep low."],
            [new ContextLine("Marco?", "Marco?"), new ContextLine("Hm.", null)]);
        Assert.Equal(["user", "assistant", "user"], messages.Select(m => m.Role));
        Assert.Equal(AiPrompts.TranslationModelPrompt("translategemma:12b", "tr", "Marco?"), messages[0].Content);
        Assert.EndsWith("into Turkish:\n\n\nOpen the hatch.\nKeep low.", messages[2].Content);
        Assert.Equal("Translate this from English to Turkish:\nEnglish: Hi\nTurkish:", AiPrompts.TranslationModelPrompt("MiLMMT-7b", "tr", "Hi"));
        Assert.Equal("Translate this from English to Arabic:\nEnglish: Hi\nArabic:", AiPrompts.TranslationModelPrompt("milmmt", "ar", "Hi"));
        Assert.Contains("English (en) to Arabic (ar)", AiPrompts.TranslationModelPrompt("translategemma", "ar", "Hi"));
    }

    [Fact]
    public void HataMetinleri()
    {
        Assert.Equal("Çalışıyor.", OnlineFailureText.Describe(KeyCheckStatus.Valid, "Gemini"));
        Assert.Contains("Gemini", OnlineFailureText.Describe(OnlineFailure.InvalidKey, "Gemini"));
        var ollama = LocalServer.Create("localhost:11434", "qwen2.5:7b")!;
        Assert.Contains("ollama pull qwen2.5:7b", OnlineFailureText.Describe(OnlineFailure.Unreachable, "", ollama));
        var lm = LocalServer.Create(LocalServer.LmStudioUrl, "m")!;
        Assert.Contains("LM Studio", OnlineFailureText.Describe(OnlineFailure.ModelRejected, "", lm));
        Assert.True(EchoCheck.IsEcho("You really came back here?", "You really came back here?"));
        Assert.False(EchoCheck.IsEcho("You really came back here?", "yerel: You really came back here?"));
    }
}
