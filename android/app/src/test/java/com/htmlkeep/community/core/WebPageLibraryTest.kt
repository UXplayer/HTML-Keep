package com.htmlkeep.community.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class WebPageLibraryTest {
    @Test
    fun importsHtmlAsSinglePageProjectAndDeduplicatesByContent() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val html = """<html><head><title>Hello Page</title></head><body>Hello</body></html>""".toByteArray()

        val first = library.importBytes(html, "hello.html")
        val second = library.importBytes(html, "copy.html")

        assertEquals(1, library.pages.size)
        assertEquals(first.page.id, second.page.id)
        assertEquals("Hello Page", library.pages.first().title)
        assertTrue(File(root, "WebPages/${first.page.folderName}/index.html").exists())
    }

    @Test
    fun importsZipAsOneProjectWithSortedHtmlEntries() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val zip = zipBytes(
            "assets/site.css" to "body { color: red; }".toByteArray(),
            "chapter/page.html" to """<html><head><title>Chapter</title></head></html>""".toByteArray(),
            "index.html" to """<html><head><title>Landing</title></head></html>""".toByteArray()
        )

        val result = library.importBytes(zip, "bundle.zip")

        assertEquals(1, library.pages.size)
        assertEquals(2, result.page.resolvedEntries().size)
        assertEquals("index.html", library.defaultEntry(result.page).entryRelativePath)
        assertTrue(File(root, "WebPages/${result.page.folderName}/assets/site.css").exists())
    }

    @Test
    fun importsPlainTextAsNativeFileProject() {
        val root = tempDir()
        val library = WebPageLibrary(root)

        val result = library.importBytes("hello native file".toByteArray(), "notes.txt")

        assertEquals(WebPageProjectType.NATIVE_FILE, result.page.resolvedProjectKind)
        assertTrue(result.page.opensInNativeFileViewer)
        assertEquals(WebPageEntrySource.NATIVE_FILE, result.entry.source)
        assertEquals("notes.txt", result.entry.entryRelativePath)
        assertTrue(File(root, "WebPages/${result.page.folderName}/notes.txt").exists())
        assertEquals(
            listOf(WebPageProjectFile("notes.txt", "notes.txt", "hello native file".toByteArray().size.toLong())),
            library.projectFilesFor(result.page)
        )
    }

    @Test
    fun importsZipWithoutHtmlAsFileCollectionWithoutVisibleFallbackHtml() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val zip = zipBytes(
            "docs/readme.txt" to "Read me".toByteArray(),
            "data/config.json" to """{"ok":true}""".toByteArray()
        )

        val result = library.importBytes(zip, "assets.zip")
        val folder = library.folderFor(result.page)

        assertEquals(WebPageProjectType.FILE_COLLECTION, result.page.resolvedProjectKind)
        assertTrue(result.page.opensInNativeFileViewer)
        assertEquals(WebPageEntrySource.FILE_INDEX, result.entry.source)
        assertEquals(WebPageLibrary.archiveFallbackIndexDataFileName, result.entry.entryRelativePath)
        assertFalse(File(folder, WebPageLibrary.archiveFallbackEntryRelativePath).exists())
        assertTrue(File(folder, WebPageLibrary.archiveFallbackIndexDataFileName).exists())
        assertEquals(
            listOf("data/config.json", "docs/readme.txt"),
            library.projectFilesFor(result.page).map { it.relativePath }
        )
    }

    @Test
    fun rejectsZipPathTraversal() {
        val library = WebPageLibrary(tempDir())
        val zip = zipBytes("../escape.html" to "<html></html>".toByteArray())

        try {
            library.importBytes(zip, "bad.zip")
        } catch (error: WebPageLibraryException) {
            assertEquals(0, library.pages.size)
            return
        }

        throw AssertionError("Expected unsafe ZIP to fail")
    }

    @Test
    fun rejectsSourceFilesAboveImportLimitBeforeCreatingProjects() {
        val root = tempDir()
        val library = WebPageLibrary(
            root,
            maximumSourceFileByteCount = 4,
            maximumExpandedArchiveByteCount = Long.MAX_VALUE
        )

        assertImportTooLarge { library.importBytes(ByteArray(5), "page.html") }
        assertImportTooLarge { library.importBytes(ByteArray(5), "notes.txt") }
        assertImportTooLarge { library.importBytes(zipBytes("index.html" to "A".toByteArray()), "page.zip") }

        val sourceFile = File(tempDir(), "large.txt").apply { writeBytes(ByteArray(5)) }
        assertImportTooLarge { library.importFromFile(sourceFile) }

        assertEquals(0, library.pages.size)
        assertNoProjectFolders(root)
    }

    @Test
    fun zipExpandedSizeLimitAllowsBoundaryAndRejectsAdditionalByte() {
        val allowedRoot = tempDir()
        val allowedLibrary = WebPageLibrary(
            allowedRoot,
            maximumSourceFileByteCount = Long.MAX_VALUE,
            maximumExpandedArchiveByteCount = 4
        )
        val allowed = allowedLibrary.importBytes(zipBytes("files/a.txt" to ByteArray(4)), "files.zip")

        assertEquals(1, allowedLibrary.pages.size)
        assertEquals(WebPageProjectType.FILE_COLLECTION, allowed.page.resolvedProjectKind)
        assertTrue(File(allowedLibrary.folderFor(allowed.page), "files/a.txt").exists())

        val rejectedRoot = tempDir()
        val rejectedLibrary = WebPageLibrary(
            rejectedRoot,
            maximumSourceFileByteCount = Long.MAX_VALUE,
            maximumExpandedArchiveByteCount = 4
        )

        assertImportTooLarge { rejectedLibrary.importBytes(zipBytes("files/a.txt" to ByteArray(5)), "files.zip") }

        assertEquals(0, rejectedLibrary.pages.size)
        assertNoProjectFolders(rejectedRoot)
    }

    @Test
    fun duplicateZipRestoreOverExpandedLimitKeepsExistingProjectFolder() {
        val root = tempDir()
        val zip = zipBytes("index.html" to "<html><head><title>Saved</title></head></html>".toByteArray())
        val originalLibrary = WebPageLibrary(
            root,
            maximumSourceFileByteCount = Long.MAX_VALUE,
            maximumExpandedArchiveByteCount = Long.MAX_VALUE
        )
        val result = originalLibrary.importBytes(zip, "project.zip")
        val folder = originalLibrary.folderFor(result.page)
        val originalHtml = File(folder, "index.html").readText()
        WebPageRuntimeStorage.saveLocalStorageItems(folder, mapOf("progress" to "saved"))

        val strictLibrary = WebPageLibrary(
            root,
            maximumSourceFileByteCount = Long.MAX_VALUE,
            maximumExpandedArchiveByteCount = 0
        )

        assertImportTooLarge { strictLibrary.importBytes(zip, "project-copy.zip") }

        val page = strictLibrary.pages.first()
        val preservedFolder = strictLibrary.folderFor(page)
        assertEquals(result.page.id, page.id)
        assertEquals(originalHtml, File(preservedFolder, "index.html").readText())
        assertEquals(mapOf("progress" to "saved"), WebPageRuntimeStorage.localStorageItems(preservedFolder))
        assertFalse(File(root, "WebPages").listFiles().orEmpty().any { it.name.contains("-restore-") })
    }

    @Test
    fun renamePageKeepsEntryTitlesAndRelativePathsUnchanged() {
        val library = WebPageLibrary(tempDir())
        val zip = zipBytes(
            "index.html" to """<html><head><title>One</title></head></html>""".toByteArray(),
            "page.html" to """<html><head><title>Two</title></head></html>""".toByteArray()
        )
        val result = library.importBytes(zip, "pages.zip")
        val page = result.page
        val beforeEntries = page.resolvedEntries().map { it.id to (it.title to it.entryRelativePath) }

        assertTrue(library.renamePage(page, "Project One"))

        val renamed = library.page(page.id)!!
        assertEquals("Project One", renamed.title)
        assertEquals(beforeEntries, renamed.resolvedEntries().map { it.id to (it.title to it.entryRelativePath) })
    }

    @Test
    fun shareExporterSharesSingleHtmlDirectlyAndArchivesResourceProjects() {
        val root = tempDir()
        val singleFolder = File(root, "single").apply { mkdirs() }
        File(singleFolder, "index.html").writeText("<html></html>")
        WebPageRuntimeStorage.saveLocalStorageItems(singleFolder, mapOf("progress" to "42"))
        val exporter = ShareExporter(File(root, "cache"))

        val single = exporter.shareFileForProject(singleFolder, "single")

        assertFalse(single.isArchive)
        assertEquals("index.html", single.file.name)

        val resourceFolder = File(root, "resource").apply { mkdirs() }
        File(resourceFolder, "index.html").writeText("<html></html>")
        File(resourceFolder, "style.css").writeText("body{}")
        WebPageRuntimeStorage.saveLocalStorageItems(resourceFolder, mapOf("progress" to "99"))

        val archive = exporter.shareFileForProject(resourceFolder, "resource")

        assertTrue(archive.isArchive)
        assertTrue(archive.file.exists())
        assertFalse(zipEntryNames(archive.file).contains(WebPageRuntimeStorage.localStorageRelativePath))
    }

    @Test
    fun runtimeStoragePersistsLocalStorageSnapshot() {
        val folder = File(tempDir(), "project").apply { mkdirs() }

        assertTrue(WebPageRuntimeStorage.saveLocalStorageItems(folder, mapOf("level" to "7")))
        assertEquals(mapOf("level" to "7"), WebPageRuntimeStorage.localStorageItems(folder))
        assertFalse(WebPageRuntimeStorage.saveLocalStorageItems(folder, mapOf("level" to "7")))

        WebPageRuntimeStorage.clearRuntimeData(folder)

        assertEquals(emptyMap<String, String>(), WebPageRuntimeStorage.localStorageItems(folder))
        assertTrue(File(folder, WebPageRuntimeStorage.localStorageRelativePath).exists())
    }

    @Test
    fun runtimeStorageClearKeepsProjectIconThumbnail() {
        val folder = File(tempDir(), "project").apply { mkdirs() }
        val iconFile = File(folder, WebPageRuntimeStorage.versionedProjectIconRelativePath(1234L))
        iconFile.parentFile?.mkdirs()
        iconFile.writeText("icon")
        WebPageRuntimeStorage.saveLocalStorageItems(folder, mapOf("progress" to "done"))

        WebPageRuntimeStorage.clearRuntimeData(folder)

        assertTrue(iconFile.exists())
        assertEquals(emptyMap<String, String>(), WebPageRuntimeStorage.localStorageItems(folder))
    }

    @Test
    fun projectIconRulesPreferLogoImagesAndRejectDecorativeCandidates() {
        val logoScore = ProjectIconRules.imageScore("assets/product-logo.png", 24_000, 160, 160)

        assertNotNull(logoScore)
        assertNull(ProjectIconRules.imageScore("assets/banner-wide.png", 24_000, 420, 90))
        assertNull(ProjectIconRules.imageScore("assets/background-texture.png", 24_000, 160, 160))
        assertNull(ProjectIconRules.imageScore("assets/sprite-sheet.png", 24_000, 128, 128))
        assertNull(ProjectIconRules.imageScore("assets/tiny-logo.png", 400, 24, 24))
    }

    @Test
    fun projectIconRulesPreferLargerManifestIcons() {
        val small = ProjectIconRules.manifestIconScore("64x64", "image/png", null)
        val large = ProjectIconRules.manifestIconScore("192x192", "image/png", null)

        assertTrue(large > small)
    }

    @Test
    fun deleteMovesProjectToRecentlyDeletedAndRestoreKeepsIdentity() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val result = library.importBytes(
            """<html><head><title>Saved</title></head><body></body></html>""".toByteArray(),
            "saved.html"
        )
        val pageID = result.page.id

        library.delete(result.page)

        assertEquals(0, library.pages.size)
        assertEquals(1, library.recentlyDeletedPages.size)
        assertTrue(library.recoverableFolderFor(library.recentlyDeletedPages.first()).exists())

        val restored = library.restore(library.recentlyDeletedPages.first())

        assertEquals(pageID, restored.id)
        assertEquals(1, library.pages.size)
        assertEquals(0, library.recentlyDeletedPages.size)
        assertTrue(library.entryFileFor(restored).exists())
    }

    @Test
    fun permanentlyDeleteRemovesRecoverableFolder() {
        val library = WebPageLibrary(tempDir())
        val result = library.importBytes("<html></html>".toByteArray(), "page.html")

        library.delete(result.page)
        val deleted = library.recentlyDeletedPages.first()
        val recoverableFolder = library.recoverableFolderFor(deleted)

        library.permanentlyDelete(deleted)

        assertEquals(0, library.recentlyDeletedPages.size)
        assertFalse(recoverableFolder.exists())
    }

    @Test
    fun restoreDoesNotMergeSameContentDifferentIdentity() {
        val root = tempDir()
        val bytes = "<html><head><title>Same</title></head></html>".toByteArray()
        val library = WebPageLibrary(root)
        val original = library.importBytes(bytes, "same.html")

        library.delete(original.page)
        val reimported = library.importBytes(bytes, "same-again.html")
        val restored = library.restore(library.recentlyDeletedPages.first())
        val reloaded = WebPageLibrary(root)

        assertEquals(2, reloaded.pages.size)
        assertTrue(reloaded.pages.any { it.id == original.page.id })
        assertTrue(reloaded.pages.any { it.id == reimported.page.id })
        assertEquals(original.page.id, restored.id)
    }

    @Test
    fun duplicateZipRestoreKeepsRuntimeStorageDirectory() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val zip = zipBytes("index.html" to "<html></html>".toByteArray())
        val result = library.importBytes(zip, "project.zip")
        val folder = library.folderFor(result.page)
        WebPageRuntimeStorage.saveLocalStorageItems(folder, mapOf("progress" to "saved"))

        library.importBytes(zip, "project-copy.zip")

        assertEquals(mapOf("progress" to "saved"), WebPageRuntimeStorage.localStorageItems(folder))
    }

    @Test
    fun duplicateZipWithoutHtmlReusesProjectAndKeepsRuntimeStorageDirectory() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val zip = zipBytes("readme.txt" to "hello".toByteArray())
        val first = library.importBytes(zip, "files.zip")
        val folder = library.folderFor(first.page)
        WebPageRuntimeStorage.saveLocalStorageItems(folder, mapOf("progress" to "saved"))

        val second = library.importBytes(zip, "files-copy.zip")

        assertEquals(1, library.pages.size)
        assertEquals(first.page.id, second.page.id)
        assertEquals(WebPageProjectType.FILE_COLLECTION, second.page.resolvedProjectKind)
        assertEquals(mapOf("progress" to "saved"), WebPageRuntimeStorage.localStorageItems(folder))
    }

    @Test
    fun projectFilesForReadsLatestIndexAndSupportsDeletedProjects() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val result = library.importBytes(zipBytes("a.txt" to "A".toByteArray()), "files.zip")
        val indexFile = File(library.folderFor(result.page), WebPageLibrary.archiveFallbackIndexDataFileName)
        indexFile.writeText(
            JSONObject()
                .put("schemaVersion", 1)
                .put("archiveName", "files.zip")
                .put(
                    "files",
                    JSONArray().put(
                        JSONObject()
                            .put("relativePath", "changed.txt")
                            .put("href", "changed.txt")
                            .put("byteCount", 99)
                    )
                )
                .toString(),
            Charsets.UTF_8
        )

        assertEquals(listOf("changed.txt"), library.projectFilesFor(result.page).map { it.relativePath })

        library.delete(result.page)

        assertEquals(
            listOf(WebPageProjectFile("changed.txt", "changed.txt", 99)),
            library.projectFilesFor(library.recentlyDeletedPages.first())
        )
    }

    @Test
    fun oldBundledArchiveIndexEntriesResolveAsFileCollections() {
        val root = tempDir()
        val pageID = "old-page"
        val folder = File(root, "WebPages/$pageID").apply { mkdirs() }
        File(folder, "readme.txt").writeText("legacy")
        File(folder, WebPageLibrary.archiveFallbackIndexDataFileName).writeText(
            JSONObject()
                .put("schemaVersion", 1)
                .put("archiveName", "legacy.zip")
                .put(
                    "files",
                    JSONArray().put(
                        JSONObject()
                            .put("relativePath", "readme.txt")
                            .put("href", "readme.txt")
                            .put("byteCount", 6)
                    )
                )
                .toString(),
            Charsets.UTF_8
        )
        File(root, "web-pages.json").writeText(
            JSONArray().put(
                JSONObject()
                    .put("id", pageID)
                    .put("title", "legacy")
                    .put("sourceDescription", "")
                    .put("sourceFileName", "legacy.zip")
                    .put("folderName", pageID)
                    .put("entryRelativePath", WebPageLibrary.archiveFallbackEntryRelativePath)
                    .put("contentSHA256", "legacy-sha")
                    .put("createdAt", 1)
                    .put("lastOpenedAt", 1)
                    .put("updatedAt", 1)
                    .put("lastLoadStatus", WebPageLoadStatus.READY.name)
                    .put("defaultEntryID", "legacy-entry")
                    .put(
                        "entries",
                        JSONArray().put(
                            JSONObject()
                                .put("id", "legacy-entry")
                                .put("title", "File List")
                                .put("entryRelativePath", WebPageLibrary.archiveFallbackEntryRelativePath)
                                .put("source", WebPageEntrySource.BUNDLED_ARCHIVE_INDEX.name)
                                .put("lastOpenedAt", 1)
                                .put("lastLoadStatus", WebPageLoadStatus.READY.name)
                        )
                    )
            ).toString(),
            Charsets.UTF_8
        )

        val library = WebPageLibrary(root)
        val page = library.pages.first()

        assertEquals(WebPageProjectType.FILE_COLLECTION, page.resolvedProjectKind)
        assertTrue(page.opensInNativeFileViewer)
        assertTrue(library.entryExists(page, library.defaultEntry(page)))
        assertEquals(listOf("readme.txt"), library.projectFilesFor(page).map { it.relativePath })
    }

    @Test
    fun htmlBackgroundExtractorUsesPageLevelEdgeColors() {
        val html = """
            <html>
            <head>
                <style>
                    .card { background: #ff0000; }
                    body { background: linear-gradient(180deg, #dde7fb 0%, #f6f9fc 100%); }
                </style>
            </head>
            <body><div class="card">Ignored</div></body>
            </html>
        """.trimIndent()

        val colors = HtmlBackgroundExtractor.extract(html)

        assertEquals("#DDE7FB", colors.top)
        assertEquals("#F6F9FC", colors.bottom)
    }

    @Test
    fun htmlBackgroundExtractorUsesLinkedStylesheetInsideProjectFolder() {
        val root = tempDir()
        val assets = File(root, "assets").also { it.mkdirs() }
        val htmlFile = File(root, "index.html")
        val stylesheet = File(assets, "style.css")
        val html = """
            <html>
            <head>
                <link rel="stylesheet" href="assets/style.css">
            </head>
            <body>Linked CSS background</body>
            </html>
        """.trimIndent()
        htmlFile.writeText(html)
        stylesheet.writeText(
            """
                :root {
                  --bg: #f4f7f3;
                }

                body {
                  background:
                    linear-gradient(140deg, rgba(47, 125, 109, 0.16), transparent 42%),
                    linear-gradient(210deg, rgba(138, 86, 36, 0.12), transparent 36%),
                    var(--bg);
                }

                @media (prefers-color-scheme: dark) {
                  :root {
                    --bg: #101614;
                  }
                }
            """.trimIndent()
        )

        val colors = HtmlBackgroundExtractor.extract(html, htmlFile, root)

        assertEquals("#F4F7F3", colors.top)
        assertEquals("#F4F7F3", colors.bottom)
    }

    @Test
    fun htmlBackgroundExtractorIgnoresLinkedStylesheetOutsideProjectFolder() {
        val root = tempDir()
        val outside = tempDir()
        val htmlFile = File(root, "index.html")
        val stylesheet = File(outside, "style.css")
        val html = """
            <html>
            <head>
                <link rel="stylesheet" href="../${outside.name}/style.css">
            </head>
            <body>Outside CSS background</body>
            </html>
        """.trimIndent()
        htmlFile.writeText(html)
        stylesheet.writeText("body { background: #ff0000; }")

        val colors = HtmlBackgroundExtractor.extract(html, htmlFile, root)

        assertEquals("#FFFFFF", colors.top)
        assertEquals("#FFFFFF", colors.bottom)
    }

    @Test
    fun htmlBackgroundExtractorFallsBackToWhite() {
        val colors = HtmlBackgroundExtractor.extract("<html><body>No explicit background</body></html>")

        assertEquals("#FFFFFF", colors.top)
        assertEquals("#FFFFFF", colors.bottom)
    }

    private fun tempDir(): File = Files.createTempDirectory("html-anywhere-test").toFile()

    private fun zipBytes(vararg entries: Pair<String, ByteArray>): ByteArray {
        val file = File.createTempFile("html-anywhere", ".zip")
        ZipOutputStream(file.outputStream()).use { zip ->
            for ((path, data) in entries) {
                zip.putNextEntry(ZipEntry(path))
                zip.write(data)
                zip.closeEntry()
            }
        }
        return file.readBytes().also { file.delete() }
    }

    private fun zipEntryNames(file: File): Set<String> {
        return ZipInputStream(file.inputStream()).use { zip ->
            val names = mutableSetOf<String>()
            while (true) {
                val entry = zip.nextEntry ?: break
                names.add(entry.name)
                zip.closeEntry()
            }
            names
        }
    }

    private fun assertImportTooLarge(block: () -> Unit) {
        try {
            block()
        } catch (error: WebPageLibraryException) {
            assertEquals("This file is too large to import.", error.message)
            return
        }

        throw AssertionError("Expected oversized import to fail")
    }

    private fun assertNoProjectFolders(root: File) {
        val webPages = File(root, "WebPages")
        assertTrue(!webPages.exists() || webPages.listFiles().orEmpty().none { it.isDirectory })
    }
}
