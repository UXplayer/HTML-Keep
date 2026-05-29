import SwiftUI

enum ProEntitlementPalette {
    static let background = Color(red: 17 / 255, green: 19 / 255, blue: 25 / 255)
    static let surfaceLow = Color(red: 25 / 255, green: 27 / 255, blue: 33 / 255)
    static let surface = Color(red: 29 / 255, green: 31 / 255, blue: 38 / 255)
    static let surfaceHigh = Color(red: 40 / 255, green: 42 / 255, blue: 48 / 255)
    static let surfaceHighest = Color(red: 51 / 255, green: 53 / 255, blue: 59 / 255)
    static let primary = Color(red: 1.0, green: 193 / 255, blue: 7 / 255)
    static let primaryContainer = Color(red: 246 / 255, green: 197 / 255, blue: 0)
    static let onPrimary = Color(red: 61 / 255, green: 47 / 255, blue: 0)
    static let onSurface = Color(red: 226 / 255, green: 226 / 255, blue: 234 / 255)
    static let onSurfaceVariant = Color(red: 212 / 255, green: 197 / 255, blue: 171 / 255)
    static let outlineVariant = Color(red: 79 / 255, green: 70 / 255, blue: 50 / 255)
    static let link = Color(red: 88 / 255, green: 166 / 255, blue: 1.0)

}

enum ProEntitlementExternalLinks {
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")
    static var termsURL: URL? { currentLinkSet.termsURL }
    static var privacyURL: URL? { currentLinkSet.privacyURL }

    private struct LinkSet {
        let termsURL: URL?
        let privacyURL: URL?
    }

    private static var currentLinkSet: LinkSet {
        links(for: localePath)
    }

    private static func links(for localePath: String?) -> LinkSet {
        let localizedPrefix = localePath.map { "/\($0)" } ?? ""
        return LinkSet(
            termsURL: URL(string: "https://help.htmlkeep.com\(localizedPrefix)/legal/terms/"),
            privacyURL: URL(string: "https://help.htmlkeep.com\(localizedPrefix)/legal/privacy/")
        )
    }

    private static var localePath: String? {
        let explicitLocalePath = localePath(for: currentLanguagePreference)
        if currentLanguagePreference != .automatic {
            return explicitLocalePath
        }

        return Locale.preferredLanguages
            .lazy
            .compactMap(localePath(forLanguageIdentifier:))
            .first
    }

    private static var currentLanguagePreference: AppLanguagePreference {
        let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKeys.language)
            ?? AppLanguagePreference.automatic.rawValue
        return AppLanguagePreference.value(for: rawValue)
    }

    private static func localePath(for preference: AppLanguagePreference) -> String? {
        switch preference {
        case .automatic, .english:
            return nil
        case .zhHans:
            return "zh-hans"
        case .zhHant:
            return "zh-hant"
        case .japanese:
            return "ja"
        case .german:
            return "de"
        case .french:
            return "fr"
        case .spanish:
            return "es"
        case .korean:
            return "ko"
        case .italian:
            return "it"
        case .dutch:
            return "nl"
        case .portuguese:
            return "pt"
        case .russian:
            return "ru"
        case .arabic:
            return "ar"
        case .hindi:
            return "hi"
        case .bengali:
            return "bn"
        case .urdu:
            return "ur"
        }
    }

    private static func localePath(forLanguageIdentifier identifier: String) -> String? {
        let normalizedIdentifier = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalizedIdentifier.hasPrefix("zh-hant")
            || normalizedIdentifier.hasPrefix("zh-tw")
            || normalizedIdentifier.hasPrefix("zh-hk")
            || normalizedIdentifier.hasPrefix("zh-mo") {
            return "zh-hant"
        }

        if normalizedIdentifier.hasPrefix("zh") {
            return "zh-hans"
        }

        let languageCode = normalizedIdentifier.split(separator: "-").first.map(String.init)
        switch languageCode {
        case "ja":
            return "ja"
        case "de":
            return "de"
        case "fr":
            return "fr"
        case "es":
            return "es"
        case "ko":
            return "ko"
        case "it":
            return "it"
        case "nl":
            return "nl"
        case "pt":
            return "pt"
        case "ru":
            return "ru"
        case "ar":
            return "ar"
        case "hi":
            return "hi"
        case "bn":
            return "bn"
        case "ur":
            return "ur"
        default:
            return nil
        }
    }
}

struct ProEntitlementOptionCard: View {
    let kind: ProEntitlementProductKind
    let title: String
    let priceText: String
    let originalPriceText: String?
    let subtitle: String
    let badgeText: String?
    let countdownText: String?
    let isSelected: Bool

