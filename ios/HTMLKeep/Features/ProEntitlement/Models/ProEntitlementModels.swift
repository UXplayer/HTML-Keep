import Foundation

enum StoreKitProductLoadEnvironment {
    case xcodeLocalTesting
    case testFlightSandbox
    case appStoreProduction

    static var current: StoreKitProductLoadEnvironment {
        if AppBuildFlavor.current.isTestingBuild {
            return .xcodeLocalTesting
        }

        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testFlightSandbox
        }

        return .appStoreProduction
    }

    private var guidanceText: String {
        switch self {
        case .xcodeLocalTesting:
            return AppStrings.localized("proEntitlement.storeKit.guidance.xcodeLocalTesting")
        case .testFlightSandbox:
            return AppStrings.localized("proEntitlement.storeKit.guidance.testFlightSandbox")
        case .appStoreProduction:
            return AppStrings.localized("proEntitlement.storeKit.guidance.appStoreProduction")
        }
    }

    func productUnavailableMessage(productName: String, details: String?) -> String {
        guard AppBuildFlavor.current.isTestingBuild else {
            return AppStrings.localized("proEntitlement.storeKit.productLoadUnavailableMessage")
        }

        if let details, !details.isEmpty {
            return String(
                format: AppStrings.localized("proEntitlement.storeKit.productUnavailableWithDetailsFormat"),
                productName,
                details,
                guidanceText
            )
        }

        return String(
            format: AppStrings.localized("proEntitlement.storeKit.productUnavailableFormat"),
            productName,
            guidanceText
        )
    }

    func incompleteCatalogMessage(loadError: String) -> String {
        guard AppBuildFlavor.current.isTestingBuild else {
            return AppStrings.localized("proEntitlement.storeKit.productLoadUnavailableMessage")
        }

        return String(
            format: AppStrings.localized("proEntitlement.storeKit.incompleteCatalogFormat"),
            loadError,
            guidanceText
        )
    }
}

enum ProEntitlementStoreError: LocalizedError {
    case productUnavailable(productName: String, details: String?)
    case verificationFailed
    case unknownPurchaseResult

    var errorDescription: String? {
        switch self {
        case .productUnavailable(let productName, let details):
            return StoreKitProductLoadEnvironment.current.productUnavailableMessage(
                productName: productName,
                details: details
            )
        case .verificationFailed:
            return AppStrings.localized("Pro 权益结果校验失败，请稍后再试。")
        case .unknownPurchaseResult:
            return AppStrings.localized("这次购买没有返回可识别的结果，请稍后再试。")
        }
    }
}

enum ProEntitlementPurchaseOutcome {
    case success
    case pending
    case userCancelled
}

enum ProEntitlementState: Equatable {
    case unknown
    case free
    case active
    case expired
}

enum ProEntitlementPresentationState: Equatable {
    case communityEdition
    case officialProEntitlement(ProEntitlementState)
}

enum ProEntitlementDestination: String, Identifiable, Equatable {
    case paywall
    case status

    var id: String { rawValue }
}

enum ProEntitlementPresentationStyle: Equatable {
    case community
    case loading
    case free
    case active
    case expired
}

enum ProEntitlementDebugOverride: String, CaseIterable, Identifiable {
    case followStoreKit
    case free
    case expired
    case activeYearly
    case activeMonthly
    case activeLifetime

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .followStoreKit:
            return AppStrings.localized("debug.proEntitlement.override.followStoreKit.title")
        case .free:
            return AppStrings.localized("debug.proEntitlement.override.free.title")
        case .expired:
            return AppStrings.localized("debug.proEntitlement.override.expired.title")
        case .activeYearly:
            return AppStrings.localized("debug.proEntitlement.override.activeYearly.title")
        case .activeMonthly:
            return AppStrings.localized("debug.proEntitlement.override.activeMonthly.title")
        case .activeLifetime:
            return AppStrings.localized("debug.proEntitlement.override.activeLifetime.title")
        }
    }

    var detailText: String {
        switch self {
        case .followStoreKit:
            return AppStrings.localized("debug.proEntitlement.override.followStoreKit.detail")
        case .free:
            return AppStrings.localized("debug.proEntitlement.override.free.detail")
        case .expired:
            return AppStrings.localized("debug.proEntitlement.override.expired.detail")
        case .activeYearly:
            return AppStrings.localized("debug.proEntitlement.override.activeYearly.detail")
        case .activeMonthly:
            return AppStrings.localized("debug.proEntitlement.override.activeMonthly.detail")
        case .activeLifetime:
            return AppStrings.localized("debug.proEntitlement.override.activeLifetime.detail")
        }
    }
}

