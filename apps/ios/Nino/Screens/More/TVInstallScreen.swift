// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SafariServices
import SwiftUI
import WebKit

// TV uygulamasını bilgisayarsız, bu telefondan kurma ve güncelleme (ayarlar.md §7). Ayarlar'dan, altyazı hedefi
// ekranından ve ana ekrandaki güncelleme kartından açılır.

/// Kurulumun ekrandaki durumu.
enum TVInstallPhase: Equatable {
    case idle
    case working(InstallStage)
    case done(TVInstallOutcome)
    case failed(String)

    var isWorking: Bool {
        guard case .working = self else { return false }
        return true
    }

    var isDone: Bool {
        guard case .done = self else { return false }
        return true
    }
}

struct TVInstallScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Ana ekrandaki "TV uygulamasını güncelle": güncellenen TV seçilir ve kurulum kendiliğinden başlar.
    var update = false
    let onDone: () -> Void
    @State private var brand: PairedTV.Brand?
    @State private var working = false

    var body: some View {
        NinoScreen {
            BackHeader(L("tv.install.title"), onBack: { dismiss() })
        } content: {
            if let brand {
                if !working {
                    SegmentPicker(options: [(PairedTV.Brand.samsung, "Samsung"), (.lg, "LG"), (.androidTV, "Android TV")],
                                  selection: Binding(get: { brand }, set: { self.brand = $0 }))
                }
                let known = model.installedTVApp ?? model.tv.map { InstalledTVApp(brand: $0.brand, host: $0.host, port: nil, version: "") }
                let target = update ? known.flatMap { $0.brand == brand ? $0 : nil } : nil
                switch brand {
                case .samsung: SamsungInstallSection(update: target, working: $working, onDone: onDone)
                case .lg: LGInstallSection(update: target, working: $working, onDone: onDone)
                case .androidTV: AndroidTVInstallSection(update: target, working: $working, onDone: onDone)
                }
            } else {
                HStack(spacing: DS.Space.gap) {
                    ProgressView().tint(DS.Palette.accent)
                    Text(L("tv.searching")).font(DS.Font.body).foregroundStyle(DS.Palette.secondary)
                }
            }
        }
        .task { await chooseBrand() }
        .onChange(of: working) { _, on in ScreenAwake.set(on, for: .tvInstall) }
        .onDisappear { ScreenAwake.set(false, for: .tvInstall) }
    }

    /// Marka: güncellenen TV → bu telefonun kurduğu TV → eşlenen TV → ağda ilk bulunan TV → Samsung.
    private func chooseBrand() async {
        guard brand == nil else { return }
        if let known = model.installedTVApp?.brand ?? model.tv?.brand {
            brand = known
            return
        }
        if model.ephemeral {
            brand = .samsung
            return
        }
        brand = await Displays.discover(seconds: 2).first?.brand ?? .samsung
    }
}

// MARK: - Ortak parçalar

func installStageText(_ stage: InstallStage) -> String {
    switch stage {
    case .pairing: L("tvi.step.pairing")
    case .approveOnTV: L("tvi.step.approve")
    case .fetchingKey: L("tvi.step.key")
    case .waitingForPlay: L("tvi.step.play")
    case .connecting: L("tvi.step.connecting")
    case .reading: L("tvi.step.reading")
    case .signIn: L("tvi.step.signin")
    case .certificate: L("tvi.step.certificate")
    case .signing: L("tvi.step.signing")
    case .installing: L("tvi.step.installing")
    case .uninstalling: L("tvi.step.uninstalling")
    case .launching: L("tvi.step.launching")
    }
}

