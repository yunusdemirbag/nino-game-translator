// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

/// WebSocket çerçevesi (RFC 6455). Yalnız protokolün ihtiyacı kadar.
public struct WebSocketFrame: Equatable, Sendable {
    public enum Opcode: UInt8, Sendable {
        case continuation = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
    }

    public enum DecodeError: Error, Equatable {
        case badOpcode(UInt8)
        case tooLarge
        case unmaskedClientFrame
        case reservedBits
    }

    public var fin: Bool
    public var opcode: Opcode
    public var payload: Data

    public init(fin: Bool = true, opcode: Opcode, payload: Data) {
        self.fin = fin
        self.opcode = opcode
        self.payload = payload
    }

    public static func text(_ s: String) -> WebSocketFrame { .init(opcode: .text, payload: Data(s.utf8)) }

    /// Çerçeveyi bayta çevirir. İstemci çerçeveleri maskelenmelidir.
    public func encoded(mask: [UInt8]? = nil) -> Data {
        var out = Data()
        out.append((fin ? 0x80 : 0) | opcode.rawValue)
        let maskBit: UInt8 = mask == nil ? 0 : 0x80
        let n = payload.count
        if n < 126 {
            out.append(maskBit | UInt8(n))
        } else if n <= 0xFFFF {
            out.append(maskBit | 126)
            out.append(UInt8(n >> 8)); out.append(UInt8(n & 0xFF))
        } else {
            out.append(maskBit | 127)
            for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8((UInt64(n) >> UInt64(shift)) & 0xFF)) }
        }
        if let mask {
            out.append(contentsOf: mask)
            for (i, b) in payload.enumerated() { out.append(b ^ mask[i % 4]) }
        } else {
            out.append(payload)
        }
        return out
    }

    /// Tampondan bir çerçeve okur. Yetersiz bayt varsa `nil`.
    public static func decode(_ buffer: Data, maxPayload: Int, requireMask: Bool) throws -> (frame: WebSocketFrame, consumed: Int)? {
        let b = [UInt8](buffer.prefix(14))
        guard b.count >= 2 else { return nil }
        if b[0] & 0x70 != 0 { throw DecodeError.reservedBits }
        guard let opcode = Opcode(rawValue: b[0] & 0x0F) else { throw DecodeError.badOpcode(b[0] & 0x0F) }
        let fin = b[0] & 0x80 != 0
        let masked = b[1] & 0x80 != 0
        if requireMask && !masked { throw DecodeError.unmaskedClientFrame }

        var length = UInt64(b[1] & 0x7F)
        var offset = 2
        if length == 126 {
            guard b.count >= 4 else { return nil }
            length = UInt64(b[2]) << 8 | UInt64(b[3])
            offset = 4
        } else if length == 127 {
            guard b.count >= 10 else { return nil }
            length = (2..<10).reduce(UInt64(0)) { $0 << 8 | UInt64(b[$1]) }
            offset = 10
        }
        guard length <= UInt64(maxPayload) else { throw DecodeError.tooLarge }

        var mask: [UInt8]?
        if masked {
            let all = [UInt8](buffer.prefix(offset + 4))
            guard all.count >= offset + 4 else { return nil }
            mask = Array(all[offset..<offset + 4])
            offset += 4
        }
        let total = offset + Int(length)
        guard buffer.count >= total else { return nil }
        let start = buffer.startIndex
        var payload = Data(buffer[(start + offset)..<(start + total)])
        if let mask {
            payload = Data(payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        }
        return (WebSocketFrame(fin: fin, opcode: opcode, payload: payload), total)
    }

    /// `Sec-WebSocket-Accept` değeri.
    public static func acceptKey(for key: String) -> String {
        let magic = key.trimmingCharacters(in: .whitespaces) + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        return Data(Insecure.SHA1.hash(data: Data(magic.utf8))).base64EncodedString()
    }
}

/// Parçalı (fragmented) mesajları birleştirir.
struct WebSocketAssembler {
    private var opcode: WebSocketFrame.Opcode?
    private var buffer = Data()
    let maxMessage: Int

    enum Result: Equatable { case message(WebSocketFrame.Opcode, Data), control(WebSocketFrame), none, tooLarge, protocolError }

    mutating func add(_ frame: WebSocketFrame) -> Result {
        switch frame.opcode {
        case .close, .ping, .pong:
            return .control(frame)
        case .text, .binary:
            guard opcode == nil else { return .protocolError }
            if frame.fin { return .message(frame.opcode, frame.payload) }
            opcode = frame.opcode
            buffer = frame.payload
            return .none
        case .continuation:
            guard let op = opcode else { return .protocolError }
            buffer.append(frame.payload)
            if buffer.count > maxMessage { return .tooLarge }
            guard frame.fin else { return .none }
            let out = buffer
            opcode = nil
            buffer = Data()
            return .message(op, out)
        }
    }
}

/// En basit HTTP/1.1 istek okuyucusu.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data
    /// `?`'den sonraki kısım (çözülmemiş); yoksa boş.
    public var query: String = ""

    public enum ParseError: Error, Equatable { case malformed, tooLarge }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// Tampondan bir istek okur. Yetersiz bayt varsa `nil`.
    public static func parse(_ buffer: Data, maxBytes: Int = 64 * 1024) throws -> (request: HTTPRequest, consumed: Int)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = buffer.range(of: separator) else {
            if buffer.count > maxBytes { throw ParseError.tooLarge }
            return nil
        }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else { throw ParseError.malformed }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { throw ParseError.malformed }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { throw ParseError.malformed }
        guard length <= maxBytes else { throw ParseError.tooLarge }
        let bodyStart = end.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: length)
        var path = String(requestLine[1])
        var query = ""
        if let q = path.firstIndex(of: "?") {
            query = String(path[path.index(after: q)...])
            path = String(path[..<q])
        }
        let request = HTTPRequest(method: String(requestLine[0]).uppercased(), path: path,
                                  headers: headers, body: Data(buffer[bodyStart..<bodyEnd]), query: query)
        return (request, buffer.distance(from: buffer.startIndex, to: bodyEnd))
    }

    /// Sorgu parametreleri (çözülmüş). Aynı ad birden çok kez varsa ilki.
    public var queryItems: [String: String] {
        var out: [String: String] = [:]
        for part in query.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decode: (Substring) -> String = { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
            let k = decode(kv[0])
            if out[k] == nil { out[k] = kv.count > 1 ? decode(kv[1]) : "" }
        }
        return out
    }

    /// Basit bir HTTP cevabı.
    public static func response(status: Int, reason: String, headers: [String: String] = [:], body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var all = headers
        if all["Content-Length"] == nil, status != 101 { all["Content-Length"] = "\(body.count)" }
        for (k, v) in all.sorted(by: { $0.key < $1.key }) { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
