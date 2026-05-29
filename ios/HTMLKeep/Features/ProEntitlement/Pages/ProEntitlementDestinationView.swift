import SwiftUI

struct ProEntitlementDestinationView: View {
    let destination: ProEntitlementDestination

    var body: some View {
        switch destination {
        case .paywall:
            ProEntitlementPaywallPage()
                .accessibilityIdentifier("pro-entitlement-paywall-page")
        case .status:
            ProEntitlementStatusPage()
                .accessibilityIdentifier("pro-entitlement-status-page")
        }
    }
}
