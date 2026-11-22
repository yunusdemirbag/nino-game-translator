// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Carbon.HIToolbox
import Foundation
import Observation

// Genel kısayollar (guncelleme-admin.md §5). Pencere arkadayken de çalışır; Erişilebilirlik izni istemez
// (sistemin eski kısayol kayıt yolu). Yalnız gerektiğinde tutulur: çeviri kapalıyken tuşlar öteki uygulamalarda
// olağan işini görür.

public enum GlobalHotKey: String, CaseIterable, Sendable {
    /// ⌥⌘T: ekranı çevir.
    case translateScreen
    /// ⌥⌘L: altyazı penceresinde tıklamalar geçsin.
    case clickThrough

    /// Carbon tuş kodu.
    public var keyCode: UInt32 {
        switch self {
        case .translateScreen: return UInt32(kVK_ANSI_T)
        case .clickThrough: return UInt32(kVK_ANSI_L)
        }
    }

    /// ⌥⌘.
    public var modifiers: UInt32 { UInt32(optionKey | cmdKey) }

    var carbonID: UInt32 {
        switch self {
        case .translateScreen: return 1
        case .clickThrough: return 2
        }
    }
}

/// Hangi kısayolun tutulacağı (saf).
public enum HotKeyRules {
    public static func wanted(translation: TranslationPhase, subtitlesOnComputer: Bool) -> Set<GlobalHotKey> {
        guard translation == .on else { return [] }
        var keys: Set<GlobalHotKey> = [.translateScreen]
        if subtitlesOnComputer { keys.insert(.clickThrough) }
        return keys
    }

    /// Tutulanlardan istenene geçmek için bırakılacaklar ve alınacaklar.
    public static func diff(held: Set<GlobalHotKey>, wanted: Set<GlobalHotKey>) -> (release: Set<GlobalHotKey>, register: Set<GlobalHotKey>) {
        (held.subtracting(wanted), wanted.subtracting(held))
    }
}

/// Carbon kısayol kaydı. Başka bir uygulama aynı tuşu tutuyorsa sessizce atlanır.
@MainActor
final class CarbonHotKeyCenter {
    static let shared = CarbonHotKeyCenter()
    private static let signature: OSType = 0x4E_49_4E_4F // "NINO"

    private var refs: [UInt32: EventHotKeyRef] = [:]
    fileprivate var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    /// Kaydedildiyse `true`.
    func register(_ key: GlobalHotKey, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        guard refs[key.carbonID] == nil else { return true }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: key.carbonID)
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[key.carbonID] = ref
        actions[key.carbonID] = action
        return true
    }

    func unregister(_ key: GlobalHotKey) {
        if let ref = refs.removeValue(forKey: key.carbonID) { UnregisterEventHotKey(ref) }
        actions[key.carbonID] = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == CarbonHotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let keyID = id.id
            // Carbon olayları ana iş parçacığında gelir.
            MainActor.assumeIsolated { CarbonHotKeyCenter.shared.actions[keyID]?() }
            return noErr
        }, 1, &type, nil, &handler)
    }
}

/// Çevirinin ve çıkışın durumuna göre kısayolları alır, bırakır ve eylemlere bağlar.
@MainActor
public final class HotKeyController {
    private weak var state: AppState?
    private let register: (GlobalHotKey, @escaping () -> Void) -> Bool
    private let unregister: (GlobalHotKey) -> Void
    /// Ekranı çevir kısayolu bırakılınca (çeviri durdu) süren iş iptal edilir.
    private let onTranslateScreenReleased: () -> Void
    public private(set) var held: Set<GlobalHotKey> = []

    public convenience init(state: AppState, onTranslateScreenReleased: @escaping () -> Void = {}) {
        self.init(state: state,
                  register: { CarbonHotKeyCenter.shared.register($0, action: $1) },
                  unregister: { CarbonHotKeyCenter.shared.unregister($0) },
                  onTranslateScreenReleased: onTranslateScreenReleased)
    }

    init(state: AppState, register: @escaping (GlobalHotKey, @escaping () -> Void) -> Bool,
         unregister: @escaping (GlobalHotKey) -> Void, onTranslateScreenReleased: @escaping () -> Void) {
        self.state = state
        self.register = register
        self.unregister = unregister
        self.onTranslateScreenReleased = onTranslateScreenReleased
        refresh()
    }

    func refresh() {
        guard let state else { return }
        let wanted = withObservationTracking {
            HotKeyRules.wanted(translation: state.translation, subtitlesOnComputer: state.subtitlesOnComputer)
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        let (release, add) = HotKeyRules.diff(held: held, wanted: wanted)
        for k in release {
            unregister(k)
            held.remove(k)
            if k == .translateScreen { onTranslateScreenReleased() }
        }
        for k in add where register(k, { [weak self] in self?.pressed(k) }) { held.insert(k) }
    }

    func pressed(_ key: GlobalHotKey) {
        guard let state else { return }
        switch key {
        case .translateScreen: state.translateScreen()
        case .clickThrough: state.settings.overlayClickThrough.toggle()
        }
    }
}
