import SwiftUI

struct ProEntitlementStatusPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var proEntitlementStore: ProEntitlementStore

    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            ProEntitlementPalette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ProEntitlementHeroArtwork(height: 270, fadeHeight: 160)
                        .padding(.bottom, -86)

                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Text(proEntitlementStore.currentProEntitlementDisplayName)
                                .font(.system(size: 32, weight: .black))
                                .foregroundStyle(ProEntitlementPalette.primary)
                                .shadow(color: ProEntitlementPalette.primary.opacity(0.35), radius: 18, x: 0, y: 0)

                            Text(statusBadgeText)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(ProEntitlementPalette.onPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(ProEntitlementPalette.primary)
                                .clipShape(Capsule())
                        }

                        Text(proEntitlementStore.currentProEntitlementStatusLine)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ProEntitlementPalette.onSurfaceVariant)
                    }

                    ProEntitlementBenefitList(
                        benefits: benefitItems,
                        spacing: 10
                    )
                        .padding(.horizontal, 16)

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    VStack(spacing: 14) {
                        if proEntitlementStore.presentationState != .communityEdition {
                            ProEntitlementSupportActionsView(
                                restoreTitle: AppStrings.localized(proEntitlementStore.isRestoring ? "正在恢复…" : "恢复购买"),
                                isRestoreDisabled: proEntitlementStore.isRestoring,
                                onRestore: {
                                    Task {
                                        await restorePurchases()
                                    }
                                }
                            )
                            .padding(.top, 2)
                        }

                        if proEntitlementStore.hasManageableSubscription {
                            proEntitlementManagementFooter
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .ignoresSafeArea(edges: .top)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ProEntitlementPalette.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel(AppStrings.localized("关闭"))

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await proEntitlementStore.refresh()
        }
    }

    private var statusBadgeText: String {
        switch proEntitlementStore.presentationState {
        case .communityEdition:
            return AppStrings.localized("社区版")
        case .officialProEntitlement:
            return AppStrings.localized("已开通")
        }
    }

    private var benefitItems: [ProEntitlementBenefitItem] {
        switch proEntitlementStore.presentationState {
        case .communityEdition:
            return ProEntitlementBenefitCatalog.communityCore
        case .officialProEntitlement:
            return ProEntitlementBenefitCatalog.proCore
        }
    }

    private var proEntitlementManagementFooter: some View {
        Group {
            if let manageURL = ProEntitlementExternalLinks.manageSubscriptionsURL {
                Text(.init(String(
                    format: AppStrings.localized("proEntitlement.manageSubscriptions.markdownFormat"),
                    manageURL.absoluteString
                )))
            } else {
                Text(AppStrings.localized("前往 App Store 管理自动续订或修改订阅设置。"))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(ProEntitlementPalette.onSurfaceVariant.opacity(0.70))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
    }

    private func restorePurchases() async {
        errorMessage = nil
        statusMessage = nil

        do {
            try await proEntitlementStore.restorePurchases()
            statusMessage = proEntitlementStore.hasProEntitlement
                ? AppStrings.localized("已重新同步当前账号下的 Pro 权益。")
                : AppStrings.localized("当前没有可恢复的 Pro 权益。")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
