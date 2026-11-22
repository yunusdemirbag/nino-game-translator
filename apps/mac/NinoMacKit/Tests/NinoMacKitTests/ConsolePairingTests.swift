// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
@testable import NinoMacKit
import XCTest

final class ConsoleFakeRegistrar: ConsoleRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<RegistrationResult, RegistrationFailure>]
    private(set) var calls: [(address: String, pin: UInt32, accountID: Data)] = []

    init(_ replies: [Result<RegistrationResult, RegistrationFailure>]) { self.replies = replies }

    func register(address: String, console: DiscoveredPS5?, accountID: Data, pin: UInt32) async throws
        -> RegistrationResult {
        let reply = lock.withLock { () -> Result<RegistrationResult, RegistrationFailure> in
            calls.append((address, pin, accountID))
            return replies.isEmpty ? .failure(RegistrationFailure()) : replies.removeFirst()
        }
        return try reply.get()
    }
}

/// Bekletmeden ilerleyen saat (eşleştirmenin kısa beklemeleri için).
final class ConsoleInstantClock: ConsoleClock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval = 0
    private(set) var slept: [TimeInterval] = []
    func now() -> TimeInterval { lock.withLock { t } }
    func sleep(seconds: TimeInterval) async throws { lock.withLock { t += seconds; slept.append(seconds) } }
}

final class ConsolePairingTests: XCTestCase {
    let key = Data("1a2b3c4d".utf8) + Data(repeating: 0, count: 8)
    let morning = Data((1...16).map { UInt8($0) })
    let account = Data([1, 2, 3, 4, 5, 6, 7, 8])

    // MARK: Girişler

    func testAddressSanitizing() {
        XCTAssertEqual(ConsoleInput.sanitizeAddress(" 192.168.1.5 "), "192.168.1.5")
        XCTAssertEqual(ConsoleInput.sanitizeAddress("192.168.1.5:9295"), "192.168.1.5")
        XCTAssertEqual(ConsoleInput.sanitizeAddress("http://192.168.1.5/"), "192.168.1.5")
        XCTAssertEqual(ConsoleInput.sanitizeAddress("https://192.168.001.005:80/x"), "192.168.1.5")
        XCTAssertEqual(ConsoleInput.sanitizeAddress("192,168,1,5"), "192.168.1.5")
        for bad in ["", "0.0.0.0", "255.255.255.255", "192.168.1.255", "224.0.0.1", "192.168.1", "192.168.1.256",
                    "ps5.local", "1.2.3.4.5", "192.168.1.x"] {
            XCTAssertNil(ConsoleInput.sanitizeAddress(bad), bad)
        }
    }

    func testPairingCode() {
        XCTAssertEqual(ConsoleInput.pairingCode("1234 5678"), "12345678")
        XCTAssertEqual(ConsoleInput.pairingCode("1234-5678"), "12345678")
        XCTAssertEqual(ConsoleInput.pairingCode("12.34_56–78"), "12345678")
        XCTAssertEqual(ConsoleInput.pairingCode("١٢٣٤٥٦٧٨"), "12345678")
        XCTAssertEqual(ConsoleInput.pairingCode("१२३४५६७८"), "12345678")
        XCTAssertNil(ConsoleInput.pairingCode("1234567"))
        XCTAssertNil(ConsoleInput.pairingCode("123456789"))
        XCTAssertNil(ConsoleInput.pairingCode("1234a678"))
        XCTAssertEqual(ConsoleInput.filterCodeInput("12a3-٤5678999"), "12345678")
    }

    func testLoginPasscode() {
        XCTAssertEqual(ConsoleInput.loginPasscode(" 12 34 "), "1234")
        XCTAssertNil(ConsoleInput.loginPasscode("123"))
        XCTAssertNil(ConsoleInput.loginPasscode("12345"))
        XCTAssertNil(ConsoleInput.loginPasscode("١٢٣٤"))
        XCTAssertNil(ConsoleInput.loginPasscode(""))
    }

    // MARK: Sınıflama

    func testReasonCodeFromLog() {
        XCTAssertEqual(RemotePlayReason.code(inLog: ["x", "Reported Application Reason: 0x80108b09 (Regist Failed)"]),
                       0x8010_8B09)
        XCTAssertNil(RemotePlayReason.code(inLog: ["nothing here"]))
    }

    func testClassifierByReasonCode() {
        func f(_ code: UInt32) -> PairingFailure { PairingClassifier.classify(RegistrationFailure(reasonCode: code)).failure }
        XCTAssertEqual(f(0x8010_8B02), .accountNotRecognised)
        XCTAssertEqual(f(0x8010_8B09), .wrongCode)
        XCTAssertEqual(f(0x8010_8B10), .inUse)
        XCTAssertEqual(f(0x8010_8B15), .crashed)
        XCTAssertEqual(f(0x8010_8B11), .unsupportedVersion)
        XCTAssertEqual(f(0x8010_8BFF), .refused)
        XCTAssertEqual(PairingClassifier.classify(RegistrationFailure(reasonCode: 0x8010_8B09)).detail, "0x80108b09")
    }

    func testClassifierByLogLines() {
        func f(_ lines: [String], timedOut: Bool = false) -> PairingFailure {
            PairingClassifier.classify(RegistrationFailure(logLines: lines, timedOut: timedOut)).failure
        }
        XCTAssertEqual(f(["Regist failed to getaddrinfo on 1.2.3.4"]), .badAddress)
        XCTAssertEqual(f(["Regist failed to send request header: No route to host"]), .localNetworkBlocked)
        XCTAssertEqual(f(["Regist failed to send search: Operation not permitted"]), .localNetworkBlocked)
        XCTAssertEqual(f(["Regist search failed"]), .noAnswer)
        XCTAssertEqual(f(["Regist connect failed: tried all addresses"]), .noAnswer)
        XCTAssertEqual(f(["Regist failed to receive response HTTP header"]), .lateAnswer)
        XCTAssertEqual(f([], timedOut: true), .lateAnswer)
        XCTAssertEqual(f([]), .refused)
        XCTAssertEqual(PairingClassifier.classify(RegistrationFailure(consoleNotFound: true)).failure, .noAnswer)
    }

