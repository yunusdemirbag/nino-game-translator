// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation
import Observation

// Güncellemenin indirme ve kurma yanı (guncelleme-admin.md §2 "İndirme ve kurma").
// Sparkle uygulama hedefindedir (apps/mac/App); bu paket yalnız `AutoUpdater` sözleşmesini bilir.
// Böylece paket Sparkle'sız derlenir ve sınanır; App Store yapısına Sparkle hiç girmez.

/// Kendiliğinden güncelleyici (uygulamada Sparkle).
@MainActor
public protocol AutoUpdater: AnyObject {
    /// Güncelleyicinin bildirdikleri (ana iş parçacığında).
    var onEvent: ((AutoUpdaterEvent) -> Void)? { get set }
    /// Saatlik denetimi ve sessiz indirmeyi başlatır.
    func start()
    /// Hemen arka planda bakar (bulursa sorulmadan indirir).
    func checkInBackground()
    /// Güncelleyicinin kendi penceresi: indirir, imzayı doğrular, kurar, yeniden açar.
    func showUpdateWindow()
    /// İnmiş güncellemeyi hemen kurar ve uygulamayı yeniden açar. İnmiş güncelleme yoksa `false`.
    @discardableResult func installReadyUpdate() -> Bool
}

public enum AutoUpdaterEvent: Equatable, Sendable {
    /// Yeni sürüm bulundu, arka planda iniyor.
    case found(version: String)
    /// İndi ve kurulmaya hazır.
    case downloaded(version: String)
    case noUpdate
    case failed
}

/// Kurma zamanı kuralları (saf).
public enum UpdateInstallTiming {
    /// Çeviri durduktan sonra kurmadan önce beklenen süre.
    public static let afterStopDelay: TimeInterval = 2
    /// Bu sürede inmeyen güncelleme "iniyor" sayılmaz; düğme güncelleyicinin penceresini açar.
    public static let downloadTimeout: TimeInterval = 180
    /// "Yeniden açılınca sürdür" işaretinin geçerlilik süresi.
    public static let resumeWindow: TimeInterval = 120

    public enum Decision: Equatable, Sendable {
        /// Boşta: hemen kur ve yeniden aç.
        case installNow
        /// Çeviri sürüyor ya da kurulum sihirbazındayız: bekle.
        case wait
        /// Çeviri az önce durdu: bu kadar saniye sonra kur.
        case installAfter(TimeInterval)
    }

    /// Güncelleme hazırken (indi ya da durum değişti) ne yapılır.
    public static func decide(translation: TranslationPhase, setupComplete: Bool, translationJustStopped: Bool) -> Decision {
        guard translation == .off, setupComplete else { return .wait }
        return translationJustStopped ? .installAfter(afterStopDelay) : .installNow
    }

    public enum RestartPlan: Equatable, Sendable {
        /// Çeviri yok: hemen kur.
        case installNow
        /// Çeviri sürüyor: "sürdür" işareti yaz, oturumu düzgün kapat, sonra kur.
        case markResumeThenStopThenInstall
    }

    /// Kullanıcı "Yeniden başlat"a bastı (çeviri sürse bile hemen kurulur).
    public static func restart(translation: TranslationPhase) -> RestartPlan {
        translation == .off ? .installNow : .markResumeThenStopThenInstall
    }

    /// Açılışta "sürdür" işareti geçerli mi (120 sn'den yeni).
    public static func shouldResume(markedAt: TimeInterval, now: TimeInterval) -> Bool {
        let age = now - markedAt
        return age >= 0 && age <= resumeWindow
    }
}

/// `UpdateService`'in gerçeği: GitHub denetimi (şerit ve ayarlar) + kendiliğinden güncelleyici (indir, kur).
///
/// Güncelleyici yoksa (deneme yapısı, App Store) düğme tarayıcıda indirme sayfasını açar.
@MainActor
public final class UpdateCoordinator: UpdateService {
    public enum Phase: Equatable, Sendable {
        case none
        case downloading(version: String)
        case ready(version: String)
    }

    public let checker: UpdateService
    public let auto: AutoUpdater?
    public private(set) var phase: Phase = .none
    public var latest: ReleaseInfo? { checker.latest }

    private weak var state: AppState?
    private let stopTranslation: @MainActor () async -> Void
    private let markResume: @MainActor () -> Void
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var lastTranslation: TranslationPhase = .off
    private var downloadTimer: Task<Void, Never>?
    private var installTimer: Task<Void, Never>?
    private var restarting = false
    /// Testler: kurma isteklerinin sayısı.
    public private(set) var installRequests = 0

