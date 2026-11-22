// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import CryptoKit
import Foundation
import Security

/// `.wgt` paketini W3C Widget Signature biçiminde imzalar (tv-kurulumu.md §9.9). Yapı sabit olduğu için kanonik
/// biçim doğrudan yazılır; dosyaya da aynı metin yazılır.
public enum WidgetSigner {
    public struct Identity: @unchecked Sendable {
        public var key: SecKey
        /// Yaprak önce, sonra ara sertifika (kök konmaz).
        public var certificates: [Data]
        public init(key: SecKey, certificates: [Data]) {
            self.key = key
            self.certificates = certificates
        }
    }

    public enum Role: String, Sendable {
        case author, distributor
        var signatureID: String { self == .author ? "AuthorSignature" : "DistributorSignature" }
        var fileName: String { self == .author ? "author-signature.xml" : "signature1.xml" }
    }

    static let dsig = "http://www.w3.org/2000/09/xmldsig#"

    /// İmzalanacak mı: klasör ve eski imza dosyaları dışarıda.
    static func isSigned(_ name: String) -> Bool {
        let l = name.lowercased()
        return !name.hasSuffix("/") && !l.hasSuffix("author-signature.xml") && !l.hasSuffix("signature1.xml")
    }

    /// Paketi imzalar: yeni zip (önce author-signature.xml, sonra signature1.xml, sonra girdiler eski sırayla; klasör
    /// girdileri zip'te kalır ama imzalanmaz, eski imzalar atılır).
    public static func sign(package: Data, author: Identity, distributor: Identity, date: Date = Date()) throws -> Data {
        let zip = try WidgetZip(data: package)
        let kept = zip.entries.filter { isSigned($0.name) }
        var files: [(String, Data)] = []
        for e in kept { files.append((e.name, try WidgetZip.contents(e))) }
        let authorXML = try signature(role: .author, files: files, identity: author)
        let distXML = try signature(role: .distributor, files: [(Role.author.fileName, authorXML)] + files,
                                    identity: distributor)
        let out = WidgetZip(entries: [WidgetZip.entry(name: Role.author.fileName, contents: authorXML, date: date),
                                      WidgetZip.entry(name: Role.distributor.fileName, contents: distXML, date: date)]
            + zip.entries.filter { $0.isDirectory || isSigned($0.name) })
        return out.encoded()
    }

    // MARK: XML

    static func escapeAttribute(_ s: String) -> String {
        var out = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case "\"": out += "&quot;"
            case "\t": out += "&#x9;"
            case "\n": out += "&#xA;"
            case "\r": out += "&#xD;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    static func digest(_ d: Data) -> String { Data(SHA512.hash(data: d)).base64EncodedString() }

    static func reference(uri: String, digest: String, transform: String? = nil) -> String {
        var r = "<Reference URI=\"\(escapeAttribute(uri))\">"
        if let transform { r += "<Transforms><Transform Algorithm=\"\(transform)\"></Transform></Transforms>" }
        r += "<DigestMethod Algorithm=\"http://www.w3.org/2001/04/xmlenc#sha512\"></DigestMethod>"
        r += "<DigestValue>\(digest)</DigestValue></Reference>"
        return r
    }

    /// `<Object Id="prop">…</Object>` iç kısmı (kök açılışı ayrı yazılır).
    static func objectBody(role: Role) -> String {
        let target = escapeAttribute("#" + role.signatureID)
        return "<SignatureProperties xmlns:dsp=\"http://www.w3.org/2009/xmldsig-properties\">"
            + "<SignatureProperty Id=\"profile\" Target=\"\(target)\"><dsp:Profile URI=\"http://www.w3.org/ns/widgets-digsig#profile\"></dsp:Profile></SignatureProperty>"
            + "<SignatureProperty Id=\"role\" Target=\"\(target)\"><dsp:Role URI=\"http://www.w3.org/ns/widgets-digsig#role-\(role.rawValue)\"></dsp:Role></SignatureProperty>"
            + "<SignatureProperty Id=\"identifier\" Target=\"\(target)\"><dsp:Identifier></dsp:Identifier></SignatureProperty>"
            + "</SignatureProperties></Object>"
    }

    static func certificateText(_ der: Data) -> String {
        "\n" + der.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]) + "\n"
    }

    /// Kanonik SignedInfo (kökte xmlns) ve dosyadaki biçimi.
    struct Parts {
        var signedInfoBody: String
        var canonicalSignedInfo: String { "<SignedInfo xmlns=\"\(WidgetSigner.dsig)\">" + signedInfoBody }
        var fileSignedInfo: String { "<SignedInfo>" + signedInfoBody }
    }

    static func signedInfo(role: Role, files: [(String, Data)]) -> Parts {
        var body = "<CanonicalizationMethod Algorithm=\"http://www.w3.org/2001/10/xml-exc-c14n#\"></CanonicalizationMethod>"
        body += "<SignatureMethod Algorithm=\"http://www.w3.org/2001/04/xmldsig-more#rsa-sha512\"></SignatureMethod>"
        for (name, data) in files { body += reference(uri: name, digest: digest(data)) }
        let canonicalObject = "<Object xmlns=\"\(dsig)\" Id=\"prop\">" + objectBody(role: role)
        body += reference(uri: "#prop", digest: digest(Data(canonicalObject.utf8)),
                          transform: "http://www.w3.org/2006/12/xml-c14n11")
        body += "</SignedInfo>"
        return Parts(signedInfoBody: body)
    }

    public static func signature(role: Role, files: [(String, Data)], identity: Identity) throws -> Data {
        let parts = signedInfo(role: role, files: files)
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(identity.key, .rsaSignatureMessagePKCS1v15SHA512,
                                              Data(parts.canonicalSignedInfo.utf8) as CFData, &err) as Data? else {
            throw ADBKey.KeyError.signFailed(err.map { "\($0.takeRetainedValue())" } ?? "XML imzası")
        }
        var xml = "<Signature xmlns=\"\(dsig)\" Id=\"\(role.signatureID)\">"
        xml += parts.fileSignedInfo
        xml += "<SignatureValue>\(sig.base64EncodedString())</SignatureValue>"
        xml += "<KeyInfo><X509Data>"
        for c in identity.certificates { xml += "<X509Certificate>\(certificateText(c))</X509Certificate>" }
        xml += "</X509Data></KeyInfo>"
        xml += "<Object Id=\"prop\">" + objectBody(role: role)
        xml += "</Signature>"
        return Data(xml.utf8)
    }
}
