// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore

// Kurulum, Ayarlar ve sayfaların eylemleri. İş mantığı olan servisler (Console/, TVSetup/, Services/) bağlanır;
// olmayanlar açık TODO olarak varsayılan (hiçbir şey yapmayan) karşılıkta kalır.
extension LiveEngine {
    // MARK: Kurulum

    public func setupFinished() {
        try? records.setSetupComplete(true)
    }

    public var psnLoginController: PSNLoginController? { psnLogin }

    public func beginPSNSignIn() {
        let c = psnLogin
        c.onFinish = { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(id): self.state.psnAccount = .signedIn(accountID: id)
            case let .failure(e): self.state.psnAccount = .failed(message: "\(e)")
            }
        }
        state.psnAccount = .signingIn
        c.begin()
    }

    public func enterPSNAccountID(_ text: String) -> Bool {
        guard let id = PSNAuth.manualAccountID(text), (try? records.setAccountID(id)) != nil else { return false }
        state.psnAccount = .signedIn(accountID: id)
        return true
    }

    public func signOutPSN() {
        try? records.signOutPSN()
        state.psnAccount = .signedOut
    }

    public func searchConsoles() {
        let pairer = ConsolePairer.live(store: consoleStore, log: consoleLogForActions)
        state.setup.consoleSearch = .searching
        Task {
            let found = await pairer.search()
            self.lastFoundConsoles = found
            self.state.setup.foundConsoles = found.map { SetupConsole(name: $0.name, address: $0.address) }
            self.state.setup.consoleSearch = .finished
        }
    }

    public func pairConsole(address: String, code: String) {
        let pairer = ConsolePairer.live(store: consoleStore, log: consoleLogForActions)
        let account = try? records.accountID()
        let known = lastFoundConsoles.first { $0.address == address }
        state.pairing = .pairing
        Task {
            do {
                let p = try await pairer.pair(address: address, code: code, accountID: account, console: known)
                self.state.pairedConsole = PairedConsole(name: p.name, host: p.host)
                self.state.pairing = .paired
            } catch let e as PairingError {
                self.state.pairing = .failed(message: e.message(logPath: self.env.folder.remotePlayLog.path))
            } catch {
                self.state.pairing = .failed(message: "\(error)")
            }
        }
    }

    public func revealRemotePlayLog() {
        NSWorkspace.shared.activateFileViewerSelecting([env.folder.remotePlayLog])
    }

    public func refreshRemotePlayApps() { capture.refreshRemotePlayApps() }

    // MARK: Xbox ve yakalama kartı (Capture/CaptureCoordinator)

    public func installGreenlight() { capture.installGreenlight() }
    public func openGreenlight() { capture.openGreenlight() }
    public func setXboxPolling(_ on: Bool) { capture.setXboxPolling(on) }
    public func setCaptureCardPreview(_ on: Bool) { capture.setCardPreview(on) }
    public func selectCaptureDevice(_ id: String?) { capture.selectCaptureDevice(id) }

    // MARK: TV (TVSetupController)

    public func searchTVs() { tvSetup?.searchTVs() }
    public func pairTV(_ tv: DiscoveredTV) { tvSetup?.pairTV(tv) }
    public func recheckTVApp() { tvSetup?.recheckTVApp() }
    public func recheckTVAppNow() { tvSetup?.recheckTVApp(force: true) }
    public func upgradeLegacyTVApp() { tvSetup?.upgradeLegacyTVApp() }
    public func installTVApp(passphrase: String?) { tvSetup?.installTVApp(passphrase: passphrase) }
    public func samsungTryAnyway() { tvSetup?.samsungTryAnyway() }
    public func samsungTypeDeveloperCode() { tvSetup?.samsungTypeDeveloperCode() }
    public func reopenSamsungSignIn() { tvSetup?.reopenSamsungSignIn() }
    /// Deneme altyazısı. Görünüm hub'a hemen ve sırayla gider (bekleyen deneme sonradan eski boyu yollamasın diye
    /// denemenin kendisi görünüm taşımaz; TV bağlanınca hub son görünümü önce yollar).
    public func sendTestSubtitle() {
        pushStyle(state.settings.style)
        tvSetup?.sendTestSubtitle(style: nil)
    }

    // MARK: Çeviri anahtarları

    public func saveGeminiKey(_ key: String) { saveTranslationKey(key, for: .gemini) }

    /// Anahtar önce örnek satırla denenir (ceviri.md §2.1): geçerli, kotası bitmiş ya da modeli reddedilmiş anahtar
    /// kaydedilir; geçersiz ya da ulaşılamayan kaydedilmez. Sonuç Ayarlar'daki deneme satırına ve kurulumun Gemini
    /// adımına yazılır.
    public func saveTranslationKey(_ key: String, for engine: MacSettings.OnlineEngine) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || engine == .local else { return }
        state.settingsStatus.engineTests[engine] = .testing
        if engine == .gemini { state.setup.geminiTest = .testing }
        let settings = state.settings
        Task {
            let (result, sample) = await self.checkKey(trimmed, engine: engine, settings: settings)
            let test: EngineTest = result == .valid ? .works(sample: sample ?? "") : Self.engineTest(result, local: engine == .local)
            self.state.settingsStatus.engineTests[engine] = test
            if engine == .gemini {
                if result.shouldSave {
                    self.state.setup.geminiTest = .idle
                    self.state.setup.geminiSample = sample
                } else if case let .failed(failure) = test {
                    let message = SettingsEngineText.failure(failure, engine: engine, settings: settings,
                                                             locale: Locale(identifier: settings.targetLanguage == "tr" ? "tr" : "en"))
                    self.state.setup.geminiTest = .failed(message: message)
                }
            }
            if engine == .deepl {
                // DeepL bölümü sonucu kullanım satırında gösterir.
                switch result {
                case .invalidKey: self.state.settingsStatus.deepLUsage = .badKey
                case .quotaExhausted: self.state.settingsStatus.deepLUsage = .limitReached
                case .unreachable, .modelRejected: self.state.settingsStatus.deepLUsage = result.shouldSave ? nil : .unreachable
                case .valid: self.state.settingsStatus.deepLUsage = nil
                }
            }
            guard result.shouldSave else {
                self.notes.append("anahtar kaydedilmedi: \(result.rawValue)")
                return
            }
            self.storeTranslationKey(trimmed, for: engine)
            if engine == .deepl, result == .valid { self.refreshDeepLUsage() }
        }
    }

    func storeTranslationKey(_ key: String, for engine: MacSettings.OnlineEngine) {
        guard (try? records.setTranslationKey(key, for: engine)) != nil else { return }
        let saved = ((try? records.translationKey(engine)) ?? nil) != nil
        if saved { state.settingsStatus.savedKeys.insert(engine) } else { state.settingsStatus.savedKeys.remove(engine) }
        if engine == .gemini { state.setup.geminiKeySaved = saved }
        guard saved else { return }
        // Kaydedilince o motor seçilir; zaten seçiliyse zincir yeni anahtarla yeniden kurulur.
        if state.settings.onlineEngine == engine, state.settings.onlineTranslation {
            if state.isTranslating { rebuildTranslatorNow() }
        } else {
            state.settings.onlineEngine = engine
            state.settings.onlineTranslation = true
        }
    }

    public func removeTranslationKey(for engine: MacSettings.OnlineEngine) {
        try? records.setTranslationKey(nil, for: engine)
        state.settingsStatus.savedKeys.remove(engine)
        if engine == .gemini { state.setup.geminiKeySaved = false }
        if state.settings.onlineEngine == engine, engine != .local, state.settings.onlineTranslation {
            state.settings.onlineTranslation = false
        } else if state.isTranslating {
            rebuildTranslatorNow()
        }
    }

    // MARK: PS5 giriş şifresi

    public func savePS5Passcode(_ code: String) {
        guard let clean = ConsoleInput.loginPasscode(code) else { return }
        try? records.setLoginPasscode(clean)
        state.settingsStatus.passcodeSaved = true
    }

    public func removePS5Passcode() {
        try? records.setLoginPasscode(nil)
        state.settingsStatus.passcodeSaved = false
    }

    // MARK: Sıfırlama

    public func resetEverything() {
        stopTranslation()
        try? records.resetEverything()
        state.psnAccount = .signedOut
        state.pairedConsole = nil
        state.pairedTV = nil
        state.pairing = .idle
        state.tvInstall = .idle
        state.settingsStatus.passcodeSaved = false
        state.setupStep = .welcome
    }

    public func resetFromTV() {
        stopTranslation()
        try? records.changeTV()
        state.pairedTV = nil
        state.tvInstall = .idle
        state.setup.tvApp = .none
        state.setupStep = .tv
    }

    // MARK: Sayfalar

    public func clearHistory() {
        history.clear()
        state.history = []
    }
}
