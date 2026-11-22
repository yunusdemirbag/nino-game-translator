// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// Ağa çıkmayan sahte taşıyıcı: istekleri kaydeder, sıradaki yanıtı verir.
final class ProvidersFakeTransport: ProviderTransport, @unchecked Sendable {
    enum Reply { case http(Int, String), offline, delayed(Duration, Int, String) }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: Reply...) { self.replies = replies }

    var count: Int { lock.withLock { requests.count } }
    var last: URLRequest? { lock.withLock { requests.last } }
    func body(_ i: Int = -1) -> [String: Any] {
        let r = lock.withLock { i < 0 ? requests.last : requests[i] }
        return (try? JSONSerialization.jsonObject(with: r?.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.count > 1 ? replies.removeFirst() : (replies.first ?? .offline)
        }
        switch reply {
        case .offline: throw URLError(.notConnectedToInternet)
        case let .http(code, body): return (Data(body.utf8), Self.response(request, code))
        case let .delayed(d, code, body):
            try await Task.sleep(for: d)
            return (Data(body.utf8), Self.response(request, code))
        }
    }

    static func response(_ r: URLRequest, _ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: r.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
    }
}

final class ProvidersClassifierTests: XCTestCase {
    func testStatusTable() {
        let c = { (s: Int, b: String) in ProviderErrorClassifier.classify(status: s, body: Data(b.utf8)) }
        XCTAssertNil(c(200, ""))
        XCTAssertEqual(c(401, ""), .invalidKey)
        XCTAssertEqual(c(403, ""), .invalidKey)
        XCTAssertEqual(c(402, ""), .quotaExhausted)
        XCTAssertEqual(c(429, "{}"), .quotaExhausted)
        XCTAssertEqual(c(400, #"{"error":{"status":"API_KEY_INVALID"}}"#), .invalidKey)
        XCTAssertEqual(c(400, "API key not valid. Please pass"), .invalidKey)
        XCTAssertEqual(c(400, #"{"error":"credit balance exhausted for this org"}"#), .quotaExhausted)
        XCTAssertEqual(c(400, #"{"code":"insufficient_quota"}"#), .quotaExhausted)
        XCTAssertEqual(c(400, "bad model"), .modelRejected)
        XCTAssertEqual(c(404, ""), .modelRejected)
        XCTAssertEqual(c(503, ""), .server(503))
        XCTAssertEqual(ProviderErrorClassifier.classifyDeepL(status: 456), .quotaExhausted)
        XCTAssertEqual(ProviderErrorClassifier.classifyDeepL(status: 403), .invalidKey)
        XCTAssertEqual(ProviderErrorClassifier.classify(transportError: URLError(.timedOut)), .network)
        XCTAssertEqual(ProviderFailure.network.alert, .network)
        XCTAssertNil(ProviderFailure.notReady.alert)
    }

    func testMinuteLimitBody() {
        let body = #"""
        {"error":{"code":429,"details":[
          {"@type":"QuotaFailure","violations":[{"quotaId":"GenerateRequestsPerMinutePerProjectPerModel","quotaValue":"5"}]},
          {"@type":"RetryInfo","retryDelay":"37s"}]}}
        """#
        XCTAssertEqual(ProviderErrorClassifier.classify(status: 429, body: Data(body.utf8)), .minuteLimit(retryAfter: 20, limit: 5))
        let short = body.replacingOccurrences(of: "37s", with: "3s")
        XCTAssertEqual(ProviderErrorClassifier.classify(status: 429, body: Data(short.utf8)), .minuteLimit(retryAfter: 3, limit: 5))
        let daily = body.replacingOccurrences(of: "PerMinutePerProject", with: "PerMinutePerDay")
        XCTAssertEqual(ProviderErrorClassifier.classify(status: 429, body: Data(daily.utf8)), .quotaExhausted)
        let noDelay = #"{"error":{"details":[{"violations":[{"quotaId":"RequestsPerMinute","quotaValue":2}]}]}}"#
        XCTAssertEqual(ProviderErrorClassifier.classify(status: 429, body: Data(noDelay.utf8)), .minuteLimit(retryAfter: 20, limit: 2))
    }

    func testHealthCooldownAndAlertChanges() async {
        let clock = ProvidersClock()
        let seen = ProvidersBox<[ProviderAlert?]>([])
        let h = ProviderHealth(now: { clock.now }, onChange: { a in seen.mutate { $0.append(a) } })
        await h.record(.network)
        var resting = await h.isResting; XCTAssertTrue(resting)
        await h.record(.network)
        clock.advance(60)
        resting = await h.isResting; XCTAssertFalse(resting)
        await h.recordSuccess()
        await h.record(.minuteLimit(retryAfter: 5, limit: nil))
        resting = await h.isResting; XCTAssertTrue(resting)
        XCTAssertEqual(seen.value, [.network, nil])
    }
}

final class ProvidersBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    func mutate(_ f: (inout T) -> Void) { lock.withLock { f(&v) } }
}

final class ProvidersParserTests: XCTestCase {
    func testTable() {
        XCTAssertEqual(AIResponseParser.parse(#"["Bir.", "İki.",]"#, expected: 2), ["Bir.", "İki."])
        XCTAssertEqual(AIResponseParser.parse(#"<think>hmm [x]</think>["Tamam."]"#, expected: 1), ["Tamam."])
        XCTAssertEqual(AIResponseParser.parse("[Köprü yıkıldı., Karşıya yüzmeliyiz.]", expected: 2), ["Köprü yıkıldı.", "Karşıya yüzmeliyiz."])
        XCTAssertEqual(AIResponseParser.parse("[Fener sönmek üzere.]", expected: 1), ["Fener sönmek üzere."])
        XCTAssertEqual(AIResponseParser.parse(#""Merhaba""#, expected: 1), ["Merhaba"])
        XCTAssertNil(AIResponseParser.parse(#"["Bir."]"#, expected: 2))
        XCTAssertEqual(AIResponseParser.parse("```json\n[\"A\",\"B\"]\n```", expected: 2), ["A", "B"])
        XCTAssertEqual(AIResponseParser.parse("<start_of_turn>Selam<end_of_turn><|im_end|>", expected: 1), ["Selam"])
        XCTAssertEqual(AIResponseParser.parse("Bir.\n\nİki.", expected: 2), ["Bir.", "İki."])
        XCTAssertEqual(AIResponseParser.parse("<b>Kalın</b>", expected: 1), ["<b>Kalın</b>"])
    }
}

final class ProvidersCatalogTests: XCTestCase {
    func testBuiltinAndResolve() {
        let c = ModelCatalog.builtin
        XCTAssertEqual(c.defaultModel(for: .gemini)?.id, "gemini-3.5-flash-lite")
        XCTAssertEqual(c.defaultModel(for: .gemini)?.requestsPerMinute, 15)
        XCTAssertEqual(c.models(for: .gemini)[1].thinking, "LOW")
        XCTAssertEqual(c.resolve(.gemini, saved: "gemini-3.6-flash")?.id, "gemini-3.6-flash")
        XCTAssertEqual(c.resolve(.gemini, saved: "eski-model")?.id, "gemini-3.5-flash-lite")
        XCTAssertEqual(c.models(for: .claude).first?.effort, "low")
        XCTAssertNil(c.services["_note"])
    }

    func testParseSkipsBadEntries() {
        let json = #"{"services":{"x":[{"id":"a"},{"label":"no id"}],"_c":"skip"}}"#
        XCTAssertEqual(ModelCatalog.parse(Data(json.utf8))?.services, ["x": [AIModel(id: "a")]])
        XCTAssertNil(ModelCatalog.parse(Data("[]".utf8)))
    }
}

final class ProvidersAITests: XCTestCase {
    let gemini = AIModel(id: "gemini-3.6-flash", thinking: "LOW", freeTier: true, requestsPerMinute: 10)

    func provider(_ service: AIService, _ model: AIModel, key: String? = " k-123 ", base: URL? = nil,
                  transport: ProvidersFakeTransport, budget: RequestBudget = RequestBudget(),
                  health: ProviderHealth = ProviderHealth()) -> AIProvider {
        AIProvider(config: AIProviderConfig(service: service, model: model, apiKey: key, localBaseURL: base),
                   transport: transport, budget: budget, health: health)
    }

    func testGeminiRequestAndResponse() async throws {
        let t = ProvidersFakeTransport(.http(200, #"{"candidates":[{"content":{"parts":[{"text":"düşünüyorum","thought":true},{"text":"[\"Koş!\", \"Saklan.\"]"}]}}]}"#))
        let p = provider(.gemini, gemini, transport: t)
        let out = try await p.translate(sentences: ["Run!", "Hide."], context: [ContextLine("We go.", "Gidiyoruz.")],
                                        game: "God of War", target: "tr")
        XCTAssertEqual(out, ["Koş!", "Saklan."])
        let r = try XCTUnwrap(t.last)
        XCTAssertEqual(r.url?.absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-goog-api-key"), "k-123")
        let body = t.body()
        let gen = body["generationConfig"] as? [String: Any]
        XCTAssertEqual(gen?["maxOutputTokens"] as? Int, 1024)
        XCTAssertEqual((gen?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "LOW")
        let user = (((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(user.hasPrefix("Game: God of War\n\n"))
        XCTAssertTrue(user.contains("English: We go.\nTurkish: Gidiyoruz."))
        XCTAssertTrue(user.hasSuffix(#"["Run!","Hide."]"#))
        XCTAssertEqual(p.engineName, "gemini:gemini-3.6-flash")
        // Gövde sıralı anahtarlı.
        let raw = String(decoding: r.httpBody!, as: UTF8.self)
        XCTAssertTrue(raw.hasPrefix(#"{"contents":"#))
    }

    func testOpenAIAndClaudeShapes() async throws {
        let t1 = ProvidersFakeTransport(.http(200, #"{"choices":[{"message":{"content":"[\"Tamam.\"]"}}]}"#))
        let o = provider(.openai, AIModel(id: "m1", effort: "none"), transport: t1)
        let a = try await o.translate("Okay.", from: "en", to: "tr")
        XCTAssertEqual(a, "Tamam.")
        XCTAssertEqual(t1.last?.value(forHTTPHeaderField: "Authorization"), "Bearer k-123")
        XCTAssertEqual(t1.body()["reasoning_effort"] as? String, "none")
        XCTAssertEqual(t1.body()["max_completion_tokens"] as? Int, 1024)
        XCTAssertEqual((t1.body()["messages"] as? [[String: Any]])?.first?["role"] as? String, "developer")
        XCTAssertNil(t1.body()["temperature"])

        let t2 = ProvidersFakeTransport(.http(200, #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"[\"Evet.\"]"}]}"#))
        let c = provider(.claude, AIModel(id: "c1", effort: "low"), transport: t2)
        let b = try await c.translate("Yes.", from: "en", to: "tr")
        XCTAssertEqual(b, "Evet.")
        XCTAssertEqual(t2.last?.value(forHTTPHeaderField: "x-api-key"), "k-123")
        XCTAssertEqual(t2.last?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual((t2.body()["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(t2.body()["thinking"])
        XCTAssertEqual(t2.body()["max_tokens"] as? Int, 1024)
    }

    func testLocalModelWithoutKeyAndTranslationModel() async throws {
        let base = LocalModelServer.normalize("localhost:11434")!
        let t = ProvidersFakeTransport(.http(200, #"{"choices":[{"message":{"content":"Koş!\nSaklan."}}]}"#))
        let p = provider(.local, AIModel(id: "translategemma:4b"), key: "  ", base: base, transport: t)
        let out = try await p.translate(sentences: ["Run!", "Hide\nnow."], context: [ContextLine("Go.", "Git."), ContextLine("Hm.")],
                                        game: nil, target: "tr")
        XCTAssertEqual(out, ["Koş!", "Saklan."])
        let r = try XCTUnwrap(t.last)
        XCTAssertEqual(r.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
        let body = t.body()
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"]! }, ["user", "assistant", "user"])
        XCTAssertEqual(messages[1]["content"], "Git.")
        XCTAssertTrue(messages[2]["content"]!.hasSuffix("\n\n\nRun!\nHide now."))
        XCTAssertEqual(p.engineName, "local:localhost:11434/translategemma:4b")

        let t2 = ProvidersFakeTransport(.http(200, #"{"choices":[{"message":{"content":"[\"A\"]"}}]}"#))
        let q = provider(.local, AIModel(id: "qwen3"), key: "secret", base: base, transport: t2)
        _ = try await q.translate("x y", from: "en", to: "tr")
        XCTAssertEqual(t2.last?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual((t2.body()["messages"] as? [[String: String]])?.first?["role"], "system")
        XCTAssertTrue(AIPrompt.isTranslationModel("MiLMMT-4B"))
    }

    func testErrorsCooldownAndBudget() async throws {
        let clock = ProvidersClock()
        let t = ProvidersFakeTransport(.http(401, "{}"), .http(200, #"{"choices":[{"message":{"content":"[\"A\"]"}}]}"#))
        let health = ProviderHealth(now: { clock.now })
        let p = provider(.openai, AIModel(id: "m", requestsPerMinute: 1), transport: t,
                         budget: RequestBudget(now: { clock.now }), health: health)
        await providersAssertThrows(try await p.translate("Hi there.", from: "en", to: "tr"), .invalidKey)
        let alert = await health.alert
        XCTAssertEqual(alert, .invalidKey)
        // Dinlenmede: istek gitmez.
        await providersAssertThrows(try await p.translate("Hi there.", from: "en", to: "tr"), .notReady)
        XCTAssertEqual(t.count, 1)
        clock.advance(61)
        // Önceki istek hakkı yedi; pencere geçti, yeni hak var.
        let ok = try await p.translate("Hi there.", from: "en", to: "tr")
        XCTAssertEqual(ok, "A")
        let cleared = await health.alert
        XCTAssertNil(cleared)
        await providersAssertThrows(try await p.translate("Again.", from: "en", to: "tr"), .notReady)
        XCTAssertEqual(t.count, 2)
    }

    func testMinuteLimitLowersBudget() async throws {
        let body = #"{"error":{"details":[{"violations":[{"quotaId":"RequestsPerMinute","quotaValue":"3"}]},{"retryDelay":"2s"}]}}"#
        let budget = RequestBudget()
        let p = provider(.gemini, gemini, transport: ProvidersFakeTransport(.http(429, body)), budget: budget)
        await providersAssertThrows(try await p.translate("Hi.", from: "en", to: "tr"), .minuteLimit(retryAfter: 2, limit: 3))
        let limit = await budget.effectiveLimit(p.engineName, 10)
        XCTAssertEqual(limit, 3)
        let alert = await p.health.alert
        XCTAssertNil(alert)
    }

    func testOfflineAndBadResponse() async {
        let p = provider(.claude, AIModel(id: "c"), transport: ProvidersFakeTransport(.offline))
        await providersAssertThrows(try await p.translate("Hi.", from: "en", to: "tr"), .network)
        let q = provider(.claude, AIModel(id: "c"), transport: ProvidersFakeTransport(.http(200, #"{"content":[]}"#)))
        await providersAssertThrows(try await q.translate("Hi.", from: "en", to: "tr"), .badResponse)
        let r = provider(.claude, AIModel(id: "c"), key: nil, transport: ProvidersFakeTransport(.offline))
        await providersAssertThrows(try await r.translate("Hi.", from: "en", to: "tr"), .notReady)
    }

    func testKeyCheckDoesNotUseBudget() async throws {
        let budget = RequestBudget()
        let model = AIModel(id: "g", requestsPerMinute: 1)
        let t = ProvidersFakeTransport(.http(200, #"{"candidates":[{"content":{"parts":[{"text":"[\"Ben Batman'im.\"]"}]}}]}"#))
        let p = provider(.gemini, model, transport: t, budget: budget)
        let r = await KeyCheck.run(p)
        XCTAssertEqual(r, .valid)
        XCTAssertTrue(r.shouldSave)
        let free = await budget.available(p.engineName, limit: 1)
        XCTAssertTrue(free)
        let user = (((t.body()["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(user.hasSuffix(#"["I'm Batman."]"#))

        let bad = provider(.gemini, model, transport: ProvidersFakeTransport(.http(400, "API_KEY_INVALID")))
        let r2 = await KeyCheck.run(bad)
        XCTAssertEqual(r2, .invalidKey)
        XCTAssertFalse(r2.shouldSave)
        let off = await KeyCheck.run(provider(.gemini, model, transport: ProvidersFakeTransport(.offline)))
        XCTAssertEqual(off, .unreachable)
        XCTAssertEqual(KeyCheck.result(for: ProviderFailure.modelRejected), .modelRejected)
        XCTAssertEqual(KeyCheck.probeConfig(AIProviderConfig(service: .local, model: model)).timeout, 90)
    }

    func testPrompts() {
        let ar = TargetLanguage.find("ar")!
        XCTAssertTrue(AIPrompt.system(for: ar).contains("،"))
        XCTAssertTrue(AIPrompt.system(for: TargetLanguage.find("nl")!).contains("Dutch"))
        let u = AIPrompt.user(sentences: ["A"], context: [], game: nil, language: .turkish)
        XCTAssertFalse(u.contains("Game:"))
        XCTAssertFalse(u.contains("English:"))
        XCTAssertTrue(u.contains("exactly 1 Turkish strings"))
    }
}

func providersAssertThrows<T>(_ expression: @autoclosure () async throws -> T, _ expected: ProviderFailure,
                             file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("bu çağrı \(expected) ile düşmeliydi", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? ProviderFailure, expected, file: file, line: line)
    }
}

final class ProvidersDeepLTests: XCTestCase {
    func testTaggingBodyAndUntag() async throws {
        var g = Glossary()
        g.addTerm("Ghost", "Ghost", exact: true)
        let t = ProvidersFakeTransport(.http(200, #"{"translations":[{"text":"<x>Ghost</x> çatıya tırmandı."},{"text":"A &amp; B"}]}"#))
        let p = DeepLProvider(apiKey: "abc:fx", glossary: g, transport: t)
        let out = try await p.translate(sentences: ["Ghost climbed the roof.", "A & B"], context: ["One.", "Two."], target: "tr")
        XCTAssertEqual(out, ["Ghost çatıya tırmandı.", "A & B"])
        let r = try XCTUnwrap(t.last)
        XCTAssertEqual(r.url?.absoluteString, "https://api-free.deepl.com/v2/translate")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "DeepL-Auth-Key abc:fx")
        let b = t.body()
        XCTAssertEqual(b["text"] as? [String], ["<x>Ghost</x> climbed the roof.", "A &amp; B"])
        XCTAssertEqual(b["tag_handling"] as? String, "xml")
        XCTAssertEqual(b["ignore_tags"] as? [String], ["x"])
        XCTAssertEqual(b["formality"] as? String, "prefer_less")
        XCTAssertEqual(b["context"] as? String, "One.\nTwo.")
        XCTAssertEqual(b["source_lang"] as? String, "EN")
        XCTAssertEqual(b["target_lang"] as? String, "TR")
        XCTAssertEqual(b["preserve_formatting"] as? Bool, true)
        XCTAssertEqual(p.cacheKey("Ghost climbed the roof."), g.fingerprint + "\u{1F}Ghost climbed the roof.")
        XCTAssertEqual(p.cacheKey("Plain."), "Plain.")
    }

    func testPlainOtherLanguageAndErrors() async throws {
        let t = ProvidersFakeTransport(.http(200, #"{"translations":[{"text":"Rennen!"}]}"#))
        let p = DeepLProvider(apiKey: "pro", glossary: BuiltinGlossary.enTr, transport: t)
        _ = try await p.translate(sentences: ["Run & hide!"], context: [], target: "nl")
        XCTAssertEqual(t.last?.url?.host, "api.deepl.com")
        XCTAssertEqual(t.body()["text"] as? [String], ["Run & hide!"])
        XCTAssertNil(t.body()["formality"])
        XCTAssertNil(t.body()["context"])
        await providersAssertThrows(try await p.translate(sentences: ["x"], context: [], target: "hi"), .notReady)
        let q = DeepLProvider(apiKey: "k", transport: ProvidersFakeTransport(.http(456, "")))
        await providersAssertThrows(try await q.translate(sentences: ["x"], context: [], target: "tr"), .quotaExhausted)
        let resting = await q.health.isResting
        XCTAssertTrue(resting)
        let r = DeepLProvider(apiKey: "k", transport: ProvidersFakeTransport(.http(200, #"{"translations":[]}"#)))
        await providersAssertThrows(try await r.translate(sentences: ["x"], context: [], target: "tr"), .badResponse)
        let check = await KeyCheck.run(DeepLProvider(apiKey: "k", transport: ProvidersFakeTransport(.http(403, ""))))
        XCTAssertEqual(check, .invalidKey)
    }

    func testUsage() async throws {
        let p = DeepLProvider(apiKey: "k:fx", transport: ProvidersFakeTransport(.http(200, #"{"character_count":500000,"character_limit":500000}"#)))
        let u = try await p.usage()
        XCTAssertTrue(u.exhausted)
    }
}

final class ProvidersLocalServerTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(LocalModelServer.normalize("localhost:11434")?.absoluteString, "http://localhost:11434/v1")
        XCTAssertEqual(LocalModelServer.normalize("http://localhost:1234/v1/chat/completions/")?.absoluteString,
                       "http://localhost:1234/v1")
        XCTAssertEqual(LocalModelServer.normalize("https://box.local:8080/api/?q=1#x")?.absoluteString, "https://box.local:8080/api")
        XCTAssertNil(LocalModelServer.normalize("ftp://x"))
        XCTAssertNil(LocalModelServer.normalize(""))
        XCTAssertNil(LocalModelServer.normalize("local host"))
        XCTAssertEqual(LocalModelServer.kind(URL(string: "http://localhost:1234/v1")!), .lmStudio)
        XCTAssertEqual(LocalModelServer.kind(URL(string: "http://localhost:11434/v1")!), .ollama)
        XCTAssertEqual(LocalModelServer.kind(URL(string: "http://localhost:9/v1")!), .other)
        XCTAssertEqual(LocalModelServer.modelName("qwen2.5:7b"), "translategemma:4b")
        XCTAssertEqual(LocalModelServer.modelName(" "), "translategemma:4b")
        XCTAssertTrue(LocalModelServer.sameModel("TranslateGemma:4b", "translategemma:4b"))
        XCTAssertTrue(LocalModelServer.sameModel("phi4", "phi4:latest"))
    }

    func testTagsAndPull() async throws {
        let t = ProvidersFakeTransport(.http(200, #"{"models":[{"name":"translategemma:4b"},{"name":"phi4:latest"}]}"#))
        let base = URL(string: "http://localhost:11434/v1")!
        let names = try await LocalModelServer.installedModels(base: base, transport: t)
        XCTAssertEqual(names, ["translategemma:4b", "phi4:latest"])
        XCTAssertEqual(t.last?.url?.absoluteString, "http://localhost:11434/api/tags")
        let pull = LocalModelServer.pullRequest(base: base, model: "translategemma:4b")
        XCTAssertEqual(pull.url?.absoluteString, "http://localhost:11434/api/pull")
        var p = LocalModelServer.PullProgress()
        XCTAssertEqual(p.feed(#"{"status":"pulling","digest":"a","total":100,"completed":50}"#), .running(0.5))
        XCTAssertEqual(p.feed(#"{"status":"pulling","digest":"b","total":100,"completed":100}"#), .running(0.75))
        XCTAssertEqual(p.feed(#"{"status":"pulling","digest":"a","total":100,"completed":100}"#), .running(0.99))
        XCTAssertEqual(p.feed(#"{"status":"success"}"#), .done)
        XCTAssertEqual(p.feed(#"{"error":"disk full"}"#), .failed("disk full"))
    }
}

final class ProvidersPoolTests: XCTestCase {
    let config = NinoPoolProvider.Config(baseURL: URL(string: "https://pool.example.test")!, install: "uuid-1", app: "1.0")

    func testRequestAndAnswer() async throws {
        let t = ProvidersFakeTransport(.http(200, #"{"ok":true,"translations":[{"text":"Koş!","tier":1},{"text":null}],"game":"gta-vi"}"#))
        let p = NinoPoolProvider(config: config, transport: t)
        let a = try await p.ask(lines: ["Run!", "Hide."], context: ["We go."], language: "tr-TR", game: nil)
        XCTAssertEqual(a, .init(translations: ["Koş!", nil], game: "gta-6"))
        XCTAssertEqual(t.last?.url?.absoluteString, "https://pool.example.test/v1/translate")
        let b = t.body()
        XCTAssertEqual(b["v"] as? Int, 1)
        XCTAssertEqual(b["lang"] as? String, "tr")
        XCTAssertEqual(b["game"] as? String, "")
        XCTAssertEqual(b["platform"] as? String, "mac")
        XCTAssertEqual(b["context"] as? [String], ["We go."])
    }

    func testOnly200AndNullFallsThrough() async {
        let p = NinoPoolProvider(config: config, transport: ProvidersFakeTransport(.http(201, #"{"ok":true,"translations":[]}"#)))
        await providersAssertThrows(try await p.ask(lines: ["x"], context: [], language: "tr", game: nil), .server(201))
        let q = NinoPoolProvider(config: config, transport: ProvidersFakeTransport(.http(200, #"{"ok":true,"translations":[{"text":null}]}"#)))
        await providersAssertThrows(try await q.translate("x", from: "en", to: "tr"), .notReady)
    }

    func testDeadlineReturnsNilAndDeliversLate() async {
        let t = ProvidersFakeTransport(.delayed(.milliseconds(400), 200, #"{"ok":true,"translations":[{"text":"Geç."}]}"#))
        let p = NinoPoolProvider(config: config, transport: t)
        let late = expectation(description: "geç yanıt")
        let a = await p.ask(lines: ["Late."], context: [], language: "tr", game: nil, deadlineMs: 100) { answer in
            XCTAssertEqual(answer.translations, ["Geç."])
            late.fulfill()
        }
        XCTAssertNil(a)
        await fulfillment(of: [late], timeout: 3)
        let fast = NinoPoolProvider(config: config, transport: ProvidersFakeTransport(.http(200, #"{"ok":true,"translations":[{"text":"Hızlı."}]}"#)))
        let b = await fast.ask(lines: ["Fast."], context: [], language: "tr", game: nil, deadlineMs: 2000) { _ in XCTFail() }
        XCTAssertEqual(b?.translations, ["Hızlı."])
    }
}
