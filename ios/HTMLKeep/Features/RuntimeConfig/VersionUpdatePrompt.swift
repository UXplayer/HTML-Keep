import SwiftUI

enum VersionUpdatePromptPresentation: Equatable {
    case softPrompt(VersionUpdatePromptPayload)
    case forcePrompt(VersionUpdatePromptPayload)
}

struct VersionUpdatePromptPayload: Codable, Equatable, Identifiable {
    var id: Int64 { configVersion }

    let title: String
    let message: String
    let appStoreURL: String?
    let testFlightURL: String?
    let softVersion: String?
    let forceVersion: String?
    let configVersion: Int64
}

@MainActor
final class VersionUpdatePromptStore: ObservableObject {
    @Published private(set) var activePresentation: VersionUpdatePromptPresentation?

    init() {}

    func bootstrapAfterLaunchReady() {}
    func refreshIfNeeded(reason: String) {}
}

struct VersionUpdatePromptRuntimeHost: View {
    @ObservedObject var store: VersionUpdatePromptStore

    var body: some View {
        EmptyView()
    }
}
