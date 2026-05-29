import Foundation
import SwiftUI

@MainActor
final class ProEntitlementStore: ObservableObject {
    @Published private(set) var proEntitlementState: ProEntitlementState = .free
    @Published private(set) var activeProEntitlementProductKind: ProEntitlementProductKind?
    @Published private(set) var currentEntitlementExpirationDate: Date?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var lastProductLoadErrorDescription: String?
    @Published private(set) var debugProEntitlementOverride: ProEntitlementDebugOverride = .followStoreKit

    init(defaults: UserDefaults = .standard) {}

    var hasProEntitlement: Bool { true }
    var isSubscribed: Bool { false }
    var canUseCloudSync: Bool { false }
    var canUseAgentAutomation: Bool { true }
    var canViewFullRecentlyDeleted: Bool { true }
    var canBindMultipleWidgetProjects: Bool { true }
    var isUsingDebugProEntitlementOverride: Bool { false }
    var debugProEntitlementOverrideSummary: String? { nil }
    var hasManageableSubscription: Bool { false }
    var presentationState: ProEntitlementPresentationState { .communityEdition }
    var destination: ProEntitlementDestination { .status }

    var presentation: ProEntitlementPresentation {
        ProEntitlementPresentation(
            title: AppStrings.localized("HTML Keep 社区版"),
            subtitle: AppStrings.localized("本地高级功能已开放"),
            badgeText: nil,
            highlights: [],
            ctaTitle: AppStrings.localized("查看社区版说明"),
            style: .community
        )
    }

    var currentProEntitlementDisplayName: String {
        AppStrings.localized("HTML Keep 社区版")
    }

    var currentProEntitlementStatusLine: String {
        AppStrings.localized("本地功能已开放，不代表官方 Pro 权益，也不包含官方 iCloud 同步。")
    }

    var availableProEntitlementProductKinds: [ProEntitlementProductKind] { [] }
    var preferredProEntitlementProductKind: ProEntitlementProductKind { .yearly }
    var yearlyPriceDescription: String { AppStrings.localized("社区版") }
    var monthlyPriceDescription: String { AppStrings.localized("社区版") }
    var lifetimePriceDescription: String { AppStrings.localized("社区版") }
    var lifetimePromoPriceDescription: String { AppStrings.localized("社区版") }
    var discountBadgeText: String { AppStrings.localized("社区版") }
    var discountSnackbarDiscountText: String? { nil }
    var discountSnackbarFullOfferText: String { "" }
    var discountSnackbarCompactOfferText: String { "" }
    var discountSnackbarFallbackText: String { "" }

    func priceDescription(for kind: ProEntitlementProductKind) -> String {
        AppStrings.localized("社区版")
    }

    func productDescription(for kind: ProEntitlementProductKind) -> String {
        AppStrings.localized("HTML Keep 社区版")
    }

    func monthlyEquivalentDescription(for kind: ProEntitlementProductKind) -> String? {
        nil
    }

    func purchaseCallToActionTitle(for kind: ProEntitlementProductKind) -> String {
        AppStrings.localized("社区版已开放")
    }

    func paywallPrimaryTitle(for kind: ProEntitlementProductKind) -> String {
        AppStrings.localized("社区版已开放")
    }

    func refresh() async {
        proEntitlementState = .free
    }

    func purchaseYearlySubscription() async throws -> ProEntitlementPurchaseOutcome {
        .success
    }

    func purchaseMonthlySubscription() async throws -> ProEntitlementPurchaseOutcome {
        .success
    }

    func purchaseLifetime() async throws -> ProEntitlementPurchaseOutcome {
        .success
    }

    func purchaseLifetimePromo() async throws -> ProEntitlementPurchaseOutcome {
        .success
    }

    func restorePurchases() async throws {
        proEntitlementState = .free
    }

    func setDebugProEntitlementOverride(_ override: ProEntitlementDebugOverride) async {
        debugProEntitlementOverride = .followStoreKit
    }

    func clearDebugProEntitlementHistory() async {
        proEntitlementState = .free
    }
}
