package com.htmlkeep.community.core

import java.io.File
import java.util.UUID

enum class WebPageLoadStatus {
    READY,
    MISSING,
    FAILED
}

enum class WebPageProjectIconSource {
    FAVICON,
    IMAGE,
    CUSTOM
}

enum class WebPageEntrySource {
    BUNDLED_ARCHIVE_INDEX,
    NATIVE_FILE,
    FILE_INDEX
}

enum class WebPageProjectType {
    WEB_PAGE,
    NATIVE_FILE,
    FILE_COLLECTION
}

data class WebPageProjectIcon(
    var source: WebPageProjectIconSource,
    var fileName: String,
    var updatedAt: Long
)

data class WebPageEntry(
    val id: String = UUID.randomUUID().toString(),
    var title: String,
    var entryRelativePath: String,
    var source: WebPageEntrySource? = null,
    var lastOpenedAt: Long,
    var lastLoadStatus: WebPageLoadStatus = WebPageLoadStatus.READY,
    var safeAreaTopColor: String? = null,
    var safeAreaBottomColor: String? = null
) {
    val entryFileName: String
        get() = File(entryRelativePath).name
}

data class WebPage(
    val id: String = UUID.randomUUID().toString(),
    var title: String,
    var sourceDescription: String,
    var sourceFileName: String?,
    var folderName: String,
    var entryRelativePath: String,
    var contentSHA256: String?,
    var createdAt: Long,
    var lastOpenedAt: Long,
    var updatedAt: Long? = null,
    var lastLoadStatus: WebPageLoadStatus = WebPageLoadStatus.READY,
    var entries: MutableList<WebPageEntry> = mutableListOf(),
    var defaultEntryID: String? = null,
    var projectIcon: WebPageProjectIcon? = null,
    var safeAreaTopColor: String? = null,
    var safeAreaBottomColor: String? = null,
    var projectType: WebPageProjectType = WebPageProjectType.WEB_PAGE
) {
    val resolvedProjectKind: WebPageProjectType
        get() {
            if (projectType != WebPageProjectType.WEB_PAGE) return projectType
            val resolved = resolvedEntries()
            if (resolved.any { it.source == WebPageEntrySource.NATIVE_FILE }) {
                return WebPageProjectType.NATIVE_FILE
            }
            if (resolved.any {
                    it.source == WebPageEntrySource.FILE_INDEX ||
                        it.source == WebPageEntrySource.BUNDLED_ARCHIVE_INDEX
                }
            ) {
                return WebPageProjectType.FILE_COLLECTION
            }
            return WebPageProjectType.WEB_PAGE
        }

    val opensInNativeFileViewer: Boolean
        get() = resolvedProjectKind != WebPageProjectType.WEB_PAGE

    fun resolvedEntries(): List<WebPageEntry> {
        if (entries.isNotEmpty()) return entries
        return listOf(
            WebPageEntry(
                id = id,
                title = title,
                entryRelativePath = entryRelativePath,
                lastOpenedAt = lastOpenedAt,
                lastLoadStatus = lastLoadStatus,
                safeAreaTopColor = safeAreaTopColor,
                safeAreaBottomColor = safeAreaBottomColor
            )
        )
    }
}

data class WebPageProjectFile(
    val relativePath: String,
    val href: String,
    val byteCount: Long
) {
    val fileName: String
        get() = File(relativePath).name
}

data class DeletedWebPage(
    var page: WebPage,
    var deletedAt: Long,
    var recoverableFolderName: String
) {
    val id: String
        get() = page.id
}

data class WebPageImportResult(
    val page: WebPage,
    val entry: WebPageEntry
)

class WebPageLibraryException(message: String) : Exception(message)
