// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation

// Samsung'un geliştirici sertifikaları: sertifika istekleri (CSR), Samsung'dan alınan TV'ye özel imza profili ve
// Tizen web paketinin (.wgt) imzalanması (W3C Widget Signature: author-signature.xml ve signature1.xml).
// Uç noktalar ve alan adları Tizen Studio'nun sertifika yöneticisinin kullandıklarıdır.

/// Sertifika istekleri.
enum SamsungCSR {
    /// Yazar isteği (CN=Nino).
    static func author(_ key: RSAPrivateKey) throws -> Bytes {
        ASN1.pem(try request(key, subject: name("Nino", email: nil), extensions: nil), label: "CERTIFICATE REQUEST")
    }

    /// Dağıtıcı isteği: CN=TizenSDK ve TV'nin DUID'i (TV imzayı yalnız kendi kimliği yazılıysa kabul eder).
    static func distributor(_ key: RSAPrivateKey, duid: String, email: String) throws -> Bytes {
        let names = ASN1.seq(ASN1.node(0x86, Bytes("URN:tizen:packageid=".utf8)),
                             ASN1.node(0x86, Bytes("URN:tizen:deviceid=\(duid)".utf8)))
        let san = ASN1.seq(ASN1.oid("2.5.29.17"), ASN1.octets(names))
        let mail = email.trimmingCharacters(in: .whitespaces)
        return ASN1.pem(try request(key, subject: name("TizenSDK", email: mail.isEmpty ? nil : mail),
                                    extensions: ASN1.seq(san)), label: "CERTIFICATE REQUEST")
    }

    private static func name(_ cn: String, email: String?) -> Bytes {
        var rdns = [ASN1.set(ASN1.seq(ASN1.oid("2.5.4.3"), ASN1.utf8(cn)))]
        if let email { rdns.append(ASN1.set(ASN1.seq(ASN1.oid("1.2.840.113549.1.9.1"), ASN1.ia5(email)))) }
        return ASN1.seq(of: rdns)
    }

    static func request(_ key: RSAPrivateKey, subject: Bytes, extensions: Bytes?) throws -> Bytes {
        let attributes = extensions.map { ASN1.node(0xA0, ASN1.seq(ASN1.oid("1.2.840.113549.1.9.14"), ASN1.set($0))) }
            ?? ASN1.node(0xA0, [])
        let info = ASN1.seq(ASN1.small(0), subject, key.subjectPublicKeyInfo, attributes)
        let signature = try key.sign(info, .rsaSignatureMessagePKCS1v15SHA256)
        return ASN1.seq(info, ASN1.seq(ASN1.oid("1.2.840.113549.1.1.11"), ASN1.null), ASN1.bits(signature))
    }
}

struct SamsungAccount: Sendable, Equatable {
    var accessToken: String
    var userID: String
    var email: String
}

/// Bir TV için imza dosyaları: `tv/samsung/<duid>/key.der, author.cer, distributor.cer, device-profile.xml, duid.txt`.
struct SamsungProfile {
    let folder: URL
    var keyFile: URL { folder.appendingPathComponent("key.der") }
    var authorFile: URL { folder.appendingPathComponent("author.cer") }
    var distributorFile: URL { folder.appendingPathComponent("distributor.cer") }
    var deviceProfileFile: URL { folder.appendingPathComponent("device-profile.xml") }
    var duidFile: URL { folder.appendingPathComponent("duid.txt") }

