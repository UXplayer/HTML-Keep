import SwiftUI
import UIKit

struct HomeSearchOverlayView: View {
    @ObservedObject var model: HomeSearchOverlayModel
    let configuration: HomeSearchOverlayConfiguration
    let projectIconURL: (WebPage) -> URL?
    let hasFullContentSearchIndex: Bool
    let searchResults: (String, WebPageSearchScope) -> [WebPageSearchResult]
    let onSearchFullContent: () async -> Void
    let onSelectEntry: (WebPage, WebPageEntry) -> Void
    let onDismiss: (@escaping () -> Void) -> Void

    @State private var searchText = ""
    @State private var fullContentSearchEnabled = false
    @State private var isSearchingFullContent = false
    @State private var cachedSearchQuery = ""
    @State private var cachedSearchScope: WebPageSearchScope = .basic
    @State private var cachedSearchResults: [WebPageSearchResult] = []
    @State private var isUpdatingSearchResults = false
    @FocusState private var isSearchFieldFocused: Bool

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSearchFullContent: Bool {
        hasFullContentSearchIndex || fullContentSearchEnabled
    }

    private var activeSearchScope: WebPageSearchScope {
        canSearchFullContent ? .full : .basic
    }

    private var searchTaskKey: String {
        "\(activeSearchScope)-\(trimmedSearchText)"
    }

