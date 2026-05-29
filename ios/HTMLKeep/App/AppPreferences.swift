import Foundation
import SwiftUI

enum AppPreferenceKeys {
    static let language = "app_language_preference"
    static let appearance = "app_appearance_preference"
    static let iCloudSyncEnabled = "icloud_sync_enabled"
    static let homeDisplayMode = "home_display_mode"
    static let expertModeEnabled = "expert_mode_enabled"
    static let agentImportGuideCompleted = "agent_import_guide_completed"
}

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case automatic
    case english
    case zhHans
    case zhHant
    case japanese
    case german
    case french
    case spanish
    case korean
    case italian
    case dutch
    case portuguese
    case russian
    case arabic
    case hindi
    case bengali
    case urdu

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .automatic: return "自动"
        case .english: return "English"
        case .zhHans: return "简体中文"
        case .hindi: return "हिन्दी"
        case .spanish: return "Español"
        case .french: return "Français"
        case .arabic: return "العربية"
        case .bengali: return "বাংলা"
        case .russian: return "Русский"
        case .portuguese: return "Português"
        case .urdu: return "اردو"
        case .japanese: return "日本語"
        case .german: return "Deutsch"
        case .korean: return "한국어"
        case .italian: return "Italiano"
        case .dutch: return "Nederlands"
        case .zhHant: return "繁體中文"
        }
    }

    var locale: Locale? {
        switch self {
        case .automatic:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .hindi:
            return Locale(identifier: "hi")
        case .spanish:
            return Locale(identifier: "es")
        case .french:
            return Locale(identifier: "fr")
        case .arabic:
            return Locale(identifier: "ar")
        case .bengali:
            return Locale(identifier: "bn")
        case .russian:
            return Locale(identifier: "ru")
        case .portuguese:
            return Locale(identifier: "pt-BR")
        case .urdu:
            return Locale(identifier: "ur")
        case .japanese:
            return Locale(identifier: "ja")
        case .german:
            return Locale(identifier: "de")
        case .korean:
            return Locale(identifier: "ko")
        case .italian:
            return Locale(identifier: "it")
        case .dutch:
            return Locale(identifier: "nl")
        case .zhHant:
            return Locale(identifier: "zh-Hant")
        }
    }

    var localizationResourceName: String? {
        switch self {
        case .automatic:
            return nil
        case .english:
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .hindi:
            return "hi"
        case .spanish:
            return "es"
        case .french:
            return "fr"
        case .arabic:
            return "ar"
        case .bengali:
            return "bn"
        case .russian:
            return "ru"
        case .portuguese:
            return "pt-BR"
        case .urdu:
            return "ur"
        case .japanese:
            return "ja"
        case .german:
            return "de"
        case .korean:
            return "ko"
        case .italian:
            return "it"
        case .dutch:
            return "nl"
        case .zhHant:
            return "zh-Hant"
        }
    }

    var layoutDirection: LayoutDirection? {
        switch self {
        case .automatic:
            return nil
        case .arabic, .urdu:
            return .rightToLeft
        case .english, .zhHans, .hindi, .spanish, .french, .bengali, .russian, .portuguese, .japanese, .german, .korean, .italian, .dutch, .zhHant:
            return .leftToRight
        }
    }

    var usesChineseDiscountStyle: Bool {
        switch self {
        case .zhHans, .zhHant:
            return true
        case .automatic:
            return Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
        case .english, .hindi, .spanish, .french, .arabic, .bengali, .russian, .portuguese, .urdu, .japanese, .german, .korean, .italian, .dutch:
            return false
        }
    }

    static func value(for rawValue: String) -> AppLanguagePreference {
        AppLanguagePreference(rawValue: rawValue) ?? .automatic
    }

    func localizedString(for key: String) -> String {
        guard let resourceName = localizationResourceName,
              let path = Bundle.main.path(forResource: resourceName, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        }

        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .automatic: return "自动"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func value(for rawValue: String) -> AppAppearancePreference {
        AppAppearancePreference(rawValue: rawValue) ?? .automatic
    }
}

enum HomeDisplayMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .list: return "列表"
        case .grid: return "图标"
        }
    }

    var layoutTitleKey: String {
        switch self {
        case .list: return "列表"
        case .grid: return "网格"
        }
    }

    var toggleTitleKey: String {
        switch self {
        case .list: return "切换到图标视图"
        case .grid: return "切换到列表视图"
        }
    }

    var toggleSystemImage: String {
        switch self {
        case .list: return "square.grid.2x2"
        case .grid: return "list.bullet"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }

    var toggled: HomeDisplayMode {
        switch self {
        case .list: return .grid
        case .grid: return .list
        }
    }

    static func value(for rawValue: String) -> HomeDisplayMode {
        HomeDisplayMode(rawValue: rawValue) ?? .list
    }
}

enum AppStrings {
    static func localized(_ key: String) -> String {
        currentLanguagePreference.localizedString(for: key)
    }

    static var usesChineseDiscountStyle: Bool {
        currentLanguagePreference.usesChineseDiscountStyle
    }

    private static var currentLanguagePreference: AppLanguagePreference {
        let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKeys.language)
            ?? AppLanguagePreference.automatic.rawValue
        return AppLanguagePreference.value(for: rawValue)
    }
}
