// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
@testable import NinoMacKit
import XCTest

/// Sırayla hazır yanıt veren sahte HTTP; ağa çıkmaz.
final class ConsoleFakeTransport: PSNHTTPTransport, @unchecked Sendable {
    enum Reply { case ok(Int, String), fail(Error) }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let reply = lock.withLock { () -> Reply in
            requests.append(request)
            return replies.isEmpty ? .ok(500, "") : replies.removeFirst()
        }
        switch reply {
        case let .ok(status, body): return (Data(body.utf8), status)
        case let .fail(error): throw error
        }
    }
}

final class ConsolePSNTests: XCTestCase {
    func testSignInURLHasRecipeQuery() throws {
        let url = PSNAuth.signInURL()
        XCTAssertTrue(url.absoluteString.hasPrefix("https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/authorize?"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let q = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(q["service_entity"], "urn:service-entity:psn")
        XCTAssertEqual(q["response_type"], "code")
        XCTAssertEqual(q["client_id"], "ba495a24-818c-472b-b12d-ff231c1b5745")
        XCTAssertEqual(q["redirect_uri"], "https://remoteplay.dl.playstation.net/remoteplay/redirect")
        XCTAssertEqual(q["scope"], "psn:clientapp referenceDataService:countryConfig.read "
            + "pushNotification:webSocket.desktop.connect sessionManager:remotePlaySession.system.update")
        XCTAssertEqual(q["request_locale"], "en_US")
        XCTAssertEqual(q["ui"], "pr")
        XCTAssertEqual(q["service_logo"], "ps")
        XCTAssertEqual(q["layout_type"], "popup")
        XCTAssertEqual(q["smcid"], "remoteplay")
        XCTAssertEqual(q["prompt"], "always")
        XCTAssertEqual(q["PlatformPrivacyWs1"], "minimal")
        XCTAssertEqual(items.count, 12)
    }

    func testRedirectCode() {
        let url = URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=AbC123&cid=x")!
        XCTAssertEqual(PSNAuth.redirect(from: url), .code("AbC123"))
    }

    func testRedirectErrorJoinsFieldsAndPlusBecomesSpace() {
        let url = URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?error=access_denied"
            + "&error_description=User+denied+access&error_code=4033")!
        XCTAssertEqual(PSNAuth.redirect(from: url), .error("access_denied: User denied access (4033)"))
    }

    func testRedirectIgnoresOtherPagesAndEmptyFields() {
        XCTAssertNil(PSNAuth.redirect(from: URL(string: "https://my.account.sony.com/signin?code=1")!))
        XCTAssertNil(PSNAuth.redirect(from: URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect")!))
        XCTAssertEqual(PSNAuth.redirect(from: URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=")!),
                       .empty)
    }

    func testTokenRequest() throws {
        let r = PSNAuth.tokenRequest(code: "a b+c")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.absoluteString, "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token")
        XCTAssertFalse(r.httpShouldHandleCookies)
        XCTAssertEqual(r.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(r.timeoutInterval, 30)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let basic = Data("ba495a24-818c-472b-b12d-ff231c1b5745:mvaiZkRsAsI1IBkY".utf8).base64EncodedString()
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Basic \(basic)")
        let body = String(decoding: try XCTUnwrap(r.httpBody), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("grant_type=authorization_code&code=a%20b%2Bc&scope=psn%3Aclientapp%20"))
        XCTAssertTrue(body.hasSuffix("&redirect_uri=https%3A%2F%2Fremoteplay.dl.playstation.net%2Fremoteplay%2Fredirect"))
    }

    func testAccountRequestPutsTokenInPath() {
        let r = PSNAuth.accountRequest(accessToken: "tok-123")
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertEqual(r.url?.absoluteString, "https://auth.api.sonyentertainmentnetwork.com/2.0/oauth/token/tok-123")
        XCTAssertNotNil(r.value(forHTTPHeaderField: "Authorization"))
    }

    func testUserIDBecomesLittleEndianBytes() {
        XCTAssertEqual(PSNAuth.accountID(userID: "1"), Data([1, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(PSNAuth.accountID(userID: "258"), Data([2, 1, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(PSNAuth.accountID(userID: "18446744073709551615"), Data(repeating: 0xFF, count: 8))
        XCTAssertNil(PSNAuth.accountID(userID: "abc"))
        XCTAssertNil(PSNAuth.accountID(userID: "-1"))
    }

    func testAccountIDFromJSONStringOrNumber() throws {
        XCTAssertEqual(try PSNAuth.accountID(status: 200, body: Data(#"{"user_id":"513"}"#.utf8)), Data([1, 2, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(try PSNAuth.accountID(status: 200, body: Data(#"{"user_id":513}"#.utf8)), Data([1, 2, 0, 0, 0, 0, 0, 0]))
        XCTAssertThrowsError(try PSNAuth.accountID(status: 200, body: Data(#"{"other":1}"#.utf8))) {
            XCTAssertEqual($0 as? PSNLoginError, .unreadable(detail: nil))
        }
        XCTAssertThrowsError(try PSNAuth.accountID(status: 200, body: Data("<html>oops</html>".utf8))) {
            XCTAssertEqual($0 as? PSNLoginError, .unreadable(detail: "<html>oops</html>"))
        }
    }

    func testStatusClassification() {
        func err(_ status: Int, _ body: String) -> PSNLoginError? {
            do { _ = try PSNAuth.accessToken(status: status, body: Data(body.utf8)); return nil } catch {
                return error as? PSNLoginError
            }
        }
        XCTAssertEqual(err(401, #"{"error":"invalid_client","error_description":"Bad client"}"#),
                       .rejected(detail: "HTTP 401, invalid_client Bad client"))
        XCTAssertEqual(err(400, "{}"), .rejected(detail: "HTTP 400"))
        XCTAssertEqual(err(429, "slow down"), .tooManyAttempts(detail: "HTTP 429, slow down"))
        XCTAssertEqual(err(400, #"{"error":"too_many_requests"}"#), .tooManyAttempts(detail: "HTTP 400, too_many_requests"))
        XCTAssertEqual(err(503, ""), .server(detail: "HTTP 503"))
        XCTAssertEqual(err(500, String(repeating: "x", count: 300)), .server(detail: "HTTP 500, " + String(repeating: "x", count: 200)))
        XCTAssertNil(err(200, #"{"access_token":"t"}"#))
    }

    func testFetcherRunsBothRequestsAndReturnsID() async throws {
        let transport = ConsoleFakeTransport([.ok(200, #"{"access_token":"T0K"}"#), .ok(200, #"{"user_id":"4294967296"}"#)])
        let id = try await PSNAccountIDFetcher(transport: transport).accountID(for: .code("C0DE"))
        XCTAssertEqual(id, Data([0, 0, 0, 0, 1, 0, 0, 0]))
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[1].url?.lastPathComponent, "T0K")
    }

    func testFetcherErrors() async {
        func run(_ redirect: PSNAuth.Redirect, _ replies: [ConsoleFakeTransport.Reply]) async -> PSNLoginError? {
            do { _ = try await PSNAccountIDFetcher(transport: ConsoleFakeTransport(replies)).accountID(for: redirect); return nil } catch {
                return error as? PSNLoginError
            }
        }
        let r1 = await run(.error("access_denied"), [])
        XCTAssertEqual(r1, .rejected(detail: "access_denied"))
        let r2 = await run(.error("rate limit exceeded"), [])
        XCTAssertEqual(r2, .tooManyAttempts(detail: "rate limit exceeded"))
        let r3 = await run(.empty, [])
        XCTAssertEqual(r3, .incomplete)
        let r4 = await run(.code("c"), [.fail(URLError(.notConnectedToInternet))])
        guard case .network = r4 else { return XCTFail("\(String(describing: r4))") }
        let r5 = await run(.code("c"), [.ok(200, #"{"access_token":"t"}"#), .ok(403, "{}")])
        XCTAssertEqual(r5, .rejected(detail: "HTTP 403"))
    }

    func testFlowCapturesRedirectOnce() {
        var flow = PSNLoginFlow()
        XCTAssertEqual(flow.decide(url: URL(string: "https://my.account.sony.com/")), .allow)
        let redirect = URL(string: "https://remoteplay.dl.playstation.net/remoteplay/redirect?code=X")
        XCTAssertEqual(flow.decide(url: redirect), .cancel(capture: .code("X")))
        XCTAssertEqual(flow.decide(url: redirect), .cancel(capture: nil))
        XCTAssertNil(flow.closedWithoutRedirect())
    }

    func testFlowPageProblems() {
        var flow = PSNLoginFlow()
        XCTAssertEqual(flow.closedWithoutRedirect(), .windowClosed)
        flow.mainFrameResponse(status: 503)
        XCTAssertEqual(flow.closedWithoutRedirect(), .pageFailed(detail: "HTTP 503"))
        flow.mainFrameResponse(status: 200)
        XCTAssertEqual(flow.closedWithoutRedirect(), .windowClosed)
        flow.mainFrameResponse(status: 429)
        XCTAssertEqual(flow.closedWithoutRedirect(), .tooManyAttempts(detail: "HTTP 429"))
        flow.mainFrameResponse(status: 200)
        flow.loadFailed(domain: NSURLErrorDomain, code: NSURLErrorCancelled, description: "cancelled")
        flow.loadFailed(domain: "WebKitErrorDomain", code: 102, description: "interrupted")
        XCTAssertEqual(flow.closedWithoutRedirect(), .windowClosed)
        flow.loadFailed(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, description: "timed out")
        XCTAssertEqual(flow.closedWithoutRedirect(), .pageFailed(detail: "timed out"))
    }

    func testManualAccountIDAndMask() {
        let id = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let b64 = id.base64EncodedString()
        XCTAssertEqual(b64.count, 12)
        XCTAssertEqual(PSNAuth.manualAccountID(" " + b64.prefix(6) + " " + b64.dropFirst(6) + "\n"), id)
        XCTAssertNil(PSNAuth.manualAccountID("AbCdEfGhIjk"))
        XCTAssertNil(PSNAuth.manualAccountID("AAAAAAAAAAAAAAAA"))
        XCTAssertNil(PSNAuth.manualAccountID("!!!!!!!!!!!="))
        XCTAssertEqual(PSNAuth.maskedAccountID(id), String(b64.prefix(4)) + "••••" + String(b64.suffix(4)))
        XCTAssertEqual(PSNAuth.maskedAccountID(Data([1])), "AQ==")
    }

    func testErrorMessagesCarryDetailAndLogPath() {
        let m = PSNLoginError.rejected(detail: "HTTP 401").message(logPath: "/tmp/remoteplay.log")
        XCTAssertTrue(m.contains("(HTTP 401)"))
        XCTAssertTrue(m.hasSuffix("/tmp/remoteplay.log"))
        XCTAssertFalse(PSNLoginError.windowClosed.message(logPath: "/tmp/remoteplay.log").contains("remoteplay.log"))
        XCTAssertFalse(PSNLoginError.rejected(detail: nil).message(logPath: "/x").contains("console.psn"))
    }

    @MainActor
    func testControllerSavesAccountIDAndManualEntry() async throws {
        let store = MemoryConsoleRecordStore()
        let transport = ConsoleFakeTransport([.ok(200, #"{"access_token":"t"}"#), .ok(200, #"{"user_id":"7"}"#)])
        let c = PSNLoginController(store: store, log: .discard, fetcher: PSNAccountIDFetcher(transport: transport))
        var results: [Result<Data, PSNLoginError>] = []
        c.onFinish = { results.append($0) }
        c.begin()
        XCTAssertTrue(c.isPresented)
        await c.complete(with: .code("x"))
        XCTAssertEqual(try store.loadAccountID(), Data([7, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertFalse(c.isWorking)

        c.signOut()
        XCTAssertNil(try store.loadAccountID())
        XCTAssertFalse(c.enterManually("nope"))
        XCTAssertTrue(c.enterManually(Data([9, 9, 9, 9, 9, 9, 9, 9]).base64EncodedString()))
        XCTAssertEqual(try store.loadAccountID(), Data(repeating: 9, count: 8))
        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func testControllerCancelBeforeRedirectReportsWindowClosed() {
        let c = PSNLoginController(store: MemoryConsoleRecordStore(), log: .discard,
                                   fetcher: PSNAccountIDFetcher(transport: ConsoleFakeTransport([])))
        c.begin()
        c.cancel()
        XCTAssertEqual(c.lastError, .windowClosed)
        XCTAssertFalse(c.isPresented)
    }
}
