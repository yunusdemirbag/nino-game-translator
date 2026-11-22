// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoMacKit

final class TVSetupPartsTests: XCTestCase {
    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: Sürüm ve paketler

    func testNumericVersionComparison() {
        XCTAssertTrue(TVVersion("0.10") > TVVersion("0.9"))
        XCTAssertTrue(TVVersion("1.0") == TVVersion("1.0.0"))
        XCTAssertTrue(TVVersion.isCurrent("0.7.0", bundled: "0.7.0"))
        XCTAssertFalse(TVVersion.isCurrent("0.6.9", bundled: "0.7"))
        XCTAssertFalse(TVVersion.isCurrent(nil, bundled: "0.7"))
    }

    func testPackageVersionsFromFileNames() {
        XCTAssertEqual(TVAppPackages.version(fromFileName: "com.ninotranslator.tv_0.7.2_all.ipk"), "0.7.2")
        XCTAssertNil(TVAppPackages.version(fromFileName: "other_0.7.2_all.ipk"))
        XCTAssertEqual(TVAppPackages.version(fromFileName: "nino-androidtv_0.2.6.apk"), "0.2.6")
        XCTAssertEqual(TVAppPackages.version(fromFileName: "nino-tizen_1.10.wgt"), "1.10")
        XCTAssertNil(TVAppPackages.version(fromFileName: "readme.txt"))
    }

