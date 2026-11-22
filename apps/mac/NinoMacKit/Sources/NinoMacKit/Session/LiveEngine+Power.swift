// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import Foundation
import NinoCore

// Uyku engeli ve uyanınca yeniden bağlanma (kaynaklar.md başı: "Çeviri başlarken sistem uykusu engellenir, Mac uykudan
// uyanınca kaynağa 'hemen yeniden bağlan' ve TV bekçisine 'yeniden bağlan' denir"; tv-kurulumu.md §4).
extension LiveEngine {
    /// Çeviri açıkken sistem uykusu engellenir (ekran kararabilir; ekran uykusu için ayar yok).
    func holdSleepAssertion(_ on: Bool) {
        if on {
            guard sleepActivity == nil, env.preventsSleep else { return }
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated],
                                                                  reason: "Nino çeviriyor")
        } else if let a = sleepActivity {
            ProcessInfo.processInfo.endActivity(a)
            sleepActivity = nil
        }
    }

    public var isHoldingSleepAssertion: Bool { sleepActivity != nil }

    /// Uyanma ve ağ değişimi bildirimleri (uygulama ömrünce bir kez).
    func observeWake() {
        let ws = NSWorkspace.shared.notificationCenter
        lifecycleObservers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectAfterWake() }
        })
    }

    /// Uyandı: kaynak hemen yeniden bağlanır, dinleyen TV'lere bağlantı yenilenir.
    public func reconnectAfterWake() {
        lastWake = Date()
        guard state.isTranslating else { return }
        notes.append("uyandı: yeniden bağlanılıyor")
        subtitleLog.write("Mac uyandı; yeniden bağlanılıyor")
        source?.reconnect()
        var hosts: [String] = []
        if let tv = state.pairedTV, tv.brand == .androidTV, state.subtitlesOnTV { hosts.append(tv.host) }
        let links = self.links
        Task {
            await links.disconnectTVs()
            await links.start(tvHosts: hosts)
        }
    }

    // MARK: Yerel ağ izni

    /// PS5'e ulaşılamıyorsa (bağlanıyor, bulunamadı, ağ, diğer) yerel ağ izni tahmin edilir; PS5 akınca uyarı kalkar.
    func localNetworkCheck(_ link: SourceStatus.ConsoleLink) {
        switch link {
        case .streaming:
            state.localNetworkBlocked = false
            return
        case .connecting, .dropped(.notFound), .dropped(.network), .dropped(.other):
            break
        default:
            return
        }
        guard state.translation != .off, let probe = env.localNetworkProbe, !localNetworkProbing else { return }
        if let last = lastLocalNetworkProbe, Date().timeIntervalSince(last) < 30 { return }
        localNetworkProbing = true
        lastLocalNetworkProbe = Date()
        let token = sessionToken
        Task {
            let verdict = await probe()
            self.localNetworkProbing = false
            guard token == self.sessionToken, self.state.translation != .off else { return }
            if case .ps5(.streaming) = self.state.source { return }
            let blocked = verdict == .blocked
            if blocked != self.state.localNetworkBlocked {
                self.state.localNetworkBlocked = blocked
                if blocked { self.remotePlayLog.write("Yerel ağa erişim izni yok gibi (gönderimler reddedildi)") }
            }
        }
    }
}
