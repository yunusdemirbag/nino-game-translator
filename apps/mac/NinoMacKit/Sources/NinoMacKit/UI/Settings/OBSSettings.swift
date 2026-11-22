// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

// OBS katmanı (ayarlar.md §8) ve gizli Arayüz bölümü (§14.1).

struct OBSSettings: View {
    let state: AppState
    @Environment(\.locale) private var locale

    private var port: Int { state.settingsStatus.overlayServerPort }

    var body: some View {
        NinoCard {
            SHint("settings.obs.hint")
            SettingsCopyRow(address: "http://localhost:\(port)/obs")
            SHint("settings.obs.otherComputer")
            if let address = state.settingsStatus.networkAddress {
                SHint("settings.obs.noLocalhost")
                SettingsCopyRow(address: "http://\(address):\(port)/obs")
            }
        }
        NinoCard(title: SettingsText.string("settings.obs.stream", locale)) {
            SHint("settings.obs.streamHint")
            SettingsSmallHeader(text: SettingsText.string("settings.obs.background", locale))
            NinoSegmentedPicker(selection: Binding(get: { state.streamBackground }, set: { state.streamBackground = $0 }),
                                options: [
                                    .init(.green, title: SettingsText.string("settings.obs.green", locale)),
                                    .init(.black, title: SettingsText.string("settings.obs.black", locale)),
                                    .init(.magenta, title: SettingsText.string("settings.obs.magenta", locale)),
                                ])
            Button {
                state.streamWindowOpen.toggle()
            } label: {
                SText(state.streamWindowOpen ? "settings.obs.close" : "settings.obs.open")
            }
            .buttonStyle(.nino(.secondary))
            SHint("settings.obs.keepOpen")
        }
    }
}

// MARK: - Arayüz (§14.1)

struct InterfaceSettings: View {
    let state: AppState
    @Environment(\.locale) private var locale

    var body: some View {
        NinoCard(title: SettingsText.string("settings.interface.home", locale)) {
            HStack(alignment: .top, spacing: NinoSpacing.m) {
                HomeStyleOption(style: .livingRoom, state: state, titleKey: "settings.interface.livingRoom",
                                detailKey: "settings.interface.livingRoomHint")
                HomeStyleOption(style: .toggle, state: state, titleKey: "settings.interface.toggle",
                                detailKey: "settings.interface.toggleHint")
            }
        }
        NinoCard {
            SettingsSmallHeader(text: SettingsText.string("settings.interface.appearance", locale))
            NinoSegmentedPicker(selection: Binding(get: { state.settings.appearance },
                                                   set: { state.settings.appearance = $0 }),
                                options: [
                                    .init(.dark, title: SettingsText.string("settings.interface.dark", locale),
                                          systemImage: "moon.fill"),
                                    .init(.light, title: SettingsText.string("settings.interface.light", locale),
                                          systemImage: "sun.max.fill"),
                                    .init(.system, title: SettingsText.string("settings.interface.system", locale),
                                          systemImage: "circle.lefthalf.filled"),
                                ])
        }
    }
}

private struct HomeStyleOption: View {
    let style: MacSettings.HomeStyle
    let state: AppState
    let titleKey: String
    let detailKey: String

    private var selected: Bool { state.settings.homeStyle == style }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button {
            state.settings.homeStyle = style
        } label: {
            VStack(alignment: .leading, spacing: NinoSpacing.s) {
                preview
                HStack(spacing: NinoSpacing.s) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.textSecondary))
                    SText(titleKey).fontWeight(.bold)
                }
                SText(detailKey).font(.nino(.callout)).foregroundStyle(NinoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(NinoSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(shape.strokeBorder(selected ? AnyShapeStyle(NinoColor.accent) : AnyShapeStyle(NinoColor.glassEdge),
                                        lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            shape.fill(NinoRGB(0.04, 0.08, 0.20).color)
            switch style {
            case .livingRoom:
                NinoAsset.livingRoom.image
                    .aspectRatio(contentMode: .fill)
                    .shadow(color: NinoRGB(0.18, 0.55, 1.0).color(opacity: 0.6), radius: 18)
            case .toggle:
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [NinoRGB(0.55, 0.60, 0.70).color, NinoRGB(0.25, 0.35, 0.55).color],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 150, height: 40)
                    Image(systemName: NinoSymbol.power)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(NinoRGB(0.04, 0.08, 0.20).color)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .offset(x: -5)
                }
            }
        }
        .frame(height: 130)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
    }
}
