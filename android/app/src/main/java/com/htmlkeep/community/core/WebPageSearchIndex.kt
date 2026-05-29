package com.htmlkeep.community.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream

enum class WebPageSearchMatchKind {
    RECOMMENDATION,
    PROJECT_TITLE,
    ENTRY_TITLE,
    SOURCE_FILE,
    HTML_FILE,
    FULL_TEXT
}

data class WebPageSearchResult(
    val page: WebPage,
    val entry: WebPageEntry?,
    val matchKind: WebPageSearchMatchKind,
    val title: String,
    val subtitle: String,
    val snippet: String? = null
)

class WebPageSearchIndex(
    private val indexFile: File,
    private val maximumHtmlReadByteCount: Int = 512 * 1024
) {
    private data class IndexedDocument(
        val pageID: String,
        val entryID: String,
        val text: String,
        val normalizedText: String
    )

    private var documents: MutableMap<String, IndexedDocument> = loadDocuments()

    val hasFullTextIndex: Boolean
        get() = documents.isNotEmpty()

    fun recommendations(library: WebPageLibrary, limit: Int = 4): List<WebPageSearchResult> {
        return library.pages
            .sortedWith(compareByDescending<WebPage> { it.lastOpenedAt }.thenByDescending { it.createdAt })
            .take(limit)
            .map { page ->
                val entry = runCatching { library.defaultEntry(page) }.getOrNull()
                WebPageSearchResult(
                    page = page,
                    entry = null,
                    matchKind = WebPageSearchMatchKind.RECOMMENDATION,
                    title = page.title,
                    subtitle = page.sourceFileName ?: entry?.entryFileName.orEmpty()
                )
            }
    }

    fun search(
        library: WebPageLibrary,
        rawQuery: String,
        includeFullText: Boolean = hasFullTextIndex
    ): List<WebPageSearchResult> {
        val query = normalizedSearchText(rawQuery)
        if (query.isBlank()) return recommendations(library)

        val candidates = linkedMapOf<String, RankedResult>()
        library.pages.forEach { page ->
            val entries = page.resolvedEntries()
            val defaultEntry = runCatching { library.defaultEntry(page) }.getOrNull()
            val sourceFileName = page.sourceFileName.orEmpty()

            if (normalizedSearchText(page.title).contains(query)) {
                addCandidate(
                    candidates,
                    page,
                    null,
                    WebPageSearchMatchKind.PROJECT_TITLE,
                    400,
                    sourceFileName.ifBlank { defaultEntry?.entryFileName.orEmpty() }
                )
            }
            if (normalizedSearchText(sourceFileName).contains(query)) {
                addCandidate(
                    candidates,
                    page,
                    null,
                    WebPageSearchMatchKind.SOURCE_FILE,
                    260,
                    sourceFileName
                )
            }

            entries.forEach { entry ->
                if (normalizedSearchText(entry.title).contains(query)) {
                    addCandidate(
                        candidates,
                        page,
                        entry,
                        WebPageSearchMatchKind.ENTRY_TITLE,
                        340,
                        entry.entryFileName
                    )
                }
                if (normalizedSearchText("${entry.entryFileName} ${entry.entryRelativePath}").contains(query)) {
                    addCandidate(
                        candidates,
                        page,
                        entry,
                        WebPageSearchMatchKind.HTML_FILE,
                        300,
                        entry.entryFileName
                    )
                }
            }

            if (page.opensInNativeFileViewer) {
                library.projectFilesFor(page).forEach { file ->
                    if (normalizedSearchText("${file.fileName} ${file.relativePath}").contains(query)) {
                        addCandidate(
                            candidates,
                            page,
                            defaultEntry,
                            WebPageSearchMatchKind.HTML_FILE,
                            300,
                            file.fileName
                        )
                    }
                }
            }

            if (includeFullText) {
                entries.forEach { entry ->
                    val document = documents[documentKey(page.id, entry.id)] ?: return@forEach
                    if (document.normalizedText.contains(query)) {
                        addCandidate(
                            candidates,
                            page,
                            entry,
                            WebPageSearchMatchKind.FULL_TEXT,
                            160,
                            snippetFor(document.text, query),
                            snippetFor(document.text, query)
                        )
                    }
                }
            }
        }

        return candidates.values
            .sortedWith(
                compareByDescending<RankedResult> { it.score }
                    .thenByDescending { it.result.page.lastOpenedAt }
                    .thenByDescending { it.result.page.createdAt }
            )
            .map { it.result }
    }

    fun rebuild(library: WebPageLibrary) {
        val next = mutableMapOf<String, IndexedDocument>()
        library.pages.forEach { page ->
            if (page.opensInNativeFileViewer) return@forEach
            val folder = library.folderFor(page)
            page.resolvedEntries().forEach { entry ->
                if (!WebPageLibrary.isSupportedHTML(entry.entryFileName.lowercase())) return@forEach
                val file = File(folder, entry.entryRelativePath)
                if (!ZipTools.isDescendant(file, folder) || !file.isFile) return@forEach
                val text = HtmlSearchTextExtractor.extract(readPrefix(file))
                if (text.isBlank()) return@forEach
                next[documentKey(page.id, entry.id)] = IndexedDocument(
                    pageID = page.id,
                    entryID = entry.id,
                    text = text,
                    normalizedText = normalizedSearchText(text)
                )
            }
        }
        documents = next
        saveDocuments()
    }

    private data class RankedResult(
        val result: WebPageSearchResult,
        val score: Int
    )

    private fun addCandidate(
        candidates: MutableMap<String, RankedResult>,
        page: WebPage,
        entry: WebPageEntry?,
        kind: WebPageSearchMatchKind,
        score: Int,
        subtitle: String,
        snippet: String? = null
    ) {
        val key = "${page.id}:${entry?.id.orEmpty()}"
        val existing = candidates[key]
        if (existing != null && existing.score >= score) return
        candidates[key] = RankedResult(
            WebPageSearchResult(
                page = page,
                entry = entry,
                matchKind = kind,
                title = page.title,
                subtitle = subtitle,
                snippet = snippet
            ),
            score
        )
    }

    private fun readPrefix(file: File): String {
        val length = minOf(file.length(), maximumHtmlReadByteCount.toLong()).toInt()
        if (length <= 0) return ""
        val data = ByteArray(length)
        val count = FileInputStream(file).use { it.read(data) }
        if (count <= 0) return ""
        return data.copyOf(count).toString(Charsets.UTF_8)
    }

    private fun snippetFor(text: String, normalizedQuery: String): String {
        val normalizedText = normalizedSearchText(text)
        val matchIndex = normalizedText.indexOf(normalizedQuery).takeIf { it >= 0 } ?: 0
        val start = (matchIndex - 42).coerceAtLeast(0)
        val end = (matchIndex + normalizedQuery.length + 72).coerceAtMost(text.length)
        val prefix = if (start > 0) "..." else ""
        val suffix = if (end < text.length) "..." else ""
        return prefix + text.substring(start, end).trim() + suffix
    }

    private fun loadDocuments(): MutableMap<String, IndexedDocument> {
        return runCatching {
            val root = JSONObject(indexFile.readText(Charsets.UTF_8))
            val documentsJSON = root.optJSONArray("documents") ?: JSONArray()
            MutableList(documentsJSON.length()) { index ->
                val item = documentsJSON.getJSONObject(index)
                IndexedDocument(
                    pageID = item.optString("pageID"),
                    entryID = item.optString("entryID"),
                    text = item.optString("text"),
                    normalizedText = item.optString("normalizedText")
                )
            }
                .filter { it.pageID.isNotBlank() && it.entryID.isNotBlank() && it.normalizedText.isNotBlank() }
                .associateBy { documentKey(it.pageID, it.entryID) }
                .toMutableMap()
        }.getOrDefault(mutableMapOf())
    }

    private fun saveDocuments() {
        indexFile.parentFile?.mkdirs()
        val documentsJSON = JSONArray()
        documents.values.forEach { document ->
            documentsJSON.put(
                JSONObject()
                    .put("pageID", document.pageID)
                    .put("entryID", document.entryID)
                    .put("text", document.text)
                    .put("normalizedText", document.normalizedText)
            )
        }
        indexFile.writeText(
            JSONObject()
                .put("schemaVersion", 1)
                .put("documents", documentsJSON)
                .toString(),
            Charsets.UTF_8
        )
    }

    private fun documentKey(pageID: String, entryID: String): String = "$pageID:$entryID"

    companion object {
        fun normalizedSearchText(text: String): String {
            return text.lowercase()
                .trim()
                .split(Regex("\\s+"))
                .filter { it.isNotBlank() }
                .joinToString(" ")
        }
    }
}

object HtmlSearchTextExtractor {
    fun extract(html: String): String {
        return html
            .replace(Regex("<!--[\\s\\S]*?-->"), " ")
            .replace(Regex("<\\s*(script|style|noscript|svg)\\b[\\s\\S]*?<\\s*/\\s*\\1\\s*>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<[^>]+>"), " ")
            .let { decodeEntities(it) }
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
            .joinToString(" ")
    }

    private fun decodeEntities(text: String): String {
        return text
            .replace("&nbsp;", " ", ignoreCase = true)
            .replace("&amp;", "&", ignoreCase = true)
            .replace("&lt;", "<", ignoreCase = true)
            .replace("&gt;", ">", ignoreCase = true)
            .replace("&quot;", "\"", ignoreCase = true)
            .replace("&#39;", "'", ignoreCase = true)
            .replace("&apos;", "'", ignoreCase = true)
            .replace(Regex("&#x([0-9a-fA-F]+);")) { match ->
                match.groupValues[1].toIntOrNull(16)?.toChar()?.toString() ?: match.value
            }
            .replace(Regex("&#([0-9]+);")) { match ->
                match.groupValues[1].toIntOrNull()?.toChar()?.toString() ?: match.value
            }
    }
}