    var exists: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: keyFile.path) && fm.fileExists(atPath: authorFile.path) && fm.fileExists(atPath: distributorFile.path)
    }

    func key() throws -> RSAPrivateKey { try RSAPrivateKey(pkcs1: Bytes(Data(contentsOf: keyFile))) }
    func author() throws -> TVCertificate { try TVCertificate(Bytes(Data(contentsOf: authorFile))) }
    func distributor() throws -> TVCertificate { try TVCertificate(Bytes(Data(contentsOf: distributorFile))) }

    /// Sertifikalar bir gün payla geçerli mi?
    func isUsable(now: Date = Date()) -> Bool {
        guard exists, let a = try? author(), let d = try? distributor() else { return false }
        let soon = now.addingTimeInterval(86_400)
        return [a, d].allSatisfy { $0.notBefore <= soon && $0.notAfter >= soon }
    }

    func belongs(to duid: String) -> Bool {
        // duid.txt yoksa (çok eski kayıt) profil bu TV'nin sayılır.
        guard let saved = try? String(contentsOf: duidFile, encoding: .utf8) else { return true }
        return saved.trimmingCharacters(in: .whitespacesAndNewlines) == duid
    }

    func summary(_ duid: String) -> String {
        guard exists else { return "none" }
        guard let a = try? author(), let d = try? distributor() else { return "unreadable" }
        let state = !belongs(to: duid) ? "another TV's" : isUsable() ? "valid" : "expired"
        return "\(state); author \(a.notBefore)…\(a.notAfter), distributor \(d.notBefore)…\(d.notAfter) by \(d.summary)"
    }

    func save(key: RSAPrivateKey, author: Bytes, distributor: Bytes, deviceProfile: Bytes, duid: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(try key.pkcs1()).write(to: keyFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try Data(author).write(to: authorFile, options: .atomic)
        try Data(distributor).write(to: distributorFile, options: .atomic)
        try Data(deviceProfile).write(to: deviceProfileFile, options: .atomic)
        try Data(duid.utf8).write(to: duidFile, options: .atomic)
    }

    /// TV'nin reddettiği profil kenara konur; bir sonraki kurulum yenisini ister.
    func setAside() {
        let target = folder.deletingLastPathComponent()
            .appendingPathComponent("\(folder.lastPathComponent).rejected-\(Int(Date().timeIntervalSince1970))")
        if (try? FileManager.default.moveItem(at: folder, to: target)) == nil { try? FileManager.default.removeItem(at: folder) }
    }
}

/// Samsung'dan TV'ye özel yazar ve dağıtıcı sertifikası alır.
struct SamsungCertificateService {
    static let authorURL = URL(string: "https://svdca.samsungqbe.com/apis/v3/authors")!
    static let deviceProfileURL = URL(string: "https://svdca.samsungqbe.com/apis/v1/distributors")!
    static let distributorURL = URL(string: "https://svdca.samsungqbe.com/apis/v3/distributors")!

    var log: TVInstallLog
    /// HTTP gönderimi (testlerde değiştirilir).
    var send: (URLRequest) throws -> Data = { try BlockingHTTP.send($0) }

