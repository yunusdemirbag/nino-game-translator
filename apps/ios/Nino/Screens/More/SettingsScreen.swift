// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI
import UIKit

/// Ayarlar: çeviri dili ve motoru, altyazı görünümü, okunan alanlar, giriş şifresi, cihaz bilgileri.
struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [Route]
    @State private var askNino = false
    @State private var report = false

    var body: some View {
        NinoScreen {
            BackHeader(L("settings.title"), onBack: { dismiss() })
        } content: {
            Tile {
                Text(L("settings.language")).font(DS.Font.headline)
                LanguageMenu(selection: $model.settings.targetLanguage, showsName: true)
                if !Languages.isTurkish(model.settings.targetLanguage) {
                    Text(L("settings.language.note"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                }
            }
            EngineTile()
            AppearanceTile()
            AreaTile()
            PasscodeTile()
            Tile(spacing: 0) {
                navRow("bolt.fill", tone: .pro, L("settings.packs"), detail: model.settings.gamePacks ? L("common.on") : L("common.off")) { path.append(.packs) }
                RowDivider()
                navRow("tv", L("settings.target"), detail: targetDetail) { path.append(.target) }
                RowDivider()
                navRow("arrow.down.app", L("tv.install.fromphone")) { path.append(.tvInstall) }
                RowDivider()
                navRow("gamecontroller", L("settings.ps5"), detail: model.console?.name) { path.append(.ps5) }
                RowDivider()
                navRow("bubble.left.and.text.bubble.right", L("ask.title")) { askNino = true }
                RowDivider()
                navRow("exclamationmark.bubble", L("report.title")) { report = true }
                RowDivider()
                navRow("info.circle", L("settings.about"), detail: AppInfo.version) { path.append(.about) }
            }
            DeviceInfoTile()
        } footer: {
            Button(L("tv.test.send")) { model.sendTestSubtitle() }.buttonStyle(.secondary)
        }
        .sheet(isPresented: $askNino) { AskNinoSheet() }
        .sheet(isPresented: $report) { ReportProblemSheet() }
    }

    private var targetDetail: String {
        if model.settings.output.showsOnPhone { return L("devices.thisphone") }
        if let tv = model.tv, model.hasPairedTV { return tv.name.isEmpty ? "TV" : tv.name }
        return L("devices.status.notsetup")
    }

    private func navRow(_ symbol: String, tone: Tone = .neutral, _ title: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow(symbol: symbol, tone: tone, title: title, detail: detail) { RowChevron() }
        }
        .buttonStyle(.plain)
    }
}

// MARK: Çeviri motoru

private struct EngineTile: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyText = ""
    @State private var checking = false
    @State private var failed = false

    private enum Choice: Hashable { case free, deepL, gemini, other }

    private var choice: Binding<Choice> {
        Binding(get: {
            guard model.settings.onlineTranslation else { return .free }
            switch model.settings.onlineEngine {
            case .deepL: return .deepL
            case .gemini: return .gemini
            default: return .other
            }
        }, set: { new in
            keyText = ""
            failed = false
            switch new {
            case .free: model.settings.onlineTranslation = false
            case .deepL: select(.deepL)
            case .gemini: select(.gemini)
            case .other: select(model.settings.onlineEngine == .claude ? .claude : .openAI)
            }
        })
    }

    private func select(_ e: TranslationEngine) {
        model.settings.onlineTranslation = true
        model.settings.onlineEngine = e
    }

    private var engine: TranslationEngine { model.settings.onlineEngine }
    private var saved: Bool { TranslationEngines.key(engine, store: model.store) != nil }

    var body: some View {
        Tile {
            Text(L("settings.engine")).font(DS.Font.headline)
            SegmentPicker(options: [(Choice.free, L("engine.price.free")), (.deepL, "DeepL"), (.gemini, "Gemini"), (.other, L("common.other"))],
                          selection: choice)
            if choice.wrappedValue == .other {
                SegmentPicker(options: [(TranslationEngine.openAI, "OpenAI"), (.claude, "Claude")],
                              selection: Binding(get: { engine == .claude ? .claude : .openAI }, set: { select($0) }))
            }
            if model.settings.onlineTranslation {
                keyField
                if checking { ProgressView().tint(DS.Palette.accent) }
                if failed { NoteLine(text: L("settings.engine.badkey")) }
            }
            Text(L("settings.engine.packnote"))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        }
    }

    private var keyField: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        let name = TranslationEngines.displayName(engine)
        return HStack(spacing: 8) {
            if saved {
                Text(L("settings.engine.key", name))
                Spacer(minLength: 0)
                Label(L("settings.engine.saved"), systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Palette.success)
                Button { model.removeKey(engine) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(L("settings.engine.removekey")))
            } else {
                SecureField(L("settings.engine.key", name), text: $keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(L("common.save")) { Task { await save() } }
                    .foregroundStyle(DS.Palette.accent)
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            }
        }
        .font(.system(size: 17))
        .padding(.horizontal, DS.Space.tile)
        .frame(minHeight: DS.Size.field)
        .background(shape.fill(DS.Palette.surface2))
        .overlay(shape.strokeBorder(DS.Palette.border, lineWidth: 1))
    }

    private func save() async {
        checking = true
        failed = false
        let ok = await model.saveKey(keyText.trimmingCharacters(in: .whitespacesAndNewlines), for: engine)
        checking = false
        if ok { keyText = "" } else { failed = true }
    }
}