    func testPackageScanPicksNewest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nino-pk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in ["nino-androidtv_0.9.apk", "nino-androidtv_0.10.apk", "com.ninotranslator.tv_1.0_all.ipk"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data())
        }
        let p = TVAppPackages.scan(folder: dir)
        XCTAssertEqual(p.android?.version, "0.10")
        XCTAssertEqual(p.lg?.version, "1.0")
        XCTAssertNil(p.samsung)
        XCTAssertFalse(p.canInstall(.samsung))
        XCTAssertEqual(TVAppPackages.scan(folder: nil), TVAppPackages())
    }

    func testServerURLFallsBackToLoopback() {
        XCTAssertEqual(TVApp.serverURL(macAddress: "192.168.0.10", port: 8787), "http://192.168.0.10:8787")
        XCTAssertEqual(TVApp.serverURL(macAddress: nil, port: 8787), "http://127.0.0.1:8787")
    }

    // MARK: Mac'in adresi

    func testMacAddressRules() {
        let wifi = NetworkInterface(name: "en0", address: "192.168.0.10")
        let vpn = NetworkInterface(name: "utun3", address: "10.8.0.2", isPointToPoint: true)
        let other = NetworkInterface(name: "en5", address: "10.0.1.5", netmask: "255.255.255.0")
        // 1) Yolun kaynak adresi açık bir bağdaştırıcınınsa o.
        XCTAssertEqual(MacAddressPicker.pick(tvHost: "10.0.1.40", interfaces: [wifi, other], routeSource: "192.168.0.10"),
                       "192.168.0.10")
        // Kaynak adres hiçbir bağdaştırıcıda yoksa: TV ile aynı alt ağ.
        XCTAssertEqual(MacAddressPicker.pick(tvHost: "10.0.1.40", interfaces: [wifi, other], routeSource: "1.2.3.4"),
                       "10.0.1.5")
        // VPN alt ağı TV'ninkiyle aynı olsa bile sanal sayılır; en* özel adres seçilir.
        XCTAssertEqual(MacAddressPicker.pick(tvHost: "10.8.0.9", interfaces: [vpn, wifi], routeSource: nil), "192.168.0.10")
        // Yalnız sanal varsa en son o.
        XCTAssertEqual(MacAddressPicker.pick(tvHost: nil, interfaces: [vpn], routeSource: nil), "10.8.0.2")
        XCTAssertNil(MacAddressPicker.pick(tvHost: nil, interfaces: [NetworkInterface(name: "lo0", address: "127.0.0.1",
                                                                                         isLoopback: true)], routeSource: nil))
        XCTAssertTrue(MacAddressPicker.isVirtual(NetworkInterface(name: "awdl0", address: "169.254.1.1")))
        XCTAssertEqual(MacAddressPicker.homeNetworks([wifi, vpn, other]).map(\.address), ["192.168.0.10", "10.0.1.5"])
    }

    // MARK: Bulma

    func testSSDPParsingAndHostExtraction() {
        let r = SSDPResponse.parse("HTTP/1.1 200 OK\r\nST: urn:lge-com:service:webos-second-screen:1\r\nlocation: http://192.168.0.50:1990/\r\n\r\n",
                                   sender: "192.168.0.50")
        XCTAssertEqual(r.headers["LOCATION"], "http://192.168.0.50:1990/")
        let other = SSDPResponse(headers: ["ST": "urn:other"], sender: "192.168.0.60")
        XCTAssertEqual(TVDiscovery.hosts(from: [r, other], target: TVDiscovery.lgSearchTarget), ["192.168.0.50"])
        XCTAssertTrue(TVDiscovery.searchRequest(target: "x").contains("MAN: \"ssdp:discover\"\r\nMX: 2\r\nST: x"))
    }

    func testDiscoveryUsesSSDPAndReadsNames() async {
        let f = TVFakes()
        f.ssdp.reply = { req, targets in
            XCTAssertEqual(targets, [SSDPTarget(.multicast(localAddress: "192.168.0.10"))])
            if req.contains("lge-com") {
                return [SSDPResponse(headers: ["ST": TVDiscovery.lgSearchTarget, "LOCATION": "http://192.168.0.50:1990/x"],
                                     sender: "192.168.0.50")]
            }
            return [SSDPResponse(headers: ["ST": TVDiscovery.samsungSearchTarget], sender: "192.168.0.7")]
        }
        f.http.set("http://192.168.0.50:1990/", 200, "<root><device><friendlyName>Salon &amp; LG</friendlyName></device></root>")
        f.http.set("http://192.168.0.7:8001/api/v2/", 200, #"{"device":{"name":"[TV] Samsung &quot;Q60&quot;"}}"#)
        let d = TVDiscovery(http: f.http, ssdp: f.ssdp, network: f.network)
        let all = await d.searchAll()
        XCTAssertEqual(all, [DiscoveredTV(name: "[TV] Samsung \"Q60\"", host: "192.168.0.7", brand: .samsung),
                             DiscoveredTV(name: "Salon & LG", host: "192.168.0.50", brand: .lg)])
    }

    func testDiscoveryFallsBackToSubnetScan() async {
        let f = TVFakes()
        f.http.set("http://192.168.0.31:3000/", 200, "Hello world")
        f.http.set("http://192.168.0.32:1990/", 200, "<device>LG Electronics<friendlyName>Oda</friendlyName></device>")
        f.http.set("http://192.168.0.33:1990/", 200, "<device>Sony</device>")
        f.http.set("http://192.168.0.40:8001/api/v2/", 200, #"{"device":{"name":"Mutfak"}}"#)
        var timing = TVDiscovery.Timing()
        timing.ssdpWindow = 0
        let d = TVDiscovery(http: f.http, ssdp: f.ssdp, network: f.network, timing: timing)
        let lg = await d.search(.lg)
        XCTAssertEqual(lg.map(\.host), ["192.168.0.31", "192.168.0.32"])
        XCTAssertEqual(lg.map(\.name), ["LG TV", "Oda"])
        // Mac'in kendi adresi taranmaz; LG'de her adrese ayrı SSDP isteği de gider.
        XCTAssertFalse(f.http.requested.contains("http://192.168.0.10:1990/"))
        let unicast = f.ssdp.requests.last?.1 ?? []
        XCTAssertEqual(unicast.count, 253)
        let samsung = await d.search(.samsung)
        XCTAssertEqual(samsung, [DiscoveredTV(name: "Mutfak", host: "192.168.0.40", brand: .samsung)])
        let android = await d.search(.androidTV)
        XCTAssertEqual(android, [])
    }

    func testReaddressPolicy() {
        let saved = TVRecord(name: "Salon", host: "192.168.0.5", brand: .lg)
        let a = DiscoveredTV(name: "Salon", host: "192.168.0.9", brand: .lg)
        let b = DiscoveredTV(name: "Oda", host: "192.168.0.8", brand: .lg)
        XCTAssertNil(TVReaddressPolicy.newAddress(saved: saved, found: [DiscoveredTV(name: "Salon", host: "192.168.0.5", brand: .lg), a]))
        XCTAssertEqual(TVReaddressPolicy.newAddress(saved: saved, found: [a, b]), a)
        XCTAssertEqual(TVReaddressPolicy.newAddress(saved: saved, found: [b]), b)
        XCTAssertNil(TVReaddressPolicy.newAddress(saved: saved, found: [b, DiscoveredTV(name: "X", host: "192.168.0.7", brand: .lg)]))
        var p = TVReaddressPolicy()
        let t = Date()
        XCTAssertTrue(p.shouldSearch(now: t))
        XCTAssertFalse(p.shouldSearch(now: t.addingTimeInterval(10)))
        XCTAssertTrue(p.shouldSearch(now: t.addingTimeInterval(31)))
    }

    // MARK: LG SSAP

    func testLGRegisterAndLaunch() async throws {
        let sockets = FakeSockets()
        sockets.factory = { url in
            guard url.absoluteString == "wss://192.168.0.50:3001" else { return nil }
            let s = FakeSocket(url: url)
            s.onSend = { text, socket in
                let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                switch o["type"] as? String {
                case "register":
                    socket.push(#"{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT"}}"#)
                    socket.push(#"{"type":"registered","id":"register_0","payload":{"client-key":"KEY1"}}"#)
                default:
                    let id = o["id"] as? String ?? ""
                    if o["uri"] as? String == "ssap://system.launcher/launch" {
                        socket.push(#"{"type":"response","id":"other","payload":{}}"#)
                        socket.push("{\"type\":\"response\",\"id\":\"\(id)\",\"payload\":{\"returnValue\":false}}")
                    } else {
                        socket.push("{\"type\":\"response\",\"id\":\"\(id)\",\"payload\":{\"appId\":\"com.webos.app.hdmi2\"}}")
                    }
                }
            }
            return s
        }
        var timing = LGSSAPClient.Timing()
        timing.approval = 0.5
        let c = LGSSAPClient(host: "192.168.0.50", sockets: sockets, timing: timing)
        let key = try await c.connect(clientKey: "OLD")
        XCTAssertEqual(key, "KEY1")
        let reg = sockets.opened[0].sentObjects[0]
        XCTAssertEqual(reg["id"] as? String, "register_0")
        let payload = reg["payload"] as? [String: Any]
        XCTAssertEqual(payload?["client-key"] as? String, "OLD")
        XCTAssertEqual(payload?["pairingType"] as? String, "PROMPT")
        XCTAssertEqual((payload?["manifest"] as? [String: Any])?["permissions"] as? [String], LGSSAPClient.permissions)
        let launched = try await c.launchApp(server: "http://192.168.0.10:8787")
        XCTAssertFalse(launched)
        let launch = try XCTUnwrap(sockets.opened[0].sentObjects.first { $0["uri"] as? String == "ssap://system.launcher/launch" })
        XCTAssertEqual((launch["payload"] as? [String: Any])?["id"] as? String, "com.ninotranslator.tv")
        XCTAssertEqual(((launch["payload"] as? [String: Any])?["params"] as? [String: Any])?["server"] as? String,
                       "http://192.168.0.10:8787")
        let fg = try await c.foregroundAppID()
        XCTAssertTrue(LGSSAPClient.isTVOwnInput(fg))
        XCTAssertTrue(LGSSAPClient.isTVOwnInput("com.webos.app.livetv"))
        XCTAssertFalse(LGSSAPClient.isTVOwnInput("netflix"))
    }

    func testLGFallsBackToPlainSocketAndHandlesRefusal() async {
        let sockets = FakeSockets()
        sockets.factory = { url in
            guard url.scheme == "ws" else { return nil }
            let s = FakeSocket(url: url)
            s.onSend = { _, socket in socket.push(#"{"type":"error","error":"403 cancelled"}"#) }
            return s
        }
        let c = LGSSAPClient(host: "192.168.0.50", sockets: sockets)
        do {
            _ = try await c.connect(clientKey: nil)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? TVPairingError, .refused("403 cancelled"))
        }
        XCTAssertEqual(sockets.attempted.map(\.absoluteString), ["wss://192.168.0.50:3001", "ws://192.168.0.50:3000"])
        XCTAssertNil((LGSSAPClient.registerMessage(clientKey: nil).data(using: .utf8)).flatMap {
            ((try? JSONSerialization.jsonObject(with: $0)) as? [String: Any])?["payload"] as? [String: Any]
        }?["client-key"])
    }

    func testLGApprovalTimeoutIsRefusalAndNoSocketIsUnreachable() async {
        let sockets = FakeSockets()
        sockets.factory = { FakeSocket(url: $0) }
        var t = LGSSAPClient.Timing()
        t.approval = 0.1
        let c = LGSSAPClient(host: "h", sockets: sockets, timing: t)
        do { _ = try await c.connect(clientKey: nil); XCTFail() } catch {
            XCTAssertEqual(error as? TVPairingError, .refused("timeout"))
        }
        let none = LGSSAPClient(host: "h", sockets: FakeSockets())
        do { _ = try await none.connect(clientKey: nil); XCTFail() } catch {
            guard case .unreachable? = error as? TVPairingError else { return XCTFail("\(error)") }
        }
    }

    // MARK: Samsung

    func testSamsungRemoteConnectAndMessages() async throws {
        let sockets = FakeSockets()
        sockets.factory = { url in FakeSocket(url: url, initial: [#"{"event":"ms.channel.connect","data":{"token":"77"}}"#]) }
        let r = SamsungRemote(host: "192.168.0.7", sockets: sockets, clock: FastClock())
        XCTAssertEqual(r.url(token: "5").absoluteString,
                       "wss://192.168.0.7:8002/api/v2/channels/samsung.remote.control?name=Tmlubw==&token=5")
        XCTAssertEqual(r.url(token: "").absoluteString,
                       "wss://192.168.0.7:8002/api/v2/channels/samsung.remote.control?name=Tmlubw==")
        let token = try await r.connect(token: nil)
        XCTAssertEqual(token, "77")
        try await r.launchApp(server: "http://192.168.0.10:8787")
        try await r.typeDeveloperCode()
        let sent = sockets.opened[0].sentObjects
        XCTAssertEqual(sent.count, 11)
        let params = sent[0]["params"] as? [String: Any]
        XCTAssertEqual(params?["event"] as? String, "ed.apps.launch")
        let data = params?["data"] as? [String: Any]
        XCTAssertEqual(data?["appId"] as? String, "NinoTVApps.Nino")
        XCTAssertEqual(data?["action_type"] as? String, "DEEP_LINK")
        XCTAssertEqual(json(data?["metaTag"] as? String ?? "")["server"] as? String, "http://192.168.0.10:8787")
        let keys = sent.dropFirst().map { (($0["params"] as? [String: Any])?["Cmd"] as? String ?? "") + ":" +
            (($0["params"] as? [String: Any])?["DataOfCmd"] as? String ?? "") }
        XCTAssertEqual(keys.prefix(4), ["Press:KEY_1", "Release:KEY_1", "Press:KEY_2", "Release:KEY_2"])
        XCTAssertEqual(keys.last, "Release:KEY_5")
    }

    func testSamsungRefusalAndTimeout() async {
        for (event, expected) in [("ms.channel.unauthorized", TVPairingError.refused(nil)), ("ms.channel.timeOut", .timedOut)] {
            let sockets = FakeSockets()
            sockets.factory = { FakeSocket(url: $0, initial: ["{\"event\":\"\(event)\"}"]) }
            let r = SamsungRemote(host: "h", sockets: sockets)
            do { _ = try await r.connect(token: nil); XCTFail() } catch { XCTAssertEqual(error as? TVPairingError, expected) }
        }
        let silent = FakeSockets()
        silent.factory = { FakeSocket(url: $0) }
        var t = SamsungRemote.Timing()
        t.approval = 0.1
        let r = SamsungRemote(host: "h", sockets: silent, timing: t)
        do { _ = try await r.connect(token: nil); XCTFail() } catch { XCTAssertEqual(error as? TVPairingError, .timedOut) }
    }

    func testSamsungDeviceInfoAndMissingSteps() {
        let info = SamsungDeviceInfo.parse(Data(#"{"device":{"name":"TV","developerMode":"1","developerIP":"0.0.0.0","model":"23_KANTSU2E_QLED"}}"#.utf8))
        XCTAssertEqual(info?.developerMode, true)
        XCTAssertNil(info?.developerIP)
        XCTAssertEqual(info?.modelYear, 2023)
        XCTAssertNil(SamsungDeviceInfo(model: "UE55").modelYear)

        func step(_ mode: Bool?, _ ip: String?, gate: Bool, info present: Bool = true) -> SamsungMissingStep {
            let i = present ? SamsungDeviceInfo(developerMode: mode, developerIP: ip) : nil
            return SamsungInspection(info: i, installGateOpen: gate, macAddress: "192.168.0.10").missingStep
        }
        XCTAssertEqual(step(nil, nil, gate: false, info: false), .tvNotResponding)
        XCTAssertEqual(step(false, nil, gate: true), .developerModeOff)
        XCTAssertEqual(step(nil, nil, gate: false), .developerModeOff)
        XCTAssertEqual(step(true, "127.0.0.1", gate: true), .hostLoopback)
        XCTAssertEqual(step(true, "192.168.000.010", gate: true), .hostLeadingZeros)
        XCTAssertEqual(step(true, "10.0.168.192", gate: true), .hostReversed)
        XCTAssertEqual(step(true, "192.168.0.99", gate: true), .hostWrong)
        XCTAssertEqual(step(true, "192.168.0.10", gate: false), .notRestarted)
        XCTAssertEqual(step(true, nil, gate: true), .none)
        XCTAssertEqual(step(nil, nil, gate: true, info: false), .none)
    }

    // MARK: Yardımcı

    func testHelperEventParsing() {
        XCTAssertEqual(TVHelperEvent.parse(#"{"event":"progress","step":"signin"}"#), .progress(step: "signin"))
        XCTAssertEqual(TVHelperEvent.parse(#"{"event":"login","url":"https://acc.example/x"}"#), .login(url: URL(string: "https://acc.example/x")!))
        XCTAssertEqual(TVHelperEvent.parse(#"{"event":"approve"}"#), .approve)
        XCTAssertEqual(TVHelperEvent.parse(#"{"event":"done","version":"0.7.0","installed":true}"#), .done(version: "0.7.0", installed: true))
        XCTAssertEqual(TVHelperEvent.parse(#"{"event":"found","hosts":["192.168.1.40"]}"#), .found(hosts: ["192.168.1.40"]))
        XCTAssertEqual(TVHelperEvent.parse(#"{"event":"error","code":"TooOld","message":"m"}"#), .error(code: "TooOld", message: "m"))
        XCTAssertNil(TVHelperEvent.parse("not json"))
        XCTAssertNil(TVHelperEvent.parse(#"{"event":"what"}"#))
        XCTAssertEqual(TVInstallError.problem(forHelperCode: "NotEnoughSpace"), .noSpace)
        XCTAssertEqual(TVInstallError.problem(forHelperCode: "Mystery"), .installFailed)
    }

    func testHelperRunReadsEventsAndArguments() async throws {
        let p = FakeProcesses()
        p.startHandler = { _ in FakeRunning(lines: [#"{"event":"progress","step":"reading"}"#, "noise",
                                                    #"{"event":"done","version":"0.7.0","installed":false}"#,
                                                    #"{"event":"error","code":"TooOld","message":"late"}"#]) }
        let sink = LogSink()
        let h = TVHelperClient(executable: URL(fileURLWithPath: "/x/nino-tv-helper"), processes: p, log: sink.log)
        let seen = LockedBox<[TVHelperEvent]>([])
        let args = TVHelperClient.samsungInstallArguments(host: "1.2.3.4", package: URL(fileURLWithPath: "/p/a.wgt"),
                                                          version: "0.7.0", profiles: URL(fileURLWithPath: "/s/samsung"),
                                                          log: URL(fileURLWithPath: "/l/tvinstall.log"))
        let out = try await h.run(args) { e in seen.mutate { $0.append(e) } }
        XCTAssertEqual(out, .done(version: "0.7.0", installed: false))
        XCTAssertEqual(seen.value, [.progress(step: "reading")])
        XCTAssertEqual(p.allCalls[0].arguments, ["samsung-install", "--host", "1.2.3.4", "--package", "/p/a.wgt", "--version",
                                                 "0.7.0", "--profiles", "/s/samsung", "--log", "/l/tvinstall.log",
                                                 "--exit-with-input"])
        XCTAssertEqual(TVHelperClient.androidInstallArguments(host: "h", package: URL(fileURLWithPath: "/a.apk"), version: "1",
                                                              keyDir: URL(fileURLWithPath: "/k")),
                       ["android-install", "--host", "h", "--package", "/a.apk", "--version", "1", "--key-dir", "/k"])
    }

    func testHelperErrorsAndMissingResult() async {
        let p = FakeProcesses()
        let sink = LogSink()
        let h = TVHelperClient(executable: URL(fileURLWithPath: "/x/nino-tv-helper"), processes: p, log: sink.log)
        p.startHandler = { _ in FakeRunning(lines: [#"{"event":"error","code":"CertificateRejected","message":""}"#], exitCode: 1) }
        do { _ = try await h.run(["samsung-install"]) { _ in }; XCTFail() } catch {
            XCTAssertEqual(error as? TVInstallError, TVInstallError(.certificateRejected, reason: "CertificateRejected"))
        }
        p.startHandler = { _ in FakeRunning(lines: [], exitCode: nil, stderr: "a\nb\nc\nd\n") }
        do { _ = try await h.run(["android-install"]) { _ in }; XCTFail() } catch {
            let e = error as? TVInstallError
            XCTAssertEqual(e?.problem, .installFailed)
            XCTAssertTrue(e?.reason?.contains("b | c | d") == true, e?.reason ?? "")
            XCTAssertFalse(e?.reason?.contains("a |") == true)
        }
        p.startHandler = { _ in FakeRunning(lines: [], exitCode: 3) }
        let scan = await h.androidScan()
        XCTAssertEqual(scan, [])
        let missing = TVHelperClient(executable: nil, processes: p, log: sink.log)
        XCTAssertFalse(missing.isAvailable)
        do { _ = try await missing.run(["samsung-install"]) { _ in }; XCTFail() } catch {
            XCTAssertEqual((error as? TVInstallError)?.problem, .installFailed)
        }
        XCTAssertTrue(sink.all.contains { $0.contains("stderr") })
    }

    // MARK: LG geliştirici modu

    private func lgDev(_ f: TVFakes) -> LGDeveloperMode {
        var t = LGDeveloperMode.Timing()
        t.verifyAfterInstalled = 4
        t.verifyWithoutResult = 4
        return LGDeveloperMode(http: f.http, ports: f.ports, processes: f.processes, clock: f.clock, log: f.logSink.log,
                               timing: t)
    }

    func testLGKeyFetchFailures() async {
        let f = TVFakes()
        let dev = lgDev(f)
        do { _ = try await dev.fetchKey(host: "h", passphrase: "P"); XCTFail() } catch {
            XCTAssertEqual((error as? TVInstallError)?.problem, .keyServerOff)
        }
        f.http.set("http://h:9991/webos_rsa", 404, "")
        do { _ = try await dev.fetchKey(host: "h", passphrase: "P"); XCTFail() } catch {
            XCTAssertEqual((error as? TVInstallError)?.problem, .keyServerOff)
        }
        f.http.set("http://h:9991/webos_rsa", 200, "ENCRYPTED")
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 1, stderr: Data("bad passphrase".utf8)) }
        do { _ = try await dev.fetchKey(host: "h", passphrase: "P"); XCTFail() } catch {
            XCTAssertEqual((error as? TVInstallError)?.problem, .wrongPassphrase)
        }
    }

    func testLGKeyFetchRemovesPassphraseWithSshKeygen() async throws {
        let f = TVFakes()
        f.http.set("http://h:9991/webos_rsa", 200, "ENCRYPTED")
        f.processes.runHandler = { call in
            let file = call.arguments.last!
            let attrs = try? FileManager.default.attributesOfItem(atPath: file)
            XCTAssertEqual((attrs?[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            try? "PLAIN".write(toFile: file, atomically: false, encoding: .utf8)
            return TVProcessResult(exitCode: 0)
        }
        let key = try await lgDev(f).fetchKey(host: "h", passphrase: "ABC123")
        XCTAssertEqual(key, "PLAIN")
        let call = f.processes.allCalls[0]
        XCTAssertEqual(call.executable, "ssh-keygen")
        XCTAssertEqual(Array(call.arguments.prefix(5)), ["-p", "-P", "ABC123", "-N", ""])
        XCTAssertFalse(FileManager.default.fileExists(atPath: call.arguments.last!))
    }

    func testLGInstallFlow() async throws {
        let f = TVFakes()
        let pkg = TVAppPackage(url: f.packagesDir.appendingPathComponent("com.ninotranslator.tv_0.7.0_all.ipk"), version: "0.7.0")
        let reads = LockedBox(0)
        f.processes.runHandler = { call in
            let cmd = call.arguments.last!
            XCTAssertTrue(call.arguments.contains("prisoner@h"))
            XCTAssertTrue(call.arguments.contains("HostKeyAlgorithms=+ssh-rsa"))
            if cmd.hasPrefix("cat /media/developer/apps") {
                let n = reads.mutate { $0 += 1; return $0 }
                return TVProcessResult(exitCode: 0, stdout: Data((n < 3 ? #"{"version":"0.6.0"}"# : #"{"version":"0.7.0"}"#).utf8))
            }
            if cmd.contains("cat > ") {
                XCTAssertEqual(call.input, Data("pkg".utf8))
                XCTAssertTrue(cmd.contains("rm -f /media/developer/temp/com.ninotranslator.tv_*.ipk /media/developer/temp/nino.ipk"))
                return TVProcessResult(exitCode: 0)
            }
            if cmd.contains("luna-send-pub") {
                XCTAssertTrue(cmd.contains("luna://com.webos.appInstallService/dev/install"))
                XCTAssertTrue(cmd.contains(#""id":"com.ares.defaultName""#))
                return TVProcessResult(exitCode: 0, stdout: Data("{\"returnValue\":true,\n\"details\":{\"state\":\"installed\"}}".utf8))
            }
            return TVProcessResult(exitCode: 0)
        }
        let r = try await lgDev(f).install(host: "h", key: "K", package: pkg)
        XCTAssertEqual(r, .installed(version: "0.7.0"))
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 0, stdout: Data(#"{"version":"0.8"}"#.utf8)) }
        let again = try await lgDev(f).install(host: "h", key: "K", package: pkg)
        XCTAssertEqual(again, .alreadyCurrent(version: "0.8"))
    }

    func testLGInstallErrors() async {
        let f = TVFakes()
        let pkg = TVAppPackage(url: f.packagesDir.appendingPathComponent("com.ninotranslator.tv_0.7.0_all.ipk"), version: "0.7.0")
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 255, stderr: Data("prisoner@h: Permission denied (publickey).".utf8)) }
        do { _ = try await lgDev(f).install(host: "h", key: "K", package: pkg); XCTFail() } catch {
            XCTAssertEqual((error as? TVInstallError)?.problem, .keyRejected)
        }
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 255, stderr: Data("Connection timed out".utf8)) }
        do { _ = try await lgDev(f).install(host: "h", key: "K", package: pkg); XCTFail() } catch {
            XCTAssertEqual((error as? TVInstallError)?.problem, .unreachable)
        }
        f.processes.runHandler = { call in
            if call.arguments.last!.contains("luna-send-pub") {
                return TVProcessResult(exitCode: 0, stdout: Data(#"{"returnValue":false,"errorCode":-5,"errorText":"Not enough storage"}"#.utf8))
            }
            return TVProcessResult(exitCode: 0)
        }
        do { _ = try await lgDev(f).install(host: "h", key: "K", package: pkg); XCTFail() } catch {
            XCTAssertEqual(error as? TVInstallError, TVInstallError(.noSpace, reason: "Not enough storage (-5)"))
        }
        // Sonuç yok, sürüm hiç görünmüyor.
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 0) }
        do { _ = try await lgDev(f).install(host: "h", key: "K", package: pkg); XCTFail() } catch {
            let e = error as? TVInstallError
            XCTAssertEqual(e?.problem, .installFailed)
            XCTAssertTrue(e?.reason?.contains("0.7.0") == true)
        }
    }

    func testLGReplyParsingAndHours() {
        XCTAssertEqual(LGDeveloperMode.parseInstallReply("{\"details\":{\"state\":\"install failed\",\"reason\":\"bad ipk\"}}"),
                       .failure("bad ipk"))
        XCTAssertEqual(LGDeveloperMode.parseInstallReply("{\"returnValue\":true}\n{\"details\":{\"state\":\"installed\"}}"), .success)
        XCTAssertEqual(LGDeveloperMode.parseInstallReply("garbage"), .unknown)
        XCTAssertEqual(LGDeveloperMode.hoursLeft(#"{"result":"success","errorMsg":"999:12:04"}"#), 999)
        XCTAssertTrue(TVInstallError.mentionsNoSpace("ENOSPC while writing"))
        XCTAssertEqual(LGDeveloperMode.extensionDefaultsKey(host: " 192.168.0.5 "), "lgDevModeExtended.192.168.0.5")
        XCTAssertTrue(LGDeveloperMode.installScript(remotePackage: "/x.ipk", wait: 180).contains("(sleep 200) | luna-send-pub"))
    }

    func testLGExtendSession() async {
        let f = TVFakes()
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 0, stdout: Data("TOKEN123\n".utf8)) }
        f.http.set("https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=TOKEN123", 200, #"{"result":"success"}"#)
        f.http.set("https://developer.lge.com/secure/CheckDevModeSession.dev?sessionToken=TOKEN123", 200, #"{"errorMsg":"998:59:59"}"#)
        let ext = await lgDev(f).extendSession(host: "h", key: "K")
        XCTAssertEqual(ext, LGDeveloperMode.Extension(hoursLeft: 998))
        f.processes.runHandler = { _ in TVProcessResult(exitCode: 0, stdout: Data("has space".utf8)) }
        let none = await lgDev(f).extendSession(host: "h", key: "K")
        XCTAssertNil(none)
    }

    // MARK: İletiler

    func testInstallMessages() {
        let samsung = TVSetupText.installMessage(TVInstallError(.installFailed, reason: "boom"), brand: .samsung,
                                                 logPath: "/L/tvinstall.log")
        let blocks = samsung.components(separatedBy: "\n\n")
        XCTAssertEqual(blocks.count, 5)
        XCTAssertTrue(blocks[1].hasSuffix(" boom"))
        XCTAssertTrue(blocks[4].contains("/L/tvinstall.log"))
        let lg = TVSetupText.installMessage(TVInstallError(.installFailed), brand: .lg, logPath: "/L", appStoreBuild: true)
        XCTAssertEqual(lg.components(separatedBy: "\n\n").count, 2)
        let android = TVSetupText.installMessage(TVInstallError(.notApproved), brand: .androidTV, logPath: "/L")
        XCTAssertFalse(android.contains("\n"))
        for p in TVInstallError.Problem.allCases {
            let text = TVSetupText.installMessage(TVInstallError(p), brand: .samsung, logPath: "")
            XCTAssertFalse(text.hasPrefix("tv."), "çevrilmemiş anahtar: \(p)")
        }
        XCTAssertFalse(TVSetupText.string("tv.test.line").hasPrefix("tv."))
    }
}

/// Testler için kilitli kutu.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { lock.withLock { v } }
    @discardableResult func mutate<R>(_ f: (inout T) -> R) -> R { lock.withLock { f(&v) } }
}
