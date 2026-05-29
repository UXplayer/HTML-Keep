import SwiftUI

struct ProEntitlementPromoSnackbar: View {
    let discountText: String?
    let fullOfferText: String
    let compactOfferText: String
    let fallbackText: String
    let remainingText: String
    let action: () -> Void
    let closeAction: () -> Void

    var body: some View {
        EmptyView()
    }
}
