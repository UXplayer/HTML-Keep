import SwiftUI

@MainActor
final class AppReviewShieldStore: ObservableObject {
    @Published private(set) var isEnabled = false

    init() {}

    func bootstrap() {}
    func refreshIfNeeded(reason: String) {}
}