    /// Samsung'un geliştirici sertifikalarını veren ara sertifikalar (uygulamayla gelir: samsung-ca).
    static let authorities: [TVCertificate] = ["vd_tizen_dev_author_ca", "author_ca", "vd_tizen_dev_public2", "public2"]
        .compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "pem"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? TVCertificate(Bytes(data))
        }

    /// İmzadaki zincir: yaprak ve onu veren ara sertifika (kök yok).
    static func chain(for leaf: TVCertificate, authorities: [TVCertificate] = authorities) -> [TVCertificate] {
        let issuer = authorities.first {
            $0.subjectName != nil && $0.subjectName == leaf.issuerName && $0.subjectName != $0.issuerName
        }
        return [leaf] + (issuer.map { [$0] } ?? [])
    }

    func issue(duid: String, account: SamsungAccount, into profile: SamsungProfile) throws -> SamsungProfile {
        let key = try RSAPrivateKey.generate()
        let authorCSR = try SamsungCSR.author(key)
        let distributorCSR = try SamsungCSR.distributor(key, duid: duid, email: account.email)
        let author = try post(Self.authorURL, form(account, authorCSR, "author.csr", distributor: false))
        let deviceProfile = try post(Self.deviceProfileURL, form(account, distributorCSR, "distributor.csr", distributor: true))
        let distributor = try post(Self.distributorURL, form(account, distributorCSR, "distributor.csr", distributor: true))
        try profile.save(key: key, author: try certificate(author, "author").der,
                         distributor: try certificate(distributor, "distributor").der,
                         deviceProfile: Bytes(deviceProfile), duid: duid)
        return profile
    }

    private func form(_ account: SamsungAccount, _ csr: Bytes, _ file: String, distributor: Bool) -> MultipartForm {
        var f = MultipartForm()
        f.field("access_token", account.accessToken)
        f.field("user_id", account.userID)
        f.field("platform", "VD")
        if distributor {
            f.field("privilege_level", "public")
            f.field("developer_type", "Individual")
        }
        f.file("csr", file, csr)
        return f
    }

    private func post(_ url: URL, _ body: MultipartForm) throws -> Data {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 60
        r.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        r.httpBody = body.encoded
        do {
            let data = try send(r)
            log.write("Certificate server \(url.path): \(data.count) bytes")
            return data
        } catch let failure as BlockingHTTP.Failure {
            log.write("Certificate server \(url.path) failed: \(failure)")
            throw SamsungFailure(problem: .certificateFailed, detail: "\(url.path): \(failure)")
        }
    }

    private func certificate(_ data: Data, _ kind: String) throws -> TVCertificate {
        do {
            return try TVCertificate(Bytes(data))
        } catch {
            let text = TVInstallLog.short(String(decoding: data, as: UTF8.self), limit: 300)
            log.write("Samsung's \(kind) certificate unreadable: \(text)")
            throw SamsungFailure(problem: .certificateFailed, detail: "\(kind): \(text)")
        }
    }
}

struct MultipartForm {
    let boundary = "nino-\(UUID().uuidString)"
    private var body = Data()
    var contentType: String { "multipart/form-data; boundary=" + boundary }

    mutating func field(_ name: String, _ value: String) {
        part("Content-Disposition: form-data; name=\"\(name)\"\r\nContent-Type: text/plain; charset=utf-8", Data(value.utf8))
    }

    mutating func file(_ name: String, _ filename: String, _ data: Bytes) {
        part("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream",
             Data(data))
    }

