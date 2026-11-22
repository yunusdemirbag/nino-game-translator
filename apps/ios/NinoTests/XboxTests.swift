// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CoreGraphics
import NinoCore
import XCTest
@testable import Nino

/// Sahte Microsoft/Xbox uçları: istekleri kaydeder, yanıtı verilen kuraldan üretir. Hiçbir istek ağa çıkmaz.
final class FakeXboxWeb: XboxWeb, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [XboxWebRequest] = []
    private let answer: @Sendable (XboxWebRequest, Int) throws -> XboxWebResponse

    /// `answer`'a istek ve aynı adrese (sorgusuz, yöntemle) kaçıncı kez gelindiği verilir.
    init(_ answer: @escaping @Sendable (XboxWebRequest, Int) throws -> XboxWebResponse) { self.answer = answer }

    var requests: [XboxWebRequest] { lock.withLock { log } }

    /// Kaydetmeden yanıt üretir (başka bir sahtenin içinden kullanmak için).
    func send(_ request: XboxWebRequest, _ n: Int) throws -> XboxWebResponse { try answer(request, n) }

    func count(_ part: String, method: String? = nil) -> Int {
        requests.filter { $0.url.contains(part) && (method == nil || $0.method == method) }.count
    }

    func send(_ request: XboxWebRequest) async throws -> XboxWebResponse {
        let n = lock.withLock { () -> Int in
            log.append(request)
            return log.filter { $0.url == request.url && $0.method == request.method }.count
        }
        return try answer(request, n)
    }

    /// Bütün zincir ve ev yayını için kusursuz yanıtlar; `/state` sırayla `states`.
    static func happy(states: [String] = ["Provisioning", "ReadyToConnect", "Provisioned"]) -> FakeXboxWeb {
        FakeXboxWeb { r, n in
            let u = r.url
            if u.contains("user.auth.xboxlive.com") {
                return .init(status: 200, text: #"{"Token":"U1","DisplayClaims":{"xui":[{"uhs":"HASH"}]},"NotAfter":"2099-01-01T00:00:00.0000000Z"}"#)
            }
            if u.contains("xsts.auth.xboxlive.com") {
                return .init(status: 200, text: #"{"Token":"X1","DisplayClaims":{"xui":[{"uhs":"HASH"}]},"NotAfter":"2099-01-01T00:00:00Z"}"#)
            }
            if u.contains("/v2/login/user") {
                return .init(status: 200, text: #"{"offeringSettings":{"regions":[{"baseUri":"https://other.test/","isDefault":false},{"baseUri":"https://home.test/","isDefault":true}]},"gsToken":"GS","durationInSeconds":3600}"#)
            }
            if u.contains("lists/devices") {
                return .init(status: 200, text: #"{"result":[{"id":"F400A","name":"Salon Xbox","consoleType":"XboxSeriesX","powerState":"On","consoleStreamingEnabled":true,"remoteManagementEnabled":true},{"id":"F400B","name":"","consoleType":"XboxOne","powerState":"ConnectedStandby","consoleStreamingEnabled":true,"remoteManagementEnabled":false}]}"#)
            }
            if u.contains("login.live.com") { return .init(status: 200, text: #"{"access_token":"LPT"}"#) }
            if u.hasSuffix("/play") { return .init(status: 200, text: #"{"sessionPath":"/v5/sessions/home/S-1"}"#) }
            if u.hasSuffix("/state") {
                let state = states[min(n - 1, states.count - 1)]
                return .init(status: 200, text: #"{"state":"\#(state)","errorDetails":{"code":null,"message":null}}"#)
            }
            if u.hasSuffix("/sdp") {
                return r.method == "POST" ? .init(status: 202)
                    : .init(status: 200, text: #"{"exchangeResponse":"{\"sdp\":\"v=0 cevap\"}"}"#)
            }
            if u.hasSuffix("/ice") {
                return r.method == "POST" ? .init(status: 202) : .init(status: 200, text: #"{"exchangeResponse":"[{\"candidate\":\"a=candidate:1 1 UDP 1 10.0.0.9 9002 typ host \",\"sdpMid\":\"0\",\"sdpMLineIndex\":0}]"}"#)
            }
            return .init(status: 200)
        }
    }
}

/// Sahte WebRTC: SDP değişince ve adaylar eklenince belirli sayıda kare verir.
final class FakeXboxPeer: XboxPeer, @unchecked Sendable {
    private let lock = NSLock()
    private let sink: XboxFrameSink
    private let frames: Int
    private var reason: String?
    private(set) var answer: String?
    private var pusher: Task<Void, Never>?

    init(frames: Int, sink: @escaping XboxFrameSink) {
        self.frames = frames
        self.sink = sink
    }

    static func image() -> CGImage {
        let ctx = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return ctx.makeImage()!
    }

    func makeOffer() async throws -> String { "v=0 teklif" }
    func acceptAnswer(_ sdp: String) async throws { lock.withLock { answer = sdp } }
    func localCandidates(timeout: TimeInterval) async -> [XboxCandidate] {
        [XboxCandidate(candidate: "candidate:1 1 udp 1 192.168.0.5 50000 typ host", sdpMid: "0", sdpMLineIndex: 0)]
    }

    func addRemoteCandidates(_ candidates: [XboxCandidate]) async -> Int {
        let count = frames, sink = sink
        pusher = Task.detached {
            for _ in 0..<count {
                sink(FakeXboxPeer.image())
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        return candidates.count
    }

    var closedReason: String? { lock.withLock { reason } }
    func drop(_ text: String) { lock.withLock { reason = text } }
    func close() {
        pusher?.cancel()
        lock.withLock { if reason == nil { reason = "kapatıldı" } }
    }
}

final class XboxTests: XCTestCase {
    // MARK: Saklanan kayıtlar (kalicilik.md §3.3–3.4)

    private let legacyToken = Data(#""{\"token_type\":\"bearer\",\"access_token\":\"EwB...\",\"refresh_token\":\"M.C5...\",\"expires_in\":3600,\"expires_on\":\"2026-11-22T15:03:05.123Z\"}""#.utf8)
    private let legacyConsole = Data(#"{"id":"F4000ABCDEF12345","name":"Salon Xbox","model":"XboxSeriesX","streamingEnabled":true,"powerState":"On"}"#.utf8)

    @MainActor
    private func model(_ store: MemoryStore, platform: String? = "xbox", web: XboxWeb = FakeXboxWeb.happy()) -> AppModel {
        let suite = "nino-xbox-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        if let platform { defaults.set(platform, forKey: Keys.platform) }
        return AppModel(store: store, defaults: defaults,
                        folders: AppFolders(support: FileManager.default.temporaryDirectory, logs: FileManager.default.temporaryDirectory),
                        ephemeral: true, xboxWeb: web)
    }

    @MainActor
    func testLegacyKeychainRecordsOpen() throws {
        let store = MemoryStore([Keys.xboxUserToken: legacyToken, Keys.xboxConsole: legacyConsole,
                                 Keys.setupComplete: Data("true".utf8)])
        let m = model(store)
        XCTAssertTrue(m.xboxSignedIn)
        XCTAssertEqual(m.xboxConsole, XboxConsole(id: "F4000ABCDEF12345", name: "Salon Xbox", model: "XboxSeriesX",
                                                  streamingEnabled: true, powerState: "On"))
        XCTAssertEqual(m.step, .done)
        XCTAssertTrue(m.consolePaired)
        XCTAssertEqual(m.consoleName, "Salon Xbox")

        let token = try XCTUnwrap(MicrosoftToken(stored: store.load(String.self, for: Keys.xboxUserToken)))
        XCTAssertEqual(token.accessToken, "EwB...")
        XCTAssertEqual(token.refreshToken, "M.C5...")
        XCTAssertEqual(token.expiresOn.timeIntervalSince1970, 1_795_359_785.123, accuracy: 0.0005)
        XCTAssertEqual(token.fields["token_type"] as? String, "bearer")
    }

    @MainActor
    func testEmptyRefreshTokenMeansSignedOut() {
        let empty = Data(#""{\"access_token\":\"A\",\"refresh_token\":\"\",\"expires_in\":3600,\"expires_on\":\"2026-11-22T15:03:05.123Z\"}""#.utf8)
        let store = MemoryStore([Keys.xboxUserToken: empty, Keys.xboxConsole: legacyConsole, Keys.setupComplete: Data("true".utf8)])
        let m = model(store)
        XCTAssertFalse(m.xboxSignedIn)
        XCTAssertEqual(m.step, .welcome)
        XCTAssertNil(MicrosoftToken(stored: #"{"access_token":"A"}"#))
        XCTAssertNil(MicrosoftToken(stored: "bozuk"))
        XCTAssertNil(MicrosoftToken(stored: nil))
    }

    @MainActor
    func testStoredTokenKeepsFieldsAndUnescapedSlashes() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try MicrosoftToken(response: ["access_token": "a/1", "refresh_token": "r/1", "expires_in": 3600,
                                                  "scope": "xboxlive.signin offline_access", "foo": ["x": 1]], receivedAt: start)
        XCTAssertTrue(first.stored.contains(#""access_token":"a/1""#))
        XCTAssertFalse(first.stored.contains(#"\/"#))
        let again = try XCTUnwrap(MicrosoftToken(stored: first.stored))
        XCTAssertEqual(again.expiresOn.timeIntervalSince(start), 3600, accuracy: 0.001)
        XCTAssertEqual((again.fields["foo"] as? [String: Any])?["x"] as? Int, 1)
        // Yenilemede yeni yenileme jetonu gelmezse eskisi kalır.
        let renewed = try MicrosoftToken(response: ["access_token": "a2", "expires_in": 60], receivedAt: start, keeping: again)
        XCTAssertEqual(renewed.refreshToken, "r/1")
        XCTAssertThrowsError(try MicrosoftToken(response: ["refresh_token": "r"], receivedAt: start))

        // Modelin yazdığı kayıt da aynı biçimde okunur.
        let store = MemoryStore()
        store.save(renewed.stored, for: Keys.xboxUserToken)
        XCTAssertEqual(MicrosoftToken(stored: store.load(String.self, for: Keys.xboxUserToken))?.accessToken, "a2")
    }

    func testMicrosoftDates() throws {
        let seven = try XCTUnwrap(XboxTime.parse("2026-11-22T15:03:05.1234567Z"))
        XCTAssertEqual(seven.timeIntervalSince1970, 1_795_359_785.1234567, accuracy: 0.000001)
        XCTAssertEqual(XboxTime.parse("2026-11-22T15:03:05Z")?.timeIntervalSince1970, 1_795_359_785)
        XCTAssertEqual(XboxTime.parse("2026-11-22T18:03:05.5+03:00")?.timeIntervalSince1970, 1_795_359_785.5)
        XCTAssertNil(XboxTime.parse(""))
        XCTAssertNil(XboxTime.parse("dün"))
        XCTAssertEqual(XboxTime.format(Date(timeIntervalSince1970: 1_795_359_785.123)), "2026-11-22T15:03:05.123Z")
    }

    // MARK: Yanıt ayrıştırma

    func testParsing() throws {
        let code = try DeviceCodeChallenge(response: try XboxJSON.object(#"{"user_code":"ABCD-1234","device_code":"dev","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":5}"#))
        XCTAssertEqual(code, DeviceCodeChallenge(userCode: "ABCD-1234", deviceCode: "dev", verificationURL: "https://www.microsoft.com/link",
                                                 lifetime: 900, interval: 5))
        XCTAssertEqual(code.displayURL, "www.microsoft.com/link")
        XCTAssertThrowsError(try DeviceCodeChallenge(response: ["user_code": "X"]))
        let minimal = try DeviceCodeChallenge(response: ["user_code": "X", "device_code": "Y", "interval": 0])
        XCTAssertEqual(minimal.interval, 1)
        XCTAssertEqual(minimal.lifetime, 900)

        let live = try XboxLiveToken(response: try XboxJSON.object(#"{"Token":"T","DisplayClaims":{"xui":[{"uhs":"42"}]},"NotAfter":"2026-11-22T15:03:05.1234567Z"}"#))
        XCTAssertEqual(live.authorization, "XBL3.0 x=42;T")
        XCTAssertThrowsError(try XboxLiveToken(response: [:]))

        let login = try StreamingLogin(response: try XboxJSON.object(#"{"offeringSettings":{"regions":[{"baseUri":"https://a.test","isDefault":false},{"baseUri":"https://b.test/","isDefault":true}]},"gsToken":"G"}"#),
                                       receivedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(login.baseURL, "https://b.test")
        XCTAssertEqual(login.expires.timeIntervalSince1970, 1800)
        XCTAssertThrowsError(try StreamingLogin(response: ["gsToken": "G"], receivedAt: Date()))

        let list = XboxConsole.list(from: try XboxJSON.object(#"{"result":[{"id":"A","name":"Salon","consoleType":"XboxSeriesS","powerState":"On","consoleStreamingEnabled":true,"remoteManagementEnabled":true},{"id":"B","consoleType":"XboxOne","consoleStreamingEnabled":true,"remoteManagementEnabled":false},{"name":"kimliksiz"}]}"#))
        XCTAssertEqual(list.map(\.id), ["A", "B"])
        XCTAssertEqual(list.map(\.streamingEnabled), [true, false])
        XCTAssertEqual(list[1].displayName, "XboxOne")
        XCTAssertEqual(list[0].powerState, "On")

        XCTAssertEqual(DeviceCodeWait(status: 400, body: Data(#"{"error":"authorization_pending"}"#.utf8)), .keepWaiting)
        XCTAssertEqual(DeviceCodeWait(status: 400, body: Data(#"{"error":"slow_down"}"#.utf8)), .slowDown)
        XCTAssertEqual(DeviceCodeWait(status: 400, body: Data(#"{"error":"expired_token"}"#.utf8)), .expired)
        XCTAssertEqual(DeviceCodeWait(status: 400, body: Data(#"{"error":"authorization_declined"}"#.utf8)), .declined)
        XCTAssertEqual(DeviceCodeWait(status: 503, body: Data()), .keepWaiting)
        XCTAssertEqual(DeviceCodeWait(status: 400, body: Data("?".utf8)), .failed)
    }

    func testStreamStateAndCandidates() {
        XCTAssertNil(XboxStreamState.meaningful(nil))
        XCTAssertNil(XboxStreamState.meaningful(NSNull()))
        XCTAssertNil(XboxStreamState.meaningful(""))
        XCTAssertNil(XboxStreamState.meaningful(["code": NSNull(), "message": ""]))
        XCTAssertNil(XboxStreamState.meaningful(#"{"code":null}"#))
        XCTAssertNotNil(XboxStreamState.meaningful(["code": "InUse"]))
        XCTAssertEqual(XboxStreamState(response: ["state": "Failed", "errorDetails": "Busy"]).errorDetails, "Busy")

        // Teredo: 2001:0:4136:e378:8000:63bf:3fff:fdd2 → 192.0.2.45, port 40000.
        let t = TeredoAddress.decode("2001:0:4136:e378:8000:63bf:3fff:fdd2")
        XCTAssertEqual(t?.ipv4, "192.0.2.45")
        XCTAssertEqual(t?.port, 40000)
        XCTAssertNil(TeredoAddress.decode("2001:db8::1"))
        XCTAssertNil(TeredoAddress.decode("10.0.0.1"))
        XCTAssertEqual(TeredoAddress.ipv6Words("::1"), [0, 0, 0, 0, 0, 0, 0, 1])
        XCTAssertNil(TeredoAddress.ipv6Words("1::2::3"))

        let teredo = XboxCandidate(candidate: "a=candidate:2 1 UDP 1 2001:0:4136:e378:8000:63bf:3fff:fdd2 3074 typ host ", sdpMid: "0", sdpMLineIndex: 0)
        let plain = XboxCandidate(candidate: "a=end-of-candidates", sdpMid: "0", sdpMLineIndex: 0)
        let out = XboxCloud.withTeredoShortcuts([teredo, plain])
        XCTAssertEqual(out.count, 4)
        XCTAssertEqual(out[0].line, "candidate:10 1 UDP 1 192.0.2.45 9002 typ host")
        XCTAssertEqual(out[1].line, "candidate:10 1 UDP 1 192.0.2.45 40000 typ host")
        XCTAssertEqual(out[2], teredo)
        XCTAssertNil(out[3].line)
        XCTAssertTrue(out[0].json["sdpMid"] is String)
        XCTAssertTrue(XboxCandidate(candidate: "x", sdpMid: nil, sdpMLineIndex: 1).json["sdpMid"] is NSNull)
    }

    func testChannelMessages() throws {
        XCTAssertEqual(XboxChannelMessages.clientMetadata(at: 12.5).count, 15)
        let packet = XboxChannelMessages.frameAcks(sequence: 3, at: 100, frames: [
            .init(rtpTimestamp: 0xAABBCCDD, arrivedMs: 90, decodedMs: 95), .init(rtpTimestamp: 1, arrivedMs: 91, decodedMs: 96),
        ])
        XCTAssertEqual(packet.count, 15 + 2 * 28)
        XCTAssertEqual(Array(packet.prefix(2)), [1, 0])
        XCTAssertEqual(packet[14], 2)
        XCTAssertEqual(Array(packet[15..<19]), [0xDD, 0xCC, 0xBB, 0xAA])
        XCTAssertTrue(XboxChannelMessages.isHandshakeAck(#"{"type":"HandshakeAck"}"#))
        XCTAssertFalse(XboxChannelMessages.isHandshakeAck(#"{"type":"Handshake"}"#))
        XCTAssertEqual(XboxChannelMessages.preferStereo("a=fmtp:111 minptime=10;useinbandfec=1\r\nuseinbandfec=1"),
                       "a=fmtp:111 minptime=10;useinbandfec=1; stereo=1\r\nuseinbandfec=1")
        let dims = try XboxJSON.object(XboxChannelMessages.clientMessages(width: 1280, height: 720).last!)
        XCTAssertEqual(dims["target"] as? String, "/streaming/characteristics/dimensionschanged")
        XCTAssertEqual(try XboxJSON.object(dims["content"] as! String)["preferredWidth"] as? Int, 1280)
    }

    // MARK: Hesap ve jeton zinciri

    private final class Saved: @unchecked Sendable {
        let lock = NSLock()
        var tokens: [MicrosoftToken?] = []
        func add(_ t: MicrosoftToken?) { lock.withLock { tokens.append(t) } }
        var all: [MicrosoftToken?] { lock.withLock { tokens } }
    }

    private func token(expiresIn seconds: TimeInterval, now: Date) throws -> MicrosoftToken {
        try MicrosoftToken(response: ["access_token": "old", "refresh_token": "R0", "expires_in": seconds], receivedAt: now)
    }

    func testDeviceCodeSignIn() async throws {
        let now = Date()
        let web = FakeXboxWeb { r, n in
            if r.url.hasSuffix("/devicecode") {
                XCTAssertTrue(r.body?.contains("client_id=1f907974-e22b-4810-a9de-d9647380c97e") == true)
                return .init(status: 200, text: #"{"user_code":"QWER-TY12","device_code":"D","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":5}"#)
            }
            switch n {
            case 1: return .init(status: 400, text: #"{"error":"authorization_pending"}"#)
            case 2: throw XboxFailure(.offline, "uygulama arka planda")
            case 3: return .init(status: 400, text: #"{"error":"slow_down"}"#)
            default: return .init(status: 200, text: #"{"token_type":"bearer","access_token":"A1","refresh_token":"R1","expires_in":3600}"#)
            }
        }
        let saved = Saved()
        let pauses = LatestBox<[TimeInterval]>()
        pauses.set([])
        let account = XboxAccount(web: web, token: nil, now: { now }, pause: { s in pauses.set((pauses.get() ?? []) + [s]) },
                                  onToken: { saved.add($0) })
        let code = try await account.requestCode()
        XCTAssertEqual(code.userCode, "QWER-TY12")
        let token = try await account.waitForApproval(code)
        XCTAssertEqual(token.accessToken, "A1")
        XCTAssertEqual(saved.all.compactMap { $0?.refreshToken }, ["R1"])
        XCTAssertEqual(pauses.get(), [5, 5, 10])
        let signedIn = await account.signedIn
        XCTAssertTrue(signedIn)
        XCTAssertTrue(web.requests.last?.body?.contains("device_code=D") == true)
    }

    func testDeviceCodeEndings() async throws {
        let code = DeviceCodeChallenge(userCode: "U", deviceCode: "D", verificationURL: "https://x.test", lifetime: 900, interval: 1)
        for (error, expected) in [("expired_token", XboxProblem.codeExpired), ("access_denied", .declined), ("weird", .unexpected)] {
            let web = FakeXboxWeb { _, _ in .init(status: 400, text: #"{"error":"\#(error)"}"#) }
            let account = XboxAccount(web: web, token: nil, pause: { _ in })
            do {
                try await account.waitForApproval(code)
                XCTFail("bitmemeliydi")
            } catch let f as XboxFailure {
                XCTAssertEqual(f.problem, expected)
            }
        }
        // Kodun süresi dolunca sormayı bırakır.
        let clock = LatestBox<Date>()
        clock.set(Date())
        let web = FakeXboxWeb { _, _ in .init(status: 400, text: #"{"error":"authorization_pending"}"#) }
        let account = XboxAccount(web: web, token: nil, now: { clock.get()! },
                                  pause: { s in clock.set(clock.get()!.addingTimeInterval(s)) })
        let short = DeviceCodeChallenge(userCode: "U", deviceCode: "D", verificationURL: "", lifetime: 3, interval: 1)
        do {
            try await account.waitForApproval(short)
            XCTFail("bitmemeliydi")
        } catch let f as XboxFailure {
            XCTAssertEqual(f.problem, .codeExpired)
        }
        XCTAssertEqual(web.requests.count, 3)
    }

    func testTokenRefresh() async throws {
        let now = Date()
        let web = FakeXboxWeb { r, _ in
            XCTAssertTrue(r.body?.contains("grant_type=refresh_token") == true)
            XCTAssertTrue(r.body?.contains("refresh_token=R0") == true)
            return .init(status: 200, text: #"{"access_token":"new","expires_in":3600}"#)
        }
        let saved = Saved()
        // Süresi bitmemiş jeton: istek yok.
        let fresh = XboxAccount(web: web, token: try token(expiresIn: 3600, now: now), now: { now }, onToken: { saved.add($0) })
        let a = try await fresh.accessToken()
        XCTAssertEqual(a, "old")
        XCTAssertEqual(web.requests.count, 0)
        // 30 sn kaldı: yenilenir, yenileme jetonu korunur, saklanır.
        let stale = XboxAccount(web: web, token: try token(expiresIn: 30, now: now), now: { now }, onToken: { saved.add($0) })
        let b = try await stale.accessToken()
        XCTAssertEqual(b, "new")
        XCTAssertEqual(saved.all.count, 1)
        XCTAssertEqual(saved.all.first??.refreshToken, "R0")

        // Microsoft yenilemeyi reddederse giriş gerekir.
        let refused = XboxAccount(web: FakeXboxWeb { _, _ in .init(status: 400, text: #"{"error":"invalid_grant"}"#) },
                                  token: try token(expiresIn: 0, now: now), now: { now })
        do {
            _ = try await refused.accessToken()
            XCTFail("hata beklenirdi")
        } catch let f as XboxFailure {
            XCTAssertEqual(f.problem, .needsSignIn)
        }
        let none = XboxAccount(web: web, token: nil)
        do {
            _ = try await none.accessToken()
            XCTFail("hata beklenirdi")
        } catch let f as XboxFailure {
            XCTAssertEqual(f.problem, .needsSignIn)
        }
    }

    func testConsoleListAndProfileErrors() async throws {
        let now = Date()
        let web = FakeXboxWeb.happy()
        let account = XboxAccount(web: web, token: try token(expiresIn: 3600, now: now), now: { now })
        let cloud = XboxCloud(account: account, web: web)
        let list = try await cloud.consoles()
        XCTAssertEqual(list.map(\.id), ["F400A", "F400B"])
        XCTAssertEqual(list.map(\.streamingEnabled), [true, false])
        let listRequest = try XCTUnwrap(web.requests.first { $0.url.contains("lists/devices") })
        XCTAssertEqual(listRequest.headers["Authorization"], "XBL3.0 x=HASH;X1")
        // İkinci istek jetonları bellekten kullanır.
        _ = try await cloud.consoles()
        XCTAssertEqual(web.count("user.auth"), 1)
        XCTAssertEqual(web.count("xsts.auth"), 1)

        for (xerr, expected) in [(2_148_916_233, XboxProblem.noProfile), (2_148_916_238, .noProfile), (1, .needsSignIn)] {
            let w = FakeXboxWeb { r, _ in
                if r.url.contains("user.auth") { return .init(status: 200, text: #"{"Token":"U","NotAfter":"2099-01-01T00:00:00Z"}"#) }
                return .init(status: 401, text: #"{"XErr":\#(xerr)}"#)
            }
            let acc = XboxAccount(web: w, token: try token(expiresIn: 3600, now: now), now: { now })
            do {
                _ = try await XboxCloud(account: acc, web: w).consoles()
                XCTFail("hata beklenirdi")
            } catch let f as XboxFailure {
                XCTAssertEqual(f.problem, expected)
            }
        }
        XCTAssertEqual(XboxCloud.problem(status: 409, text: #"{"code":"InUse"}"#), .busy)
        XCTAssertEqual(XboxCloud.problem(status: 404, text: ""), .unreachable)
        XCTAssertEqual(XboxCloud.problem(status: 403, text: ""), .needsSignIn)
        XCTAssertEqual(XboxCloud.problem(status: 500, text: "?"), .unexpected)
    }

    // MARK: Oturum kuralları

    func testPlanHappyPath() {
        var p = XboxSessionPlan()
        XCTAssertEqual(p.begin(), .open)
        XCTAssertEqual(p.opened(), .askState(after: 0))
        XCTAssertEqual(p.observed(.init(state: "Provisioning", errorDetails: nil), at: 0), .askState(after: 1))
        XCTAssertEqual(p.observed(.init(state: "ReadyToConnect", errorDetails: nil), at: 1), .connect)
        XCTAssertEqual(p.connectAccepted(at: 1), .askState(after: 1))
        // Bağlanma isteği bir kez gider.
        XCTAssertEqual(p.observed(.init(state: "ReadyToConnect", errorDetails: nil), at: 2), .askState(after: 1))
        XCTAssertEqual(p.observed(.init(state: "Provisioned", errorDetails: nil), at: 3), .negotiate)
        XCTAssertTrue(p.firstFrame(at: 4))
        XCTAssertFalse(p.firstFrame(at: 5))
        XCTAssertEqual(p.stage, .live(since: 4))
        // Olmayan sırada gelen olaylar yok sayılır.
        XCTAssertEqual(p.opened(), .nothing)
        XCTAssertEqual(p.connectAccepted(at: 5), .nothing)
    }

    func testPlanRetriesThenGivesUp() {
        var p = XboxSessionPlan()
        var delays: [TimeInterval] = []
        for i in 0..<4 {
            _ = p.begin()
            _ = p.opened()
            if case let .retry(after) = p.fail(.offline, at: Double(i)) { delays.append(after) } else {
                XCTAssertEqual(i, 3)
                XCTAssertEqual(p.stage, .gaveUp(.offline))
            }
        }
        XCTAssertEqual(delays, [5, 15, 45])
        XCTAssertEqual(p.begin(), .open) // durduran oturumdur; plan yeniden açılmayı engellemez
        XCTAssertEqual(p.restartNow(), .open)
    }

    func testPlanHealthyStreamResetsCount() {
        var p = XboxSessionPlan()
        for _ in 0..<2 {
            _ = p.begin(); _ = p.opened()
            _ = p.fail(.timeout, at: 0)
        }
        XCTAssertEqual(p.failures, 2)
        _ = p.begin(); _ = p.opened()
        _ = p.observed(.init(state: "Provisioned", errorDetails: nil), at: 0)
        XCTAssertTrue(p.firstFrame(at: 100))
        XCTAssertEqual(p.fail(.offline, at: 170), .retry(after: 5))
        XCTAssertEqual(p.failures, 1)
        // Kısa süren yayın sayacı sıfırlamaz.
        _ = p.begin(); _ = p.opened()
        _ = p.observed(.init(state: "Provisioned", errorDetails: nil), at: 0)
        _ = p.firstFrame(at: 200)
        XCTAssertEqual(p.fail(.offline, at: 210), .retry(after: 15))
    }

    func testPlanNeverRetriesRefusalsOrSignIn() {
        var p = XboxSessionPlan()
        _ = p.begin(); _ = p.opened()
        XCTAssertEqual(p.observed(.init(state: "Failed", errorDetails: nil), at: 0), .end(.unreachable))
        XCTAssertEqual(p.restartNow(), .nothing)

        p = XboxSessionPlan()
        _ = p.begin(); _ = p.opened()
        XCTAssertEqual(p.observed(.init(state: "Provisioning", errorDetails: #"{"code":"AlreadyStreaming"}"#), at: 0), .end(.busy))

        for problem in [XboxProblem.needsSignIn, .noProfile] {
            p = XboxSessionPlan()
            _ = p.begin(); _ = p.opened()
            XCTAssertEqual(p.fail(problem, at: 0), .end(problem))
        }
        p = XboxSessionPlan()
        p.stop()
        XCTAssertEqual(p.begin(), .nothing)
        XCTAssertEqual(p.fail(.offline, at: 0), .nothing)
    }

    func testPlanPollTimeout() {
        var p = XboxSessionPlan()
        p.maxPolls = 3
        _ = p.begin(); _ = p.opened()
        XCTAssertEqual(p.observed(.init(state: "Provisioning", errorDetails: nil), at: 0), .askState(after: 1))
        XCTAssertEqual(p.observed(.init(state: "Provisioning", errorDetails: nil), at: 0), .askState(after: 1))
        XCTAssertEqual(p.observed(.init(state: "Provisioning", errorDetails: nil), at: 0), .retry(after: 5))
        XCTAssertEqual(p.stage, .backingOff(.timeout, attempt: 1))
    }

    // MARK: Oturum (sahte uçlar ve sahte WebRTC)

    private func fastTiming() -> XboxSession.Timing {
        var t = XboxSession.Timing()
        t.tick = 0.01
        t.firstFrameTimeout = 2
        t.plan.pollInterval = 0.01
        t.plan.retryDelays = [0.05, 0.05, 0.05]
        return t
    }

    private func account(_ web: XboxWeb) throws -> XboxAccount {
        let now = Date()
        return XboxAccount(web: web, token: try token(expiresIn: 3600, now: now))
    }

    private func console() -> XboxConsole {
        XboxConsole(id: "F400A", name: "Salon Xbox", model: "XboxSeriesX", streamingEnabled: true, powerState: "On")
    }

    func testSessionStreamsFrames() async throws {
        let web = FakeXboxWeb.happy()
        var cloud = XboxCloud(account: try account(web), web: web)
        cloud.exchangeInterval = 0.01
        let peers = LatestBox<FakeXboxPeer>()
        let session = XboxSession(console: console(), cloud: cloud, playAudio: false, timing: fastTiming()) { _, sink in
            let p = FakeXboxPeer(frames: 400, sink: sink)
            peers.set(p)
            return p
        }
        let statuses = session.statuses()
        session.start()
        var seen: [XboxSession.Status] = []
        for await s in statuses {
            seen.append(s)
            if s == .streaming { break }
        }
        XCTAssertEqual(seen, [.connecting, .streaming])
        var frames = 0
        for await _ in session.frames() {
            frames += 1
            if frames == 2 { break }
        }
        XCTAssertEqual(peers.get()?.answer, "v=0 cevap")
        XCTAssertEqual(web.count("/connect", method: "POST"), 1)
        XCTAssertEqual(web.count("/sdp", method: "POST"), 1)
        let play = try XCTUnwrap(web.requests.first { $0.url.hasSuffix("/play") })
        XCTAssertEqual(play.url, "https://home.test/v5/sessions/home/play")
        XCTAssertEqual(play.headers["Authorization"], "Bearer GS")
        XCTAssertTrue(play.body?.contains(#""serverId":"F400A""#) == true)
        let connect = try XCTUnwrap(web.requests.first { $0.url.hasSuffix("/connect") })
        XCTAssertTrue(connect.body?.contains("LPT") == true)
        let ice = try XCTUnwrap(web.requests.first { $0.url.hasSuffix("/ice") && $0.method == "POST" })
        XCTAssertTrue(ice.body?.contains("192.168.0.5") == true)
        session.stop()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(web.count("S-1", method: "DELETE"), 1)
    }

    func testSessionRetriesAfterDropThenGivesUp() async throws {
        let web = FakeXboxWeb.happy()
        var cloud = XboxCloud(account: try account(web), web: web)
        cloud.exchangeInterval = 0.01
        let session = XboxSession(console: console(), cloud: cloud, playAudio: false, timing: fastTiming()) { _, sink in
            let p = FakeXboxPeer(frames: 1, sink: sink)
            Task.detached {
                try? await Task.sleep(for: .milliseconds(40))
                p.drop("WebRTC bağlantısı kesildi")
            }
            return p
        }
        session.start()
        var lost: [XboxSession.Status] = []
        for await s in session.statuses() {
            if case .lost = s { lost.append(s) }
            if case .lost(_, false, _) = s { break }
        }
        XCTAssertEqual(lost.count, 4)
        XCTAssertEqual(lost.first, .lost(.offline, willRetry: true, detail: "WebRTC bağlantısı kesildi"))
        if case let .lost(problem, retry, _) = lost.last {
            XCTAssertEqual(problem, .offline)
            XCTAssertFalse(retry)
        }
        XCTAssertEqual(web.count("/play"), 4)
        session.stop()
    }

    func testSessionStopsOnConsoleRefusal() async throws {
        let web = FakeXboxWeb.happy(states: ["Provisioning", "Failed"])
        let session = XboxSession(console: console(), cloud: XboxCloud(account: try account(web), web: web), playAudio: false,
                                  timing: fastTiming()) { _, sink in FakeXboxPeer(frames: 1, sink: sink) }
        session.start()
        var last: XboxSession.Status?
        for await s in session.statuses() {
            last = s
            if case .lost = s { break }
        }
        if case let .lost(problem, retry, _) = last {
            XCTAssertEqual(problem, .unreachable)
            XCTAssertFalse(retry)
        } else {
            XCTFail("kopma beklenirdi")
        }
        XCTAssertEqual(web.count("/play"), 1)
        XCTAssertEqual(web.count("/sdp"), 0)
        session.stop()
    }

    // MARK: Model

    @MainActor
    func testModelStartsXboxSessionAndShowsReasons() async throws {
        let now = Date()
        let store = MemoryStore()
        store.save(try token(expiresIn: 3600, now: now).stored, for: Keys.xboxUserToken)
        store.save(console(), for: Keys.xboxConsole)
        store.save(true, for: Keys.setupComplete)
        let web = FakeXboxWeb.happy()
        let m = model(store, web: web)
        var timing = fastTiming()
        timing.plan.retryDelays = [60, 60, 60] // kopuk durum test boyunca sürsün
        m.xboxTiming = timing
        m.settings.output = .computer
        let peer = LatestBox<FakeXboxPeer>()
        m.xboxPeerOverride = { _, sink in
            let p = FakeXboxPeer(frames: 3, sink: sink)
            peer.set(p)
            return p
        }
        XCTAssertTrue(m.canStart)
        await m.start()
        XCTAssertTrue(m.isRunning)
        let deadline = Date().addingTimeInterval(5)
        while m.link != .streaming && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(m.link, .streaming)
        XCTAssertEqual(m.consoleStatusText, L("status.connected"))
        while m.lastFrame == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(m.lastFrame)

        // Kopunca Xbox'ın kendi metni yazılır.
        peer.get()?.drop("kesildi")
        while m.link == .streaming && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(m.link, .disconnected(.other(L("xbox.session.dropped"))))
        XCTAssertEqual(m.consoleStatusText, L("xbox.session.dropped"))
        XCTAssertEqual(m.problemText, L("xbox.session.dropped"))
        XCTAssertEqual(m.lastFailure, .other(L("xbox.session.dropped")))
        m.stop()
        XCTAssertFalse(m.isRunning)
        XCTAssertEqual(m.link, .disconnected(.stopped))
        XCTAssertEqual(m.consoleStatusText, L("status.disconnected"))
    }

    @MainActor
    func testModelSignInSavesAndSignOutForgets() async throws {
        let web = FakeXboxWeb { r, _ in
            if r.url.hasSuffix("/devicecode") {
                return .init(status: 200, text: #"{"user_code":"U","device_code":"D","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":1}"#)
            }
            return .init(status: 200, text: #"{"access_token":"A/1","refresh_token":"R/1","expires_in":3600}"#)
        }
        let store = MemoryStore()
        let m = model(store, web: web)
        XCTAssertFalse(m.xboxSignedIn)
        m.finishWelcome()
        XCTAssertEqual(m.step, .psnLogin)
        XCTAssertFalse(m.canAdvance)
        let code = try await m.xboxRequestCode()
        try await m.xboxWaitForApproval(code)
        XCTAssertTrue(m.xboxSignedIn)
        XCTAssertTrue(m.canAdvance)
        let saved = try XCTUnwrap(MicrosoftToken(stored: store.load(String.self, for: Keys.xboxUserToken)))
        XCTAssertEqual(saved.refreshToken, "R/1")
        m.advance()
        m.chooseXbox(console())
        XCTAssertEqual(store.load(XboxConsole.self, for: Keys.xboxConsole), console())

        // Yeniden açılınca girişli gelir.
        let reopened = model(store, web: web)
        XCTAssertTrue(reopened.xboxSignedIn)
        XCTAssertEqual(reopened.xboxConsole, console())

        m.xboxSignOut()
        XCTAssertFalse(m.xboxSignedIn)
        XCTAssertNil(store.data(for: Keys.xboxUserToken))
        XCTAssertEqual(m.xboxConsole, console())
        m.resetSetup()
        XCTAssertNil(store.data(for: Keys.xboxConsole))
        XCTAssertNil(m.xboxConsole)
    }

    @MainActor
    func testModelSavesRefreshedToken() async throws {
        let store = MemoryStore()
        store.save(try token(expiresIn: 10, now: Date()).stored, for: Keys.xboxUserToken)
        let happy = FakeXboxWeb.happy()
        let web = FakeXboxWeb { r, n in
            if r.url.contains("oauth2/v2.0/token") {
                return .init(status: 200, text: #"{"access_token":"fresh","expires_in":3600}"#)
            }
            return try happy.send(r, n)
        }
        let m = model(store, web: web)
        let list = try await m.xboxConsoles()
        XCTAssertEqual(list.count, 2)
        let deadline = Date().addingTimeInterval(3)
        var saved = MicrosoftToken(stored: store.load(String.self, for: Keys.xboxUserToken))
        while saved?.accessToken != "fresh" && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            saved = MicrosoftToken(stored: store.load(String.self, for: Keys.xboxUserToken))
        }
        XCTAssertEqual(saved?.accessToken, "fresh")
        XCTAssertEqual(saved?.refreshToken, "R0")
        XCTAssertTrue(m.xboxSignedIn)
    }

    func testReconnectNowOnlyRestartsLiveStream() async throws {
        let web = FakeXboxWeb.happy(states: ["Provisioning", "Provisioning", "Provisioning", "Provisioned"])
        var cloud = XboxCloud(account: try account(web), web: web)
        cloud.exchangeInterval = 0.01
        var timing = fastTiming()
        timing.plan.pollInterval = 0.05
        let session = XboxSession(console: console(), cloud: cloud, playAudio: false, timing: timing) { _, sink in
            FakeXboxPeer(frames: 400, sink: sink)
        }
        var statuses = session.statuses().makeAsyncIterator()
        session.start()
        try await Task.sleep(for: .milliseconds(30))
        session.reconnectNow() // açılırken: yok sayılır
        var seen: [XboxSession.Status] = []
        while let s = await statuses.next() {
            seen.append(s)
            if s == .streaming { break }
        }
        XCTAssertEqual(seen, [.connecting, .streaming])
        XCTAssertEqual(web.count("/play"), 1)
        session.reconnectNow() // canlıyken: kapatılıp hemen açılır
        seen = []
        while let s = await statuses.next() {
            seen.append(s)
            if s == .streaming { break }
        }
        XCTAssertEqual(seen, [.connecting, .streaming])
        XCTAssertEqual(web.count("/play"), 2)
        XCTAssertEqual(web.count("S-1", method: "DELETE"), 1)
        session.stop()
    }

    func testSessionTexts() {
        XCTAssertEqual(XboxText.session(.needsSignIn, willRetry: false), L("xbox.error.signin"))
        XCTAssertEqual(XboxText.session(.busy, willRetry: true), L("xbox.session.busy"))
        XCTAssertEqual(XboxText.session(.busy, willRetry: false), L("xbox.session.gaveup"))
        XCTAssertEqual(XboxText.setup(XboxFailure(.codeExpired)), L("xbox.error.code"))
        XCTAssertEqual(XboxText.setup(XboxFailure(.unexpected, "HTTP 500")), L("xbox.error.unexpected", "HTTP 500"))
    }
}
