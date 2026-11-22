// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore

// Güncelleme, indirme sayacı, Nino'ya Sor, sorun bildirimi, günlük dışa aktarma ve Ayarlar'daki motor denemeleri.
// Ağ `env.network` ile gelir; testlerde nil (hiçbir istek gitmez).
extension LiveEngine {
    var installID: String {
        let translations = env.folder.translationsFolder.appendingPathComponent("install")
        if FileManager.default.fileExists(atPath: translations.path) { return InstallID.load(at: translations) }
        let known = InstallIdentity.read(folder: env.folder)
        return known.isEmpty ? InstallID.load(at: translations) : known
    }

    // MARK: Güncelleme

    public func checkForUpdates() { runUpdateCheck(force: false) }
    public func forceCheckForUpdates() { runUpdateCheck(force: true) }

    private func runUpdateCheck(force: Bool) {
        guard let updater else { return }
        let previous = state.update
        state.update = .checking
        Task {
            let result = await updater.check(force: force)
            self.state.update = UpdateStatus.from(result, previous: previous)
        }
    }

    /// Kurma zamanı `UpdateCoordinator`'da (AppSupport/): hazırsa çeviri sürse bile hemen kurar, çeviri yeniden
    /// açılınca sürer; iniyorsa bir şey yapmaz; inemediyse güncelleyicinin penceresi.
    public func installUpdate() {
        updater?.install()
    }

    public func openReleaseNotes() {
        NSWorkspace.shared.open(updater?.latest?.notesURL ?? GitHubUpdateChecker.releasesPage)
    }

    public func refreshDownloadTotal() {
        guard let counter = downloadCounter else { return }
        Task { if let n = await counter.refresh() { self.state.downloadTotal = n } }
    }

    // MARK: Sayfalar

    public func askAssistant(_ chat: [AssistantMessage]) async -> Result<AssistantReply, AssistantError> {
        guard let network = env.network else { return .failure(.noAddress) }
        let client = AssistantClient(network: network, baseURL: env.poolBaseURL, appVersion: env.appVersion)
        let context = AssistantContext(install: installID, app: env.appVersion, language: state.settings.targetLanguage,
                                       device: state.sheetsStatus.deviceFacts.model)
        return await client.ask(chat, context: context)
    }

    public func sendProblemReport(_ report: ProblemReport) async -> Result<Void, ReportError> {
        guard let network = env.network else { return .failure(.offline) }
        let client = ReportClient(network: network, baseURL: env.poolBaseURL, appVersion: env.appVersion)
        // Kayıtlı API anahtarları kullanıcının eklediği dosyalarda ya da yazısında geçse bile gitmez.
        let secrets = MacSettings.OnlineEngine.allCases.compactMap { (try? records.translationKey($0)) ?? nil }
        return await client.send(report.redacting(secrets), context: ReportContext(install: installID, app: env.appVersion,
                                                                 language: state.settings.targetLanguage))
    }

    public func saveLogsZip(details: String) async throws -> URL {
        subtitleLog.flush()
        remotePlayLog.flush()
        let exporter = LogExporter.live(folder: env.folder)
        return try await Task.detached { try exporter.export(details: details) }.value
    }

    // MARK: Ayarlar: motor denemeleri

    public func testTranslationEngine(_ engine: MacSettings.OnlineEngine) {
        let s = state.settings
        state.settingsStatus.engineTests[engine] = .testing
        let key = ((try? records.translationKey(engine)) ?? nil) ?? ""
        Task {
            let (result, sample) = await self.checkKey(key, engine: engine, settings: s)
            self.state.settingsStatus.engineTests[engine] = result == .valid
                ? .works(sample: sample ?? "") : Self.engineTest(result, local: engine == .local)
        }
    }

