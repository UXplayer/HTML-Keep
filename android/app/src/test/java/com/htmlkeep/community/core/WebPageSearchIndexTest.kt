package com.htmlkeep.community.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class WebPageSearchIndexTest {
    @Test
    fun basicSearchMatchesProjectEntrySourceAndFileNames() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val imported = library.importBytes(
            zipBytes(
                "index.html" to "<html><head><title>Landing</title></head><body></body></html>".toByteArray(),
                "chapters/intro.html" to "<html><head><title>Alpha Page</title></head><body></body></html>".toByteArray()
            ),
            "bundle.zip"
        )
        library.renamePage(imported.page, "Project Atlas")
        library.importBytes("plain notes".toByteArray(), "notes-final.txt")
        val index = WebPageSearchIndex(File(root, "search-index.json"))

        assertEquals("Project Atlas", index.search(library, "atlas").first().page.title)
        assertEquals("chapters/intro.html", index.search(library, "alpha").first().entry!!.entryRelativePath)
        assertEquals("chapters/intro.html", index.search(library, "intro.html").first().entry!!.entryRelativePath)
        assertEquals("Project Atlas", index.search(library, "bundle.zip").first().page.title)
        assertEquals(WebPageProjectType.NATIVE_FILE, index.search(library, "notes-final").first().page.resolvedProjectKind)
    }

    @Test
    fun fullTextIndexExtractsReadableHtmlAndIgnoresNoisyTags() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        library.importBytes(
            """
                <html>
                  <head>
                    <title>Quiet Title</title>
                    <style>.hidden { color: red; } style-only-token</style>
                    <script>var marker = "script-only-token";</script>
                  </head>
                  <body><h1>Visible orchid &amp; fern</h1></body>
                </html>
            """.trimIndent().toByteArray(),
            "quiet.html"
        )
        val index = WebPageSearchIndex(File(root, "search-index.json"))

        assertTrue(index.search(library, "orchid").isEmpty())

        index.rebuild(library)

        val result = index.search(library, "orchid").first()
        assertEquals(WebPageSearchMatchKind.FULL_TEXT, result.matchKind)
        assertTrue(result.snippet!!.contains("orchid"))
        assertTrue(index.search(library, "script-only-token").isEmpty())
        assertTrue(index.search(library, "style-only-token").isEmpty())
    }

    @Test
    fun searchOnlyReturnsActivePagesEvenWhenIndexStillHasDeletedDocuments() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        val imported = library.importBytes(
            "<html><head><title>Archive Candidate</title></head><body>restore-token</body></html>".toByteArray(),
            "candidate.html"
        )
        val index = WebPageSearchIndex(File(root, "search-index.json"))
        index.rebuild(library)

        assertEquals(imported.page.id, index.search(library, "restore-token").first().page.id)

        library.delete(imported.page)

        assertTrue(index.search(library, "restore-token").isEmpty())

        val restored = library.restore(library.recentlyDeletedPages.first())

        assertEquals(restored.id, index.search(library, "restore-token").first().page.id)

        library.delete(restored)
        library.permanentlyDelete(library.recentlyDeletedPages.first())

        assertTrue(index.search(library, "restore-token").isEmpty())
    }

    @Test
    fun damagedIndexCanBeRebuiltFromProjectFolders() {
        val root = tempDir()
        val library = WebPageLibrary(root)
        library.importBytes(
            "<html><head><title>Broken Index</title></head><body>rebuilt-token</body></html>".toByteArray(),
            "broken.html"
        )
        val indexFile = File(root, "search-index.json").apply {
            writeText("{not json", Charsets.UTF_8)
        }
        val index = WebPageSearchIndex(indexFile)

        assertTrue(index.search(library, "rebuilt-token").isEmpty())

        index.rebuild(library)

        assertEquals("Broken Index", index.search(library, "rebuilt-token").first().page.title)
    }

    private fun tempDir(): File = Files.createTempDirectory("html-anywhere-search-test").toFile()

    private fun zipBytes(vararg entries: Pair<String, ByteArray>): ByteArray {
        val file = File.createTempFile("html-anywhere-search", ".zip")
        ZipOutputStream(file.outputStream()).use { zip ->
            for ((path, data) in entries) {
                zip.putNextEntry(ZipEntry(path))
                zip.write(data)
                zip.closeEntry()
            }
        }
        return file.readBytes().also { file.delete() }
    }
}
