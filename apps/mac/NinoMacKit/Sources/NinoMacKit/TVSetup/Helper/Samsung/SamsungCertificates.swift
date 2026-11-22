// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Security

// MARK: CSR (PKCS#10)

/// Yazar ve dağıtıcı sertifika istekleri (tv-kurulumu.md §9.7). ASN.1 elle yazılır: SAN'daki `URN:` büyük harf kalmalı.
public enum SamsungCSR {
    static let sha256WithRSA = "1.2.840.113549.1.1.11"
    static let rsaEncryption = "1.2.840.113549.1.1.1"
    static let commonName = "2.5.4.3"
    static let emailAddress = "1.2.840.113549.1.9.1"
    static let extensionRequest = "1.2.840.113549.1.9.14"
    static let subjectAltName = "2.5.29.17"

    public static func subjectPublicKeyInfo(_ key: SecKey) throws -> Data {
        guard let pub = SecKeyCopyPublicKey(key) else { throw ADBKey.KeyError.unreadable("public key") }
        var err: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(pub, &err) as Data? else {
            throw ADBKey.KeyError.unreadable(err.map { "\($0.takeRetainedValue())" } ?? "public key")
        }
        return DER.sequence(DER.algorithm(rsaEncryption), DER.bitString(pkcs1))
    }

    static func name(cn: String, email: String?) -> Data {
        var rdns = [DER.set(DER.sequence(DER.oid(commonName), DER.utf8(cn)))]
        if let email, !email.isEmpty { rdns.append(DER.set(DER.sequence(DER.oid(emailAddress), DER.ia5(email)))) }
        return DER.sequence(rdns)
    }

    /// Dağıtıcının SAN'ı: iki URI (`[6]`, IA5).
    static func distributorSAN(duid: String) -> Data {
        let uris = ["URN:tizen:packageid=", "URN:tizen:deviceid=\(duid)"].map { DER.tlv(0x86, Data($0.utf8)) }
        return DER.sequence(uris)
    }

    static func build(key: SecKey, subject: Data, attributes: Data) throws -> Data {
        let info = DER.sequence(DER.integer(0), subject, try subjectPublicKeyInfo(key), DER.tlv(0xa0, attributes))
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, info as CFData, &err) as Data? else {
            throw ADBKey.KeyError.signFailed(err.map { "\($0.takeRetainedValue())" } ?? "CSR")
        }
        return DER.sequence(info, DER.algorithm(sha256WithRSA), DER.bitString(sig))
    }

    public static func author(key: SecKey) throws -> Data {
        try build(key: key, subject: name(cn: "Nino", email: nil), attributes: Data())
    }

    public static func distributor(key: SecKey, email: String, duid: String) throws -> Data {
        let ext = DER.sequence(DER.oid(subjectAltName), DER.octets(distributorSAN(duid: duid)))
        let attr = DER.sequence(DER.oid(extensionRequest), DER.set(DER.sequence(ext)))
        return try build(key: key, subject: name(cn: "TizenSDK", email: email), attributes: attr)
    }

    public static func pem(_ der: Data, label: String = "CERTIFICATE REQUEST") -> Data {
        let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Data("-----BEGIN \(label)-----\n\(b64)\n-----END \(label)-----\n".utf8)
    }
}

// MARK: Sertifika sunucusu

/// Çok parçalı POST (testte sahte).
public protocol SamsungCertificateTransport: Sendable {
    /// Dönen: durum, neden metni, gövde. Ağ hatası fırlatır.
    func post(_ url: URL, body: Data, contentType: String, timeout: TimeInterval) async throws
        -> (status: Int, reason: String, body: Data)
}

public struct URLSessionCertificateTransport: SamsungCertificateTransport {
    public init() {}

    public func post(_ url: URL, body: Data, contentType: String, timeout: TimeInterval) async throws
        -> (status: Int, reason: String, body: Data) {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, HTTPURLResponse.localizedString(forStatusCode: status), data)
    }
}

/// Samsung'un sertifika uç noktaları ve yanıt işleme.
public struct SamsungCertificateClient: Sendable {
    public static let host = "svdca.samsungqbe.com"
    public static let authorPath = "/apis/v3/authors"
    public static let profilePath = "/apis/v1/distributors"
    public static let distributorPath = "/apis/v3/distributors"

    public struct Failure: Error, Equatable, Sendable {
        public var message: String
    }

    let transport: SamsungCertificateTransport
    let timeout: TimeInterval
    let log: @Sendable (String) -> Void

    public init(transport: SamsungCertificateTransport, timeout: TimeInterval = 60,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.transport = transport
        self.timeout = timeout
        self.log = log
    }

    public struct Issued: Sendable {
        public var author: Data
        public var distributor: Data
        public var deviceProfile: Data
        /// Yanıtta yapraktan sonra gelen sertifikalar (varsa).
        public var extraAuthor: [Data] = []
        public var extraDistributor: [Data] = []
    }

