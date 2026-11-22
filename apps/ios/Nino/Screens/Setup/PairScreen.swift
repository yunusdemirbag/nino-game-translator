// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import NinoRemotePlay
import SwiftUI

/// Kurulum 2/3: PS5'i 8 haneli kodla eşleme.
struct PairScreen: View {
    @EnvironmentObject private var model: AppModel
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    let onDone: () -> Void

    @State private var found: [Consoles.Found] = []
    @State private var searching = false
    @State private var manual = ""
    @State private var code = ""
    @State private var pairing = false
    @State private var error: String?
    @State private var showManual = false
    @State private var showDemo = false
    @FocusState private var codeFocused: Bool

    private var address: String {
        let m = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? (found.first?.address ?? "") : m
    }

    var body: some View {
        NinoScreen {
            SetupHeader(step: 2, onBack: onBack, onSkip: onSkip)
        } content: {
            HeroTitle(step: L("setup.step", 2), title: L("pair.title"), lead: L("pair.body"))
            DarkStage {
                GlassRow(symbol: "gamecontroller.fill", title: consoleTitle, detail: consoleDetail) {
                    if !address.isEmpty && !searching {
                        Circle().fill(Color(rgb: 0x30C578)).frame(width: 10, height: 10)
                    } else {
                        SearchAgainButton(searching: searching) { Task { await search() } }
                    }
                }
                .padding(14)
            }
            .padding(.top, 6)
            codeTile
            if pairing {
                HStack(spacing: 8) {
                    ProgressView().tint(DS.Palette.accent)
                    Text(L("pair.connecting")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                }
            }
        } footer: {
            HStack {
                Button(L("pair.notfound")) { showManual = true }.buttonStyle(.ghost).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                TryWithoutPS5Button { showDemo = true }
            }
            Button(L("pair.button")) { Task { await pair() } }
                .buttonStyle(.primary)
                .disabled(pairing || code.count != 8 || address.isEmpty)
        }
        .task { await searchLoop() }
        .sheet(isPresented: $showManual) { manualSheet }
        .fullScreenCover(isPresented: $showDemo) { DemoPreview() }
    }

    private var consoleTitle: String {
        if manual.trimmingCharacters(in: .whitespaces).isEmpty, let f = found.first { return L("pair.found", f.name) }
        if !manual.trimmingCharacters(in: .whitespaces).isEmpty { return "PS5" }
        return L("pair.searching")
    }

    private var consoleDetail: String {
        let m = manual.trimmingCharacters(in: .whitespaces)
        if m.isEmpty, let f = found.first { return L("pair.samewifi", f.address) }
        if !m.isEmpty { return m }
        return L("pair.searching.detail")
    }

    private var codeTile: some View {
        Tile {
            Text(L("pair.code")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            ZStack {
                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .opacity(0.01)
                    .onChange(of: code) { _, new in
                        let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(8))
                        if digits != new { code = digits }
                    }
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        let chars = Array(code)
                        let next = i == chars.count
                        Text(i < chars.count ? String(chars[i]) : "")
                            .font(DS.Font.title)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.inner).fill(DS.Palette.surface2))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.inner)
                                .strokeBorder(next && codeFocused ? DS.Palette.accent : DS.Palette.secondary.opacity(0.4),
                                              lineWidth: next && codeFocused ? 2 : 1.5))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { codeFocused = true }
            }
            if let error {
                NoteLine(text: error)
            } else {
                Text(L("pair.code.note")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
        }
    }

    private var manualSheet: some View {
        SheetBody {
            HeroTitle(title: L("pair.help.title"),
                      lead: L("pair.help.body"),
                      spacing: 4)
            TextField(L("ip.placeholder"), text: $manual)
                .keyboardType(.decimalPad)
                .textFieldStyle(NinoFieldStyle())
            Button(L("common.searchagain")) { Task { await search() } }.buttonStyle(.secondary)
            Button(L("common.done.alt")) { showManual = false }.buttonStyle(.primary)
        }
        .fittedSheet()
    }

    private func search() async {
        guard !searching else { return }
        searching = true
        found = await Consoles.discover()
        searching = false
    }

    private func searchLoop() async {
        await search()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(found.isEmpty ? 2 : 6))
            if Task.isCancelled { return }
            if found.isEmpty {
                await search()
            } else if !searching && !pairing {
                let fresh = await Consoles.discover(seconds: 2)
                if !fresh.isEmpty { found = fresh }
            }
        }
    }

    private func pair() async {
        guard !pairing else { return }
        pairing = true
        error = nil
        defer { pairing = false }
        do {
            try await model.pairConsole(address: address, info: found.first { $0.address == address }?.info, pin: code)
            onDone()
        } catch let failure as Consoles.PairFailure {
            error = failure.message
        } catch {
            self.error = Consoles.PairFailure.other.message
        }
    }
}
