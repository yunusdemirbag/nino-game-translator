// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import AppKit
import SwiftUI

/// Paketteki görseller (tasarim-dili.md §1, "Görseller"). Tek ölçek: 1 piksel = 1 nokta.
public enum NinoAsset: String, CaseIterable, Sendable {
    case logo = "Logo"
    case livingRoom = "LivingRoom"
    case livingRoomXbox = "LivingRoomXbox"
    case consolePS5 = "ConsolePS5"
    case consoleXbox = "ConsoleXbox"
    case tvOptionAndroid = "TVOptionAndroid"
    case tvOptionLGSamsung = "TVOptionLGSamsung"
    case tvOptionMac = "TVOptionMac"
    /// Nino maskotu (kurulumun çeviri adımındaki kütüphane kartı).
    case mascot = "Mascot"

    /// SwiftUI görseli (yeniden boyutlandırılabilir).
    public var image: Image {
        Image(rawValue, bundle: .module).resizable()
    }

    /// Piksel ölçüsü (nokta olarak).
    public var pixelSize: CGSize {
        switch self {
        case .logo: return CGSize(width: 512, height: 512)
        case .livingRoom: return CGSize(width: 1672, height: 941)
        case .livingRoomXbox: return CGSize(width: 1671, height: 941)
        case .consolePS5: return CGSize(width: 500, height: 870)
        case .consoleXbox: return CGSize(width: 970, height: 270)
        case .tvOptionAndroid: return CGSize(width: 360, height: 296)
        case .tvOptionLGSamsung: return CGSize(width: 351, height: 360)
        case .tvOptionMac: return CGSize(width: 360, height: 330)
        case .mascot: return CGSize(width: 342, height: 400)
        }
    }
}

/// "Nino'ya Sor" robotunun görselleri (Resources/Bot).
public enum NinoBotImage: String, CaseIterable, Sendable {
    case open = "nino-bot-256"
    case blink = "nino-bot-blink-256"

    public var nsImage: NSImage? {
        Bundle.module.url(forResource: rawValue, withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    public var image: Image {
        if let nsImage { return Image(nsImage: nsImage).resizable() }
        return Image(systemName: "face.smiling").resizable()
    }
}