    init(
        kind: ProEntitlementProductKind,
        title: String,
        priceText: String,
        originalPriceText: String? = nil,
        subtitle: String,
        badgeText: String?,
        countdownText: String? = nil,
        isSelected: Bool
    ) {
        self.kind = kind
        self.title = title
        self.priceText = priceText
        self.originalPriceText = originalPriceText
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.countdownText = countdownText
        self.isSelected = isSelected
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(ProEntitlementPalette.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VStack(spacing: 1) {
                ProEntitlementPriceText(text: priceText, isSelected: isSelected)

                if let originalPriceText {
                    ProEntitlementPriceText(
                        text: originalPriceText,
                        isSelected: false,
                        size: .compact,
                        colorOverride: ProEntitlementPalette.onSurfaceVariant.opacity(0.46)
                    )
                        .strikethrough()
                }

                Text(subtitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(kind == .lifetimePromo ? ProEntitlementPalette.primary : ProEntitlementPalette.onSurfaceVariant.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let countdownText {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9, weight: .black))

                        Text(countdownText)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .foregroundStyle(ProEntitlementPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, badgeText == nil ? 16 : 20)
        .padding(.bottom, kind == .lifetimePromo ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: kind == .lifetimePromo ? 136 : 118)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(isSelected ? ProEntitlementPalette.surfaceHighest : ProEntitlementPalette.surfaceHigh)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    isSelected ? ProEntitlementPalette.primary : ProEntitlementPalette.outlineVariant.opacity(0.12),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .overlay(alignment: .top) {
            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(ProEntitlementPalette.onPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ProEntitlementPalette.primary)
                    .clipShape(Capsule())
                    .offset(y: -12)
            }
        }
        .shadow(color: isSelected ? ProEntitlementPalette.primary.opacity(0.25) : .clear, radius: 20, x: 0, y: 0)
        .shadow(color: isSelected ? Color.black.opacity(0.45) : .clear, radius: 24, x: 0, y: 12)
        .scaleEffect(isSelected ? 1.0 : 0.98)
    }
}

struct ProEntitlementPriceText: View {
    enum Size {
        case regular
        case compact
    }

    let text: String
    let isSelected: Bool
    var size: Size = .regular
    var colorOverride: Color? = nil

    private var priceColor: Color {
        if let colorOverride {
            return colorOverride
        }
        return isSelected ? ProEntitlementPalette.primary : ProEntitlementPalette.onSurface
    }

    private var prefixFontSize: CGFloat {
        size == .compact ? 8 : 11
    }

    private var numberFontSize: CGFloat {
        size == .compact ? 15 : 26
    }

    private var suffixFontSize: CGFloat {
        size == .compact ? 8 : 10
    }

    private var components: (prefix: String, number: String, suffix: String) {
        let digitSet = CharacterSet.decimalDigits
        guard let firstDigitIndex = text.firstIndex(where: { character in
            character.unicodeScalars.contains { digitSet.contains($0) }
        }),
            let lastDigitIndex = text.lastIndex(where: { character in
                character.unicodeScalars.contains { digitSet.contains($0) }
            })
        else {
            return ("", text, "")
        }

        let afterLastDigitIndex = text.index(after: lastDigitIndex)
        return (
            String(text[..<firstDigitIndex]),
            String(text[firstDigitIndex ... lastDigitIndex]),
            String(text[afterLastDigitIndex...])
        )
    }

    var body: some View {
        let components = components

        HStack(alignment: .lastTextBaseline, spacing: 1) {
            if !components.prefix.isEmpty {
                Text(components.prefix)
                    .font(.system(size: prefixFontSize, weight: .black))
            }

            Text(components.number)
                .font(.system(size: numberFontSize, weight: .black))

            if !components.suffix.isEmpty {
                Text(components.suffix)
                    .font(.system(size: suffixFontSize, weight: .bold))
            }
        }
        .foregroundStyle(priceColor)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
    }
}

struct ProEntitlementBenefitRow: View {
    let text: String
    var iconName: String = "checkmark.seal.fill"
    var accentColor: Color = ProEntitlementPalette.primary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 32, height: 32)

            Text(AppStrings.localized(text))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(ProEntitlementPalette.onSurface)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 8)
        }
        .frame(minHeight: 42)
        .accessibilityElement(children: .combine)
    }
}

struct ProEntitlementBenefitItem: Identifiable {
    let id: String
    let text: String
    let iconName: String
    let accentColor: Color
    let compactTitle: String?
    let compactSubtitle: String?

    init(
        text: String,
        iconName: String = "checkmark.seal.fill",
        accentColor: Color = ProEntitlementPalette.primary,
        compactTitle: String? = nil,
        compactSubtitle: String? = nil
    ) {
        self.id = "\(iconName)-\(text)"
        self.text = text
        self.iconName = iconName
        self.accentColor = accentColor
        self.compactTitle = compactTitle
        self.compactSubtitle = compactSubtitle
    }
}

