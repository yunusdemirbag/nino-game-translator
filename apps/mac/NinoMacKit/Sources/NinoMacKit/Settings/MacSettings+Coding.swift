// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

extension MacSettings {
    /// Saklanan JSON'dan okur. Bozuk ya da nesne olmayan veri için `nil`.
    public static func decode(_ data: Data) -> MacSettings? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), let fields = value.object else { return nil }
        return MacSettings(fields: fields)
    }

    /// Saklanacak JSON. Tanınmayan alanlar da yazılır; anahtarlar sıralıdır.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(JSONValue.object(fields))) ?? Data("{}".utf8)
    }

    init(fields: [String: JSONValue]) {
        self.init()
        var r = FieldReader(fields)
        if let o = r.object("region"), let v = Region(fields: o) { region = v }
        areaPreset = r.choice("areaPreset")
        if let list = r.array("extraAreas") { extraAreas = list.compactMap { $0.object.map(ExtraArea.init(fields:)) } }
        if let o = r.object("style") { style = SubtitleStyle(fields: o) }
        sourceLanguage = r.string("sourceLanguage") ?? sourceLanguage
        targetLanguage = r.string("targetLanguage") ?? targetLanguage
        onlineTranslation = r.bool("onlineTranslation") ?? onlineTranslation
        if let engine = r.string("onlineEngine") {
            // Eski "ücretsiz" seçeneği artık yok; yerine DeepL.
            onlineEngine = engine == "free" ? .deepl : (OnlineEngine(rawValue: engine) ?? .deepl)
        }
        geminiModel = r.string("geminiModel") ?? geminiModel
        openAIModel = r.string("openAIModel") ?? openAIModel
        claudeModel = r.string("claudeModel") ?? claudeModel
        localAIBaseURL = r.string("localAIBaseURL") ?? localAIBaseURL
        localAIModel = r.string("localAIModel") ?? localAIModel
        output = r.choice("output") ?? output
        overlayClickThrough = r.bool("overlayClickThrough") ?? overlayClickThrough
        videoSource = r.choice("videoSource") ?? videoSource
        gameConsole = r.choice("gameConsole") ?? gameConsole
        gamePacks = r.bool("gamePacks") ?? gamePacks
        sharePool = r.bool("sharePool") ?? sharePool
        autoReport = r.bool("autoReport") ?? autoReport
        translateCorners = r.bool("translateCorners") ?? translateCorners
        askGame = r.bool("askGame") ?? askGame
        showSpeakerNames = r.bool("showSpeakerNames") ?? showSpeakerNames
        fastSubtitleDetection = r.bool("fastSubtitleDetection") ?? fastSubtitleDetection
        subtitlesOnly = r.bool("subtitlesOnly") ?? subtitlesOnly
        xboxAudioOnDevice = r.bool("xboxAudioOnDevice") ?? xboxAudioOnDevice
        appearance = r.choice("appearance") ?? appearance
        homeStyle = r.choice("homeStyle") ?? homeStyle
        frameSource = r.string("frameSource") ?? frameSource
        remotePlayApp = r.choice("remotePlayApp") ?? remotePlayApp
        unknownFields = r.leftovers
    }

    var fields: [String: JSONValue] {
        var f = unknownFields
        f["region"] = region.json
        if let areaPreset { f["areaPreset"] = .string(areaPreset.rawValue) }
        f["extraAreas"] = .array(extraAreas.map(\.json))
        f["style"] = style.json
        f["sourceLanguage"] = .string(sourceLanguage)
        f["targetLanguage"] = .string(targetLanguage)
        f["onlineTranslation"] = .bool(onlineTranslation)
        f["onlineEngine"] = .string(onlineEngine.rawValue)
        f["geminiModel"] = .string(geminiModel)
        f["openAIModel"] = .string(openAIModel)
        f["claudeModel"] = .string(claudeModel)
        f["localAIBaseURL"] = .string(localAIBaseURL)
        f["localAIModel"] = .string(localAIModel)
        f["output"] = .string(output.rawValue)
        f["overlayClickThrough"] = .bool(overlayClickThrough)
        f["videoSource"] = .string(videoSource.rawValue)
        f["gameConsole"] = .string(gameConsole.rawValue)
        f["gamePacks"] = .bool(gamePacks)
        f["sharePool"] = .bool(sharePool)
        f["autoReport"] = .bool(autoReport)
        f["translateCorners"] = .bool(translateCorners)
        f["askGame"] = .bool(askGame)
        f["showSpeakerNames"] = .bool(showSpeakerNames)
        f["fastSubtitleDetection"] = .bool(fastSubtitleDetection)
        f["subtitlesOnly"] = .bool(subtitlesOnly)
        f["xboxAudioOnDevice"] = .bool(xboxAudioOnDevice)
        f["appearance"] = .string(appearance.rawValue)
        f["homeStyle"] = .string(homeStyle.rawValue)
        f["frameSource"] = .string(frameSource)
        f["remotePlayApp"] = .string(remotePlayApp.rawValue)
        return f
    }
}

extension Region {
    init?(fields: [String: JSONValue]) {
        guard let t = fields["top"]?.double, let b = fields["bottom"]?.double,
              let l = fields["left"]?.double, let r = fields["right"]?.double else { return nil }
        self.init(top: t, bottom: b, left: l, right: r)
    }

    var json: JSONValue {
        .object(["top": .number(top), "bottom": .number(bottom), "left": .number(left), "right": .number(right)])
    }
}

extension ExtraArea {
    init(fields: [String: JSONValue]) {
        self.init(id: fields["id"]?.string ?? UUID().uuidString,
                  name: fields["name"]?.string ?? "",
                  region: fields["region"]?.object.flatMap(Region.init(fields:)) ?? ExtraArea.questPreset,
                  enabled: fields["enabled"]?.bool ?? true)
    }

    var json: JSONValue {
        .object(["id": .string(id), "name": .string(name), "region": region.json, "enabled": .bool(enabled)])
    }
}

extension SubtitleStyle {
    init(fields: [String: JSONValue]) {
        self.init()
        var r = FieldReader(fields)
        fontSize = r.int("fontSize") ?? fontSize
        bottomPercent = r.int("bottomPercent") ?? bottomPercent
        placement = r.choice("placement") ?? placement
        background = r.int("background") ?? background
        displayMode = r.choice("displayMode") ?? displayMode
        stackPrevious = r.bool("stackPrevious") ?? stackPrevious
        autoSize = r.bool("autoSize") ?? autoSize
        // Görünüş ayarları sadeleşti: yazı tipi, kalınlık, renk, tema, zemin şekli ve Nino işareti artık
        // seçilmiyor, hep varsayılanda. Kayıtlı değerleri okunmaz; `unknownFields`'ta olduğu gibi kalır ve
        // yazarken geri konur (eski sürüme dönen kullanıcı seçimini bulur).
        unknownFields = r.leftovers
    }

    var json: JSONValue {
        var f = unknownFields
        f["fontSize"] = .number(Double(fontSize))
        f["bottomPercent"] = .number(Double(bottomPercent))
        f["placement"] = .string(placement.rawValue)
        f["background"] = .number(Double(background))
        f["displayMode"] = .string(displayMode.rawValue)
        f["stackPrevious"] = .bool(stackPrevious)
        f["autoSize"] = .bool(autoSize)
        return .object(f)
    }
}
