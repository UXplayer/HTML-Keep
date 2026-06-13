import SwiftUI

struct WebPageEntryNavigationState: Hashable {
    let percentEncodedQuery: String?
    let percentEncodedFragment: String?

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let query = components.percentEncodedQuery
        let fragment = components.percentEncodedFragment
        guard query != nil || fragment != nil else {
            return nil
        }

        percentEncodedQuery = query
        percentEncodedFragment = fragment
    }

    func applied(to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.percentEncodedQuery = percentEncodedQuery
        components.percentEncodedFragment = percentEncodedFragment
        return components.url ?? url
    }
}

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func openProject(_ page: WebPage) {
        if page.opensInNativeFileViewer || page.opensInSingleFilePreview {
            path = [.fileViewer(page.id)]
            return
        }
        if let entry = singleEntry(in: page) {
            path = [.viewer(page.id, entry.id, nil)]
            return
        }
        path = [.project(page.id)]
    }

    func open(page: WebPage, entry: WebPageEntry) {
        if page.opensInNativeFileViewer || page.opensInSingleFilePreview {
            path = [.fileViewer(page.id)]
            return
        }
        path = [.viewer(page.id, entry.id, nil)]
    }

    func push(page: WebPage, entry: WebPageEntry, navigationState: WebPageEntryNavigationState? = nil) {
        if page.opensInNativeFileViewer || page.opensInSingleFilePreview {
            path.append(.fileViewer(page.id))
            return
        }
        path.append(.viewer(page.id, entry.id, navigationState))
    }

    func replaceViewerRoot(page: WebPage, entry: WebPageEntry) {
        if page.opensInNativeFileViewer || page.opensInSingleFilePreview {
            path = path.dropTrailingViewerRoutes(pageID: page.id) + [.fileViewer(page.id)]
            return
        }
        path = path.dropTrailingViewerRoutes(pageID: page.id) + [.viewer(page.id, entry.id, nil)]
    }

    func popToRoot() {
        path = []
    }

    func viewerHasParent(pageID: WebPage.ID) -> Bool {
        guard case .viewer(let currentPageID, _, _) = path.last,
              currentPageID == pageID,
              case .viewer(let previousPageID, _, _) = path.dropLast().last else {
            return false
        }
        return previousPageID == pageID
    }

    func openRecentlyDeleted() {
        path = [.recentlyDeleted]
    }

    func openDeletedProject(_ deletedPage: DeletedWebPage) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path = [.recentlyDeleted, .deletedFileViewer(deletedPage.id)]
            return
        }
        if let entry = singleEntry(in: deletedPage.page) {
            path = [.recentlyDeleted, .deletedViewer(deletedPage.id, entry.id, nil)]
            return
        }
        path = [.recentlyDeleted, .deletedProject(deletedPage.id)]
    }

    func openDeletedViewer(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path = [.recentlyDeleted, .deletedFileViewer(deletedPage.id)]
            return
        }
        path = [.recentlyDeleted, .deletedViewer(deletedPage.id, entry.id, nil)]
    }

    func pushDeletedViewer(
        deletedPage: DeletedWebPage,
        entry: WebPageEntry,
        navigationState: WebPageEntryNavigationState? = nil
    ) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path.append(.deletedFileViewer(deletedPage.id))
            return
        }
        path.append(.deletedViewer(deletedPage.id, entry.id, navigationState))
    }

    func replaceDeletedViewerRoot(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path = path.dropTrailingDeletedViewerRoutes(pageID: deletedPage.id) + [.deletedFileViewer(deletedPage.id)]
            return
        }
        path = path.dropTrailingDeletedViewerRoutes(pageID: deletedPage.id) +
            [.deletedViewer(deletedPage.id, entry.id, nil)]
    }

    func deletedViewerHasParent(deletedPageID: DeletedWebPage.ID) -> Bool {
        guard case .deletedViewer(let currentPageID, _, _) = path.last,
              currentPageID == deletedPageID,
              case .deletedViewer(let previousPageID, _, _) = path.dropLast().last else {
            return false
        }
        return previousPageID == deletedPageID
    }

    private func singleEntry(in page: WebPage) -> WebPageEntry? {
        let entries = page.resolvedEntries
        guard entries.count == 1 else { return nil }
        return entries[0]
    }
}

enum AppRoute: Hashable {
    case project(WebPage.ID)
    case viewer(WebPage.ID, WebPageEntry.ID, WebPageEntryNavigationState?)
    case fileViewer(WebPage.ID)
    case recentlyDeleted
    case deletedProject(WebPage.ID)
    case deletedViewer(WebPage.ID, WebPageEntry.ID, WebPageEntryNavigationState?)
    case deletedFileViewer(WebPage.ID)
}

private extension Array where Element == AppRoute {
    func dropTrailingViewerRoutes(pageID: WebPage.ID) -> [AppRoute] {
        var routes = self
        while case .viewer(let routePageID, _, _) = routes.last, routePageID == pageID {
            routes.removeLast()
        }
        return routes
    }

    func dropTrailingDeletedViewerRoutes(pageID: DeletedWebPage.ID) -> [AppRoute] {
        var routes = self
        while case .deletedViewer(let routePageID, _, _) = routes.last, routePageID == pageID {
            routes.removeLast()
        }
        return routes
    }
}