    /// Örnek satır denemesi (`KeyCheck.sampleLine`: etiket çevrilmez, cümle çevrilir); sonuç ve örnek çeviri.
    func checkKey(_ key: String, engine: MacSettings.OnlineEngine, settings s: MacSettings) async -> (KeyCheckResult, String?) {
        if let custom = env.keyCheck { return await custom(engine, key) }
        let transport = env.providerTransport
        do {
            let out: [String]
            if engine == .deepl {
                out = try await DeepLProvider(apiKey: key, transport: transport)
                    .translate(sentences: [KeyCheck.sampleSentence], context: [], target: s.targetLanguage, probe: true)
            } else if let service = TranslatorFactory.service(engine) {
                let model = service == .local ? AIModel(id: LocalModelServer.modelName(s.localAIModel))
                    : (ModelCatalog.builtin.resolve(service, saved: TranslatorFactory.savedModel(engine, s)) ?? AIModel(id: ""))
                let config = KeyCheck.probeConfig(AIProviderConfig(
                    service: service, model: model, apiKey: key,
                    localBaseURL: service == .local ? LocalModelServer.normalize(s.localAIBaseURL) : nil))
                out = try await AIProvider(config: config, transport: transport)
                    .translate(sentences: [KeyCheck.sampleSentence], context: [], game: nil, target: s.targetLanguage, probe: true)
            } else {
                return (.unreachable, nil)
            }
            let label = String(KeyCheck.sampleLine.prefix { $0 != " " })
            return (.valid, out.first.map { "\(label) \($0)" })
        } catch {
            return (KeyCheck.result(for: error), nil)
        }
    }

    static func engineTest(_ r: KeyCheckResult, local: Bool) -> EngineTest {
        switch r {
        case .valid: return .works(sample: "")
        case .quotaExhausted: return .failed(local ? .localBusy : .quota)
        case .modelRejected: return .failed(local ? .localModelMissing : .modelRejected)
        case .invalidKey: return .failed(local ? .localBadKey : .badKey)
        case .unreachable: return .failed(local ? .localUnreachable : .unreachable)
        }
    }

    public func refreshDeepLUsage() {
        guard let key = (try? records.translationKey(.deepl)) ?? nil else { return }
        state.settingsStatus.deepLUsage = .checking
        let provider = DeepLProvider(apiKey: key, transport: env.providerTransport)
        Task {
            do {
                let u = try await provider.usage()
                self.state.settingsStatus.deepLUsage = u.exhausted
                    ? .limitReached : .used(characters: u.characterCount, limit: u.characterLimit)
            } catch ProviderFailure.invalidKey {
                self.state.settingsStatus.deepLUsage = .badKey
            } catch ProviderFailure.quotaExhausted {
                self.state.settingsStatus.deepLUsage = .limitReached
            } catch {
                self.state.settingsStatus.deepLUsage = .unreachable
            }
        }
    }

    public func checkOllama() {
        guard let base = LocalModelServer.normalize(state.settings.localAIBaseURL) else {
            state.settingsStatus.ollama = .notRunning
            return
        }
        state.settingsStatus.ollama = .checking
        let transport = env.providerTransport
        Task {
            if let models = try? await LocalModelServer.installedModels(base: base, transport: transport) {
                self.state.settingsStatus.installedLocalModels = models
                self.state.settingsStatus.ollama = .running
            } else {
                self.state.settingsStatus.ollama = .notRunning
            }
        }
    }

    public func downloadLocalModel(_ model: String) {
        guard let base = LocalModelServer.normalize(state.settings.localAIBaseURL) else { return }
        state.settingsStatus.localDownload = LocalModelDownload(model: model, progress: 0)
        state.settingsStatus.localDownloadFailed = false
        let request = LocalModelServer.pullRequest(base: base, model: model)
        Task {
            var progress = LocalModelServer.PullProgress()
            var ok = false
            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    switch progress.feed(line) {
                    case let .running(p): self.state.settingsStatus.localDownload = LocalModelDownload(model: model, progress: p)
                    case .done: ok = true
                    case .failed: ok = false
                    }
                }
            } catch { ok = false }
            self.state.settingsStatus.localDownload = nil
            self.state.settingsStatus.localDownloadFailed = !ok
            if ok { self.checkOllama() }
        }
    }

    // MARK: Paket içe aktarma

    public func prepareGamePackImport(_ url: URL) {
        // TODO: kullanıcı dosyasından paket (.json/.txt/.srt) içe aktarma; NinoCore'da henüz yok (kutuphane.md "Henüz yok").
        state.settingsStatus.packError = .badFormat
    }

    public func installGamePack(title: String, replacing: Bool) {
        // TODO: içe aktarma hazır olunca.
    }

    public func cancelGamePackImport() {
        state.settingsStatus.packImport = nil
        state.settingsStatus.packError = nil
    }
}