struct InstallIntro: View {
    let text: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.inline) {
            Text(text).font(DS.Font.body).foregroundStyle(DS.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Text(note).font(DS.Font.caption).foregroundStyle(DS.Palette.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct InstallStepsTile: View {
    let title: String
    let steps: [String]
    var highlight: String?
    var after: [String] = []

    var body: some View {
        Tile {
            Text(title).font(DS.Font.headline)
            ForEach(steps, id: \.self) { line($0) }
            if let highlight {
                Text(highlight).font(DS.Font.title).foregroundStyle(DS.Palette.accent).textSelection(.enabled)
            }
            ForEach(after, id: \.self) { line($0) }
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).font(DS.Font.body).foregroundStyle(DS.Palette.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct InstallCandidateRow: View {
    let name: String
    let detail: String
    var status: (text: String, good: Bool)?
    let selected: Bool

    var body: some View {
        Tile(selected: selected) {
            HStack(spacing: DS.Space.gap) {
                TileSymbol(symbol: "tv", tone: selected ? .accent : .neutral)
                VStack(alignment: .leading, spacing: DS.Space.hair) {
                    Text(name).font(DS.Font.headline)
                    Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    if let status {
                        Text(status.text).font(DS.Font.caption)
                            .foregroundStyle(status.good ? DS.Palette.success : DS.Palette.warning)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.accent) }
            }
        }
        .contentShape(Rectangle())
    }
}

struct InstallResultView: View {
    @EnvironmentObject private var model: AppModel
    let phase: TVInstallPhase

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .working(let stage):
            Tile {
                HStack(spacing: DS.Space.gap) {
                    ProgressView().tint(DS.Palette.accent)
                    Text(installStageText(stage)).font(DS.Font.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .done(let outcome):
            Tile(selected: true) {
                Label {
                    Text(outcome.installed ? L("tvi.done", outcome.version) : L("tvi.uptodate", outcome.version))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.success)
                }
                .font(DS.Font.headline)
                Text(L("tvi.next")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let text):
            NoteLine(text: text)
            ShareLink(item: model.tvInstallFiles.logFile) { Text(L("tvi.sharelog")) }
                .font(DS.Font.caption).tint(DS.Palette.accent)
        }
    }
}

/// Ana düğme: bittiyse ana ekrana, değilse "Yükle ve aç" / "Yeniden Dene".
struct InstallMainButton: View {
    let phase: TVInstallPhase
    var disabled = false
    let install: () -> Void
    let home: () -> Void

    var body: some View {
        if phase.isDone {
            Button(L("tvi.home"), action: home).buttonStyle(.primary)
        } else {
            let failed = if case .failed = phase { true } else { false }
            Button(failed ? L("common.retry") : L("tv.install.button"), action: install)
                .buttonStyle(.primary)
                .disabled(phase.isWorking || disabled)
        }
    }
}

struct InstallAddressField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .numbersAndPunctuation

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(NinoFieldStyle())
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}

// MARK: - Samsung

struct SamsungInstallSection: View {
    @EnvironmentObject private var model: AppModel
    let update: InstalledTVApp?
    @Binding var working: Bool
    let onDone: () -> Void
    @State private var candidates: [(host: String, name: String, info: SamsungTVInfo?)]?
    @State private var host = ""
    @State private var manual = false
    @State private var phase = TVInstallPhase.idle
    @State private var signIn: SamsungSignIn.Listener?
    @State private var started = false
    @State private var phoneIP: String?

    var body: some View {
        InstallIntro(text: L("tv.install.samsung.body"), note: L("tvi.samsung.note"))
        Text(L("tvi.samsung.list")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        if let candidates {
            if candidates.isEmpty { NoteLine(text: L("tvi.samsung.none"), color: DS.Palette.secondary) }
            ForEach(candidates, id: \.host) { item in
                Button { if !phase.isWorking { host = item.host } } label: {
                    InstallCandidateRow(name: item.info?.name ?? item.name,
                                        detail: [item.info?.model, item.host].compactMap { $0 }.joined(separator: " · "),
                                        status: developerState(item.info), selected: host == item.host)
                }
                .buttonStyle(.plain)
            }
        } else {
            ProgressView().tint(DS.Palette.accent)
        }
        if manual {
            InstallAddressField(placeholder: L("tvi.address"), text: $host, keyboard: .decimalPad)
        } else if !phase.isWorking {
            Button(L("tv.notlisted")) { manual = true }.buttonStyle(.ghost)
        }
        InstallStepsTile(title: L("tvi.dev.title"),
                         steps: [L("tvi.samsung.step1"), L("tvi.samsung.step2"), L("tvi.samsung.step3")],
                         highlight: phoneIP ?? L("tvi.samsung.nophoneip"), after: [L("tvi.samsung.step4")])
        Text(L("tvi.samsung.signin.note")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        InstallResultView(phase: phase)
        InstallMainButton(phase: phase, disabled: host.trimmingCharacters(in: .whitespaces).isEmpty, install: install, home: onDone)
            .task { await search() }
            .onChange(of: host) { _, h in phoneIP = TVDiscovery.phoneAddress(towards: cleanHost(h)) }
            .sheet(isPresented: Binding(get: { signIn != nil }, set: { if !$0 { signIn?.cancel(); signIn = nil } })) {
                SamsungSignInSheet { signIn?.cancel(); signIn = nil }
            }
    }

    private func cleanHost(_ h: String) -> String? { Displays.cleanAddress(normalizedDigits(h)) }

    private func developerState(_ info: SamsungTVInfo?) -> (text: String, good: Bool)? {
        guard let on = info?.developerMode else { return nil }
        if !on { return (L("tvi.dev.off"), false) }
        if let ip = info?.developerIP, let phone = phoneIP, ip != phone { return (L("tvi.dev.otherip", ip), false) }
        return (L("tvi.dev.on"), true)
    }

    private func search() async {
        guard candidates == nil else { return }
        if let update { host = update.host }
        phoneIP = TVDiscovery.phoneAddress(towards: cleanHost(host))
        guard !model.ephemeral else {
            candidates = []
            manual = true
            return
        }
        var hosts = await TVDiscovery.scan(port: 8001, near: update?.host ?? model.tv?.host)
        if let known = model.tv, known.brand == .samsung, !known.host.isEmpty, !hosts.contains(known.host) { hosts.insert(known.host, at: 0) }
        var list: [(host: String, name: String, info: SamsungTVInfo?)] = []
        for h in hosts {
            let info = await SamsungTVInfo.fetch(host: h)
            if info != nil || h == model.tv?.host { list.append((h, info?.name ?? "Samsung TV", info)) }
        }
        candidates = list
        if host.isEmpty, let first = list.first { host = first.host }
        if list.isEmpty { manual = true }
        if update != nil, !started {
            started = true
            install()
        }
    }

    private func install() {
        guard let target = cleanHost(host) else { return }
        phase = .working(.connecting)
        working = true
        let files = model.tvInstallFiles, log = model.tvInstallLog, store = model.tvPackages
        let phone = TVDiscovery.phoneAddress(towards: target)
        let present: @Sendable (SamsungSignIn.Listener?) -> Void = { l in Task { @MainActor in signIn = l } }
        Task {
            defer { working = false }
            do {
                let outcome = try await runOffMain({ stage in
                    let package: TVPackage
                    do { package = try store.package(.samsung, log: log) } catch {
                        throw SamsungFailure(problem: .packageMissing, detail: "\(error)")
                    }
                    var installer = SamsungInstaller(host: target, files: files, log: log, signIn: {
                        // Giriş sayfası açılır; Samsung hesabı bu telefondaki dinleyiciye gönderince devam edilir.
                        let listener = try SamsungSignIn.Listener()
                        present(listener)
                        defer { present(nil) }
                        return try listener.wait(timeout: 600)
                    })
                    installer.stage = stage
                    return try installer.install(wgt: { package })
                }, stage: { s in if phase.isWorking { phase = .working(s) } })
                phase = .done(outcome)
                await model.tvAppInstalled(brand: .samsung, host: target, port: nil, version: outcome.version)
            } catch let f as SamsungFailure {
                phase = .failed(failureText(f, phone: phone))
            } catch {
                phase = .failed(L("tvi.err.failed") + "\n\n" + L("tvi.details", "\(error)"))
            }
        }
    }

    private func failureText(_ f: SamsungFailure, phone: String?) -> String {
        var text: String = switch f.problem {
        case .unreachable: L("tvi.samsung.err.unreachable", phone ?? "?")
        case .tooOld: L("tvi.samsung.err.tooold")
        case .loginFailed: L("tvi.samsung.err.login")
        case .certificateFailed: L("tvi.samsung.err.certificate")
        case .notEnoughSpace: L("tvi.err.space")
        case .certificateMismatch: L("tvi.samsung.err.mismatch")
        case .certificateRejected: L("tvi.samsung.err.rejected")
        case .clockBehind: L("tvi.samsung.err.clock")
        case .packageBlocked: L("tvi.samsung.err.blocked")
        case .connectionLost: L("tvi.err.connection")
        case .packageMissing: L("tvi.err.package")
        case .installFailed: L("tvi.err.failed")
        }
        if let d = f.detail, !d.isEmpty { text += "\n\n" + L("tvi.details", d) }
        if f.problem == .installFailed || f.problem == .certificateRejected { text += "\n\n" + L("tvi.samsung.maintenance") }
        return text
    }
}

/// Samsung'un giriş sayfası (uygulama içinde); sayfa hesabı bu telefonun localhost'undaki dinleyiciye gönderir.
struct SamsungSignInSheet: View {
    let onClose: () -> Void
    @State private var safari = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.gap) {
                SquareIconButton(symbol: "xmark", label: L("common.close"), action: onClose)
                Text(L("tvi.samsung.signin.title")).font(DS.Font.title)
                Spacer(minLength: 0)
                SquareIconButton(symbol: "safari", label: "Safari") { safari = true }
            }
            .padding(DS.Space.screen)
            SamsungWebView(url: SamsungSignIn.pageURL)
        }
        .background(DS.Palette.bg)
        .sheet(isPresented: $safari) { SafariSheet(url: SamsungSignIn.pageURL) }
    }
}

struct SamsungWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.isOpaque = false
        view.backgroundColor = UIColor(DS.Palette.bg)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - LG

struct LGInstallSection: View {
    @EnvironmentObject private var model: AppModel
    let update: InstalledTVApp?
    @Binding var working: Bool
    let onDone: () -> Void
    @State private var found: [LGCandidate]?
    @State private var host = ""
    @State private var manual = false
    @State private var badAddress = false
    @State private var passphrase = ""
    @State private var phase = TVInstallPhase.idle
    @State private var hint: String?
    @State private var started = false

    private var keys: LGKeyStore { LGKeyStore(files: model.tvInstallFiles) }
    private var hasKey: Bool { Displays.cleanAddress(normalizedDigits(host)).map { keys.load($0) != nil } ?? false }

    var body: some View {
        InstallIntro(text: L("tv.install.lg.body"), note: L("tvi.lg.note"))
        Text(L("tvi.lg.list")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        if let found {
            if found.isEmpty { NoteLine(text: L("tvi.lg.none"), color: DS.Palette.secondary) }
            ForEach(found, id: \.host) { item in
                Button { if !phase.isWorking { host = item.host } } label: {
                    InstallCandidateRow(name: item.name, detail: item.host,
                                        status: item.devMode ? (L("tvi.dev.on"), true) : (L("tvi.dev.off"), false),
                                        selected: host == item.host)
                }
                .buttonStyle(.plain)
            }
        } else {
            ProgressView().tint(DS.Palette.accent)
        }
        if badAddress { NoteLine(text: L("tvi.lg.badip")) }
        if manual {
            InstallAddressField(placeholder: L("tvi.address"), text: $host)
                .onChange(of: host) { _, _ in badAddress = false }
        } else if !phase.isWorking {
            Button(L("tv.notlisted")) { manual = true }.buttonStyle(.ghost)
        }
        TextField(hasKey ? L("tvi.lg.pass.saved") : L("tvi.lg.pass"),
                  text: Binding(get: { passphrase }, set: { passphrase = $0.filter { !$0.isWhitespace }.uppercased() }))
            .textFieldStyle(NinoFieldStyle())
            .keyboardType(.asciiCapable)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
        InstallStepsTile(title: L("tvi.dev.title"),
                         steps: [L("tvi.lg.step1"), L("tvi.lg.step2"), L("tvi.lg.step3"), L("tvi.lg.step4")])
        Text(L("tvi.lg.session")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
        InstallResultView(phase: phase)
        if let hint, !phase.isWorking { NoteLine(text: hint) }
        InstallMainButton(phase: phase, install: install, home: onDone)
            .task { await search() }
    }

    private func search() async {
        guard found == nil else { return }
        if let update {
            host = update.host
        } else if let installed = model.installedTVApp, installed.brand == .lg {
            host = installed.host
        }
        if update != nil, !started, hasKey {
            started = true
            install()
        }
        guard !model.ephemeral else {
            found = []
            manual = true
            return
        }
        let near = host.isEmpty ? model.tv?.host : host
        async let devOn = TVDiscovery.scan(port: LGInstaller.sshPort, near: near)
        async let webOS = TVDiscovery.scan(port: 3001, near: near)
        let on = await devOn, all = await webOS
        var list = on.map { LGCandidate(host: $0, name: "LG TV", devMode: true) }
        list += all.filter { !on.contains($0) }.map { LGCandidate(host: $0, name: "LG TV", devMode: false) }
        if let known = model.tv, known.brand == .lg, !known.host.isEmpty, !list.contains(where: { $0.host == known.host }) {
            let open = await TVDiscovery.isOpen(known.host, LGInstaller.sshPort)
            list.insert(LGCandidate(host: known.host, name: known.name, devMode: open), at: 0)
        }
        found = list
        if host.isEmpty { host = (list.first { $0.devMode } ?? list.first)?.host ?? "" }
        if list.isEmpty { manual = true }
    }

    private func install() {
        hint = nil
        let log = model.tvInstallLog
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            hint = L("tvi.lg.needtv")
            return
        }
        guard let target = Displays.cleanAddress(normalizedDigits(host)) else {
            badAddress = true
            hint = L("tvi.lg.badip")
            log.write("LG: address not valid (\(host)).")
            return
        }
        badAddress = false
        let typed = passphrase
        let keys = self.keys
        guard !typed.isEmpty || keys.load(target) != nil else {
            hint = L("tvi.lg.needpass")
            return
        }
        phase = .working(.connecting)
        working = true
        let store = model.tvPackages, defaults = model.defaults
        Task {
            defer { working = false }
            do {
                let outcome = try await runOffMain({ stage in
                    let package: TVPackage
                    do { package = try store.package(.lg, log: log) } catch {
                        throw LGFailure(problem: .packageMissing, detail: "\(error)")
                    }
                    func freshKey() throws -> Bytes {
                        guard !typed.isEmpty else { throw LGFailure(problem: .keyRefused, detail: "no passphrase") }
                        stage(.fetchingKey)
                        guard let url = LGInstaller.keyURL(target), let data = try? BlockingHTTP.get(url, timeout: 5) else {
                            throw LGFailure(problem: .keyServerOff, detail: "Key Server did not answer")
                        }
                        let key = try LGInstaller.decodeKey(Bytes(data), passphrase: typed)
                        keys.save(target, key)
                        log.write("Got the key from Key Server.")
                        return key
                    }
                    func attempt(_ key: Bytes) throws -> TVInstallOutcome {
                        let rsa: RSAPrivateKey
                        do { rsa = try RSAPrivateKey(pem: key) } catch {
                            throw LGFailure(problem: .keyRefused, detail: "saved key unreadable")
                        }
                        var installer = LGInstaller(shell: LGSSHShell(host: target, key: rsa), log: log)
                        installer.stage = stage
                        let outcome = try installer.install(ipk: package)
                        LGSessionRenewal.renewIfDue(host: target, defaults: defaults) { (try? installer.renewSession()) ?? nil }
                        return outcome
                    }
                    guard let saved = keys.load(target) else { return try attempt(freshKey()) }
                    do {
                        return try attempt(saved)
                    } catch let f as LGFailure where f.problem == .keyRefused {
                        // Geliştirici modu yeniden açılınca TV yeni anahtar üretir: eskisi unutulur.
                        keys.remove(target)
                        log.write("Saved key refused; forgotten.")
                        return try attempt(freshKey())
                    }
                }, stage: { s in if phase.isWorking { phase = .working(s) } })
                phase = .done(outcome)
                await model.tvAppInstalled(brand: .lg, host: target, port: nil, version: outcome.version)
            } catch let f as LGFailure {
                phase = .failed(failureText(f))
            } catch {
                phase = .failed(L("tvi.err.failed") + "\n\n" + L("tvi.lg.tvsays", "\(error)"))
            }
        }
    }

    private func failureText(_ f: LGFailure) -> String {
        let advice: String = switch f.problem {
        case .unreachable: L("tvi.lg.err.unreachable")
        case .keyServerOff: L("tvi.lg.err.keyserver")
        case .wrongPassphrase: L("tvi.lg.err.passphrase")
        case .keyRefused: L("tvi.lg.err.keyrefused")
        case .notEnoughSpace: L("tvi.err.space")
        case .connectionLost: L("tvi.err.connection")
        case .packageMissing: L("tvi.err.package")
        case .installFailed: L("tvi.err.failed")
        }
        guard f.problem != .wrongPassphrase, let d = f.detail, !d.isEmpty else { return advice }
        return advice + "\n\n" + L("tvi.lg.tvsays", d)
    }
}

// MARK: - Android TV

struct AndroidTVInstallSection: View {
    @EnvironmentObject private var model: AppModel
    let update: InstalledTVApp?
    @Binding var working: Bool
    let onDone: () -> Void
    @State private var candidates: [(host: String, open: Bool)]?
    @State private var address = ""
    @State private var wireless = false
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var phase = TVInstallPhase.idle
    @State private var replaceNeeded = false
    @State private var started = false

    var body: some View {
        InstallIntro(text: L("tvi.android.body"), note: L("tvi.android.note"))
        Text(L("tvi.android.list")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        if let candidates {
            if candidates.isEmpty { NoteLine(text: L("tvi.android.none"), color: DS.Palette.secondary) }
            ForEach(candidates, id: \.host) { item in
                Button { select(item.host) } label: {
                    InstallCandidateRow(name: "Android TV", detail: item.host,
                                        status: item.open ? (L("tvi.android.debug.on"), true) : (L("tvi.android.debug.off"), false),
                                        selected: AndroidTVInstaller.split(address)?.host == item.host)
                }
                .buttonStyle(.plain)
            }
        } else {
            ProgressView().tint(DS.Palette.accent)
        }
        Text(L("tvi.android.mode")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        SegmentPicker(options: [(false, L("tvi.android.mode.network")), (true, L("tvi.android.mode.wireless"))], selection: $wireless)
        InstallAddressField(placeholder: wireless ? L("tvi.android.address.wireless") : L("tvi.address"), text: $address)
        if wireless {
            InstallAddressField(placeholder: L("tvi.android.pair.address"), text: $pairAddress)
            InstallAddressField(placeholder: L("tvi.android.pair.code"), text: $pairCode, keyboard: .numberPad)
            Text(L("tvi.android.localnet")).font(DS.Font.caption).foregroundStyle(DS.Palette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        InstallStepsTile(title: L("tvi.android.steps.title"),
                         steps: wireless ? [L("tvi.android.step1"), L("tvi.android.wstep2"), L("tvi.android.wstep3")]
                            : [L("tvi.android.step1"), L("tvi.android.step2"), L("tvi.android.step3")])
        InstallResultView(phase: phase)
        if replaceNeeded, !phase.isWorking {
            Button(L("tvi.android.replace")) { install(allowReplace: true) }.buttonStyle(.danger)
        }
        InstallMainButton(phase: phase, disabled: address.trimmingCharacters(in: .whitespaces).isEmpty,
                          install: { install() }, home: onDone)
            .task { await search() }
    }

    private func select(_ host: String) {
        guard !phase.isWorking else { return }
        address = host
    }

    private func search() async {
        guard candidates == nil else { return }
        if let update {
            address = update.host + (update.port.map { ":\($0)" } ?? "")
        }
        var known: [String] = []
        for (brand, h) in [(update?.brand, update?.host), (model.installedTVApp?.brand, model.installedTVApp?.host),
                           (model.tv?.brand, model.tv?.host)] {
            if brand == .androidTV, let h, !h.isEmpty, !known.contains(h) { known.append(h) }
        }
        if update != nil, !started {
            started = true
            install()
        }
        guard !model.ephemeral else {
            candidates = []
            return
        }
        let open = await TVDiscovery.scan(port: AdbClient.defaultPort, near: known.first)
        var list = open.map { (host: $0, open: true) }
        for h in known.reversed() where !list.contains(where: { $0.host == h }) { list.insert((h, false), at: 0) }
        candidates = list
        if address.isEmpty, let first = list.first(where: { $0.open }) ?? list.first { address = first.host }
    }

    private func install(allowReplace: Bool = false) {
        guard let target = AndroidTVInstaller.split(address, defaultPort: wireless ? 0 : AdbClient.defaultPort) else {
            phase = .failed(L("tvi.android.needport"))
            return
        }
        let code = normalizedDigits(pairCode).filter(\.isNumber)
        var pairing: AndroidTVInstaller.Pairing?
        if wireless, !code.isEmpty {
            guard let pair = AndroidTVInstaller.split(pairAddress, defaultPort: 0) else {
                phase = .failed(L("tvi.android.needpairport"))
                return
            }
            pairing = .init(port: pair.port, code: code)
        }
        replaceNeeded = false
        phase = .working(pairing != nil ? .pairing : .connecting)
        working = true
        let files = model.tvInstallFiles, log = model.tvInstallLog, store = model.tvPackages
        let chosenPairing = pairing
        Task {
            defer { working = false }
            do {
                let outcome = try await runOffMain({ stage in
                    var installer = AndroidTVInstaller(host: target.host, port: target.port,
                                                       identity: { try AdbIdentity.stored(in: files.adb) },
                                                       pairing: chosenPairing, log: log)
                    installer.stage = stage
                    // Paket TV okunduktan sonra istenir: paket yoksa da TV'deki Nino'ya izin verilip açılır.
                    return try installer.install(package: { try store.package(.android, log: log) }, allowReplace: allowReplace)
                }, stage: { s in if phase.isWorking { phase = .working(s) } })
                phase = .done(outcome)
                await model.tvAppInstalled(brand: .androidTV, host: target.host,
                                           port: target.port == AdbClient.defaultPort ? nil : target.port, version: outcome.version)
            } catch let f as AndroidTVFailure {
                replaceNeeded = f.problem == .replaceNeeded
                phase = .failed(failureText(f))
            } catch {
                phase = .failed(L("tvi.err.failed") + "\n\n" + L("tvi.details", "\(error)"))
            }
        }
    }

    /// Kaldırıp kurduktan sonra da imza tutmadıysa TV eski kopyayı silmemiştir: kullanıcı TV'de kendisi kaldırır.
    private func mustRemoveOnTV(_ f: AndroidTVFailure) -> Bool {
        f.problem == .installFailed && AndroidTVInstaller.needsReplace(f.detail ?? "")
    }

    private func failureText(_ f: AndroidTVFailure) -> String {
        let advice: String = switch f.problem {
        case .unreachable: L("tvi.android.err.unreachable")
        case .notApproved: L("tvi.android.err.notapproved")
        case .notPaired: L("tvi.android.err.notpaired")
        case .pairingFailed: L("tvi.android.err.pairing")
        case .replaceNeeded: f.fromPlay ? L("tvi.android.err.playcopy") : L("tvi.android.err.othercopy")
        case .notEnoughSpace: L("tvi.err.space")
        case .connectionLost: L("tvi.err.connection")
        case .packageMissing: L("tvi.err.package")
        case .installFailed: mustRemoveOnTV(f) ? L("tvi.android.err.removemanually") : L("tvi.err.failed")
        }
        guard f.problem != .replaceNeeded, !mustRemoveOnTV(f), let d = f.detail, !d.isEmpty else { return advice }
        return advice + "\n\n" + L("tvi.details", d)
    }
}

/// LG listesindeki bir TV: geliştirici modu açıksa SSH portu (9922) yanıt verir.
struct LGCandidate: Equatable {
    var host: String
    var name: String
    var devMode: Bool
}
