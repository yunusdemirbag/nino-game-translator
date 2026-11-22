// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UniformTypeIdentifiers

// Listede görünmeyen ama sayfası hazır bölümler (ayarlar.md §14.3, §14.4).

// MARK: - Oyun paketleri (§14.3)

struct GamePackSettings: View {
    let state: AppState
    @State private var importing = false
    @State private var title = ""
    @Environment(\.locale) private var locale

    private var status: SettingsStatus { state.settingsStatus }

    private func text(_ key: String) -> String { SettingsText.string(key, locale) }

    static var importTypes: [UTType] {
        [.json, .plainText] + [UTType(filenameExtension: "srt")].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            header
            SHint("settings.packs.hint")
            if state.settings.targetLanguage != "tr" {
                NinoCard { NinoErrorLabel(text("settings.packs.turkishOnly")) }
            }
            Button {
                importing = true
            } label: {
                Label { SText("settings.packs.import") } icon: { Image(systemName: "square.and.arrow.down") }
            }
            .buttonStyle(.nino(.secondary, size: .large))
            if let error = status.packError, let key = Self.errorKey(error) {
                NinoErrorLabel(text(key))
            }
            if status.gamePacks.isEmpty {
                NinoCard { SText("settings.packs.none").foregroundStyle(NinoColor.textSecondary) }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: NinoSpacing.m),
                                    GridItem(.flexible(), spacing: NinoSpacing.m)], spacing: NinoSpacing.m) {
                    ForEach(status.gamePacks) { pack in packTile(pack) }
                }
            }
            toggles
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes) { result in
            if case .success(let url) = result { state.prepareGamePackImport(url) }
        }
        .sheet(isPresented: Binding(get: { status.packImport != nil }, set: { if !$0 { state.cancelGamePackImport() } })) {
            if let pending = status.packImport { importSheet(pending) }
        }
        .alert(text("settings.packs.replaceTitle"), isPresented: replacing) {
            Button(text("settings.packs.replace"), role: .destructive) {
                state.installGamePack(title: title, replacing: true)
            }
            Button(text("settings.cancel"), role: .cancel) { status.packError = nil }
        } message: {
            SText("settings.packs.replaceMessage")
        }
    }

    private var replacing: Binding<Bool> {
        Binding(get: { if case .alreadyExists = status.packError { return true }; return false },
                set: { if !$0, case .alreadyExists = status.packError { status.packError = nil } })
    }

    static func errorKey(_ error: GamePackError) -> String? {
        switch error {
        case .unreadable: return "settings.packs.error.unreadable"
        case .badFormat: return "settings.packs.error.format"
        case .sameFile: return "settings.packs.error.sameFile"
        case .installFailed: return "settings.packs.error.install"
        case .alreadyExists: return nil
        }
    }

    private var header: some View {
        HStack(spacing: NinoSpacing.m) {
            SettingsSectionIcon(section: .packs, large: true)
            SText("settings.section.packs").font(.ninoRounded(28, weight: .bold))
            Spacer(minLength: 0)
            if !status.gamePacks.isEmpty {
                Text(SettingsText.string("settings.packs.badge %lld", locale, status.gamePacks.count))
                    .font(.nino(.caption).weight(.semibold))
                    .foregroundStyle(NinoColor.success)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(NinoColor.successSoft))
            }
        }
    }

    private func packTile(_ pack: GamePackInfo) -> some View {
        HStack(spacing: NinoSpacing.m) {
            Text(verbatim: Self.initials(pack.name))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [SettingsSection.packs.color.color, NinoRGB(0.85, 0.35, 0.05).color],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: pack.name).font(.nino(.headline)).lineLimit(1)
                Text(SettingsText.string("settings.packs.lines %@", locale, pack.lines.formatted(.number.locale(locale))))
                    .font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .ninoTile(padding: NinoSpacing.m)
    }

    /// Adın ilk üç kelimesinin baş harfleri, büyük harfle.
    static func initials(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == ":" })
            .prefix(3)
            .compactMap(\.first)
            .map { String($0).uppercased() }
            .joined()
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: NinoSpacing.m) {
            NinoToggleRow(text("settings.packs.use"), isOn: bind(\.gamePacks))
            Divider()
            NinoToggleRow(text("settings.packs.share"), isOn: bind(\.sharePool))
            SHint("settings.packs.shareHint")
            Divider()
            NinoToggleRow(text("settings.packs.subtitlesOnly"), isOn: bind(\.subtitlesOnly))
            SHint("settings.packs.subtitlesOnlyHint")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninoTile()
    }

    private func bind(_ path: WritableKeyPath<MacSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.settings[keyPath: path] }, set: { state.settings[keyPath: path] = $0 })
    }

    private func importSheet(_ pending: GamePackImport) -> some View {
        VStack(alignment: .leading, spacing: NinoSpacing.l) {
            SText("settings.packs.importTitle").font(.nino(.title))
            VStack(alignment: .leading, spacing: NinoSpacing.xs) {
                SText("settings.packs.gameTitle").font(.nino(.caption)).foregroundStyle(NinoColor.textSecondary)
                SettingsField(placeholder: pending.suggestedTitle, text: $title)
            }
            Grid(alignment: .leading, horizontalSpacing: NinoSpacing.l, verticalSpacing: NinoSpacing.s) {
                countRow("settings.packs.usable", pending.usable)
                countRow("settings.packs.invalid", pending.invalid)
                countRow("settings.packs.duplicates", pending.duplicates)
                countRow("settings.packs.conflicts", pending.conflicts)
            }
            if pending.usable == 0 { NinoErrorLabel(text("settings.packs.empty")) }
            HStack {
                Spacer()
                Button { state.cancelGamePackImport() } label: { SText("settings.cancel") }
                    .buttonStyle(.nino(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    state.installGamePack(title: title.isEmpty ? pending.suggestedTitle : title, replacing: false)
                } label: { SText("settings.packs.install") }
                    .buttonStyle(.nino(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(pending.usable == 0)
            }
        }
        .padding(NinoSpacing.xl)
        .frame(width: 440)
        .ninoScreen()
        .onAppear { title = pending.suggestedTitle }
    }

    private func countRow(_ key: String, _ value: Int) -> some View {
        GridRow {
            SText(key).foregroundStyle(NinoColor.textSecondary)
            Text(verbatim: value.formatted(.number.locale(locale))).monospacedDigit().fontWeight(.semibold)
        }
    }
}

// MARK: - Altyazı alanı (§14.4)

struct SubtitleAreaSettings: View {
    let state: AppState
    @Environment(\.locale) private var locale

    private func text(_ key: String) -> String { SettingsText.string(key, locale) }

    private var preset: Binding<AreaPreset> {
        Binding(get: { state.settings.areaPreset ?? AreaPreset.custom }, set: { preset in
            var settings = state.settings
            settings.areaPreset = preset
            if let region = preset.region { settings.region = region }
            state.settings = settings
        })
    }

    private var region: Binding<Region> {
        Binding(get: { state.settings.region }, set: { region in
            var settings = state.settings
            settings.region = region
            settings.areaPreset = .custom
            state.settings = settings
        })
    }

    var body: some View {
        NinoCard {
            NinoSegmentedPicker(selection: preset, options: [
                .init(.bottom, title: text("settings.area.bottom")), .init(.top, title: text("settings.area.top")),
                .init(.full, title: text("settings.area.full")), .init(.custom, title: text("settings.area.custom")),
            ])
            RegionEditor(frame: state.settingsStatus.lastFrame, region: region)
            if preset.wrappedValue == .custom {
                SettingsSliderRow(title: text("settings.area.vertical"), value: percent(\.top, range: 0...95),
                                  range: 0...95, minLabel: "", maxLabel: "",
                                  valueText: SettingsText.string("settings.area.percent %lld", locale,
                                                                 Int((state.settings.region.top * 100).rounded())))
                SettingsSliderRow(title: text("settings.area.height"), value: heightPercent, range: 5...100,
                                  minLabel: "", maxLabel: "",
                                  valueText: SettingsText.string("settings.area.percent %lld", locale,
                                                                 Int((state.settings.region.height * 100).rounded())))
                Button { preset.wrappedValue = .bottom } label: { SText("settings.area.reset") }
                    .buttonStyle(.nino(.secondary))
            }
            SHint("settings.area.fitHint")
            SHint("settings.area.dragHint")
        }
        ExtraAreasCard(state: state)
        NinoCard(title: text("settings.area.translateScreen")) {
            SHint("settings.area.translateScreenHint")
        }
    }

    /// Dikey konum: üst kenar yüzdesi; yükseklik korunur, alt kenar 1'i geçmez.
    private func percent(_ path: WritableKeyPath<Region, Double>, range: ClosedRange<Int>) -> Binding<Int> {
        Binding(get: { Int((state.settings.region.top * 100).rounded()) }, set: { value in
            var r = state.settings.region
            let height = r.height
            r.top = min(Double(value) / 100, 1 - height)
            r.bottom = r.top + height
            region.wrappedValue = r
        })
    }

    private var heightPercent: Binding<Int> {
        Binding(get: { Int((state.settings.region.height * 100).rounded()) }, set: { value in
            var r = state.settings.region
            r.bottom = min(1, r.top + max(Region.minimumSize, Double(value) / 100))
            region.wrappedValue = r
        })
    }
}

/// Son PS5 karesi üstünde sürüklenip köşeden boyutlanan bölge çerçevesi.
struct RegionEditor: View {
    let frame: CGImage?
    @Binding var region: Region
    var dimmed: Bool = false
    var height: CGFloat = 220
    @State private var dragStart: Region?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        GeometryReader { proxy in
            let size = proxy.size
            let rect = CGRect(x: region.left * size.width, y: region.top * size.height,
                              width: region.width * size.width, height: region.height * size.height)
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                } else {
                    GameSceneBackground()
                    SText("settings.area.noFrame")
                        .font(.nino(.callout)).foregroundStyle(Color.white.opacity(0.8))
                        .frame(width: size.width, height: size.height * 0.4)
                }
                Rectangle()
                    .fill(NinoColor.accent.opacity(0.18))
                    .overlay(Rectangle().strokeBorder(NinoColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .gesture(DragGesture().onChanged { value in move(by: value.translation, in: size) }
                        .onEnded { _ in dragStart = nil })
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(NinoColor.accent, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: rect.maxX - 7, y: rect.maxY - 7)
                    .gesture(DragGesture().onChanged { value in resize(by: value.translation, in: size) }
                        .onEnded { _ in dragStart = nil })
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxHeight: height)
        .clipShape(shape)
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    private func move(by translation: CGSize, in size: CGSize) {
        let start = dragStart ?? region
        dragStart = start
        let dx = translation.width / size.width, dy = translation.height / size.height
        let left = min(max(0, start.left + dx), 1 - start.width)
        let top = min(max(0, start.top + dy), 1 - start.height)
        region = Region(top: top, bottom: top + start.height, left: left, right: left + start.width)
    }

    private func resize(by translation: CGSize, in size: CGSize) {
        let start = dragStart ?? region
        dragStart = start
        let right = min(1, max(start.left + Region.minimumSize, start.right + translation.width / size.width))
        let bottom = min(1, max(start.top + Region.minimumSize, start.bottom + translation.height / size.height))
        region = Region(top: start.top, bottom: bottom, left: start.left, right: right)
    }
}

private struct ExtraAreasCard: View {
    let state: AppState
    @Environment(\.locale) private var locale

    private func text(_ key: String) -> String { SettingsText.string(key, locale) }

    enum Place: String, CaseIterable { case quest, notification, phone, custom
        var region: Region? {
            switch self {
            case .quest: return ExtraArea.questPreset
            case .notification: return ExtraArea.notificationPreset
            case .phone: return ExtraArea.phonePreset
            case .custom: return nil
            }
        }
        static func matching(_ region: Region) -> Place {
            for place in [Place.quest, .notification, .phone] where place.region == region { return place }
            return .custom
        }
    }

    var body: some View {
        NinoCard(title: text("settings.area.extra")) {
            SHint("settings.area.extraHint")
            ForEach(state.settings.extraAreas) { area in
                areaEditor(area)
            }
            if state.settings.extraAreas.count < MacSettings.maxExtraAreas {
                Menu {
                    ForEach([Place.quest, .notification, .phone], id: \.self) { place in
                        Button(text("settings.area.place.\(place.rawValue)")) { add(place) }
                    }
                } label: {
                    Label { SText("settings.area.add") } icon: { Image(systemName: "plus") }
                }
                .menuStyle(.button)
                .fixedSize()
            }
        }
    }

    private func index(of id: String) -> Int? { state.settings.extraAreas.firstIndex { $0.id == id } }

    private func binding<V>(_ id: String, _ path: WritableKeyPath<ExtraArea, V>, fallback: V) -> Binding<V> {
        Binding(get: { index(of: id).map { state.settings.extraAreas[$0][keyPath: path] } ?? fallback },
                set: { value in if let i = index(of: id) { state.settings.extraAreas[i][keyPath: path] = value } })
    }

    private func areaEditor(_ area: ExtraArea) -> some View {
        VStack(alignment: .leading, spacing: NinoSpacing.s) {
            HStack(spacing: NinoSpacing.s) {
                SettingsField(placeholder: text("settings.area.name"), text: binding(area.id, \.name, fallback: ""))
                Button(role: .destructive) {
                    state.settings.extraAreas.removeAll { $0.id == area.id }
                } label: { SText("settings.area.remove") }
                    .buttonStyle(.nino(.danger))
            }
            SettingsSwitch(title: text("settings.area.read"), isOn: binding(area.id, \.enabled, fallback: false))
            SettingsPickerRow(title: text("settings.area.preset"),
                              selection: Binding(get: { Place.matching(area.region) }, set: { place in
                                  if let region = place.region, let i = index(of: area.id) {
                                      state.settings.extraAreas[i].region = region
                                  }
                              }),
                              options: Place.allCases.map { ($0, text($0 == .custom ? "settings.area.custom"
                                                                                       : "settings.area.place.\($0.rawValue)")) })
            RegionEditor(frame: state.settingsStatus.lastFrame,
                         region: binding(area.id, \.region, fallback: ExtraArea.questPreset),
                         dimmed: !area.enabled, height: 160)
        }
        .padding(NinoSpacing.m)
        .background(NinoRadius.shape(NinoRadius.control).strokeBorder(NinoColor.glassEdge, lineWidth: 1))
    }

    private func add(_ place: Place) {
        let name = text("settings.area.default.\(place.rawValue)")
        state.settings.extraAreas.append(ExtraArea(name: name, region: place.region ?? ExtraArea.questPreset))
    }
}