    private mutating func part(_ headers: String, _ data: Data) {
        body.append(Data("--\(boundary)\r\n\(headers)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    var encoded: Data { body + Data("--\(boundary)--\r\n".utf8) }
}

// MARK: - .wgt imzası

/// Tizen web paketini imzalar: özetler SHA-512, imza RSA-SHA512, SignedInfo dışlayıcı C14N biçiminde yazılır
/// (metin elle kanonik biçimde üretilir; ayrıca kanonikleştirme gerekmez).
enum WidgetSigner {
    static let dsig = "http://www.w3.org/2000/09/xmldsig#"
    private static let props = "http://www.w3.org/2009/xmldsig-properties"
    private static let rsaSHA512 = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"
    private static let sha512 = "http://www.w3.org/2001/04/xmlenc#sha512"
    private static let excC14N = "http://www.w3.org/2001/10/xml-exc-c14n#"
    private static let c14n11 = "http://www.w3.org/2006/12/xml-c14n11"

    struct Signer {
        var key: RSAPrivateKey
        /// Yaprak önce, kök yok.
        var chain: [TVCertificate]
    }

    enum Role: String {
        case author = "AuthorSignature"
        case distributor = "DistributorSignature"
    }

    static func sign(_ wgt: Bytes, author: Signer, distributor: Signer) throws -> Bytes {
        let files = try ZipArchive(wgt).entries.filter { e in
            let lower = e.name.lowercased()
            return !e.name.hasSuffix("/") && lower != "author-signature.xml" && !(lower.hasPrefix("signature") && lower.hasSuffix(".xml"))
        }
        let authorXML = ZipArchive.Entry(name: "author-signature.xml", data: try signature(.author, files, author))
        let distributorXML = ZipArchive.Entry(name: "signature1.xml", data: try signature(.distributor, [authorXML] + files, distributor))
        return ZipArchive(entries: [authorXML, distributorXML] + files).stored()
    }

    static func signature(_ role: Role, _ files: [ZipArchive.Entry], _ signer: Signer) throws -> Bytes {
        let info = signedInfo(files, propertiesDigest: digest(Bytes(properties(role, standalone: true).utf8)))
        // Kanonik SignedInfo: ad alanı öğenin kendisinde yazılır.
        let canonical = "<SignedInfo xmlns=\"\(dsig)\">" + info.dropFirst("<SignedInfo>".count)
        let value = try signer.key.sign(Bytes(canonical.utf8), .rsaSignatureMessagePKCS1v15SHA512)
        var xml = "<Signature xmlns=\"\(dsig)\" Id=\"\(escape(role.rawValue))\">" + info
        xml += "<SignatureValue>\(Data(value).base64EncodedString())</SignatureValue><KeyInfo><X509Data>"
        for cert in signer.chain {
            xml += "<X509Certificate>\n" + Data(cert.der).base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
                + "\n</X509Certificate>"
        }
        xml += "</X509Data></KeyInfo>" + properties(role, standalone: false) + "</Signature>"
        return Bytes(xml.utf8)
    }

    static func signedInfo(_ files: [ZipArchive.Entry], propertiesDigest: String) -> String {
        var xml = "<SignedInfo><CanonicalizationMethod Algorithm=\"\(excC14N)\"></CanonicalizationMethod>"
        xml += "<SignatureMethod Algorithm=\"\(rsaSHA512)\"></SignatureMethod>"
        for f in files {
            xml += "<Reference URI=\"\(escape(referenceURI(f.name)))\"><DigestMethod Algorithm=\"\(sha512)\"></DigestMethod>"
            xml += "<DigestValue>\(digest(f.data))</DigestValue></Reference>"
        }
        xml += "<Reference URI=\"#prop\"><Transforms><Transform Algorithm=\"\(c14n11)\"></Transform></Transforms>"
        xml += "<DigestMethod Algorithm=\"\(sha512)\"></DigestMethod><DigestValue>\(propertiesDigest)</DigestValue></Reference>"
        return xml + "</SignedInfo>"
    }

    /// `<Object Id="prop">`; özetlenen (kanonik) biçimde ad alanı öğede yazılır.
    static func properties(_ role: Role, standalone: Bool) -> String {
        let target = escape("#\(role.rawValue)")
        let roleURI = "http://www.w3.org/ns/widgets-digsig#role-\(role == .author ? "author" : "distributor")"
        func property(_ id: String, _ element: String, _ uri: String?) -> String {
            let attr = uri.map { " URI=\"\(escape($0))\"" } ?? ""
            return "<SignatureProperty Id=\"\(id)\" Target=\"\(target)\"><dsp:\(element)\(attr)></dsp:\(element)></SignatureProperty>"
        }
        return (standalone ? "<Object xmlns=\"\(dsig)\" Id=\"prop\">" : "<Object Id=\"prop\">")
            + "<SignatureProperties xmlns:dsp=\"\(props)\">"
            + property("profile", "Profile", "http://www.w3.org/ns/widgets-digsig#profile")
            + property("role", "Role", roleURI)
            + property("identifier", "Identifier", nil)
            + "</SignatureProperties></Object>"
    }

    /// Dosya adı URI olarak (yalnız gerekli karakterler kodlanır; düz adlar olduğu gibi kalır).
    static func referenceURI(_ name: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/!$&'()*+,;=:@")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    static func digest(_ data: Bytes) -> String { Data(SHA512.hash(data: data)).base64EncodedString() }

    static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case "\"": out += "&quot;"
            case "\t": out += "&#x9;"
            case "\n": out += "&#xA;"
            case "\r": out += "&#xD;"
            default: out.append(c)
            }
        }
        return out
    }
}
