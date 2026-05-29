package com.htmlkeep.community.core

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID

class WebPageLibrary(
    private val rootDirectory: File,
    private val strings: LibraryStrings = LibraryStrings(),
    private val maximumSourceFileByteCount: Long = maximumImportedFileByteCount,
    private val maximumExpandedArchiveByteCount: Long = maximumImportedFileByteCount
) {
    data class LibraryStrings(
        val unsupportedFile: String = "Please choose an .html, .htm, or .zip file.",
        val unreadableFile: String = "Unable to read this file.",
        val archiveMissingHtml: String = "This ZIP archive does not contain an HTML file.",
        val archiveExtractFailed: String = "Unable to extract this ZIP archive.",
        val storageFailed: String = "Unable to prepare local web storage.",
        val untitledWebPage: String = "Untitled Web Page",
        val missingRecoverableFolder: String = "Web page files are missing.",
        val fileListTitle: String = "File List",
        val importFileTooLarge: String = "This file is too large to import."
    )

    private val webPagesDirectory = File(rootDirectory, "WebPages")
    private val recentlyDeletedDirectory = File(rootDirectory, "RecentlyDeleted")
    private val storeFile = File(rootDirectory, "web-pages.json")
    private val recentlyDeletedStoreFile = File(rootDirectory, "recently-deleted-web-pages.json")

    var pages: MutableList<WebPage> = mutableListOf()
        private set
    var recentlyDeletedPages: MutableList<DeletedWebPage> = mutableListOf()
        private set

    init {
        load()
        loadRecentlyDeleted()
        normalizeEntryOrdering()
        refreshAvailability()
        refreshRecentlyDeletedAvailability()
    }

    fun folderFor(page: WebPage): File = File(webPagesDirectory, page.folderName)

    fun recoverableFolderFor(deletedPage: DeletedWebPage): File {
        return File(recentlyDeletedDirectory, deletedPage.recoverableFolderName)
    }

    fun projectIconFileFor(page: WebPage): File? {
        val icon = page.projectIcon ?: return null
        return File(folderFor(page), icon.fileName).takeIf { it.exists() }
    }

    fun projectIconFileFor(deletedPage: DeletedWebPage): File? {
        val icon = deletedPage.page.projectIcon ?: return null
        return File(recoverableFolderFor(deletedPage), icon.fileName).takeIf { it.exists() }
    }

    fun entryFileFor(page: WebPage, entry: WebPageEntry = defaultEntry(page)): File {
        return File(folderFor(page), entry.entryRelativePath)
    }

    fun entryExists(page: WebPage, entry: WebPageEntry = defaultEntry(page)): Boolean {
        if (entry.source == WebPageEntrySource.BUNDLED_ARCHIVE_INDEX) return true
        if (entry.source == WebPageEntrySource.FILE_INDEX) return File(folderFor(page), archiveFallbackIndexDataFileName).exists()
        return entryFileFor(page, entry).exists()
    }

    fun entryExists(deletedPage: DeletedWebPage, entry: WebPageEntry = defaultEntry(deletedPage.page)): Boolean {
        if (entry.source == WebPageEntrySource.BUNDLED_ARCHIVE_INDEX) return true
        if (entry.source == WebPageEntrySource.FILE_INDEX) {
            return File(recoverableFolderFor(deletedPage), archiveFallbackIndexDataFileName).exists()
        }
        return File(recoverableFolderFor(deletedPage), entry.entryRelativePath).exists()
    }

    fun usesNativeFileViewer(page: WebPage): Boolean = page.opensInNativeFileViewer

    fun projectFilesFor(page: WebPage): List<WebPageProjectFile> {
        val folder = folderFor(page)
        return projectFilesForFolder(folder)
    }

    fun projectFilesFor(deletedPage: DeletedWebPage): List<WebPageProjectFile> {
        val folder = recoverableFolderFor(deletedPage)
        return projectFilesForFolder(folder)
    }

    fun page(id: String): WebPage? = pages.firstOrNull { it.id == id }

    fun recentlyDeletedPage(id: String): DeletedWebPage? = recentlyDeletedPages.firstOrNull { it.id == id }

    fun defaultEntry(page: WebPage): WebPageEntry {
        val entries = page.resolvedEntries()
        return page.defaultEntryID?.let { id -> entries.firstOrNull { it.id == id } } ?: entries.first()
    }

    fun importFromFile(source: File): WebPageImportResult {
        val name = source.name.ifBlank { "webpage" }
        if (source.length() > maximumSourceFileByteCount) {
            throw WebPageLibraryException(strings.importFileTooLarge)
        }
        val bytes = source.readBytes()
        return importBytes(bytes, name, source.parentFile?.name ?: "")
    }

    fun importBytes(bytes: ByteArray, sourceFileName: String, sourceDescription: String = ""): WebPageImportResult {
        if (bytes.size.toLong() > maximumSourceFileByteCount) {
            throw WebPageLibraryException(strings.importFileTooLarge)
        }
        val lowerName = sourceFileName.lowercase()
        ensureStorage()
        return if (isSupportedArchive(lowerName)) {
            importArchive(bytes, sourceFileName, sourceDescription)
        } else if (isSupportedHTML(lowerName)) {
            importHtml(bytes, sourceFileName, sourceDescription)
        } else {
            importNativeFile(bytes, sourceFileName, sourceDescription)
        }
    }

    fun markOpened(page: WebPage, entry: WebPageEntry) {
        val now = System.currentTimeMillis()
        update(page.id) {
            it.lastOpenedAt = now
            it.lastLoadStatus = WebPageLoadStatus.READY
            updateEntry(it, entry.id) { target ->
                target.lastOpenedAt = now
                target.lastLoadStatus = WebPageLoadStatus.READY
            }
        }
    }

    fun markFailed(page: WebPage, entry: WebPageEntry) {
        update(page.id) {
            it.lastLoadStatus = WebPageLoadStatus.FAILED
            updateEntry(it, entry.id) { target -> target.lastLoadStatus = WebPageLoadStatus.FAILED }
        }
    }

    fun renamePage(page: WebPage, proposedTitle: String): Boolean {
        val trimmed = HtmlMetadata.normalizedDisplayTitle(proposedTitle)
        if (trimmed.isBlank()) return false
        val currentPage = page(page.id) ?: return false
        val renamed = uniqueTitle(trimmed, currentPage.id)
        if (currentPage.title == renamed) return false
        update(currentPage.id) {
            it.title = renamed
            it.updatedAt = System.currentTimeMillis()
        }
        return true
    }

    fun delete(page: WebPage) {
        val index = pages.indexOfFirst { it.id == page.id }
        if (index < 0) return
        val removed = pages.removeAt(index)
        val deletedAt = System.currentTimeMillis()
        val sourceFolder = folderFor(removed)
        val recoverableFolderName = uniqueFolderName(removed.folderName, recentlyDeletedDirectory)
        val destinationFolder = File(recentlyDeletedDirectory, recoverableFolderName)
        ensureStorage()
        if (sourceFolder.exists()) {
            destinationFolder.parentFile?.mkdirs()
            if (!sourceFolder.renameTo(destinationFolder)) {
                sourceFolder.copyRecursively(destinationFolder, overwrite = true)
                sourceFolder.deleteRecursively()
            }
        }
        recentlyDeletedPages.removeAll { it.id == removed.id }
        recentlyDeletedPages.add(
            DeletedWebPage(
                page = removed,
                deletedAt = deletedAt,
                recoverableFolderName = recoverableFolderName
            )
        )
        sortRecentlyDeleted()
        saveAll()
    }

    fun restore(deletedPage: DeletedWebPage): WebPage {
        val index = recentlyDeletedPages.indexOfFirst { it.id == deletedPage.id }
        if (index < 0) throw WebPageLibraryException(strings.missingRecoverableFolder)
        val item = recentlyDeletedPages[index]
        val recoverableFolder = recoverableFolderFor(item)
        if (!recoverableFolder.exists()) {
            refreshRecentlyDeletedAvailability()
            throw WebPageLibraryException(strings.missingRecoverableFolder)
        }

        val now = System.currentTimeMillis()
        val restored = item.page.copy(
            folderName = uniqueFolderName(item.page.folderName, webPagesDirectory),
            title = uniqueTitle(item.page.title, item.page.id),
            createdAt = now,
            lastOpenedAt = now,
            updatedAt = now,
            entries = item.page.resolvedEntries().map { it.copy(lastOpenedAt = now) }.toMutableList()
        )
        val destinationFolder = folderFor(restored)
        if (!recoverableFolder.renameTo(destinationFolder)) {
            recoverableFolder.copyRecursively(destinationFolder, overwrite = true)
            recoverableFolder.deleteRecursively()
        }
        recentlyDeletedPages.removeAt(index)
        pages.add(0, restored)
        sortPages()
        saveAll()
        return restored
    }

    fun permanentlyDelete(deletedPage: DeletedWebPage) {
        val index = recentlyDeletedPages.indexOfFirst { it.id == deletedPage.id }
        if (index < 0) return
        val item = recentlyDeletedPages.removeAt(index)
        recoverableFolderFor(item).deleteRecursively()
        saveAll()
    }

    fun setCustomProjectIcon(page: WebPage, imageBytes: ByteArray): Boolean {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size) ?: return false
        val currentPage = page(page.id) ?: return false
        val icon = saveProjectIcon(folderFor(currentPage), bitmap, WebPageProjectIconSource.CUSTOM) ?: return false
        currentPage.projectIcon = icon
        currentPage.updatedAt = System.currentTimeMillis()
        save()
        return true
    }

    private fun importHtml(bytes: ByteArray, sourceFileName: String, sourceDescription: String): WebPageImportResult {
        val contentSHA256 = sha256(bytes)
        val html = bytes.toString(Charsets.UTF_8)
        val now = System.currentTimeMillis()

        pages.firstOrNull { it.contentSHA256 == contentSHA256 }?.let { existing ->
            val entryFile = entryFileFor(existing)
            if (!entryFile.exists()) {
                entryFile.parentFile?.mkdirs()
                entryFile.writeBytes(bytes)
            }
            existing.lastOpenedAt = now
            existing.lastLoadStatus = WebPageLoadStatus.READY
            existing.sourceFileName = existing.sourceFileName ?: sourceFileName
            val colors = backgroundColorsFor(entryFile, folderFor(existing), html)
            val firstEntry = existing.resolvedEntries().first()
            existing.entries = mutableListOf(
                firstEntry.copy(
                    entryRelativePath = existing.entryRelativePath,
                    lastLoadStatus = WebPageLoadStatus.READY,
                    safeAreaTopColor = colors.top,
                    safeAreaBottomColor = colors.bottom
                )
            )
            existing.safeAreaTopColor = colors.top
            existing.safeAreaBottomColor = colors.bottom
            refreshGeneratedIconIfNeeded(existing)
            sortPages()
            save()
            return WebPageImportResult(existing, defaultEntry(existing))
        }

        val id = UUID.randomUUID().toString()
        val folderName = id
        val folder = File(webPagesDirectory, folderName)
        folder.mkdirs()
        val entryFile = File(folder, "index.html")
        entryFile.writeBytes(bytes)
        val baseTitle = HtmlMetadata.title(html, File(sourceFileName), strings.untitledWebPage)
        val colors = backgroundColorsFor(entryFile, folder, html)
        val entry = WebPageEntry(
            id = id,
            title = baseTitle,
            entryRelativePath = "index.html",
            lastOpenedAt = now,
            safeAreaTopColor = colors.top,
            safeAreaBottomColor = colors.bottom
        )
        val page = WebPage(
            id = id,
            title = uniqueTitle(baseTitle),
            sourceDescription = sourceDescription,
            sourceFileName = sourceFileName,
            folderName = folderName,
            entryRelativePath = "index.html",
            contentSHA256 = contentSHA256,
            createdAt = now,
            lastOpenedAt = now,
            updatedAt = now,
            entries = mutableListOf(entry),
            defaultEntryID = entry.id,
            safeAreaTopColor = colors.top,
            safeAreaBottomColor = colors.bottom
        )
        page.projectIcon = generatedProjectIcon(page, html, folder, entry.entryRelativePath)
        pages.add(0, page)
        sortPages()
        save()
        return WebPageImportResult(page, entry)
    }

    private fun importNativeFile(bytes: ByteArray, sourceFileName: String, sourceDescription: String): WebPageImportResult {
        val contentSHA256 = sha256(bytes)
        val now = System.currentTimeMillis()

        pages.firstOrNull { it.contentSHA256 == contentSHA256 }?.let { existing ->
            if (existing.opensInNativeFileViewer) {
                val entry = defaultEntry(existing)
                val entryFile = entryFileFor(existing, entry)
                if (!entryFile.exists()) {
                    entryFile.parentFile?.mkdirs()
                    entryFile.writeBytes(bytes)
                }
                writeProjectFileIndex(folderFor(existing), existing.sourceFileName ?: sourceFileName)
                existing.projectType = WebPageProjectType.NATIVE_FILE
                updateEntry(existing, entry.id) { target ->
                    target.source = WebPageEntrySource.NATIVE_FILE
                    target.lastOpenedAt = now
                    target.lastLoadStatus = WebPageLoadStatus.READY
                }
            }
            existing.lastOpenedAt = now
            existing.lastLoadStatus = WebPageLoadStatus.READY
            existing.sourceFileName = existing.sourceFileName ?: sourceFileName
            refreshGeneratedIconIfNeeded(existing)
            sortPages()
            save()
            return WebPageImportResult(existing, defaultEntry(existing))
        }

        val id = UUID.randomUUID().toString()
        val folderName = id
        val folder = File(webPagesDirectory, folderName)
        folder.mkdirs()
        val fileName = safeImportedFileName(sourceFileName)
        val entryFile = File(folder, fileName)
        entryFile.writeBytes(bytes)
        writeProjectFileIndex(folder, sourceFileName)
        val title = HtmlMetadata.normalizedDisplayTitle(File(sourceFileName).nameWithoutExtension)
            .ifBlank { HtmlMetadata.normalizedDisplayTitle(File(sourceFileName).name) }
            .ifBlank { strings.untitledWebPage }
        val entry = WebPageEntry(
            id = id,
            title = title,
            entryRelativePath = fileName,
            source = WebPageEntrySource.NATIVE_FILE,
            lastOpenedAt = now,
            lastLoadStatus = WebPageLoadStatus.READY
        )
        val page = WebPage(
            id = id,
            title = uniqueTitle(title),
            sourceDescription = sourceDescription,
            sourceFileName = sourceFileName,
            folderName = folderName,
            entryRelativePath = fileName,
            contentSHA256 = contentSHA256,
            createdAt = now,
            lastOpenedAt = now,
            updatedAt = now,
            entries = mutableListOf(entry),
            defaultEntryID = entry.id,
            projectType = WebPageProjectType.NATIVE_FILE
        )
        page.projectIcon = generatedProjectIcon(page, "", folder, entry.entryRelativePath)
        pages.add(0, page)
        sortPages()
        save()
        return WebPageImportResult(page, entry)
    }

    private fun importArchive(bytes: ByteArray, sourceFileName: String, sourceDescription: String): WebPageImportResult {
        val contentSHA256 = sha256(bytes)
        val now = System.currentTimeMillis()

        pages.firstOrNull { it.contentSHA256 == contentSHA256 }?.let { existing ->
            restoreArchiveFolder(existing, bytes, now)
            refreshGeneratedIconIfNeeded(existing)
            existing.contentSHA256 = contentSHA256
            existing.lastOpenedAt = now
            existing.lastLoadStatus = WebPageLoadStatus.READY
            existing.sourceFileName = existing.sourceFileName ?: sourceFileName
            sortPages()
            save()
            return WebPageImportResult(existing, defaultEntry(existing))
        }

        val id = UUID.randomUUID().toString()
        val folderName = id
        val folder = File(webPagesDirectory, folderName)
        try {
            ZipTools.extract(bytes, folder, maximumExpandedArchiveByteCount)
        } catch (_: ZipTools.ExpandedSizeLimitExceeded) {
            folder.deleteRecursively()
            throw WebPageLibraryException(strings.importFileTooLarge)
        } catch (_: Throwable) {
            folder.deleteRecursively()
            throw WebPageLibraryException(strings.archiveExtractFailed)
        }

        val htmlEntries = htmlEntries(folder, now)
        val isFileCollection = htmlEntries.isEmpty()
        val entries = if (isFileCollection) {
            writeProjectFileIndex(folder, sourceFileName)
            listOf(fileIndexEntry(now))
        } else {
            htmlEntries
        }
        val sortedEntries = uniquedEntryTitles(entries).sortedWith(entryDisplayComparator())
        val defaultEntry = sortedEntries.first()
        val page = WebPage(
            id = id,
            title = uniqueTitle(HtmlMetadata.archiveTitle(sourceFileName, strings.untitledWebPage)),
            sourceDescription = sourceDescription,
            sourceFileName = sourceFileName,
            folderName = folderName,
            entryRelativePath = defaultEntry.entryRelativePath,
            contentSHA256 = contentSHA256,
            createdAt = now,
            lastOpenedAt = now,
            updatedAt = now,
            entries = sortedEntries.toMutableList(),
            defaultEntryID = defaultEntry.id,
            safeAreaTopColor = defaultEntry.safeAreaTopColor,
            safeAreaBottomColor = defaultEntry.safeAreaBottomColor,
            projectType = if (isFileCollection) WebPageProjectType.FILE_COLLECTION else WebPageProjectType.WEB_PAGE
        )
        if (!isFileCollection) {
            val defaultHtml = htmlContentFor(defaultEntry, folder)
            page.projectIcon = generatedProjectIcon(page, defaultHtml, folder, defaultEntry.entryRelativePath)
        } else {
            page.projectIcon = generatedProjectIcon(page, "", folder, defaultEntry.entryRelativePath)
        }
        pages.add(0, page)
        sortPages()
        save()
        return WebPageImportResult(page, defaultEntry)
    }

    private fun restoreArchiveFolder(page: WebPage, bytes: ByteArray, openedAt: Long) {
        val folder = folderFor(page)
        val temporaryFolder = File(webPagesDirectory, "${page.folderName}-restore-${UUID.randomUUID()}")
        try {
            ZipTools.extract(bytes, temporaryFolder, maximumExpandedArchiveByteCount)
            val htmlEntries = htmlEntries(temporaryFolder, openedAt)
            val isFileCollection = htmlEntries.isEmpty()
            val entries = if (isFileCollection) {
                writeProjectFileIndex(temporaryFolder, page.sourceFileName ?: page.title)
                listOf(fileIndexEntry(openedAt))
            } else {
                htmlEntries
            }
            WebPageRuntimeStorage.copyRuntimeDirectoryIfPresent(folder, temporaryFolder)
            folder.deleteRecursively()
            temporaryFolder.renameTo(folder)
            val merged = mergeEntries(page.resolvedEntries(), entries)
            page.entries = merged.toMutableList()
            page.defaultEntryID = page.defaultEntryID?.takeIf { id -> merged.any { it.id == id } }
                ?: merged.first().id
            val defaultEntry = defaultEntry(page)
            page.entryRelativePath = defaultEntry.entryRelativePath
            page.safeAreaTopColor = defaultEntry.safeAreaTopColor
            page.safeAreaBottomColor = defaultEntry.safeAreaBottomColor
            page.projectType = if (isFileCollection) WebPageProjectType.FILE_COLLECTION else WebPageProjectType.WEB_PAGE
        } catch (error: WebPageLibraryException) {
            throw error
        } catch (_: ZipTools.ExpandedSizeLimitExceeded) {
            throw WebPageLibraryException(strings.importFileTooLarge)
        } catch (_: Throwable) {
            throw WebPageLibraryException(strings.archiveExtractFailed)
        } finally {
            temporaryFolder.deleteRecursively()
        }
    }

    private fun refreshGeneratedIconIfNeeded(page: WebPage) {
        if (page.projectIcon?.source == WebPageProjectIconSource.CUSTOM) return
        val folder = folderFor(page)
        val html = htmlContentFor(defaultEntry(page), folder)
        page.projectIcon = generatedProjectIcon(page, html, folder, page.entryRelativePath)
    }

    private fun generatedProjectIcon(
        page: WebPage,
        html: String,
        folder: File,
        entryRelativePath: String
    ): WebPageProjectIcon? {
        iconBitmapFromHtmlLinks(html, folder, entryRelativePath)?.let { (bitmap, source) ->
            return saveProjectIcon(folder, bitmap, source)
        }
        iconBitmapFromManifest(html, folder, entryRelativePath)?.let { bitmap ->
            return saveProjectIcon(folder, bitmap, WebPageProjectIconSource.FAVICON)
        }
        iconBitmapFromRootFallback(folder, entryRelativePath)?.let { bitmap ->
            return saveProjectIcon(folder, bitmap, WebPageProjectIconSource.FAVICON)
        }
        iconBitmapFromImages(folder)?.let { bitmap ->
            return saveProjectIcon(folder, bitmap, WebPageProjectIconSource.IMAGE)
        }
        if (page.projectIcon?.source != WebPageProjectIconSource.CUSTOM) {
            WebPageRuntimeStorage.cleanupProjectIconFiles(folder, null)
        }
        page.projectIcon = null
        return null
    }

    private fun iconBitmapFromHtmlLinks(
        html: String,
        folder: File,
        entryRelativePath: String
    ): Pair<Bitmap, WebPageProjectIconSource>? {
        val links = Regex("<link\\b[^>]*>", RegexOption.IGNORE_CASE).findAll(html).map { it.value }.toList()
        val prioritized = links.mapNotNull { tag ->
            val rel = attributeValue(tag, "rel")?.lowercase() ?: return@mapNotNull null
            val href = attributeValue(tag, "href") ?: return@mapNotNull null
            val rank = when {
                rel.contains("apple-touch-icon") -> 0
                rel.split(Regex("\\s+")).contains("icon") || rel.contains("shortcut icon") -> 1
                else -> return@mapNotNull null
            }
            rank to href
        }.sortedBy { it.first }
        for ((_, href) in prioritized) {
            decodeIconHref(href, folder, entryRelativePath)?.let {
                return it to WebPageProjectIconSource.FAVICON
            }
        }
        return null
    }

    private fun iconBitmapFromManifest(
        html: String,
        folder: File,
        entryRelativePath: String
    ): Bitmap? {
        val links = Regex("<link\\b[^>]*>", RegexOption.IGNORE_CASE).findAll(html).map { it.value }.toList()
        val manifestHrefs = links.mapNotNull { tag ->
            val rel = attributeValue(tag, "rel")?.lowercase() ?: return@mapNotNull null
            if (!rel.split(Regex("\\s+")).contains("manifest")) return@mapNotNull null
            attributeValue(tag, "href")
        }
        for (href in manifestHrefs) {
            val manifestFile = projectFileForHref(href, folder, entryRelativePath) ?: continue
            if (!manifestFile.exists() || !manifestFile.isFile) continue
            val manifestRelativePath = relativePathForFile(folder, manifestFile) ?: continue
            val json = runCatching { JSONObject(manifestFile.readText(Charsets.UTF_8)) }.getOrNull() ?: continue
            val icons = json.optJSONArray("icons") ?: continue
            val candidates = List(icons.length()) { index -> icons.optJSONObject(index) }
                .mapNotNull { item ->
                    val src = item?.optString("src")?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                    val score = ProjectIconRules.manifestIconScore(
                        sizes = item.optString("sizes").takeIf { it.isNotBlank() },
                        type = item.optString("type").takeIf { it.isNotBlank() },
                        purpose = item.optString("purpose").takeIf { it.isNotBlank() }
                    )
                    score to src
                }
                .sortedByDescending { it.first }
            for ((_, src) in candidates) {
                decodeIconHref(src, folder, manifestRelativePath)?.let { return it }
            }
        }
        return null
    }

    private fun iconBitmapFromRootFallback(folder: File, entryRelativePath: String): Bitmap? {
        val entryParent = File(entryRelativePath).parent?.replace(File.separatorChar, '/').orEmpty()
        val fallbackNames = listOf(
            "favicon.ico",
            "favicon.png",
            "favicon.jpg",
            "favicon.jpeg",
            "favicon.svg",
            "apple-touch-icon.png",
            "apple-touch-icon-precomposed.png"
        )
        val searchFolders = listOf("", entryParent).distinct()
        for (searchFolder in searchFolders) {
            for (name in fallbackNames) {
                val candidate = if (searchFolder.isBlank()) name else "$searchFolder/$name"
                decodeProjectBitmap(File(folder, candidate))?.let {
                    return it
                }
            }
        }
        return null
    }

    private fun iconBitmapFromImages(folder: File): Bitmap? {
        val candidates = folder.walkTopDown()
            .filter { it.isFile && !WebPageRuntimeStorage.isRuntimeStoragePath(folder.toPath().relativize(it.toPath()).toString().replace(File.separatorChar, '/')) }
            .filter { ProjectIconRules.isSupportedImageFileName(it.name) }
            .mapNotNull { file ->
                val dimensions = imageDimensions(file) ?: return@mapNotNull null
                val score = ProjectIconRules.imageScore(file.name, file.length(), dimensions.first, dimensions.second)
                    ?: return@mapNotNull null
                Triple(score, file.path.length, file)
            }
            .sortedWith(compareByDescending<Triple<Int, Int, File>> { it.first }.thenBy { it.second })
            .map { it.third }
            .toList()
        for (file in candidates) {
            decodeProjectBitmap(file)?.let { return it }
        }
        return null
    }

    private fun decodeIconHref(href: String, folder: File, entryRelativePath: String): Bitmap? {
        if (href.startsWith("http://", ignoreCase = true) || href.startsWith("https://", ignoreCase = true)) return null
        if (href.startsWith("data:", ignoreCase = true)) {
            val base64Marker = ";base64,"
            val markerIndex = href.indexOf(base64Marker, ignoreCase = true)
            if (markerIndex < 0) return null
            val raw = href.substring(markerIndex + base64Marker.length)
            val bytes = runCatching { Base64.decode(raw, Base64.DEFAULT) }.getOrNull() ?: return null
            return runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
        }
        return decodeProjectBitmap(projectFileForHref(href, folder, entryRelativePath) ?: return null)
    }

    private fun projectFileForHref(href: String, folder: File, entryRelativePath: String): File? {
        val relativePath = projectRelativePathForHref(href, entryRelativePath) ?: return null
        return File(folder, relativePath)
    }

    private fun projectRelativePathForHref(href: String, entryRelativePath: String): String? {
        if (href.startsWith("http://", ignoreCase = true) || href.startsWith("https://", ignoreCase = true)) return null
        if (href.startsWith("data:", ignoreCase = true)) return null
        val path = href.substringBefore('#').substringBefore('?')
        if (path.isBlank() || path.startsWith("//")) return null
        val decodedPath = runCatching { URLDecoder.decode(path, StandardCharsets.UTF_8.name()) }.getOrNull() ?: return null
        val relative = if (decodedPath.startsWith('/')) {
            decodedPath.removePrefix("/")
        } else {
            val parent = File(entryRelativePath).parent?.replace(File.separatorChar, '/')
            if (parent.isNullOrBlank()) decodedPath else "$parent/$decodedPath"
        }
        return runCatching { ZipTools.safeRelativePath(relative) }.getOrNull()
    }

    private fun relativePathForFile(folder: File, file: File): String? {
        return runCatching {
            folder.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
        }.getOrNull()
    }

    private fun decodeProjectBitmap(file: File): Bitmap? {
        if (!file.exists() || !file.isFile) return null
        return runCatching { BitmapFactory.decodeFile(file.absolutePath) }.getOrNull()
    }

    private fun imageDimensions(file: File): Pair<Int, Int>? {
        if (!file.exists() || !file.isFile) return null
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        runCatching { BitmapFactory.decodeFile(file.absolutePath, options) }.getOrNull()
        if (options.outWidth <= 0 || options.outHeight <= 0) return null
        return options.outWidth to options.outHeight
    }

    private fun attributeValue(tag: String, name: String): String? {
        val quoted = Regex("\\b$name\\s*=\\s*([\"'])(.*?)\\1", RegexOption.IGNORE_CASE).find(tag)
        if (quoted != null) return quoted.groupValues.getOrNull(2)
        return Regex("\\b$name\\s*=\\s*([^\\s>]+)", RegexOption.IGNORE_CASE).find(tag)
            ?.groupValues
            ?.getOrNull(1)
    }

    private fun saveProjectIcon(
        folder: File,
        sourceBitmap: Bitmap,
        source: WebPageProjectIconSource
    ): WebPageProjectIcon? {
        if (sourceBitmap.width <= 0 || sourceBitmap.height <= 0) return null
        val runtimeDirectory = WebPageRuntimeStorage.runtimeDirectory(folder)
        runtimeDirectory.mkdirs()
        val updatedAt = System.currentTimeMillis()
        var sequence = 0
        var relativePath = WebPageRuntimeStorage.versionedProjectIconRelativePath(updatedAt, sequence)
        var destination = File(folder, relativePath)
        while (destination.exists()) {
            sequence += 1
            relativePath = WebPageRuntimeStorage.versionedProjectIconRelativePath(updatedAt, sequence)
            destination = File(folder, relativePath)
        }
        val normalized = normalizedIconBitmap(sourceBitmap)
        val saved = runCatching {
            destination.outputStream().use { stream ->
                normalized.compress(Bitmap.CompressFormat.PNG, 100, stream)
            }
        }.getOrDefault(false)
        if (!saved) return null
        WebPageRuntimeStorage.cleanupProjectIconFiles(folder, relativePath)
        return WebPageProjectIcon(
            source = source,
            fileName = relativePath,
            updatedAt = updatedAt
        )
    }

    private fun normalizedIconBitmap(source: Bitmap): Bitmap {
        val size = minOf(source.width, source.height)
        val left = (source.width - size) / 2
        val top = (source.height - size) / 2
        val cropped = Bitmap.createBitmap(source, left, top, size, size)
        val output = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(cropped, null, Rect(0, 0, 256, 256), paint)
        return output
    }

    private fun htmlEntries(folder: File, openedAt: Long): List<WebPageEntry> {
        return folder.walkTopDown()
            .filter { it.isFile && isSupportedHTML(it.name.lowercase()) }
            .map { file ->
                val relative = folder.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
                val html = runCatching { file.readText(Charsets.UTF_8) }.getOrDefault("")
                val colors = backgroundColorsFor(file, folder, html)
                WebPageEntry(
                    title = HtmlMetadata.title(html, file, strings.untitledWebPage),
                    entryRelativePath = relative,
                    lastOpenedAt = openedAt,
                    lastLoadStatus = WebPageLoadStatus.READY,
                    safeAreaTopColor = colors.top,
                    safeAreaBottomColor = colors.bottom
                )
            }
            .toList()
    }

    private fun archiveFallbackEntry(folder: File, archiveName: String, openedAt: Long): WebPageEntry {
        writeProjectFileIndex(folder, archiveName)
        val colors = backgroundColorsFor(File(folder, archiveFallbackEntryRelativePath), folder, bundledArchiveFallbackTemplateHTML)
        return WebPageEntry(
            title = strings.fileListTitle,
            entryRelativePath = archiveFallbackEntryRelativePath,
            source = WebPageEntrySource.BUNDLED_ARCHIVE_INDEX,
            lastOpenedAt = openedAt,
            lastLoadStatus = WebPageLoadStatus.READY,
            safeAreaTopColor = colors.top,
            safeAreaBottomColor = colors.bottom
        )
    }

    private fun fileIndexEntry(openedAt: Long): WebPageEntry {
        return WebPageEntry(
            title = strings.fileListTitle,
            entryRelativePath = archiveFallbackIndexDataFileName,
            source = WebPageEntrySource.FILE_INDEX,
            lastOpenedAt = openedAt,
            lastLoadStatus = WebPageLoadStatus.READY
        )
    }

    private fun writeProjectFileIndex(folder: File, archiveName: String) {
        val files = projectFilesByWalking(folder)

        val jsonFiles = JSONArray()
        files.forEach { file ->
            jsonFiles.put(
                JSONObject()
                    .put("relativePath", file.relativePath)
                    .put("href", file.href)
                    .put("byteCount", file.byteCount)
            )
        }
        File(folder, archiveFallbackIndexDataFileName).writeText(
            JSONObject()
                .put("schemaVersion", 1)
                .put("archiveName", archiveName)
                .put("files", jsonFiles)
                .toString(),
            Charsets.UTF_8
        )
    }

    private fun htmlContentFor(entry: WebPageEntry, folder: File): String {
        if (entry.source == WebPageEntrySource.BUNDLED_ARCHIVE_INDEX) return bundledArchiveFallbackTemplateHTML
        if (entry.source == WebPageEntrySource.FILE_INDEX || entry.source == WebPageEntrySource.NATIVE_FILE) return ""
        return runCatching { File(folder, entry.entryRelativePath).readText(Charsets.UTF_8) }.getOrDefault("")
    }

    private fun projectFilesForFolder(folder: File): List<WebPageProjectFile> {
        val indexed = projectFilesFromIndex(folder)
        if (indexed.isNotEmpty() || File(folder, archiveFallbackIndexDataFileName).exists()) return indexed
        return projectFilesByWalking(folder)
    }

    private fun projectFilesFromIndex(folder: File): List<WebPageProjectFile> {
        val file = File(folder, archiveFallbackIndexDataFileName)
        if (!file.exists()) return emptyList()
        return runCatching {
            val json = JSONObject(file.readText(Charsets.UTF_8))
            val files = json.optJSONArray("files") ?: JSONArray()
            List(files.length()) { index ->
                val item = files.getJSONObject(index)
                val relativePath = item.optString("relativePath")
                WebPageProjectFile(
                    relativePath = relativePath,
                    href = item.optString("href").ifBlank { percentEncodedRelativeHref(relativePath) },
                    byteCount = item.optLong("byteCount")
                )
            }.filter { it.relativePath.isNotBlank() }
        }.getOrDefault(emptyList())
    }

    private fun projectFilesByWalking(folder: File): List<WebPageProjectFile> {
        if (!folder.exists()) return emptyList()
        return folder.walkTopDown()
            .filter { it.isFile }
            .map { file ->
                val relative = folder.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
                WebPageProjectFile(
                    relativePath = relative,
                    href = percentEncodedRelativeHref(relative),
                    byteCount = file.length()
                )
            }
            .filterNot { isAppManagedFallbackPath(it.relativePath) }
            .sortedBy { it.relativePath.lowercase() }
            .toList()
    }

    private fun backgroundColorsFor(file: File, folder: File, html: String): HtmlBackgroundExtractor.EdgeColors {
        return runCatching { HtmlBackgroundExtractor.extract(html, file, folder) }
            .getOrDefault(HtmlBackgroundExtractor.EdgeColors("#FFFFFF", "#FFFFFF"))
    }

    private fun mergeEntries(existing: List<WebPageEntry>, incoming: List<WebPageEntry>): List<WebPageEntry> {
        return incoming.map { next ->
            val old = existing.firstOrNull { it.entryRelativePath == next.entryRelativePath }
            if (old == null) next else next.copy(id = old.id, title = old.title, lastOpenedAt = old.lastOpenedAt)
        }.let { uniquedEntryTitles(it).sortedWith(entryDisplayComparator()) }
    }

    private fun normalizeEntryOrdering() {
        pages.forEach { page ->
            page.entries = page.resolvedEntries().sortedWith(entryDisplayComparator()).toMutableList()
        }
        save()
    }

    private fun refreshAvailability() {
        var changed = false
        for (page in pages) {
            var hasReady = false
            val entries = page.resolvedEntries().map { entry ->
                val exists = entryExists(page, entry)
                hasReady = hasReady || exists
                val nextStatus = if (exists) WebPageLoadStatus.READY else WebPageLoadStatus.MISSING
                var nextEntry = if (entry.lastLoadStatus == nextStatus) {
                    entry
                } else {
                    changed = true
                    entry.copy(lastLoadStatus = nextStatus)
                }
                if (exists) {
                    val entryFile = entryFileFor(page, entry)
                    val html = htmlContentFor(entry, folderFor(page))
                    val colors = backgroundColorsFor(entryFile, folderFor(page), html)
                    if (nextEntry.safeAreaTopColor != colors.top || nextEntry.safeAreaBottomColor != colors.bottom) {
                        nextEntry = nextEntry.copy(safeAreaTopColor = colors.top, safeAreaBottomColor = colors.bottom)
                        changed = true
                    }
                }
                nextEntry
            }.toMutableList()
            page.entries = entries
            val defaultEntry = defaultEntry(page)
            if (page.safeAreaTopColor != defaultEntry.safeAreaTopColor ||
                page.safeAreaBottomColor != defaultEntry.safeAreaBottomColor
            ) {
                page.safeAreaTopColor = defaultEntry.safeAreaTopColor
                page.safeAreaBottomColor = defaultEntry.safeAreaBottomColor
                changed = true
            }
            val projectStatus = if (hasReady) WebPageLoadStatus.READY else WebPageLoadStatus.MISSING
            if (page.lastLoadStatus != projectStatus) {
                page.lastLoadStatus = projectStatus
                changed = true
            }
        }
        if (changed) save()
    }

    private fun refreshRecentlyDeletedAvailability() {
        var changed = false
        for (deletedPage in recentlyDeletedPages) {
            val folder = recoverableFolderFor(deletedPage)
            var hasReady = false
            val entries = deletedPage.page.resolvedEntries().map { entry ->
                val exists = entryExists(deletedPage, entry)
                hasReady = hasReady || exists
                val nextStatus = if (exists) WebPageLoadStatus.READY else WebPageLoadStatus.MISSING
                var nextEntry = if (entry.lastLoadStatus == nextStatus) {
                    entry
                } else {
                    changed = true
                    entry.copy(lastLoadStatus = nextStatus)
                }
                if (exists) {
                    val entryFile = File(folder, entry.entryRelativePath)
                    val html = htmlContentFor(entry, folder)
                    val colors = backgroundColorsFor(entryFile, folder, html)
                    if (nextEntry.safeAreaTopColor != colors.top || nextEntry.safeAreaBottomColor != colors.bottom) {
                        nextEntry = nextEntry.copy(safeAreaTopColor = colors.top, safeAreaBottomColor = colors.bottom)
                        changed = true
                    }
                }
                nextEntry
            }.toMutableList()
            deletedPage.page.entries = entries
            val defaultEntry = defaultEntry(deletedPage.page)
            if (deletedPage.page.safeAreaTopColor != defaultEntry.safeAreaTopColor ||
                deletedPage.page.safeAreaBottomColor != defaultEntry.safeAreaBottomColor
            ) {
                deletedPage.page.safeAreaTopColor = defaultEntry.safeAreaTopColor
                deletedPage.page.safeAreaBottomColor = defaultEntry.safeAreaBottomColor
                changed = true
            }
            val projectStatus = if (hasReady) WebPageLoadStatus.READY else WebPageLoadStatus.MISSING
            if (deletedPage.page.lastLoadStatus != projectStatus) {
                deletedPage.page.lastLoadStatus = projectStatus
                changed = true
            }
        }
        if (changed) saveRecentlyDeleted()
    }

    private fun update(pageID: String, mutate: (WebPage) -> Unit) {
        val page = page(pageID) ?: return
        mutate(page)
        sortPages()
        save()
    }

    private fun updateEntry(page: WebPage, entryID: String, mutate: (WebPageEntry) -> Unit) {
        val entries = page.resolvedEntries().toMutableList()
        val index = entries.indexOfFirst { it.id == entryID }
        if (index < 0) return
        mutate(entries[index])
        page.entries = entries
        if (page.defaultEntryID == entryID) {
            page.entryRelativePath = entries[index].entryRelativePath
            page.safeAreaTopColor = entries[index].safeAreaTopColor
            page.safeAreaBottomColor = entries[index].safeAreaBottomColor
        }
    }

    private fun uniqueTitle(baseTitle: String, excludingPageID: String? = null): String {
        val existing = pages.filter { it.id != excludingPageID }.map { it.title }.toSet()
        if (!existing.contains(baseTitle)) return baseTitle
        var suffix = 2
        while (existing.contains("$baseTitle ($suffix)")) suffix += 1
        return "$baseTitle ($suffix)"
    }

    private fun uniquedEntryTitles(entries: List<WebPageEntry>): List<WebPageEntry> {
        val used = mutableSetOf<String>()
        return entries.map { entry ->
            var title = entry.title
            if (used.contains(title)) {
                var suffix = 2
                while (used.contains("$title ($suffix)")) suffix += 1
                title = "$title ($suffix)"
            }
            used.add(title)
            entry.copy(title = title)
        }
    }

    private fun entryDisplayComparator(): Comparator<WebPageEntry> {
        return compareBy<WebPageEntry> { entryLandingRank(it) }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.title }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.entryRelativePath }
    }

    private fun entryLandingRank(entry: WebPageEntry): Int {
        val parts = entry.entryRelativePath.split('/').filter { it.isNotBlank() }
        val fileName = File(entry.entryRelativePath).nameWithoutExtension.lowercase()
        val depth = parts.size
        return when (fileName) {
            "index" -> if (depth == 1) 0 else 2 + depth
            "default" -> if (depth == 1) 1 else 102 + depth
            else -> 1000
        }
    }

    private fun sortPages() {
        pages.sortWith(compareByDescending<WebPage> { it.createdAt }.thenByDescending { it.lastOpenedAt })
    }

    private fun sortRecentlyDeleted() {
        recentlyDeletedPages.sortByDescending { it.deletedAt }
    }

    private fun ensureStorage() {
        try {
            rootDirectory.mkdirs()
            webPagesDirectory.mkdirs()
            recentlyDeletedDirectory.mkdirs()
        } catch (_: Throwable) {
            throw WebPageLibraryException(strings.storageFailed)
        }
    }

    private fun uniqueFolderName(baseName: String, directory: File): String {
        val safeBase = baseName.ifBlank { UUID.randomUUID().toString() }
        var candidate = safeBase
        var suffix = 2
        while (File(directory, candidate).exists()) {
            candidate = "$safeBase-$suffix"
            suffix += 1
        }
        return candidate
    }

    private fun safeImportedFileName(sourceFileName: String): String {
        val name = File(sourceFileName).name.ifBlank { "file" }
        val withoutSeparators = name
            .replace('/', '_')
            .replace('\\', '_')
            .trim()
            .ifBlank { "file" }
        return runCatching { ZipTools.safeRelativePath(withoutSeparators) }.getOrDefault("file")
    }

    private fun load() {
        pages = runCatching {
            if (!storeFile.exists()) return@runCatching mutableListOf<WebPage>()
            val array = JSONArray(storeFile.readText())
            MutableList(array.length()) { index -> pageFromJson(array.getJSONObject(index)) }
        }.getOrElse { mutableListOf() }
        sortPages()
    }

    private fun loadRecentlyDeleted() {
        recentlyDeletedPages = runCatching {
            if (!recentlyDeletedStoreFile.exists()) return@runCatching mutableListOf<DeletedWebPage>()
            val array = JSONArray(recentlyDeletedStoreFile.readText())
            MutableList(array.length()) { index -> deletedPageFromJson(array.getJSONObject(index)) }
        }.getOrElse { mutableListOf() }
        sortRecentlyDeleted()
    }

    private fun save() {
        ensureStorage()
        val array = JSONArray()
        pages.forEach { array.put(pageToJson(it)) }
        storeFile.writeText(array.toString(2))
    }

    private fun saveRecentlyDeleted() {
        ensureStorage()
        val array = JSONArray()
        recentlyDeletedPages.forEach { array.put(deletedPageToJson(it)) }
        recentlyDeletedStoreFile.writeText(array.toString(2))
    }

    private fun saveAll() {
        save()
        saveRecentlyDeleted()
    }

    private fun pageToJson(page: WebPage): JSONObject {
        return JSONObject()
            .put("id", page.id)
            .put("title", page.title)
            .put("sourceDescription", page.sourceDescription)
            .put("sourceFileName", page.sourceFileName)
            .put("folderName", page.folderName)
            .put("entryRelativePath", page.entryRelativePath)
            .put("contentSHA256", page.contentSHA256)
            .put("createdAt", page.createdAt)
            .put("lastOpenedAt", page.lastOpenedAt)
            .put("updatedAt", page.updatedAt)
            .put("lastLoadStatus", page.lastLoadStatus.name)
            .put("defaultEntryID", page.defaultEntryID)
            .put("projectIcon", page.projectIcon?.let { projectIconToJson(it) })
            .put("safeAreaTopColor", page.safeAreaTopColor)
            .put("safeAreaBottomColor", page.safeAreaBottomColor)
            .put("projectType", page.projectType.name)
            .put("entries", JSONArray().also { entries ->
                page.resolvedEntries().forEach { entries.put(entryToJson(it)) }
            })
    }

    private fun projectIconToJson(icon: WebPageProjectIcon): JSONObject {
        return JSONObject()
            .put("source", icon.source.name)
            .put("fileName", icon.fileName)
            .put("updatedAt", icon.updatedAt)
    }

    private fun deletedPageToJson(deletedPage: DeletedWebPage): JSONObject {
        return JSONObject()
            .put("page", pageToJson(deletedPage.page))
            .put("deletedAt", deletedPage.deletedAt)
            .put("recoverableFolderName", deletedPage.recoverableFolderName)
    }

    private fun entryToJson(entry: WebPageEntry): JSONObject {
        return JSONObject()
            .put("id", entry.id)
            .put("title", entry.title)
            .put("entryRelativePath", entry.entryRelativePath)
            .put("source", entry.source?.name)
            .put("lastOpenedAt", entry.lastOpenedAt)
            .put("lastLoadStatus", entry.lastLoadStatus.name)
            .put("safeAreaTopColor", entry.safeAreaTopColor)
            .put("safeAreaBottomColor", entry.safeAreaBottomColor)
    }

    private fun pageFromJson(json: JSONObject): WebPage {
        val entriesArray = json.optJSONArray("entries") ?: JSONArray()
        val entries = MutableList(entriesArray.length()) { index -> entryFromJson(entriesArray.getJSONObject(index)) }
        val projectType = runCatching { WebPageProjectType.valueOf(json.optString("projectType")) }
            .getOrNull()
        val page = WebPage(
            id = json.getString("id"),
            title = json.optString("title"),
            sourceDescription = json.optString("sourceDescription"),
            sourceFileName = json.optString("sourceFileName").ifBlank { null },
            folderName = json.optString("folderName", json.getString("id")),
            entryRelativePath = json.optString("entryRelativePath", "index.html"),
            contentSHA256 = json.optString("contentSHA256").ifBlank { null },
            createdAt = json.optLong("createdAt"),
            lastOpenedAt = json.optLong("lastOpenedAt"),
            updatedAt = if (json.isNull("updatedAt")) null else json.optLong("updatedAt"),
            lastLoadStatus = runCatching { WebPageLoadStatus.valueOf(json.optString("lastLoadStatus")) }
                .getOrDefault(WebPageLoadStatus.READY),
            entries = entries,
            defaultEntryID = json.optString("defaultEntryID").ifBlank { null },
            projectIcon = json.optJSONObject("projectIcon")?.let { projectIconFromJson(it) },
            safeAreaTopColor = json.optString("safeAreaTopColor").ifBlank { null },
            safeAreaBottomColor = json.optString("safeAreaBottomColor").ifBlank { null },
            projectType = projectType ?: WebPageProjectType.WEB_PAGE
        )
        if (projectType == null) {
            page.projectType = page.resolvedProjectKind
        }
        return page
    }

    private fun projectIconFromJson(json: JSONObject): WebPageProjectIcon {
        return WebPageProjectIcon(
            source = runCatching { WebPageProjectIconSource.valueOf(json.optString("source")) }
                .getOrDefault(WebPageProjectIconSource.IMAGE),
            fileName = json.optString("fileName", WebPageRuntimeStorage.projectIconRelativePath),
            updatedAt = json.optLong("updatedAt")
        )
    }

    private fun deletedPageFromJson(json: JSONObject): DeletedWebPage {
        return DeletedWebPage(
            page = pageFromJson(json.getJSONObject("page")),
            deletedAt = json.optLong("deletedAt"),
            recoverableFolderName = json.optString("recoverableFolderName")
        )
    }

    private fun entryFromJson(json: JSONObject): WebPageEntry {
        return WebPageEntry(
            id = json.getString("id"),
            title = json.optString("title"),
            entryRelativePath = json.optString("entryRelativePath", "index.html"),
            source = json.optString("source").ifBlank { null }?.let { raw ->
                runCatching { WebPageEntrySource.valueOf(raw) }.getOrNull()
            },
            lastOpenedAt = json.optLong("lastOpenedAt"),
            lastLoadStatus = runCatching { WebPageLoadStatus.valueOf(json.optString("lastLoadStatus")) }
                .getOrDefault(WebPageLoadStatus.READY),
            safeAreaTopColor = json.optString("safeAreaTopColor").ifBlank { null },
            safeAreaBottomColor = json.optString("safeAreaBottomColor").ifBlank { null }
        )
    }

    companion object {
        const val maximumImportedFileByteCount: Long = 200_000_000L
        const val archiveFallbackIndexDataFileName = ".htmlanywhere-file-index.json"
        const val archiveFallbackEntryRelativePath = ".htmlanywhere-bundled-file-list.html"

        fun isSupportedHTML(name: String): Boolean = name.endsWith(".html") || name.endsWith(".htm")
        fun isSupportedArchive(name: String): Boolean = name.endsWith(".zip")

        fun isAppManagedFallbackPath(relativePath: String): Boolean {
            return relativePath == archiveFallbackEntryRelativePath ||
                relativePath == archiveFallbackIndexDataFileName ||
                relativePath == WebPageRuntimeStorage.directoryName ||
                relativePath.startsWith("${WebPageRuntimeStorage.directoryName}/")
        }

        fun percentEncodedRelativeHref(relativePath: String): String {
            return relativePath.split('/').joinToString("/") { component ->
                URLEncoder.encode(component, Charsets.UTF_8.name()).replace("+", "%20")
            }
        }

        fun sha256(bytes: ByteArray): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
            return digest.joinToString("") { "%02x".format(it) }
        }

        val bundledArchiveFallbackTemplateHTML: String = """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
              <title>File List</title>
              <style>
                :root{color-scheme:light dark;--top:#f6faff;--bottom:#eef5f7;--surface:rgba(255,255,255,.92);--border:rgba(90,112,128,.18);--ink:#20313d;--secondary:#647582;--accent:#386cff;--icon:#e9f1ff}
                @media (prefers-color-scheme:dark){:root{--top:#10181f;--bottom:#17232b;--surface:rgba(31,42,50,.92);--border:rgba(226,236,242,.14);--ink:#d4d9dc;--secondary:#a9b5bc;--accent:#8fb4ff;--icon:#25384b}}
                *{box-sizing:border-box}html{min-height:100%;background:linear-gradient(180deg,var(--top),var(--bottom));color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",sans-serif}body{min-height:100vh;margin:0;padding:28px 16px 40px}main{width:min(720px,100%);margin:0 auto}header{padding:4px 4px 18px}h1{margin:0 0 8px;font-size:28px;line-height:1.15;letter-spacing:0}.summary{margin:0;color:var(--secondary);font-size:15px;line-height:1.5}.panel{overflow:hidden;border:1px solid var(--border);border-radius:8px;background:var(--surface);box-shadow:0 3px 0 rgba(0,0,0,.06)}.file-row{display:grid;grid-template-columns:44px minmax(0,1fr) auto;gap:12px;align-items:center;min-height:64px;padding:12px 14px;border-top:1px solid var(--border);color:inherit;text-decoration:none}.file-row:first-child{border-top:0}.file-icon{display:grid;place-items:center;width:44px;height:44px;border-radius:8px;background:var(--icon);color:var(--accent);font-size:13px;font-weight:800}.file-main{display:grid;min-width:0;gap:4px}.file-name{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:16px;font-weight:700}.file-path{overflow-wrap:anywhere;color:var(--secondary);font-size:12px;line-height:1.3}.file-meta{display:grid;gap:4px;justify-items:end;color:var(--secondary);font-size:12px;white-space:nowrap}.empty{margin:0;padding:20px;color:var(--secondary);font-size:15px}@media(max-width:520px){body{padding:22px 12px 32px}.file-row{grid-template-columns:40px minmax(0,1fr)}.file-meta{grid-column:2;grid-auto-flow:column;justify-items:start}}
              </style>
            </head>
            <body>
              <main><header><h1 id="title">File List</h1><p class="summary" id="summary">This archive does not include an HTML file, so it opened as a file list.</p><p class="summary" id="archiveName"></p></header><section class="panel" id="fileList"><p class="empty">Reading files...</p></section></main>
              <script>
                (function(){var zh=(navigator.language||"").toLowerCase().indexOf("zh")===0;var t=zh?{title:"文件清单",summary:"这个压缩包没有 HTML 文件，已使用文件清单打开。点击文件会交给浏览器默认方式处理。",empty:"没有可列出的文件。",failed:"无法读取文件清单。",image:"图片",video:"视频",audio:"音频",document:"文档",resource:"资源",file:"文件"}:{title:"File List",summary:"This archive does not include an HTML file, so it opened as a file list. Tap a file to use the browser's default behavior.",empty:"No files to list.",failed:"Could not read the file list.",image:"Image",video:"Video",audio:"Audio",document:"Document",resource:"Resource",file:"File"};document.documentElement.lang=zh?"zh-Hans":"en";document.title=t.title;title.textContent=t.title;summary.textContent=t.summary;function name(p){var parts=String(p||"").split("/");return parts[parts.length-1]||p||t.file}function ext(p){var n=name(p).toLowerCase();var i=n.lastIndexOf(".");return i>=0?n.slice(i+1):""}function kind(p){var e=ext(p);if(["png","jpg","jpeg","gif","webp","svg","ico","heic","heif"].indexOf(e)>=0)return t.image;if(["mp4","mov","m4v","webm","avi","mkv"].indexOf(e)>=0)return t.video;if(["mp3","m4a","wav","aac","ogg","flac"].indexOf(e)>=0)return t.audio;if(["pdf","txt","md","json","xml","csv"].indexOf(e)>=0)return t.document;if(["css","js","map","wasm"].indexOf(e)>=0)return t.resource;return t.file}function badge(p){var k=kind(p);return k===t.image?"IMG":k===t.video?"VID":k===t.audio?"AUD":"FILE"}function size(b){var c=Number(b||0),u=["B","KB","MB","GB"],i=0;while(c>=1024&&i<u.length-1){c/=1024;i++}return c.toFixed(i===0||c>=10?0:1)+" "+u[i]}function empty(m){fileList.textContent="";var p=document.createElement("p");p.className="empty";p.textContent=m;fileList.appendChild(p)}function render(d){archiveName.textContent=d.archiveName||"";var files=Array.isArray(d.files)?d.files:[];if(!files.length){empty(t.empty);return}fileList.textContent="";files.forEach(function(f){var a=document.createElement("a");a.className="file-row";a.href=f.href||"#";var ic=document.createElement("span");ic.className="file-icon";ic.textContent=badge(f.relativePath);a.appendChild(ic);var main=document.createElement("span");main.className="file-main";var n=document.createElement("span");n.className="file-name";n.textContent=name(f.relativePath);var p=document.createElement("span");p.className="file-path";p.textContent=f.relativePath||"";main.appendChild(n);main.appendChild(p);a.appendChild(main);var meta=document.createElement("span");meta.className="file-meta";var ty=document.createElement("span");ty.textContent=kind(f.relativePath);var sz=document.createElement("span");sz.textContent=size(f.byteCount);meta.appendChild(ty);meta.appendChild(sz);a.appendChild(meta);fileList.appendChild(a)})}fetch(".htmlanywhere-file-index.json",{cache:"no-store"}).then(function(r){if(!r.ok)throw new Error("index");return r.json()}).then(render).catch(function(){empty(t.failed)})})();
              </script>
            </body>
            </html>
        """.trimIndent()
    }
}