    /// Üç istek sırayla: yazar, cihaz profili (v1), dağıtıcı (v3).
    public func request(account: SamsungLogin.Account, authorCSR: Data, distributorCSR: Data) async throws -> Issued {
        let authorBody = try await post(Self.authorPath, account: account, distributor: false,
                                        fileName: "author.csr", csr: authorCSR)
        let author = try Self.certificates(authorBody, what: "yazar")
        logChain(Self.authorPath, author)
        let profile = try await post(Self.profilePath, account: account, distributor: true,
                                     fileName: "distributor.csr", csr: distributorCSR)
        let distBody = try await post(Self.distributorPath, account: account, distributor: true,
                                      fileName: "distributor.csr", csr: distributorCSR)
        let distributor = try Self.certificates(distBody, what: "dağıtıcı")
        logChain(Self.distributorPath, distributor)
        return Issued(author: author[0], distributor: distributor[0], deviceProfile: profile,
                      extraAuthor: Array(author.dropFirst()), extraDistributor: Array(distributor.dropFirst()))
    }

    /// Yanıttaki her sertifikanın konusu ve vereni (Samsung zinciri de veriyor mu, günlükte görünsün).
    func logChain(_ path: String, _ certs: [Data]) {
        let parts = certs.compactMap { X509Info(der: $0) }.map { "\($0.subjectCN) ← \($0.issuerCN)" }
        log("Sertifika yanıtı \(path): \(certs.count) sertifika: \(parts.joined(separator: "; "))")
    }

    static func multipart(boundary: String, account: SamsungLogin.Account, distributor: Bool,
                          fileName: String, csr: Data) -> Data {
        var fields = [("access_token", account.accessToken), ("user_id", account.userID), ("platform", "VD")]
        if distributor { fields += [("privilege_level", "public"), ("developer_type", "Individual")] }
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n".utf8))
            body.append(Data("Content-Type: text/plain; charset=utf-8\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"csr\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(csr)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    func post(_ path: String, account: SamsungLogin.Account, distributor: Bool, fileName: String,
              csr: Data) async throws -> Data {
        let boundary = "----nino" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let body = Self.multipart(boundary: boundary, account: account, distributor: distributor,
                                  fileName: fileName, csr: csr)
        let url = URL(string: "https://\(Self.host)\(path)")!
        let r: (status: Int, reason: String, body: Data)
        do {
            r = try await transport.post(url, body: body, contentType: "multipart/form-data; boundary=\(boundary)",
                                         timeout: timeout)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure(message: "Samsung'un sertifika sunucusuna (\(Self.host)) ulaşılamadı: \(error.localizedDescription)")
        }
        log("Sertifika sunucusu \(path): \(r.status) \(r.reason), \(r.body.count) bayt")
        guard (200..<300).contains(r.status) else {
            throw Failure(message: "Samsung sertifika sunucusu \(path): \(r.status) \(r.reason) \(Self.errorText(r.body))")
        }
        return r.body
    }

    /// Hata gövdesinin özeti: JSON ise bilinen alanlar `ad=değer`; değilse ilk 300 karakter + `…`.
    static func errorText(_ body: Data) -> String {
        if let o = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
            let keys = ["code", "errorCode", "error", "message", "errorMessage", "error_description"]
            return keys.compactMap { k -> String? in
                switch o[k] {
                case let s as String: return "\(k)=\(s)"
                case let n as NSNumber: return "\(k)=\(n.stringValue)"
                default: return nil
                }
            }.joined(separator: ", ")
        }
        let text = String(decoding: body, as: UTF8.self)
        return text.count > 300 ? String(text.prefix(300)) + "…" : text
    }

    /// PEM varsa PEM (birden çok olabilir), yoksa DER; okunamazsa hata. İlki yapraktır.
    static func certificates(_ body: Data, what: String) throws -> [Data] {
        let all = X509Info.certificates(fromPEMOrDER: body).filter { SecCertificateCreateWithData(nil, $0 as CFData) != nil }
        if !all.isEmpty { return all }
        throw Failure(message: "Samsung \(what) sertifikası vermedi: \(errorText(body))")
    }
}

// MARK: Ara sertifikalar

/// Gömülü dört Samsung ara sertifikası (Tizen Studio dosyaları; sıra sabit, §9.7).
public enum SamsungIntermediates {
    public static let fileNames = ["vd_tizen_dev_author_ca", "author_ca", "vd_tizen_dev_public2", "public2"]

    /// Paketteki PEM'ler, sabit sırayla (bulunamayanlar atlanır).
    public static func bundled() -> [Data] { bundled(in: .module) }

    static func bundled(in bundle: Bundle) -> [Data] {
        fileNames.compactMap { name in
            let url = bundle.url(forResource: name, withExtension: "pem")
                ?? bundle.url(forResource: name, withExtension: "pem", subdirectory: "samsung-ca")
            guard let url, let data = try? Data(contentsOf: url) else { return nil }
            return X509Info.certificates(fromPEMOrDER: data).first
        }
    }

    /// Konusu yaprağın verenine eşit, kendini vermemiş ilk sertifika.
    public static func pick(for leaf: Data, from candidates: [Data]) -> Data? {
        guard let info = X509Info(der: leaf) else { return nil }
        return candidates.first { c in
            guard let ci = X509Info(der: c) else { return false }
            return ci.subjectDER == info.issuerDER && !ci.isSelfIssued
        }
    }
}