    func testMessagesHaveSuffixOnlyForPS5Problems() {
        XCTAssertFalse(PairingError(.badCode).message(logPath: "/l.log").contains("/l.log"))
        let m = PairingError(.wrongCode, detail: "0x80108b09").message(logPath: "/l.log")
        XCTAssertTrue(m.contains("(0x80108b09)"))
        XCTAssertTrue(m.hasSuffix("/l.log"))
    }

    // MARK: Eşleştirici

    func makePairer(_ registrar: ConsoleFakeRegistrar, store: MemoryConsoleRecordStore = MemoryConsoleRecordStore(),
                    clock: ConsoleInstantClock = ConsoleInstantClock()) -> ConsolePairer {
        ConsolePairer(discovery: ConsoleFakeDiscovery(), registrar: registrar, store: store, clock: clock)
    }

    func pairError(_ p: ConsolePairer, address: String = "192.168.0.20", code: String = "12345678",
                   account: Data? = Data([1, 2, 3, 4, 5, 6, 7, 8])) async -> PairingFailure? {
        do { _ = try await p.pair(address: address, code: code, accountID: account); return nil } catch {
            return (error as? PairingError)?.failure
        }
    }

    func testInputChecksComeBeforeNetwork() async {
        let reg = ConsoleFakeRegistrar([])
        let p = makePairer(reg)
        let e1 = await pairError(p, address: "  ")
        XCTAssertEqual(e1, .noAddress)
        let e2 = await pairError(p, address: "0.0.0.0")
        XCTAssertEqual(e2, .badAddress)
        let e3 = await pairError(p, code: "1234")
        XCTAssertEqual(e3, .badCode)
        let e4 = await pairError(p, account: nil)
        XCTAssertEqual(e4, .noAccount)
        let e5 = await pairError(p, account: Data([1, 2]))
        XCTAssertEqual(e5, .noAccount)
        XCTAssertTrue(reg.calls.isEmpty)
    }

    func testSuccessSavesRecord() async throws {
        let store = MemoryConsoleRecordStore()
        let reg = ConsoleFakeRegistrar([.success(RegistrationResult(name: "PS5-123", registKey: key, morning: morning))])
        let pairing = try await makePairer(reg, store: store).pair(address: "192.168.0.20:9295", code: "1234-5678",
                                                                    accountID: account)
        XCTAssertEqual(pairing, PS5Pairing(host: "192.168.0.20", name: "PS5-123", registKey: key, morning: morning))
        XCTAssertEqual(try store.loadPairing(), pairing)
        XCTAssertEqual(reg.calls.first?.pin, 12_345_678)
        XCTAssertEqual(reg.calls.first?.accountID, account)
    }

    func testZeroKeyIsNotSuccess() async {
        let store = MemoryConsoleRecordStore()
        let reg = ConsoleFakeRegistrar([.success(RegistrationResult(name: "PS5", registKey: Data(count: 16), morning: morning))])
        let e = await pairError(makePairer(reg, store: store))
        XCTAssertEqual(e, .refused)
        XCTAssertNil(try store.loadPairing())
    }

    func testRetriesThreeTimesOnlyWhenCodeNeverReachedPS5() async throws {
        let clock = ConsoleInstantClock()
        let reg = ConsoleFakeRegistrar([.failure(RegistrationFailure(logLines: ["Regist search failed"])),
                                 .failure(RegistrationFailure(consoleNotFound: true)),
                                 .failure(RegistrationFailure(logLines: ["Regist search failed"]))])
        let e = await pairError(makePairer(reg, clock: clock))
        XCTAssertEqual(e, .noAnswer)
        XCTAssertEqual(reg.calls.count, 3)
        XCTAssertEqual(clock.slept, [0.5, 0.5])

        let reg2 = ConsoleFakeRegistrar([.failure(RegistrationFailure(reasonCode: 0x8010_8B09))])
        let e2 = await pairError(makePairer(reg2))
        XCTAssertEqual(e2, .wrongCode)
        XCTAssertEqual(reg2.calls.count, 1)

        let reg3 = ConsoleFakeRegistrar([.failure(RegistrationFailure(consoleNotFound: true)),
                                  .success(RegistrationResult(name: "", registKey: key, morning: morning))])
        let ok = try await makePairer(reg3).pair(address: "192.168.0.20", code: "12345678", accountID: account,
                                                 console: DiscoveredPS5(hostID: "H", name: "Salon PS5",
                                                                        address: "192.168.0.20", asleep: false))
        XCTAssertEqual(ok.name, "Salon PS5")
    }

    func testSearchKeepsOnlyPS5s() async {
        let d = ConsoleFakeDiscovery()
        d.all = [DiscoveredPS5(hostID: "A", name: "PS5", address: "10.0.0.2", asleep: true),
                 DiscoveredPS5(hostID: "B", name: "PS4", address: "10.0.0.3", asleep: false, isPS5: false)]
        let p = ConsolePairer(discovery: d, registrar: ConsoleFakeRegistrar([]), store: MemoryConsoleRecordStore())
        let found = await p.search()
        XCTAssertEqual(found.map(\.hostID), ["A"])
    }
}
