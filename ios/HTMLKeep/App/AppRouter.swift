import SwiftUI

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
            path = [.viewer(page.id, entry.id)]
            return
        }
        path = [.project(page.id)]
    }

    func open(page: WebPage, entry: WebPageEntry) {
        if page.opensInNativeFileViewer || page.opensInSingleFilePreview {
            path = [.fileViewer(page.id)]
            return
        }
        path = [.viewer(page.id, entry.id)]
    }

    func push(page: WebPage, entry: WebPageEntry) {
        if page.opensInNativeFileViewer || page.opensInSingleFilePreview {
            path.append(.fileViewer(page.id))
            return
        }
        path.append(.viewer(page.id, entry.id))
    }

    func popToRoot() {
        path = []
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
            path = [.recentlyDeleted, .deletedViewer(deletedPage.id, entry.id)]
            return
        }
        path = [.recentlyDeleted, .deletedProject(deletedPage.id)]
    }

    func openDeletedViewer(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path = [.recentlyDeleted, .deletedFileViewer(deletedPage.id)]
            return
        }
        path = [.recentlyDeleted, .deletedViewer(deletedPage.id, entry.id)]
    }

    func pushDeletedViewer(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer || deletedPage.page.opensInSingleFilePreview {
            path.append(.deletedFileViewer(deletedPage.id))
            return
        }
        path.append(.deletedViewer(deletedPage.id, entry.id))
    }

    private func singleEntry(in page: WebPage) -> WebPageEntry? {
        let entries = page.resolvedEntries
        guard entries.count == 1 else { return nil }
        return entries[0]
    }
}

enum AppRoute: Hashable {
    case project(WebPage.ID)
    case viewer(WebPage.ID, WebPageEntry.ID)
    case fileViewer(WebPage.ID)
    case recentlyDeleted
    case deletedProject(WebPage.ID)
    case deletedViewer(WebPage.ID, WebPageEntry.ID)
    case deletedFileViewer(WebPage.ID)
}
