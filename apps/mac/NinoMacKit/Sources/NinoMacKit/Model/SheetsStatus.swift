// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Observation

// Sayfaların (Geçmiş, Hakkında, Sistem sağlığı, Sorun Bildir, Nino'ya Sor, oyun kartı) okuduğu ve
// uygulama açık kaldıkça süren durum. Sohbet ve Sorun Bildir taslağı burada durur: sayfa kapanıp
// açılınca kaybolmaz, uygulama kapanınca silinir (diske yazılmaz).

@MainActor
@Observable
public final class SheetsStatus {
    /// Sistem sağlığının ölçümleri (motor biriktirir; sayfa iki saniyede bir kopyasını okur).
    public var healthMetrics = HealthMetrics()
    /// Kayıtlı sorunlar, en yeni başta (`sorunlar.json`).
    public var problems: [ProblemRecord] = []
    /// Nino TV uygulamasının kurulum durumu.
    public var tvApp: TVAppHealth = .unknown
    /// Bu Mac'in değişmeyen bilgileri.
    public var deviceFacts = DeviceFacts(appVersion: "4.1.0", build: nil, model: "Mac", systemVersion: "macOS",
                                         processor: "Apple", memoryGB: 16)
    /// Günlük klasörü; "Ayrıntılar"daki günlük sonları buradan okunur. Yoksa "-".
    public var dataFolder: DataFolder?

    /// Bu PS5'te son oynanan oyun ve kurulu paketlerin oyunları (oyun kendiliğinden tanınır; elle seçim yok).
    public var lastPlayedGame: String?
    public var packGames: [String] = []

    public let chat = AssistantChat()
    public let report = ReportDraft()

    public init() {}
}

// MARK: - Nino'ya Sor sohbeti

@MainActor
@Observable
public final class AssistantChat {
    public enum Mode: Equatable, Sendable { case chat, report }

    public private(set) var messages: [AssistantMessage] = []
    public private(set) var waiting = false
    public var mode: Mode = .chat
    /// Yazma alanı ve ekler (taslak).
    public var draft = ""
    public var attachments: [PhotoAttachment] = []
    public var preparingPhotos = 0
    public var photoError = false

    private var task: Task<Void, Never>?
    private var generation = 0

    public init() {}

    public var hasMessages: Bool { !messages.isEmpty }

    public var canSend: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && !waiting && preparingPhotos == 0
    }

    public var canAddPhoto: Bool { attachments.count < PhotoAttachment.maxCount }

    public func addPhotos(_ photos: [PhotoAttachment]) {
        let room = PhotoAttachment.maxCount - attachments.count
        attachments.append(contentsOf: photos.prefix(max(0, room)))
    }

    public func removePhoto(_ id: UUID) { attachments.removeAll { $0.id == id } }

    /// Yazılanı (ya da öneri hapının metnini) gönderir.
    public func send(text: String? = nil,
                     using ask: @escaping @MainActor ([AssistantMessage]) async -> Result<AssistantReply, AssistantError>) {
        let body = text ?? draft
        let photos = text == nil ? attachments : []
        guard !waiting, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !photos.isEmpty else { return }
        if text == nil {
            draft = ""
            attachments = []
            photoError = false
        }
        removeLocalErrors()
        messages.append(AssistantMessage(role: .user, text: body, photos: photos))
        request(using: ask)
    }

    /// Gönderilemeyen son mesajı yeniden dener.
    public func retry(using ask: @escaping @MainActor ([AssistantMessage]) async -> Result<AssistantReply, AssistantError>) {
        guard !waiting, let index = messages.lastIndex(where: { $0.role == .user }),
              messages[index].failed?.retryable == true else { return }
        messages[index].failed = nil
        removeLocalErrors()
        request(using: ask)
    }

    /// Yeni sohbet: her şey silinir, bekleyen istek iptal edilir.
    public func reset() {
        task?.cancel()
        task = nil
        generation += 1
        messages = []
        waiting = false
        draft = ""
        attachments = []
        photoError = false
        mode = .chat
    }

    private func removeLocalErrors() { messages.removeAll { $0.localError != nil } }

    private func request(using ask: @escaping @MainActor ([AssistantMessage]) async -> Result<AssistantReply, AssistantError>) {
        waiting = true
        generation += 1
        let current = generation
        let snapshot = messages
        task = Task { @MainActor [weak self] in
            let result = await ask(snapshot)
            guard let self, self.generation == current, !Task.isCancelled else { return }
            self.waiting = false
            switch result {
            case .success(let reply):
                self.messages.append(AssistantMessage(role: .assistant, text: reply.text,
                                                      reportSent: reply.reportID != nil))
            case .failure(let error):
                if error.retryable, let index = self.messages.lastIndex(where: { $0.role == .user }) {
                    self.messages[index].failed = error
                }
                self.messages.append(AssistantMessage(role: .assistant, text: "", localError: error))
            }
        }
    }

    /// Testler için: bekleyen isteğin bitmesini bekler.
    public func waitForReply() async { await task?.value }
}

