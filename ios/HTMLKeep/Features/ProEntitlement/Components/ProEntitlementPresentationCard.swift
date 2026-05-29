import SwiftUI

struct ProEntitlementPresentationCard: View {
    let presentation: ProEntitlementPresentation
    private let cardCornerRadius: CGFloat = 12
    private let cardBackgroundImageAspectRatio: CGFloat = 1.5
    private let wideCardBackgroundHeightMultiplier: CGFloat = 2.0

    private var cardBackground: LinearGradient {
        let baseColor = Color(red: 45 / 255, green: 59 / 255, blue: 80 / 255)

        switch presentation.style {
        case .loading:
            return LinearGradient(
                colors: [baseColor.opacity(1.06), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .free:
            return LinearGradient(
                colors: [baseColor.opacity(1.04), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .community, .active:
            return LinearGradient(
                colors: [baseColor.opacity(1.02), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .expired:
            return LinearGradient(
                colors: [baseColor.opacity(1.02), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var shadowColor: Color {
        Color(red: 25 / 255, green: 39 / 255, blue: 58 / 255)
    }

    private var subtitleColor: Color {
        switch presentation.style {
        case .community, .active, .loading:
            return ProEntitlementPalette.onSurfaceVariant
        case .free, .expired:
            return ProEntitlementPalette.onSurfaceVariant.opacity(0.96)
        }
    }

    private var badgeBackgroundColor: Color {
        ProEntitlementPalette.surfaceHighest.opacity(presentation.style == .expired ? 0.96 : 1.0)
    }

    private var showsCTAButton: Bool {
        presentation.style == .free || presentation.style == .expired
    }

    var body: some View {
        Group {
            switch presentation.style {
            case .community, .active:
                compactCard
            case .loading, .free, .expired:
                detailCard
            }
        }
        .padding(showsCTAButton ? 20 : 18)
        .background(cardBackgroundView)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }

        .shadow(color: shadowColor.opacity(0.95), radius: 0, x: 0, y: 2)
    }

    private var cardBackgroundView: some View {
        ZStack {
            cardBackground

            GeometryReader { proxy in
                let cardWidth = max(proxy.size.width, 1)
                let cardHeight = max(proxy.size.height, 1)
                let cardAspectRatio = cardWidth / cardHeight
                let usesUpperSlice = cardAspectRatio > cardBackgroundImageAspectRatio
                let heightDrivenImageHeight = cardHeight * (usesUpperSlice ? wideCardBackgroundHeightMultiplier : 1)
                let widthDrivenImageHeight = cardWidth / cardBackgroundImageAspectRatio
                let imageHeight = max(heightDrivenImageHeight, widthDrivenImageHeight)
                let imageWidth = imageHeight * cardBackgroundImageAspectRatio

                Image("ProEntitlementSettingsCardBackground")
                    .resizable()
                    .frame(width: imageWidth, height: imageHeight)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .topTrailing
                    )
                    .clipped()
                    .opacity(0.96)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.30)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 8) {
                presentationTitleText(presentation.title)

                if let badgeText = presentation.badgeText {
                    Text(badgeText)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ProEntitlementPalette.onSurfaceVariant)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(badgeBackgroundColor)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 8)
            }

            if !presentation.subtitle.isEmpty {
                Text(presentation.subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subtitleColor)
            }

            if !presentation.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(presentation.highlights) { highlight in
                        ProEntitlementPresentationHighlightRow(highlight: highlight)
                    }
                }
            }

            if showsCTAButton {
                presentationCTA
                    .padding(.top, presentation.highlights.isEmpty ? 4 : 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                presentationTitleText(presentation.title)

                Text(presentation.subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(subtitleColor)
            }

            if presentation.style != .community {
                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(ProEntitlementPalette.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
    }

    private var presentationCTA: some View {
        AppActionButtonSurface(
            presentation.ctaTitle,
            scene: .premiumGold,
            size: .medium
        )
    }

    private func presentationTitleText(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .heavy))
            .multilineTextAlignment(.center)
            .foregroundColor(Color(red: 1, green: 0.76, blue: 0.03))
    }
}

private struct ProEntitlementPresentationHighlightRow: View {
    let highlight: ProEntitlementPresentationHighlight

    private var fallbackText: String {
        highlight.compactText ?? highlight.standardText
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rowContent(text: highlight.standardText, scalesToFit: false)
                .fixedSize(horizontal: true, vertical: false)

            rowContent(text: fallbackText, scalesToFit: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(highlight.standardText)
    }

    private func rowContent(text: String, scalesToFit: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ProEntitlementPalette.primary)

            label(text, scalesToFit: scalesToFit)
        }
    }

    @ViewBuilder
    private func label(_ text: String, scalesToFit: Bool) -> some View {
        let label = Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ProEntitlementPalette.primary.opacity(0.96))
            .lineLimit(1)

        if scalesToFit {
            label.minimumScaleFactor(0.78)
        } else {
            label
        }
    }
}