enum ProEntitlementBenefitCatalog {
    static let communityCore: [ProEntitlementBenefitItem] = [
        ProEntitlementBenefitItem(
            text: "本地高级功能开放",
            iconName: "checkmark.seal.fill",
            compactTitle: "本地功能",
            compactSubtitle: "已开放"
        ),
        ProEntitlementBenefitItem(
            text: "Agent 自动化管理",
            iconName: "desktopcomputer",
            compactTitle: "Agent",
            compactSubtitle: "管理"
        ),
        ProEntitlementBenefitItem(
            text: "多项目桌面小组件",
            iconName: "square.grid.2x2.fill",
            compactTitle: "小组件",
            compactSubtitle: "多项目"
        ),
        ProEntitlementBenefitItem(
            text: "长期最近删除恢复",
            iconName: "clock.arrow.circlepath",
            compactTitle: "最近删除",
            compactSubtitle: "长期恢复"
        )
    ]

    static let proCore: [ProEntitlementBenefitItem] = [
        ProEntitlementBenefitItem(
            text: "iCloud 多设备同步",
            iconName: "icloud.fill",
            compactTitle: "iCloud",
            compactSubtitle: "同步"
        ),
        ProEntitlementBenefitItem(
            text: "Agent 自动化管理",
            iconName: "desktopcomputer",
            compactTitle: "Agent",
            compactSubtitle: "管理"
        ),
        ProEntitlementBenefitItem(
            text: "多项目桌面小组件",
            iconName: "square.grid.2x2.fill",
            compactTitle: "小组件",
            compactSubtitle: "多项目"
        ),
        ProEntitlementBenefitItem(
            text: "长期最近删除恢复",
            iconName: "clock.arrow.circlepath",
            compactTitle: "最近删除",
            compactSubtitle: "长期恢复"
        ),
        ProEntitlementBenefitItem(
            text: "更多后续功能",
            iconName: "gift.fill",
            compactTitle: "更多后续",
            compactSubtitle: "功能"
        )
    ]

    static let settingsCardPreview: [ProEntitlementBenefitItem] = [
        proCore[0],
        proCore[1],
        proCore[2],
        ProEntitlementBenefitItem(
            text: "查看更多 Pro 权益",
            iconName: "ellipsis.circle.fill",
            compactTitle: "查看更多",
            compactSubtitle: "Pro 权益"
        )
    ]
}

struct ProEntitlementBenefitList: View {
    let benefits: [ProEntitlementBenefitItem]
    var spacing: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            ForEach(benefits.indices, id: \.self) { index in
                let benefit = benefits[index]

                ProEntitlementBenefitRow(
                    text: benefit.text,
                    iconName: benefit.iconName,
                    accentColor: benefit.accentColor
                )

                if index < benefits.count - 1 {
                    Rectangle()
                        .fill(ProEntitlementPalette.outlineVariant.opacity(0.18))
                        .frame(height: 1)
                        .padding(.leading, 44)
                        .padding(.vertical, max(4, spacing * 0.24))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ProEntitlementPalette.surfaceLow.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(ProEntitlementPalette.outlineVariant.opacity(0.16), lineWidth: 1)
        )
    }
}

struct ProEntitlementSupportActionsView: View {
    let restoreTitle: String
    let isRestoreDisabled: Bool
    let onRestore: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                supportActionButtons
            }

            VStack(spacing: 8) {
                supportActionButtons
            }
        }
    }

    @ViewBuilder
    private var supportActionButtons: some View {
        Button(action: onRestore) {
            ProEntitlementSupportActionLabel(
                title: restoreTitle,
                isEnabled: !isRestoreDisabled
            )
        }
        .buttonStyle(.plain)
            .disabled(isRestoreDisabled)

        if let termsURL = ProEntitlementExternalLinks.termsURL {
            Link(destination: termsURL) {
                ProEntitlementSupportActionLabel(title: AppStrings.localized("订阅条款"))
            }
        }

        if let privacyURL = ProEntitlementExternalLinks.privacyURL {
            Link(destination: privacyURL) {
                ProEntitlementSupportActionLabel(title: AppStrings.localized("隐私政策"))
            }
        }
    }
}

struct ProEntitlementSupportActionLabel: View {
    let title: String
    var isEnabled = true

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(
                isEnabled
                    ? ProEntitlementPalette.link
                    : ProEntitlementPalette.link.opacity(0.45)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentShape(Rectangle())
    }
}

struct ProEntitlementHeroArtwork: View {
    var height: CGFloat
    var fadeHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .bottom) {
                ProEntitlementMascotImage()
                    .frame(width: width, height: height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: ProEntitlementPalette.background.opacity(0.76), location: 0.58),
                        .init(color: ProEntitlementPalette.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: fadeHeight)
                .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
        }
        .frame(height: height)
        .clipped()
    }
}

struct ProEntitlementMascotImage: View {
    var body: some View {
        Image("ProEntitlementMascot")
            .resizable()
            .scaledToFill()
    }
}
