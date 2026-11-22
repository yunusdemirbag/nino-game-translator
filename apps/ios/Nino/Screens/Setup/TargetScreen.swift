// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// Altyazının yeri: TV'de ya da bu telefonda. Kurulumda adım 3/3; ana ekrandan da açılır.
struct TargetScreen: View {
    @EnvironmentObject private var model: AppModel
    var setup = true
    var onBack: (() -> Void)?
    let onDone: () -> Void

    @State private var found: [Displays.Found] = []
    @State private var searching = false
    @State private var pairingHost: String?
    @State private var results: [String: Bool] = [:]
    @State private var error: String?
    @State private var showManual = false
    @State private var showInstall = false

    var body: some View {
        NinoScreen {
            if setup {
                SetupHeader(step: 3, onBack: onBack)
            } else {
                BackHeader(L("settings.target"), onBack: { onBack?() })
            }
        } content: {
            HeroTitle(step: setup ? L("setup.step", 3) : nil, title: L("target.title"), lead: L("target.body"))
            tvTile
            BentoGrid {
                Button { model.useOutput(.computer) } label: {
                    InfoTile(symbol: "iphone", title: L("target.phone"), detail: L("tv.none"),
                             selected: model.settings.output.showsOnPhone)
                }
                .buttonStyle(.plain)
                Button { showManual = true } label: {
                    InfoTile(symbol: "questionmark.circle", title: L("tv.notlisted"), detail: L("tv.supported"))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(DS.Palette.text)
            Button { showInstall = true } label: {
                InfoTile(symbol: "arrow.down.app", title: L("tv.install.fromphone"),
                         detail: "Samsung · LG · Android TV", selected: model.tvAppMissing)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Palette.text)
            if let error { NoteLine(text: error) }
        } footer: {
            Button(setup ? L("ob.continue") : L("common.done"), action: onDone)
                .buttonStyle(.primary)
                .disabled(!model.hasPairedTV && !model.settings.output.showsOnPhone)
        }
        .task { await search() }
        .sheet(isPresented: $showManual) {
            ManualTVSheet { tv in Task { await pair(tv) } }
        }
        .sheet(isPresented: $showInstall, onDismiss: { Task { await search() } }) {
            TVInstallScreen(onDone: {
                showInstall = false
                if !setup || model.hasPairedTV || model.settings.output.showsOnPhone { onDone() }
            })
        }
    }

    /// Bulunanlar; kayıtlı TV listede yoksa en başta.
    private var list: [PairedTV] {
        var tvs = found.map(\.tv)
        if let saved = model.tv, model.hasPairedTV, !tvs.contains(where: { $0.host == saved.host }) {
            tvs.insert(saved, at: 0)
        }
        return tvs
    }

    private var tvTile: some View {
        Tile(selected: !model.settings.output.showsOnPhone && model.hasPairedTV) {
            HStack(spacing: DS.Space.gap) {
                Image(systemName: "tv").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.Palette.secondary)
                Text(L("target.tv")).font(DS.Font.headline)
                Spacer(minLength: 0)
                if !list.isEmpty { SearchAgainButton(searching: searching) { Task { await search() } } }
            }
            if list.isEmpty {
                HStack {
                    Text(searching ? L("tv.searching") : L("tv.error.notfound"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    Spacer(minLength: 0)
                    SearchAgainButton(searching: searching) { Task { await search() } }
                }
            } else {
                ForEach(list, id: \.host) { tv in
                    RowDivider()
                    tvRow(tv)
                }
            }
        }
    }

    private func tvRow(_ tv: PairedTV) -> some View {
        let selected = model.hasPairedTV && model.tv?.host == tv.host && !model.settings.output.showsOnPhone
        let ready: Bool? = results[tv.host] ?? (selected ? !model.tvAppMissing : nil)
        var detail = tv.brandName
        if let ready { detail += " · " + (ready ? L("tv.status.installed") : L("tv.status.noapp")) }
        return Button { Task { await pair(tv) } } label: {
            HStack(spacing: DS.Space.gap) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tv.name).font(DS.Font.headline)
                    Text(verbatim: detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                }
                Spacer(minLength: 0)
                if pairingHost == tv.host {
                    ProgressView().tint(DS.Palette.accent)
                } else if ready == true {
                    StatusLabel(text: L("status.ready"), dotColor: DS.Palette.success)
                } else if ready == false {
                    TagLabel(text: L("tv.status.notinstalled"))
                }
            }
            .frame(minHeight: DS.Size.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.Palette.text)
        .disabled(pairingHost != nil)
    }

    private func search() async {
        guard !searching else { return }
        searching = true
        found = await Displays.discover()
        searching = false
    }

    private func pair(_ tv: PairedTV) async {
        pairingHost = tv.host
        error = nil
        let ok = await model.pairTV(tv)
        results[tv.host] = ok
        pairingHost = nil
        if !ok && tv.brand != .androidTV {
            error = L("tv.error.connect")
        }
    }
}

/// "TV'm listede yok": marka ve IP adresi.
private struct ManualTVSheet: View {
    let onConnect: (PairedTV) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var brand: PairedTV.Brand = .lg
    @State private var address = ""
    @State private var invalid = false

    var body: some View {
        SheetBody {
            HeroTitle(title: L("tv.notlisted"),
                      lead: L("tv.supported.body"),
                      spacing: 4)
            SegmentPicker(options: [(.lg, "LG"), (.samsung, "Samsung"), (.androidTV, "Android TV")], selection: $brand)
            if brand != .androidTV {
                TextField(L("ip.placeholder"), text: $address)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(NinoFieldStyle())
                if invalid {
                    NoteLine(text: L("ip.error.invalid"))
                }
            }
            Link(L("tv.supported"), destination: URL(string: "https://github.com/yunusdemirbag/nino-game-translator#tv-uygulamasini-kurma")!)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Palette.accent)
            Button(L("common.connect")) { connect() }
                .buttonStyle(.primary)
                .disabled(brand != .androidTV && address.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .fittedSheet()
    }

    private func connect() {
        if brand == .androidTV {
            onConnect(PairedTV(name: "Android TV", host: "", brand: .androidTV))
        } else {
            guard let host = Displays.cleanAddress(address) else { invalid = true; return }
            onConnect(PairedTV(name: host, host: host, brand: brand))
        }
        invalid = false
        dismiss()
    }
}
