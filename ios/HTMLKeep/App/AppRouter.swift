import SwiftUI

@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []

    func openProject(_ page: WebPage) {
        if page.opensInNativeFileViewer {
            path = [.fileViewer(page.id)]
            return
        }
        path = [.project(page.id)]
    }

    func open(page: WebPage, entry: WebPageEntry) {
        if page.opensInNativeFileViewer {
            path = [.fileViewer(page.id)]
            return
        }
        path = [.viewer(page.id, entry.id)]
    }

    func push(page: WebPage, entry: WebPageEntry) {
        if page.opensInNativeFileViewer {
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
        if deletedPage.page.opensInNativeFileViewer {
            path = [.recentlyDeleted, .deletedFileViewer(deletedPage.id)]
            return
        }
        path = [.recentlyDeleted, .deletedProject(deletedPage.id)]
    }

    func openDeletedViewer(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer {
            path = [.recentlyDeleted, .deletedFileViewer(deletedPage.id)]
            return
        }
        path = [.recentlyDeleted, .deletedViewer(deletedPage.id, entry.id)]
    }

    func pushDeletedViewer(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        if deletedPage.page.opensInNativeFileViewer {
            path.append(.deletedFileViewer(deletedPage.id))
            return
        }
        path.append(.deletedViewer(deletedPage.id, entry.id))
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