enum ProEntitlementProductKind: String, CaseIterable, Identifiable {
    case yearly
    case monthly
    case lifetime
    case lifetimePromo

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .yearly:
            return AppRuntimeConfiguration.string(
                forInfoKey: "HTMLKeepPremiumYearlyProductID",
                default: "com.htmlkeep.community.subscription.yearly"
            )
        case .monthly:
            return AppRuntimeConfiguration.string(
                forInfoKey: "HTMLKeepPremiumMonthlyProductID",
                default: "com.htmlkeep.community.subscription.monthly"
            )
        case .lifetime:
            return AppRuntimeConfiguration.string(
                forInfoKey: "HTMLKeepPremiumLifetimeProductID",
                default: "com.htmlkeep.community.lifetime"
            )
        case .lifetimePromo:
            return AppRuntimeConfiguration.string(
                forInfoKey: "HTMLKeepPremiumLifetimePromoProductID",
                default: "com.htmlkeep.community.lifetime.promo"
            )
        }
    }

    var storeKitName: String {
        switch self {
        case .yearly:
            return AppStrings.localized("年度会员")
        case .monthly:
            return AppStrings.localized("月度会员")
        case .lifetime:
            return AppStrings.localized("永久会员")
        case .lifetimePromo:
            return AppStrings.localized("限时永久会员")
        }
    }

    var proEntitlementDisplayName: String {
        switch self {
        case .yearly:
            return AppStrings.localized("年度会员")
        case .monthly:
            return AppStrings.localized("月度会员")
        case .lifetime, .lifetimePromo:
            return AppStrings.localized("永久会员")
        }
    }

    var purchaseButtonTitle: String {
        switch self {
        case .yearly, .monthly:
            return String(
                format: AppStrings.localized("proEntitlement.purchase.subscriptionCTAFormat"),
                proEntitlementDisplayName
            )
        case .lifetime:
            return AppStrings.localized("立即买断")
        case .lifetimePromo:
            return AppStrings.localized("立即买断")
        }
    }

    var footerDescription: String {
        switch self {
        case .yearly:
            return AppStrings.localized("自动续订")
        case .monthly:
            return AppStrings.localized("按月自动续订")
        case .lifetime:
            return AppStrings.localized("一次买断，不会过期")
        case .lifetimePromo:
            return AppStrings.localized("一次性付款，不自动续费")
        }
    }

    var priceLoadingPlaceholder: String {
        AppStrings.localized("价格待加载")
    }

    var isAutoRenewable: Bool {
        self == .yearly || self == .monthly
    }
}

struct ProEntitlementPresentationHighlight: Identifiable, Hashable {
    let id: String
    let standardText: String
    let compactText: String?

    init(id: String, standardText: String, compactText: String? = nil) {
        self.id = id
        self.standardText = standardText
        self.compactText = compactText
    }

    static func localized(
        id: String,
        standardKey: String,
        compactKey: String? = nil
    ) -> ProEntitlementPresentationHighlight {
        ProEntitlementPresentationHighlight(
            id: id,
            standardText: AppStrings.localized(standardKey),
            compactText: compactKey.map(AppStrings.localized)
        )
    }
}

struct ProEntitlementPresentation {
    let title: String
    let subtitle: String
    let badgeText: String?
    let highlights: [ProEntitlementPresentationHighlight]
    let ctaTitle: String
    let style: ProEntitlementPresentationStyle
}