// MARK: - Sorun Bildir taslağı

@MainActor
@Observable
public final class ReportDraft {
    public enum Phase: Equatable, Sendable { case editing, sending, sent }

    public var description = "" { didSet { if description != oldValue { error = nil } } }
    /// Resim ve yazı dosyaları (en çok 5; ReportAttachments sınırları).
    public private(set) var attachments: [ReportAttachment] = []
    public var preparing = 0
    /// Son eklemede okunamayan ya da sınıra takılan dosya.
    public var attachError: ReportAttachments.Failure?
    public private(set) var phase: Phase = .editing
    public private(set) var error: ReportError?

    public init() {}

    public var canSend: Bool { phase == .editing && preparing == 0 }
    public var canAdd: Bool { attachments.count < ReportAttachments.maxFiles && phase == .editing }
    public var photos: [PhotoAttachment] { attachments.compactMap(\.photo) }
    public var textFiles: [ReportTextFile] { attachments.compactMap(\.textFile) }

    /// Hazırlanan ekleri ekler; sığmayan ya da okunamayan varsa `attachError`.
    public func add(_ new: [ReportAttachment], failed: Bool = false) {
        let merged = ReportAttachments.merge(attachments, new)
        attachments = merged.attachments
        attachError = merged.limited ? .limit : (failed ? .unreadable : nil)
        error = nil
    }

    public func remove(_ id: UUID) {
        attachments.removeAll { $0.id == id }
        attachError = nil
        error = nil
    }

    /// Gönderir. Başarılıysa 1,6 sn "Teşekkürler" gösterilir, sonra form sıfırlanır ve `onDone` çağrılır.
    public func send(build: () -> ProblemReport,
                     using deliver: @escaping @MainActor (ProblemReport) async -> Result<Void, ReportError>,
                     thanksDuration: Duration = .milliseconds(1600),
                     onDone: @escaping @MainActor () -> Void = {}) async {
        guard canSend else { return }
        error = nil
        phase = .sending
        let report = build()
        switch await deliver(report) {
        case .success:
            phase = .sent
            try? await Task.sleep(for: thanksDuration)
            reset()
            onDone()
        case .failure(let failure):
            error = failure
            phase = .editing
        }
    }

    public func reset() {
        description = ""
        attachments = []
        attachError = nil
        error = nil
        phase = .editing
    }
}

// MARK: - Motor eylemleri (varsayılanları hiçbir şey yapmaz ve ağa çıkmaz)

public extension AppEngine {
    func clearHistory() {}
    func askAssistant(_ chat: [AssistantMessage]) async -> Result<AssistantReply, AssistantError> { .failure(.noAddress) }
    func sendProblemReport(_ report: ProblemReport) async -> Result<Void, ReportError> { .failure(.offline) }
    func saveLogsZip(details: String) async throws -> URL { throw CocoaError(.featureUnsupported) }
}

// MARK: - AppState kısa yolları

public extension AppState {
    /// Geçmişi temizler (liste hemen, dosya motorda).
    func clearHistory() {
        history = []
        engine?.clearHistory()
    }

    func askAssistant(_ chat: [AssistantMessage]) async -> Result<AssistantReply, AssistantError> {
        guard let engine else { return .failure(.noAddress) }
        return await engine.askAssistant(chat)
    }

    func sendProblemReport(_ report: ProblemReport) async -> Result<Void, ReportError> {
        guard let engine else { return .failure(.offline) }
        return await engine.sendProblemReport(report)
    }
}
