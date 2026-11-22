// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

// Nino'ya Sor: sohbet mesajları ve sunucu sözleşmesi (ninoya-sor.md §3–4).

public struct AssistantMessage: Equatable, Sendable, Identifiable {
    public enum Role: String, Sendable { case user, assistant }

    public var id: UUID
    public var role: Role
    public var text: String
    public var photos: [PhotoAttachment]
    /// Kullanıcı mesajı gönderilemedi (soluk görünür, "Tekrar Dene").
    public var failed: AssistantError?
    /// Robotun yerel hata balonu (sunucuya gitmez).
    public var localError: AssistantError?
    /// Robot cevabıyla ekibe bildirim açtı ("Bildirim gönderildi").
    public var reportSent: Bool

    public init(id: UUID = UUID(), role: Role, text: String, photos: [PhotoAttachment] = [],
                failed: AssistantError? = nil, localError: AssistantError? = nil, reportSent: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.photos = photos
        self.failed = failed
        self.localError = localError
        self.reportSent = reportSent
    }
}

public enum AssistantError: String, Error, Equatable, Sendable {
    case disabled, dailyLimit, busy, tooLarge, rejected, serverError, offline, noAddress

    /// Kullanıcı mesajının altında "Tekrar Dene" çıkar mı.
    public var retryable: Bool {
        switch self {
        case .busy, .serverError, .offline, .noAddress: return true
        case .disabled, .dailyLimit, .tooLarge, .rejected: return false
        }
    }

    /// Balonun altında "Sorun Bildir" düğmesi var mı.
    public var offersReport: Bool { self == .disabled || self == .dailyLimit }
}

public struct AssistantReply: Equatable, Sendable {
    public var text: String
    public var reportID: String?
}

/// İstek bağlamı: her mesajda yeniden toplanır (TV sonradan bağlanmış olabilir).
public struct AssistantContext: Equatable, Sendable {
    public var install: String
    public var app: String
    public var language: String
    public var device: String

    public init(install: String, app: String, language: String, device: String) {
        self.install = install
        self.app = app
        self.language = language
        self.device = device
    }
}

public enum AssistantContract {
    public static let maxMessages = 24
    public static let maxTextUnits = 2000
    public static let maxPhotosPerMessage = 3
    public static let photoMessagesKept = 2
    public static let maxBodyBytes = 6 << 20  // 6 MB
    public static let timeout: TimeInterval = 90
    static let screenshotMark = "[screenshot]"

    /// Metni kırpar ve UTF-16 birimiyle en çok `limit` yapar; karakterin ortasından kesmez.
    public static func clip(_ text: String, limit: Int = maxTextUnits) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count > limit else { return trimmed }
        var out = ""
        var units = 0
        for character in trimmed {
            let n = String(character).utf16.count
            if units + n > limit { break }
            out.append(character)
            units += n
        }
        return out
    }

    struct Prepared {
        var role: AssistantMessage.Role
        var text: String
        var photos: [PhotoAttachment]
    }

    /// Sohbetten gönderilecek mesajlar. Kurallara uymuyorsa `.rejected`.
    static func prepare(_ chat: [AssistantMessage]) throws -> [Prepared] {
        var list: [Prepared] = chat.compactMap { m in
            guard m.localError == nil, m.failed == nil else { return nil }
            let text = clip(m.text)
            let photos = m.role == .user ? Array(m.photos.prefix(maxPhotosPerMessage)) : []
            if text.isEmpty, photos.isEmpty { return nil }
            return Prepared(role: m.role, text: text, photos: photos)
        }
        if list.count > maxMessages { list.removeFirst(list.count - maxMessages) }
        if list.first?.role == .assistant { list.removeFirst() }
        // Fotoğraflar yalnız fotoğraflı son iki kullanıcı mesajında gider.
        var kept = 0
        for index in list.indices.reversed() where !list[index].photos.isEmpty {
            if kept < photoMessagesKept {
                kept += 1
            } else {
                dropPhotos(&list[index])
            }
        }
        guard let last = list.last, last.role == .user, !(last.text.isEmpty && last.photos.isEmpty) else {
            throw AssistantError.rejected
        }
        return list
    }

    static func dropPhotos(_ message: inout Prepared) {
        message.photos = []
        message.text = message.text.isEmpty ? screenshotMark : screenshotMark + " " + message.text
    }

    static func object(_ messages: [Prepared], context: AssistantContext) -> [String: Any] {
        var body: [String: Any] = [
            "v": 1, "install": context.install, "app": context.app, "platform": "mac",
            "language": context.language,
            "messages": messages.map { m -> [String: Any] in
                var item: [String: Any] = ["role": m.role.rawValue, "text": m.text]
                if !m.photos.isEmpty { item["images"] = m.photos.map(\.json) }
                return item
            },
        ]
        if !context.device.isEmpty { body["device"] = context.device }
        return body
    }

    /// İstek gövdesi. 6 MB'yi geçerse yalnız en son fotoğraflı mesajın fotoğrafları kalır; yine sığmazsa `.tooLarge`.
    public static func body(for chat: [AssistantMessage], context: AssistantContext) throws -> Data {
        var messages = try prepare(chat)
        var data = try ContractJSON.encode(object(messages, context: context))
        if data.count > maxBodyBytes {
            var keptLatest = false
            for index in messages.indices.reversed() where !messages[index].photos.isEmpty {
                if keptLatest { dropPhotos(&messages[index]) } else { keptLatest = true }
            }
            data = try ContractJSON.encode(object(messages, context: context))
            if data.count > maxBodyBytes { throw AssistantError.tooLarge }
        }
        return data
    }

    /// Cevap ve durum kodu eşlemesi (§4 "Cevap").
    public static func interpret(status: Int, data: Data) -> Result<AssistantReply, AssistantError> {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        switch status {
        case 200..<300:
            guard json?["ok"] as? Bool == true,
                  let reply = (json?["reply"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reply.isEmpty else { return .failure(.serverError) }
            let report = (json?["report"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .success(AssistantReply(text: reply, reportID: report))
        case 400: return .failure(.rejected)
        case 413: return .failure(.tooLarge)
        case 429: return .failure(json?["error"] as? String == "busy" ? .busy : .dailyLimit)
        case 503: return .failure(json?["error"] as? String == "assistant_disabled" ? .disabled : .busy)
        default: return .failure(.serverError)
        }
    }
}

/// `POST v1/assistant` istemcisi. Ağ `NetworkClient` arkasındadır.
public struct AssistantClient: Sendable {
    public var network: NetworkClient
    public var baseURL: URL?
    public var appVersion: String

    public init(network: NetworkClient, baseURL: URL?, appVersion: String) {
        self.network = network
        self.baseURL = baseURL
        self.appVersion = appVersion
    }

    public func ask(_ chat: [AssistantMessage], context: AssistantContext) async -> Result<AssistantReply, AssistantError> {
        guard let baseURL else { return .failure(.noAddress) }
        let body: Data
        do {
            body = try AssistantContract.body(for: chat, context: context)
        } catch let error as AssistantError {
            return .failure(error)
        } catch {
            return .failure(.rejected)
        }
        var request = URLRequest(url: PoolServer.endpoint(baseURL, "v1/assistant"),
                                 timeoutInterval: AssistantContract.timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("nino-assistant/1 (mac; \(appVersion))", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await network.send(request)
            return AssistantContract.interpret(status: response.statusCode, data: data)
        } catch {
            return .failure(.offline)
        }
    }
}
