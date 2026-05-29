package com.htmlkeep.community.core

import java.io.File

object HtmlMetadata {
    fun title(htmlContent: String, fallbackFile: File, untitled: String): String {
        return documentTitle(htmlContent) ?: fallbackFile.nameWithoutExtension.ifBlank { untitled }
    }

    fun archiveTitle(fileName: String, untitled: String): String {
        return fileName.substringBeforeLast('.', fileName).ifBlank { untitled }
    }

    fun normalizedDisplayTitle(title: String): String {
        return title.trim().split(Regex("\\s+")).filter { it.isNotBlank() }.joinToString(" ")
    }

    private fun documentTitle(htmlContent: String): String? {
        val head = firstTagContent("head", htmlContent) ?: return null
        val title = firstTagContent("title", head) ?: return null
        return normalizeTitle(title).ifBlank { null }
    }

    private fun firstTagContent(tagName: String, text: String): String? {
        val opening = Regex("<\\s*$tagName(?:\\s[^>]*)?>", RegexOption.IGNORE_CASE).find(text) ?: return null
        val rest = text.substring(opening.range.last + 1)
        val closing = Regex("</\\s*$tagName\\s*>", RegexOption.IGNORE_CASE).find(rest) ?: return null
        return rest.substring(0, closing.range.first)
    }

    private fun normalizeTitle(title: String): String {
        val withoutTags = title.replace(Regex("<[^>]+>"), " ")
        return decodeBasicEntities(withoutTags)
            .trim()
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
            .joinToString(" ")
    }

    private fun decodeBasicEntities(text: String): String {
        return text
            .replace("&nbsp;", " ", ignoreCase = true)
            .replace("&amp;", "&", ignoreCase = true)
            .replace("&lt;", "<", ignoreCase = true)
            .replace("&gt;", ">", ignoreCase = true)
            .replace("&quot;", "\"", ignoreCase = true)
            .replace("&#39;", "'", ignoreCase = true)
            .replace("&apos;", "'", ignoreCase = true)
    }
}