    public init(checker: UpdateService, auto: AutoUpdater?, state: AppState,
                stopTranslation: @escaping @MainActor () async -> Void,
                markResume: @escaping @MainActor () -> Void,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.checker = checker
        self.auto = auto
        self.state = state
        self.stopTranslation = stopTranslation
        self.markResume = markResume
        self.sleep = sleep
        lastTranslation = state.translation
        auto?.onEvent = { [weak self] e in self?.handle(e) }
        observe()
    }

    /// Güncelleyiciyi başlatır (yalnız yayın yapısında çağrılır).
    public func start() { auto?.start() }

    // MARK: UpdateService

    public func check(force: Bool) async -> UpdateCheckResult {
        // Güncelleyici iniyor ya da indirdi: o durum ekranda kalsın.
        if phase != .none { return .skipped }
        let result = await checker.check(force: force)
        if case .available = result, let auto { auto.checkInBackground() }
        return result
    }

    public func install() {
        guard let auto else {
            checker.install()
            return
        }
        switch phase {
        case .ready: restartNow()
        case .downloading: break
        case .none: auto.showUpdateWindow()
        }
    }

    // MARK: Güncelleyici olayları

    func handle(_ e: AutoUpdaterEvent) {
        switch e {
        case let .found(v):
            if case .ready = phase { return }
            phase = .downloading(version: v)
            state?.update = .downloading(version: v, progress: nil)
            downloadTimer?.cancel()
            let sleep = self.sleep
            downloadTimer = Task { [weak self] in
                await sleep(UpdateInstallTiming.downloadTimeout)
                guard !Task.isCancelled, let self, case .downloading = self.phase else { return }
                self.phase = .none
                self.state?.update = .available(version: v)
            }
        case let .downloaded(v):
            downloadTimer?.cancel()
            phase = .ready(version: v)
            evaluate(justStopped: false)
        case .noUpdate, .failed:
            if case .downloading(let v) = phase {
                downloadTimer?.cancel()
                phase = .none
                state?.update = .available(version: v)
            }
        }
    }

    // MARK: Kurma zamanı

    private func observe() {
        guard let state else { return }
        withObservationTracking {
            _ = state.translation
            _ = state.setupStep
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stateChanged()
                self.observe()
            }
        }
    }

    private func stateChanged() {
        guard let state else { return }
        let stopped = lastTranslation != .off && state.translation == .off
        lastTranslation = state.translation
        if case .ready = phase { evaluate(justStopped: stopped) }
    }

    private func evaluate(justStopped: Bool) {
        guard case let .ready(v) = phase, let state, !restarting else { return }
        installTimer?.cancel()
        switch UpdateInstallTiming.decide(translation: state.translation, setupComplete: state.isSetupComplete,
                                          translationJustStopped: justStopped) {
        case .installNow:
            state.update = .readyToInstall(version: v)
            requestInstall()
        case .wait:
            state.update = state.translation == .off ? .readyToInstall(version: v) : .waitingForTranslationToStop(version: v)
        case let .installAfter(seconds):
            state.update = .readyToInstall(version: v)
            let sleep = self.sleep
            installTimer = Task { [weak self] in
                await sleep(seconds)
                guard !Task.isCancelled, let self, let state = self.state else { return }
                // Bu arada çeviri yeniden başladıysa bekle.
                if UpdateInstallTiming.decide(translation: state.translation, setupComplete: state.isSetupComplete,
                                              translationJustStopped: false) == .installNow {
                    self.requestInstall()
                }
            }
        }
    }

    /// "Yeniden başlat": çeviri sürse bile hemen kurar; çeviri sürüyorsa yeniden açılınca sürer.
    private func restartNow() {
        guard let state, !restarting else { return }
        installTimer?.cancel()
        switch UpdateInstallTiming.restart(translation: state.translation) {
        case .installNow:
            requestInstall()
        case .markResumeThenStopThenInstall:
            restarting = true
            markResume()
            let stop = stopTranslation
            Task { [weak self] in
                await stop()
                self?.requestInstall()
                self?.restarting = false
            }
        }
    }

    private func requestInstall() {
        installRequests += 1
        if auto?.installReadyUpdate() != true, let auto {
            // İnmiş güncelleme kaybolduysa güncelleyicinin penceresi.
            phase = .none
            auto.showUpdateWindow()
        }
    }
}
