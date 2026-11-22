// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import XCTest
@testable import NinoCore

/// Var olan mesajların JSON'u uzantılardan sonra da birebir aynı kalmalı.
final class LinkGoldenTests: XCTestCase {
    func testExistingMessagesKeepTheirJSON() {
        let cases: [(NinoMessage, String)] = [
            (.hello(version: 1, device: "Mac", client: "nino-mac/0.1.0"),
             #"{"app":"nino","client":"nino-mac/0.1.0","device":"Mac","type":"hello","version":1}"#),
            (.welcome(version: 1, name: "Salon TV"), #"{"app":"nino","name":"Salon TV","type":"welcome","version":1}"#),
            (.info(version: 1, versions: [1], name: "Salon TV", id: "abc"),
             #"{"app":"nino","id":"abc","name":"Salon TV","type":"info","version":1,"versions":[1]}"#),
            (.show(ShowPayload(id: 42, text: "Buraya gel.", source: "Come here.", position: .top, durationMs: 1500)),
             #"{"app":"nino","durationMs":1500,"id":42,"position":"top","source":"Come here.","text":"Buraya gel.","type":"show"}"#),
            (.show(ShowPayload(id: 1, text: "Selam")),
             #"{"app":"nino","durationMs":0,"id":1,"position":"bottom","text":"Selam","type":"show"}"#),
            (.clear(id: 42), #"{"app":"nino","id":42,"type":"clear"}"#),
            (.clear(id: nil), #"{"app":"nino","type":"clear"}"#),
            (.ping(t: 1_732_233_600_000), #"{"app":"nino","t":1732233600000,"type":"ping"}"#),
            (.pong(t: 7), #"{"app":"nino","t":7,"type":"pong"}"#),
            (.error(code: "version_unsupported", message: nil, versions: [1]),
             #"{"app":"nino","code":"version_unsupported","type":"error","versions":[1]}"#),
            (.ok, #"{"app":"nino","type":"ok"}"#),
        ]
        for (m, json) in cases { XCTAssertEqual(m.jsonString, json) }
    }
}
