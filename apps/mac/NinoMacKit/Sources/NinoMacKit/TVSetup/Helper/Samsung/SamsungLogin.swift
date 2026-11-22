// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Darwin
import Foundation

/// Samsung hesabıyla giriş (tv-kurulumu.md §9.6): tarayıcıda giriş kapısı, dönüş `localhost:4794`'te dinlenir.
public enum SamsungLogin {
    public static let gate = "https://account.samsung.com/accounts/be1dce529476c1a6d407c4c7578c31bd/signInGate"
    public static let clientID = "v285zxnl3h"
    public static let state = "accountcheckdogeneratedstatetext"
    public static let port: UInt16 = 4794
    public static let callbackPath = "/signin/callback"

    public static func redirectURI(port: UInt16 = port) -> String { "http://localhost:\(port)\(callbackPath)" }

    /// Tarayıcıda açılacak adres (dönüş adresi yüzde kodlu).
    public static func url(port: UInt16 = port) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let redirect = redirectURI(port: port).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "\(gate)?locale=&clientId=\(clientID)&redirect_uri=\(redirect)&state=\(state)&tokenType=TOKEN")!
    }

    public struct Account: Equatable, Sendable {
        public var accessToken: String
        public var userID: String
        public var email: String
        public init(accessToken: String, userID: String, email: String) {
            self.accessToken = accessToken
            self.userID = userID
            self.email = email
        }
    }

    public enum LoginError: Error, Equatable, Sendable {
        case portUnavailable(String)
        case timedOut(summary: String?)
    }

    // MARK: Dönüş isteği

    struct Request {
        var method: String
        var path: String
        var body: Data
    }

    /// Başlık (en çok 1 MB) ve `Content-Length` kadar gövde; eksikse nil (daha veri gerekli).
    static func parseRequest(_ data: Data) -> Request?? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 1024 * 1024 ? .some(nil) : nil
        }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return .some(nil) }
        var length = 0
        for l in lines.dropFirst() {
            guard let colon = l.firstIndex(of: ":") else { continue }
            if l[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(l[l.index(after: colon)...].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = end.upperBound
        guard data.endIndex - bodyStart >= length else { return nil }
        return .some(Request(method: String(parts[0]), path: String(parts[1]),
                             body: Data(data[bodyStart..<(bodyStart + length)])))
    }

    /// Form gövdesi alanları (`+` boşluk, yüzde kodu çözülür) — `code` için ham değer de tutulur.
    static func formFields(_ body: Data) -> [(name: String, raw: String)] {
        String(decoding: body, as: UTF8.self).split(separator: "&").map { pair in
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(kv[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(kv[0])
            return (name, kv.count > 1 ? String(kv[1]) : "")
        }
    }

    static func formDecode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }

    /// Dönüş gövdesinden hesap; yoksa nil ve günlük için özet.
    static func account(fromCallbackBody body: Data) -> (Account?, String) {
        let fields = formFields(body)
        let state = fields.first { $0.name == "state" }.map { formDecode($0.raw) }
        let code = fields.first { $0.name == "code" }.flatMap { $0.raw.removingPercentEncoding } ?? ""
        let summary = summarize(fields)
        guard state == Self.state, !code.isEmpty,
              let o = (try? JSONSerialization.jsonObject(with: Data(code.utf8))) as? [String: Any],
              let token = o["access_token"] as? String, !token.isEmpty,
              let user = o["userId"] as? String, !user.isEmpty else {
            return (nil, summary)
        }
        return (Account(accessToken: token, userID: user, email: (o["inputEmailID"] as? String) ?? ""), summary)
    }

    /// Alan adları; yalnız `error`, `error_description`, `error_code`, `state` değerleri; en çok 200 karakter.
    static func summarize(_ fields: [(name: String, raw: String)]) -> String {
        let shown: Set<String> = ["error", "error_description", "error_code", "state"]
        let text = fields.map { f in shown.contains(f.name) ? "\(f.name)=\(formDecode(f.raw))" : f.name }
            .joined(separator: ", ")
        return text.count > 200 ? String(text.prefix(200)) : text
    }

    static func response(_ status: String, _ body: String) -> Data {
        let b = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(b.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + b
    }

    static let donePage = """
    <!doctype html><html><head><meta charset="utf-8"><title>Nino</title></head>\
    <body style="font-family:-apple-system,sans-serif;text-align:center;padding:48px">\
    <h2>Giriş tamam / Signed in</h2>\
    <p>Nino'ya geri dönebilirsiniz, bu sekme kapatılabilir. / All done here, head back to Nino.</p></body></html>
    """
}

/// Giriş dönüşünü bekleyen dinleyici (testte sahte).
public protocol SamsungLoginListening: Sendable {
    /// Dinleyiciyi açar (açılamazsa `portUnavailable`), `onReady` çağırır ve hesabı bekler.
    func waitForAccount(timeout: TimeInterval, onReady: @escaping @Sendable () -> Void) async throws -> SamsungLogin.Account
}

/// BSD soketleriyle `[::]:port` (çift yığın) dinleyici.
public struct SocketLoginListener: SamsungLoginListening {
    public let port: UInt16
    /// Yalnız 127.0.0.1 (test). Varsayılan: IPv6 her adres, çift yığın.
    public let loopbackOnly: Bool

    public init(port: UInt16 = SamsungLogin.port, loopbackOnly: Bool = false) {
        self.port = port
        self.loopbackOnly = loopbackOnly
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    public func waitForAccount(timeout: TimeInterval, onReady: @escaping @Sendable () -> Void) async throws -> SamsungLogin.Account {
        let fd = try openSocket()
        let cancelled = Flag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SamsungLogin.Account, Error>) in
                let thread = Thread {
                    defer { Darwin.close(fd) }
                    onReady()
                    cont.resume(with: Self.serve(fd: fd, timeout: timeout, cancelled: cancelled))
                }
                thread.name = "nino.samsung.login"
                thread.start()
            }
        } onCancel: {
            cancelled.set()
        }
    }

    func openSocket() throws -> Int32 {
        let family = loopbackOnly ? AF_INET : AF_INET6
        let fd = socket(family, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw SamsungLogin.LoginError.portUnavailable(String(cString: strerror(errno))) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var result: Int32
        if loopbackOnly {
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = port.bigEndian
            a.sin_addr.s_addr = inet_addr("127.0.0.1")
            result = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        } else {
            var zero: Int32 = 0
            setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &zero, socklen_t(MemoryLayout<Int32>.size))
            var a = sockaddr_in6()
            a.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            a.sin6_family = sa_family_t(AF_INET6)
            a.sin6_port = port.bigEndian
            a.sin6_addr = in6addr_any
            result = withUnsafePointer(to: &a) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        }
        if result != 0 || listen(fd, 16) != 0 {
            let msg = String(cString: strerror(errno))
            Darwin.close(fd)
            throw SamsungLogin.LoginError.portUnavailable(msg)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    static func serve(fd: Int32, timeout: TimeInterval, cancelled: Flag) -> Result<SamsungLogin.Account, Error> {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSummary: String?
        while Date() < deadline {
            if cancelled.isSet { return .failure(CancellationError()) }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 200) > 0 else { continue }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }
            defer { Darwin.close(client) }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var tv = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var data = Data()
            var request: SamsungLogin.Request?
            var buf = [UInt8](repeating: 0, count: 16 * 1024)
            reading: while true {
                if let parsed = SamsungLogin.parseRequest(data) {
                    request = parsed
                    break reading
                }
                let n = recv(client, &buf, buf.count, 0)
                if n <= 0 { break reading }
                data.append(buf, count: n)
            }
            guard let req = request else {
                send(client, SamsungLogin.response("404 Not Found", "Not found"))
                continue
            }
            guard req.method == "POST", req.path.hasPrefix(SamsungLogin.callbackPath) else {
                send(client, SamsungLogin.response("404 Not Found", "Not found"))
                continue
            }
            let (account, summary) = SamsungLogin.account(fromCallbackBody: req.body)
            if let account {
                send(client, SamsungLogin.response("200 OK", SamsungLogin.donePage))
                return .success(account)
            }
            lastSummary = summary
            send(client, SamsungLogin.response("400 Bad Request", "Not found"))
        }
        return .failure(SamsungLogin.LoginError.timedOut(summary: lastSummary))
    }

    static func send(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = Darwin.send(fd, raw.baseAddress! + off, raw.count - off, 0)
                if n <= 0 { return }
                off += n
            }
        }
    }
}
