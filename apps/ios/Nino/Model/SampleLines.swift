// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

import Foundation

/// Nino'nun kendi örnek altyazıları (oyun metni değil): karşılama sahnesi ve PS5'siz deneme.
enum SampleLines {
    struct Line: Equatable, Sendable {
        let source: String
        let translation: String
    }

    private static let six: [(en: String, tr: String, ar: String)] = [
        ("Are you listening to me?", "Beni dinliyor musun?", "هل تستمع إليّ؟"),
        ("The bridge is out. Find another way.", "Köprü yıkılmış. Başka bir yol bul.", "الجسر مهدوم. ابحث عن طريق آخر."),
        ("Stay close and watch your step.", "Yakınımda kal, adımına dikkat et.", "ابقَ قريبًا مني وانتبه لخطواتك."),
        ("Wait for my signal at the old station.", "Eski istasyonda işaretimi bekle.", "انتظر إشارتي عند المحطة القديمة."),
        ("No one moves until I say so.", "Ben söyleyene kadar kimse kımıldamıyor.", "لا أحد يتحرك حتى أقول ذلك."),
        ("Relax, I know exactly what I'm doing.", "Rahat ol, ne yaptığımı çok iyi biliyorum.", "اهدأ، أعرف تمامًا ما أفعله."),
    ]

    private static let threeSources = ["Who's there?", "Footsteps. Get behind the wall.", "Run for the boat. Go!"]

    private static let three: [String: [String]] = [
        "hi": ["वहाँ कौन है?", "कदमों की आहट। दीवार के पीछे छिपो।", "नाव की ओर भागो। चलो!"],
        "id": ["Siapa di sana?", "Ada langkah kaki. Sembunyi di balik tembok.", "Lari ke perahu. Cepat!"],
        "th": ["ใครอยู่ตรงนั้น?", "มีเสียงฝีเท้า หลบหลังกำแพง", "วิ่งไปที่เรือ ไปเลย!"],
        "vi": ["Ai ở đó?", "Có tiếng bước chân. Nấp sau bức tường.", "Chạy ra thuyền. Đi!"],
        "ur": ["وہاں کون ہے؟", "قدموں کی آہٹ۔ دیوار کے پیچھے چھپ جاؤ۔", "کشتی کی طرف بھاگو۔ چلو!"],
        "bn": ["ওখানে কে?", "পায়ের শব্দ। দেয়ালের পেছনে লুকাও।", "নৌকার দিকে দৌড়াও। যাও!"],
        "ms": ["Siapa di sana?", "Ada bunyi tapak kaki. Sembunyi di sebalik dinding.", "Lari ke bot. Pergi!"],
        "tl": ["Sino'ng nandiyan?", "May yabag. Magtago ka sa likod ng pader.", "Tumakbo ka sa bangka. Bilis!"],
        "nl": ["Wie is daar?", "Voetstappen. Ga achter de muur.", "Ren naar de boot. Nu!"],
    ]

    /// Hedef dilin örnekleri: üç satırlık listesi olan dillerde o, yoksa Türkçe ya da Arapça altılı liste.
    static func lines(for target: String) -> [Line] {
        let code = Languages.normalized(target)
        if let list = three[code] {
            return zip(threeSources, list).map { Line(source: $0, translation: $1) }
        }
        let arabic = code == "ar"
        return six.map { Line(source: $0.en, translation: arabic ? $0.ar : $0.tr) }
    }

    /// Sıradaki satır.
    static func line(_ index: Int, for target: String) -> Line {
        let all = lines(for: target)
        return all[((index % all.count) + all.count) % all.count]
    }
}