    var body: some View {
        let progress = model.progress
        let maskOpacity = min(progress / homeSearchOpaqueMaskProgress, 1)
        let cardScale = model.cardScale ?? searchCardScale(progress: progress)

        ZStack(alignment: .top) {
            Rectangle()
                .fill(.thinMaterial)
                .overlay(AppTheme.surfaceStrong.opacity(0.14))
                .opacity(maskOpacity)
                .frame(width: configuration.screenSize.width, height: configuration.screenSize.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 12) {
                searchFieldRow

                if trimmedSearchText.isEmpty {
                    searchRecommendationContent(maxHeight: configuration.contentMaxHeight)
                } else {
                    searchResultOverlayContent(maxHeight: configuration.contentMaxHeight)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(width: min(configuration.screenSize.width - 32, 720))
            .frame(maxHeight: configuration.cardMaxHeight, alignment: .top)
            .background(AppTheme.surfaceStrong, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
            .opacity(progress)
            .scaleEffect(cardScale, anchor: .top)
            .padding(.top, configuration.topInset)
            .accessibilityIdentifier("home.searchOverlay.card")
        }
        .frame(width: configuration.screenSize.width, height: configuration.screenSize.height, alignment: .top)
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: searchTaskKey) {
            await refreshSearchResults(
                query: trimmedSearchText,
                scope: activeSearchScope,
                debounce: true
            )
        }
        .onChange(of: model.focusRequestID) { _, requestID in
            guard requestID > 0 else {
                isSearchFieldFocused = false
                return
            }
            isSearchFieldFocused = true
        }
    }

    private func searchCardScale(progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return 1 + homeSearchOverlayScaleExpansion * (1 - clampedProgress)
    }

    private var searchFieldRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField(AppStrings.localized("搜索网页"), text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isSearchFieldFocused)
                .font(.system(size: 19, weight: .regular))

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("关闭搜索"))
        }
        .frame(height: 42)
        .padding(.horizontal, 8)
    }

    private func searchRecommendationContent(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.localized("最近打开"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.9))
                .padding(.horizontal, 10)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(searchRecommendations.enumerated()), id: \.element.id) { index, page in
                        recommendationRow(page, isHighlighted: index == 0)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: maxHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func searchResultOverlayContent(maxHeight: CGFloat) -> some View {
        let results = currentSearchResults

        if isUpdatingSearchResults || isSearchingFullContent {
            searchLoadingContent(maxHeight: maxHeight)
        } else if results.isEmpty {
            searchEmptyResultContent(maxHeight: maxHeight)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.localized("网页"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.9))
                    .padding(.horizontal, 10)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            searchResultRow(result, query: trimmedSearchText, isHighlighted: index == 0)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 420)
                .frame(maxHeight: maxHeight)
            }
        }
    }

    private func searchLoadingContent(maxHeight: CGFloat) -> some View {
        ProgressView()
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .frame(height: maxHeight, alignment: .center)
            .background(AppTheme.surfaceStrong.opacity(0.54), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func searchEmptyResultContent(maxHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text(AppStrings.localized("没有找到相关网页"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.contentPrimary)
            Text(emptySearchMessage(canSearchFullContent: canSearchFullContent))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            if !canSearchFullContent {
                Button {
                    searchFullContent()
                } label: {
                    Text(AppStrings.localized("搜索全部文件内容"))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.contentPrimary)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .frame(height: maxHeight, alignment: .center)
        .background(AppTheme.surfaceStrong.opacity(0.54), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var currentSearchResults: [WebPageSearchResult] {
        guard cachedSearchQuery == trimmedSearchText,
              cachedSearchScope == activeSearchScope else {
            return []
        }
        return cachedSearchResults
    }

    private func emptySearchMessage(canSearchFullContent: Bool) -> String {
        if canSearchFullContent {
            return AppStrings.localized("可以试试网页标题、文件名，或网页里出现过的文字。")
        }
        return AppStrings.localized("当前只搜索了标题、页面名和文件名。你也可以继续搜索全部文件内容。")
    }

    @MainActor
    private func refreshSearchResults(
        query: String,
        scope: WebPageSearchScope,
        debounce: Bool
    ) async {
        guard !query.isEmpty else {
            cachedSearchQuery = ""
            cachedSearchResults = []
            isUpdatingSearchResults = false
            return
        }

        isUpdatingSearchResults = true
        if debounce {
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
        }

        let results = searchResults(query, scope)
        guard !Task.isCancelled else { return }
        cachedSearchQuery = query
        cachedSearchScope = scope
        cachedSearchResults = results
        isUpdatingSearchResults = false
    }

    private func searchFullContent() {
        guard !isSearchingFullContent else { return }
        isSearchingFullContent = true
        Task {
            await onSearchFullContent()
            await MainActor.run {
                fullContentSearchEnabled = true
                isSearchingFullContent = false
            }
        }
    }

    private func searchResultRow(_ result: WebPageSearchResult, query: String, isHighlighted: Bool = false) -> some View {
        searchOverlayRow(
            page: result.page,
            title: highlightedSearchText(result.page.title, query: query),
            subtitle: searchResultSubtitle(for: result, query: query),
            isHighlighted: isHighlighted
        ) {
            dismiss {
                onSelectEntry(result.page, result.entry)
            }
        }
    }

    private func recommendationRow(_ page: WebPage, isHighlighted: Bool = false) -> some View {
        searchOverlayRow(
            page: page,
            title: AttributedString(page.title),
            subtitle: searchOverlaySubtitle(for: page).map(AttributedString.init),
            isHighlighted: isHighlighted
        ) {
            dismiss {
                onSelectEntry(page, preferredEntry(for: page))
            }
        }
    }

    private func searchOverlayRow(
        page: WebPage,
        title: AttributedString,
        subtitle: AttributedString?,
        isHighlighted: Bool = false,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                ProjectIconImage(
                    iconURL: projectIconURL(page),
                    iconVersion: page.projectIcon?.updatedAt,
                    fallbackSymbolName: projectIconSymbolName(for: page),
                    size: 32,
                    cornerRadius: 8,
                    fallbackBackground: .webPageTop(safeAreaTopBackground(for: page)),
                    fallbackPlacement: .listItem
                )
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.listItemTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isHighlighted ? AppTheme.surfaceInset.opacity(0.72) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchRecommendations: [WebPage] {
        configuration.recommendations
    }

    private func dismiss(completion: (() -> Void)? = nil) {
        isSearchFieldFocused = false
        onDismiss {
            completion?()
        }
    }

    private func safeAreaTopBackground(for page: WebPage) -> String? {
        preferredEntry(for: page).safeAreaTopColor ?? page.safeAreaTopColor
    }

    private func searchOverlaySubtitle(for page: WebPage) -> String? {
        if let sourceFileName = page.sourceFileName, !sourceFileName.isEmpty {
            return sourceFileName
        }
        if page.resolvedEntries.count > 1 {
            return AppStrings.localized("多页面项目")
        }
        return preferredEntry(for: page).entryFileName
    }

    private func searchResultSubtitle(for result: WebPageSearchResult, query: String) -> AttributedString? {
        if let snippet = result.snippet, !snippet.isEmpty {
            return highlightedSearchText(snippet, query: query)
        }
        if result.matchKind == .pageTitle {
            return highlightedSearchText(result.entry.title, query: query)
        }
        if result.entry.id != preferredEntry(for: result.page).id {
            return highlightedSearchText("\(result.entry.title) · \(result.entry.entryFileName)", query: query)
        }
        return searchOverlaySubtitle(for: result.page).map { highlightedSearchText($0, query: query) }
    }

    private func highlightedSearchText(_ text: String, query: String) -> AttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let nsText = text as NSString
        let highlightColor = UIColor.systemYellow.withAlphaComponent(0.35)

        for token in Self.searchHighlightTokens(query) {
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let foundRange = nsText.range(
                    of: token,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: searchRange
                )
                guard foundRange.location != NSNotFound, foundRange.length > 0 else {
                    break
                }

                attributed.addAttribute(.backgroundColor, value: highlightColor, range: foundRange)

                let nextLocation = foundRange.location + foundRange.length
                searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
            }
        }

        return AttributedString(attributed)
    }

    private static func searchHighlightTokens(_ query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var seen = Set<String>()
        return ([trimmedQuery] + trimmedQuery.split(whereSeparator: \.isWhitespace).map(String.init))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { token in
                let key = token.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .sorted { $0.count > $1.count }
    }

    private func projectIconSymbolName(for page: WebPage) -> String {
        if page.opensInNativeFileViewer {
            return "folder.fill"
        }
        return page.resolvedEntries.count > 1 ? "folder.fill" : "doc.text.fill"
    }

    private func preferredEntry(for page: WebPage) -> WebPageEntry {
        if let defaultEntryID = page.defaultEntryID,
           let entry = page.resolvedEntries.first(where: { $0.id == defaultEntryID }) {
            return entry
        }
        return page.resolvedEntries[0]
    }
}