// MARK: Altyazı görünümü

private struct AppearanceTile: View {
    @EnvironmentObject private var model: AppModel

    private var percent: Int { Int((Double(model.settings.style.fontSize) / 46 * 10).rounded()) * 10 }

    private var sample: String {
        let t = Languages.normalized(model.settings.targetLanguage)
        if t == "tr" { return "Dinliyor musun beni?" }
        return SampleLines.lines(for: t).first?.translation ?? "هل تستمع إليّ؟"
    }

    var body: some View {
        let style = $model.settings.style
        Tile {
            HStack {
                Text(L("settings.appearance")).font(DS.Font.headline)
                Spacer(minLength: 0)
                Text(percent.formatted(.percent.locale(Loc.locale).scale(1))).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
            Slider(value: Binding(get: { Double(percent) },
                                  set: { style.wrappedValue.fontSize = Int((46 * $0 / 100).rounded()) }),
                   in: 40...160, step: 10)
                .tint(DS.Palette.accent)
            preview
            Text(L("subtitle.font")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            FontGrid(selection: style.font)
            HStack {
                Text(L("subtitle.textcolor")).font(DS.Font.caption)
                Spacer(minLength: 0)
                colorDot(.white, "white", L("subtitle.color.white"))
                colorDot(DS.Palette.subtitleYellow, "yellow", L("subtitle.color.yellow"))
            }
            HStack {
                Text(L("subtitle.background")).font(DS.Font.caption)
                Spacer(minLength: 0)
                Text(model.settings.style.background.formatted(.percent.locale(Loc.locale).scale(1)))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
            Slider(value: Binding(get: { Double(model.settings.style.background) }, set: { style.wrappedValue.background = Int($0) }),
                   in: 0...100, step: 5)
                .tint(DS.Palette.accent)
            Text(L("subtitle.background.area")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            SegmentPicker(options: [("fit", L("subtitle.width.fit")), ("band", L("subtitle.band.full"))], selection: style.backgroundShape)
            Text(L("subtitle.background.solidhint"))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            if !model.settings.output.showsOnPhone {
                Text(L("settings.tvposition")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                SegmentPicker(options: [("cover", L("subtitle.layout.cover")), ("above", L("subtitle.layout.above")), ("below", L("subtitle.layout.below")), ("fixed", L("subtitle.position.fixed"))],
                              selection: style.placement)
                if model.settings.style.placement == "fixed" {
                    HStack {
                        Text(L("subtitle.height.screen")).font(DS.Font.caption)
                        Spacer(minLength: 0)
                        Text(model.settings.style.bottomPercent.formatted(.percent.locale(Loc.locale).scale(1)))
                            .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                    }
                    Slider(value: Binding(get: { Double(model.settings.style.bottomPercent) },
                                          set: { style.wrappedValue.bottomPercent = Int($0.rounded()) }),
                           in: 0...85, onEditingChanged: { editing in if !editing { model.sendTestSubtitle() } })
                        .tint(DS.Palette.accent)
                    Text(L("subtitle.position.hint"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                } else {
                    Text(L("subtitle.layout.hint"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                }
            }
            toggle(L("settings.stack.lines"),
                   L("settings.stack.detail"), style.stackPrevious)
            if !model.settings.output.showsOnPhone {
                Text(L("settings.picturemode")).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                SegmentPicker(options: [("inApp", L("target.inapp")), ("overlay", L("settings.picturemode.overlay"))], selection: style.displayMode)
                Text(L("settings.picturemode.hint"))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
            toggle(L("settings.watermark"),
                   L("settings.watermark.detail"), style.watermark)
        }
    }

    private var preview: some View {
        let size = (DS.isPad ? 36 : 28) * model.settings.style.scale
        let font = model.settings.style.font
        return Text(verbatim: TextDirection.prepared(sample))
            .font(font.font(size: size))
            .tracking(font.tracking(size: size))
            .foregroundStyle(model.settings.style.isYellow ? DS.Palette.subtitleYellow : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85)))
    }

    private func colorDot(_ color: Color, _ value: String, _ name: String) -> some View {
        let selected = model.settings.style.textColor == value
        return Button { model.settings.style.textColor = value } label: {
            Circle().fill(color)
                .overlay(Circle().strokeBorder(DS.Palette.borderStrong, lineWidth: 1))
                .frame(width: 28, height: 28)
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? DS.Palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.Font.headline)
                Text(detail).font(DS.Font.caption).foregroundStyle(DS.Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(DS.Palette.accent)
    }
}

/// 2×2 altyazı yazı tipi seçimi; her ad kendi yazı tipiyle.
struct FontGrid: View {
    @Binding var selection: SubtitleTypeface

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 4) {
            ForEach(SubtitleTypeface.allCases, id: \.self) { face in
                let selected = face == selection
                Button { selection = face } label: {
                    Text(face.title)
                        .font(face.font(size: 16))
                        .foregroundStyle(selected ? DS.Palette.text : DS.Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background { if selected { SelectedChip() } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.surface2))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: Altyazı alanı

private struct AreaTile: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Tile {
            Text(L("settings.region")).font(DS.Font.headline)
            SegmentPicker(options: [(AreaPreset.bottom, L("region.bottom")), (.top, L("region.top")), (.full, L("subtitle.width.full")), (.custom, L("common.custom"))],
                          selection: Binding(get: { model.settings.areaPreset }, set: { model.settings.selectAreaPreset($0) }))
            RegionEditor(region: Binding(get: { model.settings.region }, set: { model.settings.setCustomRegion($0) }),
                         frame: model.lastFrame)
            if model.settings.areaPreset == .custom {
                let r = model.settings.region
                let height = r.bottom - r.top
                sliderRow(L("subtitle.position.vertical"), value: r.top, range: 0...max(0.001, 1 - height)) { v in
                    var n = model.settings.region
                    n.top = v; n.bottom = v + height
                    model.settings.setCustomRegion(n.clamped())
                }
                sliderRow(L("subtitle.height"), value: height, range: 0.05...1) { v in
                    var n = model.settings.region
                    n.bottom = min(1, n.top + v)
                    model.settings.setCustomRegion(n.clamped())
                }
            }
            Text(L("region.edit.hint"))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        }
    }

    private func sliderRow(_ title: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(DS.Font.caption)
                Spacer(minLength: 0)
                Text(Int((value * 100).rounded()).formatted(.percent.locale(Loc.locale).scale(1)))
                    .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            }
            Slider(value: Binding(get: { value }, set: set), in: range).tint(DS.Palette.accent)
        }
    }
}

/// PS5 görüntüsü üstünde altyazının okunacağı bölge; sürüklenerek taşınır, köşesinden boyutlanır.
struct RegionEditor: View {
    @Binding var region: CropRegion
    var frame: CGImage?
    @State private var start: CropRegion?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let r = region
            ZStack(alignment: .topLeading) {
                if let frame {
                    Image(decorative: frame, scale: 1).resizable().frame(width: w, height: h)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(DS.Palette.bg)
                    Text(L("home.preview.empty"))
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
                        .multilineTextAlignment(.center).padding(12)
                        .frame(width: w, height: h)
                }
                Rectangle()
                    .fill(DS.Palette.accent.opacity(0.14))
                    .overlay(Rectangle().strokeBorder(DS.Palette.accent, lineWidth: 2))
                    .frame(width: (r.right - r.left) * w, height: (r.bottom - r.top) * h)
                    .offset(x: r.left * w, y: r.top * h)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let s = start ?? region
                        start = s
                        let dx = v.translation.width / w, dy = v.translation.height / h
                        let width = s.right - s.left, height = s.bottom - s.top
                        let left = min(max(0, s.left + dx), 1 - width), top = min(max(0, s.top + dy), 1 - height)
                        region = CropRegion(top: top, bottom: top + height, left: left, right: left + width)
                    }.onEnded { _ in start = nil })
                    .accessibilityLabel(Text(L("settings.region")))
                Rectangle()
                    .fill(DS.Palette.accent)
                    .frame(width: 14, height: 14)
                    .offset(x: r.right * w - 14, y: r.bottom * h - 14)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        let s = start ?? region
                        start = s
                        var n = s
                        n.right = s.right + v.translation.width / w
                        n.bottom = s.bottom + v.translation.height / h
                        region = n.clamped()
                    }.onEnded { _ in start = nil })
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: Giriş şifresi

private struct PasscodeTile: View {
    @EnvironmentObject private var model: AppModel
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        Tile {
            Text(L("passcode.title")).font(DS.Font.headline)
            HStack(spacing: 8) {
                if model.hasLoginPasscode {
                    Text(L("passcode.saved"))
                    Spacer(minLength: 0)
                    Button { model.removeLoginPasscode() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Palette.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(L("passcode.remove")))
                } else {
                    SecureField(L("passcode.placeholder"), text: $text)
                        .keyboardType(.numberPad)
                        .onChange(of: text) { _, new in
                            let d = String(new.filter { $0.isASCII && $0.isNumber }.prefix(4))
                            if d != new { text = d }
                        }
                    Button(L("common.save")) {
                        invalid = !model.saveLoginPasscode(text)
                        if !invalid { text = "" }
                    }
                    .foregroundStyle(DS.Palette.accent)
                    .disabled(text.isEmpty)
                }
            }
            .font(.system(size: 17))
            .padding(.horizontal, DS.Space.tile)
            .frame(minHeight: DS.Size.field)
            .background(shape.fill(DS.Palette.surface2))
            .overlay(shape.strokeBorder(DS.Palette.border, lineWidth: 1))
            if invalid { NoteLine(text: L("passcode.prompt")) }
            Text(L("passcode.note"))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
        }
    }
}

// MARK: Cihaz bilgileri

@MainActor
struct DeviceInfo {
    static func rows(_ model: AppModel) -> [(id: String, label: String, value: String)] {
        var rows: [(String, String, String)] = []
        let build = AppInfo.build
        rows.append(("app", L("diag.appversion"), build.isEmpty ? AppInfo.version : "\(AppInfo.version) (\(build))"))
        rows.append(("device", L("diag.devicemodel"), modelCode()))
        let v = ProcessInfo.processInfo.operatingSystemVersion
        rows.append(("system", L("diag.os"), "iOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")))
        if let tv = model.tv, model.hasPairedTV { rows.append(("tv", "TV", tv.brandName)) }
        if model.isXbox, let x = model.xboxConsole {
            rows.append(("console", L("devices.console"), x.model.isEmpty ? "Xbox" : "Xbox · \(x.model)"))
        } else if model.console != nil {
            rows.append(("console", L("devices.console"), "PS5 · Remote Play"))
        }
        if model.isRunning { rows.append(("status", L("diag.status.current"), model.consoleStatusText)) }
        return rows.map { ($0.0, $0.1, clean($0.2)) }.filter { !$0.2.isEmpty }
    }

    static func summary(_ model: AppModel) -> String {
        String(rows(model).map { "\($0.id): \($0.value)" }.joined(separator: " | ").prefix(600))
    }

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
        t = t.replacingOccurrences(of: #"\b\d{1,3}(\.\d{1,3}){3}(:\d+)?\b"#, with: "(adres)", options: .regularExpression)
        return t
    }

    static func modelCode() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

private struct DeviceInfoTile: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        Tile {
            Text(L("diag.deviceinfo")).font(DS.Font.headline)
            ForEach(DeviceInfo.rows(model), id: \.id) { row in
                HStack(alignment: .top) {
                    Text(row.label).foregroundStyle(DS.Palette.secondary)
                    Spacer(minLength: 8)
                    Text(verbatim: row.value).multilineTextAlignment(.trailing)
                }
                .font(DS.Font.caption)
            }
            Text(L("diag.deviceinfo.note"))
                .font(DS.Font.caption).foregroundStyle(DS.Palette.secondary)
            Button(copied ? L("common.copied") : L("diag.deviceinfo.copy")) {
                UIPasteboard.general.string = DeviceInfo.summary(model)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            }
            .buttonStyle(.secondary)
        }
    }
}
