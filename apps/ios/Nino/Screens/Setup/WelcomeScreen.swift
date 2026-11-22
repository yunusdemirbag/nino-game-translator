// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import SwiftUI

/// İlk açılıştaki üç sayfalık karşılama.
struct WelcomeScreen: View {
    @Binding var target: String
    let onFinish: () -> Void
    @State private var page = 0

    var body: some View {
        NinoScreen {
            HStack(spacing: 10) {
                NinoLogo(size: 36)
                Spacer(minLength: 0)
                LanguageMenu(selection: $target)
                Button(L("ob.skip"), action: onFinish).buttonStyle(.ghost)
            }
            .frame(height: DS.Size.icon)
            .environment(\.layoutDirection, .leftToRight)
        } content: {
            TabView(selection: $page) {
                WelcomePage(title: L("ob.p1.title"), lead: L("ob.p1.body")) { SampleStage(target: target) }.tag(0)
                WelcomePage(title: L("ob.p2.title"), lead: L("ob.p2.body")) { PacksStage() }.tag(1)
                WelcomePage(title: L("ob.p3.title"), lead: L("ob.p3.body")) { ScreensStage() }.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(minHeight: 610)
        } footer: {
            PageIndicator(count: 3, current: page)
            Button(page < 2 ? L("ob.continue") : L("ob.start")) {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.primary)
        }
    }
}

private struct WelcomePage<Stage: View>: View {
    let title: String
    let lead: String
    @ViewBuilder let stage: () -> Stage

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DarkStage(height: 380, content: stage)
            HeroTitle(title: title, lead: lead)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

/// 1. sayfa: 2,8 sn'de bir değişen örnek altyazı.
private struct SampleStage: View {
    let target: String
    private let start = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let index = Int(context.date.timeIntervalSince(start) / 2.8)
            let line = SampleLines.line(index, for: target)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    Text(verbatim: line.source)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(verbatim: TextDirection.prepared(line.translation))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55)))
                        .subtitleDirection(for: line.translation)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: index)

                Text(L("ob.sample"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .padding(16)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// 2. sayfa: hazır paketler.
private struct PacksStage: View {
    private let games: [(String, Int)] = [("Grand Theft Auto V", 190), ("Red Dead Redemption 2", 195), ("Mafia", 18)]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(games, id: \.0) { game in
                GlassRow(symbol: "gamecontroller.fill", title: game.0, detail: L("ob.p2.lines", "\(game.1)")) {
                    FreeBadge(text: L("ob.free"))
                }
            }
        }
        .padding(18)
    }
}

/// 3. sayfa: altyazının görünebileceği ekranlar.
private struct ScreensStage: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                box(symbol: "tv", title: L("ob.p3.tv"), detail: L("ob.p3.tv.detail"))
                box(symbol: "iphone", title: L("ob.p3.phone"), detail: L("ob.p3.phone.detail"))
            }
            GlassRow(symbol: "wifi", title: L("ob.p3.wifi"), detail: L("ob.p3.wifi.detail"))
        }
        .padding(18)
    }

    private func box(symbol: String, title: String, detail: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.10)))
            Spacer(minLength: 0)
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .padding(16)
        .background(shape.fill(Color.white.opacity(0.07)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
