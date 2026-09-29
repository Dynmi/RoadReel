import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "English"
        }
    }

    var shortName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "EN"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }
}
