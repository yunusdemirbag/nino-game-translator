// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Ağa ve PS5'e dokunmayan sahte motor. Önizlemeler, ekran görüntüsü testleri ve
/// ekran geliştirme için: eylemler durumu hemen beklenen sonuca götürür.
@MainActor
public final class PreviewEngine: AppEngine {
    public private(set) weak var state: AppState?
    public private(set) var calls: [String] = []

    public init(state: AppState) {
        self.state = state
        state.attach(self)
    }

    public func settingsChanged(from old: MacSettings, to new: MacSettings) { calls.append("settings") }

    public func startTranslation() {
        calls.append("start")
        guard let state else { return }
        state.translation = .on
        if case .ps5 = state.source { state.source = .ps5(.streaming) }
        state.connectedDisplays = max(1, state.connectedDisplays)
    }

    public func stopTranslation() {
        calls.append("stop")
        guard let state else { return }
        state.translation = .off
        if case .ps5 = state.source { state.source = .ps5(.idle) }
    }

    public func checkForUpdates() { calls.append("checkUpdates"); state?.update = .upToDate }
    public func installUpdate() { calls.append("installUpdate") }
    public func refreshDownloadTotal() { calls.append("downloads") }

    // MARK: Kurulum (sahte karşılıklar; hepsi hemen beklenen sonuca gider)

    public func setupFinished() { calls.append("setupFinished") }

    public func beginPSNSignIn() {
        calls.append("psnSignIn")
        state?.psnAccount = .signedIn(accountID: Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
    }

    public func enterPSNAccountID(_ text: String) -> Bool {
        calls.append("psnManual")
        guard let id = PSNAuth.manualAccountID(text) else { return false }
        state?.psnAccount = .signedIn(accountID: id)
        return true
    }

    public func signOutPSN() { calls.append("psnSignOut"); state?.psnAccount = .signedOut }

    public func searchConsoles() {
        calls.append("searchConsoles")
        state?.setup.consoleSearch = .finished
        state?.setup.foundConsoles = [SetupConsole(name: "PS5-123", address: "192.168.0.20")]
    }

    public func pairConsole(address: String, code: String) {
        calls.append("pairConsole")
        guard let state else { return }
        guard ConsoleInput.pairingCode(code) != nil else {
            state.pairing = .failed(message: ConsoleText.string("console.pair.error.badCode"))
            return
        }
        let name = state.setup.foundConsoles.first { $0.address == address }?.name ?? "PS5"
        state.pairedConsole = PairedConsole(name: name, host: address)
        state.pairing = .paired
    }

    public func revealRemotePlayLog() { calls.append("revealLog") }
    public func refreshRemotePlayApps() { calls.append("remotePlayApps") }

    public func searchTVs() {
        calls.append("searchTVs")
        state?.setup.tvSearch = .finished
        state?.setup.foundTVs = [DiscoveredTV(name: "LG OLED55", host: "192.168.0.31", brand: .lg)]
    }

    public func pairTV(_ tv: DiscoveredTV) {
        calls.append("pairTV")
        guard let state else { return }
        state.pairedTV = PairedTV(name: tv.name, host: tv.host, brand: tv.brand, hasKey: true)
        state.setup.tvConnect = .idle
        if state.settings.output == .computer { state.settings.output = .tv }
        state.setup.tvApp = .ready(version: "4.1.0", lgHoursLeft: tv.brand == .lg ? 980 : nil)
    }

    public func recheckTVApp() { calls.append("recheckTVApp") }
    public func installTVApp(passphrase: String?) {
        calls.append("installTVApp")
        state?.setup.tvApp = .ready(version: "4.1.0", lgHoursLeft: 999)
    }
    public func samsungTryAnyway() { calls.append("samsungTryAnyway") }
    public func samsungTypeDeveloperCode() { calls.append("samsungTypeCode") }
    public func reopenSamsungSignIn() { calls.append("samsungSignIn") }

    public func sendTestSubtitle() {
        calls.append("testSubtitle")
        state?.setup.test = .sent
    }

    public func saveGeminiKey(_ key: String) {
        calls.append("geminiKey")
        guard let state else { return }
        state.setup.geminiKeySaved = true
        state.setup.geminiTest = .idle
        state.setup.geminiSample = "Buraya gel, hemen."
        state.settings.onlineTranslation = true
        state.settings.onlineEngine = .gemini
    }

    public func installGreenlight() {
        calls.append("installGreenlight")
        state?.setup.xbox.greenlightInstalled = true
    }
    public func openGreenlight() { calls.append("openGreenlight") }
    public func setXboxPolling(_ on: Bool) { calls.append(on ? "xboxPoll" : "xboxPollStop") }
    public func setCaptureCardPreview(_ on: Bool) { calls.append(on ? "cardPreview" : "cardPreviewStop") }
    public func selectCaptureDevice(_ id: String?) { calls.append("cardDevice") }

    // MARK: Sayfalar (ağa çıkmaz)

    /// Nino'ya Sor'un sahte cevabı.
    public var assistantResult: Result<AssistantReply, AssistantError> = .success(AssistantReply(
        text: "1. PS5'te şu yolu açın: Ayarlar › Sistem › Uzaktan Oynatma.\n2. TV'de Nino'yu başlatın.", reportID: nil))
    /// Sorun Bildir'in sahte sonucu.
    public var reportResult: Result<Void, ReportError> = .success(())
    public private(set) var sentReports: [ProblemReport] = []

    public func clearHistory() { calls.append("clearHistory") }
    public func askAssistant(_ chat: [AssistantMessage]) async -> Result<AssistantReply, AssistantError> {
        calls.append("assistant")
        return assistantResult
    }
    public func sendProblemReport(_ report: ProblemReport) async -> Result<Void, ReportError> {
        calls.append("report")
        sentReports.append(report)
        return reportResult
    }
    public func saveLogsZip(details: String) async throws -> URL {
        calls.append("logsZip")
        return FileManager.default.temporaryDirectory.appendingPathComponent("Nino-kayitlar-onizleme.zip")
    }

    /// Kurulumu bitmiş, PS5 ve TV eşli, çeviri kapalı bir örnek durum.
    public static func sampleState() -> AppState {
        var settings = MacSettings()
        settings.targetLanguage = "tr"
        let state = AppState(settings: settings)
        state.setupStep = .done
        state.psnAccount = .signedIn(accountID: Data(repeating: 1, count: 8))
        state.pairedConsole = PairedConsole(name: "PS5-123", host: "192.168.0.20")
        state.pairedTV = PairedTV(name: "Salon TV", host: "192.168.0.110", brand: .androidTV, hasKey: true)
        state.downloadTotal = 7028
        state.lastLine = LiveLine(translated: "Buraya gel, hemen.", source: "Come here, now.", origin: .pack, latencyMs: 180)
        return state
    }
}
