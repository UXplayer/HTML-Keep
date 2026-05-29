import Foundation
import SwiftUI

enum ProEntitlementMarketingFunnelPhase: Equatable {
    case idle
    case promoSnackbar
    case expired
}

@MainActor
final class ProEntitlementMarketingFunnelStore: ObservableObject {
    @Published private(set) var phase: ProEntitlementMarketingFunnelPhase = .idle
    @Published private(set) var discountStartDate: Date?
    @Published private(set) var cooldownStartDate: Date?
    @Published private(set) var now: Date = .now
    @Published private(set) var isPromoSnackbarDismissedInSession = false
    @Published private(set) var discountSheetPresentationRequestID: UUID?

    init(defaults: UserDefaults = .standard) {}

    var shouldShowPromoSnackbar: Bool { false }
    var hasActiveDiscountCountdown: Bool { false }
    var discountEndDate: Date? { nil }
    var remainingDiscountDuration: TimeInterval { 0 }
    var isInCooldown: Bool { false }
    var promoSnackbarCountdownText: String { "" }
    var discountCountdownText: String { "" }
    var debugMarketingFunnelSummary: String {
        AppStrings.localized("HTML Keep 社区版")
    }

    func updateProEntitlementStatus(hasProEntitlement: Bool) {}
    func updateAppReviewShield(isEnabled: Bool) {}
    func handlePaywallClosed() {}
    func noteDiscountSheetPresented() {}
    func dismissPromoSnackbarForCurrentSession() {}
    func dismissDiscountSheet() {}
    func notePurchaseCompleted() {}
    func clearDebugMarketingFunnelState() {}
    func refreshState() {
        now = .now
        phase = .idle
        discountSheetPresentationRequestID = nil
    }
}
