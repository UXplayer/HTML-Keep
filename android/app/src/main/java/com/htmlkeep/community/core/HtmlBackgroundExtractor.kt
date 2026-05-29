package com.htmlkeep.community.core

import java.io.File
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

object HtmlBackgroundExtractor {
    data class EdgeColors(val top: String, val bottom: String)

    fun extract(html: String): EdgeColors {
        return extract(html, emptyList())
    }

    fun extract(html: String, htmlFile: File, projectFolder: File): EdgeColors {
        return extract(html, linkedStylesheetContents(html, htmlFile, projectFolder))
    }

    private fun extract(html: String, stylesheetContents: List<String>): EdgeColors {
        val withoutComments = html.replace(Regex("/\\*[\\s\\S]*?\\*/"), "")
        val stylesheetsWithoutComments = stylesheetContents.map { it.replace(Regex("/\\*[\\s\\S]*?\\*/"), "") }
        val cssVariables = cssVariables(
            (stylesheetsWithoutComments + styleBlocks(withoutComments))
                .joinToString("\n") { removeCssAtRuleBlocks(it) }
        )
        val candidates = mutableListOf<String>()

        inlineStyle("body", withoutComments)?.let { candidates.add(it) }
        inlineStyle("html", withoutComments)?.let { candidates.add(it) }
        (stylesheetsWithoutComments + styleBlocks(withoutComments)).forEach { style ->
            val topLevelStyle = removeCssAtRuleBlocks(style)
            cssRule("body", topLevelStyle)?.let { candidates.add(it) }
            cssRule("html", topLevelStyle)?.let { candidates.add(it) }
            cssRule(":root", topLevelStyle)?.let { candidates.add(it) }
        }

        for (candidate in candidates) {
            colorsFromDeclarations(candidate, cssVariables)?.let { return it }
        }
        return EdgeColors("#FFFFFF", "#FFFFFF")
    }

    private fun linkedStylesheetContents(html: String, htmlFile: File, projectFolder: File): List<String> {
        return Regex("<link\\b[^>]*>", RegexOption.IGNORE_CASE)
            .findAll(html)
            .mapNotNull { match ->
                val tag = match.value
                val rel = attributeValue("rel", tag)?.lowercase() ?: return@mapNotNull null
                if (!rel.split(Regex("\\s+")).contains("stylesheet")) return@mapNotNull null
                val href = attributeValue("href", tag) ?: return@mapNotNull null
                val stylesheet = localStylesheetFile(href, htmlFile, projectFolder) ?: return@mapNotNull null
                if (!stylesheet.exists() || stylesheet.extension.lowercase() != "css") return@mapNotNull null
                runCatching { stylesheet.readText(Charsets.UTF_8) }.getOrNull()
            }
            .toList()
    }

    private fun attributeValue(name: String, tag: String): String? {
        val escapedName = Regex.escape(name)
        val match = Regex(
            "\\b$escapedName\\s*=\\s*(?:([\"'])([\\s\\S]*?)\\1|([^\\s\"'=<>`]+))",
            RegexOption.IGNORE_CASE
        ).find(tag) ?: return null
        return match.groups[2]?.value?.trim() ?: match.groups[3]?.value?.trim()
    }

    private fun localStylesheetFile(href: String, htmlFile: File, projectFolder: File): File? {
        val trimmed = href.trim()
        if (trimmed.isBlank() || trimmed.startsWith("#") || trimmed.startsWith("//")) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (uri.scheme != null || uri.host != null) return null
        val path = uri.path ?: return null
        if (path.isBlank()) return null
        val decodedPath = runCatching { URLDecoder.decode(path, StandardCharsets.UTF_8) }.getOrNull() ?: return null
        val candidate = if (decodedPath.startsWith("/")) {
            File(projectFolder, decodedPath.removePrefix("/"))
        } else {
            File(htmlFile.parentFile ?: projectFolder, decodedPath)
        }.canonicalFile
        val root = projectFolder.canonicalFile
        return candidate.takeIf { it.path == root.path || it.path.startsWith(root.path + File.separator) }
    }

    private fun inlineStyle(element: String, html: String): String? {
        val match = Regex("<$element\\b[^>]*\\sstyle\\s*=\\s*([\"'])([\\s\\S]*?)\\1", RegexOption.IGNORE_CASE)
            .find(html) ?: return null
        return match.groupValues.getOrNull(2)
    }

    private fun styleBlocks(html: String): List<String> {
        return Regex("<style\\b[^>]*>([\\s\\S]*?)</style>", RegexOption.IGNORE_CASE)
            .findAll(html)
            .mapNotNull { it.groupValues.getOrNull(1) }
            .toList()
    }

    private fun cssRule(selector: String, css: String): String? {
        Regex("([^{}]+)\\{([^{}]*)\\}")
            .findAll(css)
            .forEach { match ->
                val selectors = match.groupValues[1].split(',').map { it.trim().lowercase() }
                if (selectors.any { it == selector || it.startsWith("$selector.") || it.startsWith("$selector#") }) {
                    return match.groupValues[2]
                }
            }
        return null
    }

    private fun colorsFromDeclarations(declarations: String, variables: Map<String, String>): EdgeColors? {
        val backgroundValue = Regex("\\bbackground(?:-color)?\\s*:\\s*([^;]+)", RegexOption.IGNORE_CASE)
            .find(declarations)
            ?.groupValues
            ?.getOrNull(1)
            ?: return null
        val resolvedBackgroundValue = resolveCssVariables(backgroundValue, variables)
        baseColorLayer(resolvedBackgroundValue)?.let { color ->
            return EdgeColors(color, color)
        }
        val colors = colorTokens(resolvedBackgroundValue)
        if (colors.isEmpty()) return null
        return EdgeColors(colors.first(), colors.last())
    }

    private fun baseColorLayer(value: String): String? {
        val lastLayer = splitBackgroundLayers(value).lastOrNull()?.trim().orEmpty()
        if (lastLayer.isBlank()) return null
        if (lastLayer.contains("gradient(", ignoreCase = true) || lastLayer.contains("url(", ignoreCase = true)) {
            return null
        }
        val colors = colorTokens(lastLayer)
        return colors.singleOrNull()
    }

    private fun splitBackgroundLayers(value: String): List<String> {
        val layers = mutableListOf<String>()
        var depth = 0
        var start = 0
        value.forEachIndexed { index, char ->
            when (char) {
                '(' -> depth += 1
                ')' -> if (depth > 0) depth -= 1
                ',' -> if (depth == 0) {
                    layers.add(value.substring(start, index))
                    start = index + 1
                }
            }
        }
        layers.add(value.substring(start))
        return layers
    }

    private fun colorTokens(value: String): List<String> {
        return Regex(
            "#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\\b|rgba?\\([^)]*\\)|hsla?\\([^)]*\\)|\\b(?:white|black|transparent)\\b",
            RegexOption.IGNORE_CASE
        )
            .findAll(value)
            .mapNotNull { colorToken(it.value) }
            .toList()
    }

    private fun colorToken(value: String): String? {
        val token = value.trim()
        return when {
            token.startsWith("#") -> normalizeHex(token)
            token.startsWith("rgb", ignoreCase = true) -> rgbColor(token)
            token.startsWith("hsl", ignoreCase = true) -> hslColor(token)
            token.equals("white", ignoreCase = true) -> "#FFFFFF"
            token.equals("black", ignoreCase = true) -> "#000000"
            token.equals("transparent", ignoreCase = true) -> "#FFFFFF"
            else -> null
        }
    }

    private fun rgbColor(value: String): String? {
        val components = cssFunctionComponents(value)
        if (components.size < 3) return null
        val red = cssRgbComponent(components[0]) ?: return null
        val green = cssRgbComponent(components[1]) ?: return null
        val blue = cssRgbComponent(components[2]) ?: return null
        return hexColor(red, green, blue)
    }

    private fun hslColor(value: String): String? {
        val components = cssFunctionComponents(value)
        if (components.size < 3) return null
        val hue = components[0].removeSuffix("deg").toDoubleOrNull() ?: return null
        val saturation = cssPercentComponent(components[1]) ?: return null
        val lightness = cssPercentComponent(components[2]) ?: return null
        val chroma = (1.0 - kotlin.math.abs(2.0 * lightness - 1.0)) * saturation
        val huePrime = ((hue % 360.0) + 360.0) % 360.0 / 60.0
        val x = chroma * (1.0 - kotlin.math.abs(huePrime % 2.0 - 1.0))
        val match = when {
            huePrime < 1.0 -> Triple(chroma, x, 0.0)
            huePrime < 2.0 -> Triple(x, chroma, 0.0)
            huePrime < 3.0 -> Triple(0.0, chroma, x)
            huePrime < 4.0 -> Triple(0.0, x, chroma)
            huePrime < 5.0 -> Triple(x, 0.0, chroma)
            else -> Triple(chroma, 0.0, x)
        }
        val m = lightness - chroma / 2.0
        return hexColor(
            ((match.first + m) * 255.0).roundToColorComponent(),
            ((match.second + m) * 255.0).roundToColorComponent(),
            ((match.third + m) * 255.0).roundToColorComponent()
        )
    }

    private fun cssFunctionComponents(value: String): List<String> {
        return value.substringAfter('(', "").substringBeforeLast(')', "")
            .substringBefore('/')
            .replace(",", " ")
            .split(Regex("\\s+"))
            .map { it.trim() }
            .filter { it.isNotBlank() }
    }

    private fun cssRgbComponent(value: String): Int? {
        return if (value.endsWith("%")) {
            ((value.dropLast(1).toDoubleOrNull() ?: return null) * 255.0 / 100.0).roundToColorComponent()
        } else {
            (value.toDoubleOrNull() ?: return null).roundToColorComponent()
        }
    }

    private fun cssPercentComponent(value: String): Double? {
        return if (value.endsWith("%")) {
            ((value.dropLast(1).toDoubleOrNull() ?: return null) / 100.0).coerceIn(0.0, 1.0)
        } else {
            (value.toDoubleOrNull() ?: return null).coerceIn(0.0, 1.0)
        }
    }

    private fun Double.roundToColorComponent(): Int {
        return Math.round(this).toInt().coerceIn(0, 255)
    }

    private fun hexColor(red: Int, green: Int, blue: Int): String {
        return "#%02X%02X%02X".format(red, green, blue)
    }

    private fun cssVariables(css: String): Map<String, String> {
        return Regex("--([a-zA-Z0-9-]+)\\s*:\\s*([^;]+);")
            .findAll(css)
            .associate { match ->
                match.groupValues[1] to match.groupValues[2].trim()
            }
    }

    private fun resolveCssVariables(value: String, variables: Map<String, String>): String {
        var resolved = value
        val variablePattern = Regex("var\\(\\s*--([a-zA-Z0-9-]+)\\s*(?:,\\s*([^)]*))?\\)")
        repeat(8) {
            val matches = variablePattern.findAll(resolved).toList()
            if (matches.isEmpty()) return resolved
            for (match in matches.asReversed()) {
                val name = match.groupValues[1]
                val fallback = match.groups[2]?.value?.trim().orEmpty()
                val replacement = variables[name] ?: fallback
                resolved = resolved.replaceRange(match.range, replacement)
            }
        }
        return resolved
    }

    private fun removeCssAtRuleBlocks(css: String): String {
        val result = StringBuilder()
        var index = 0
        while (index < css.length) {
            if (css[index] != '@') {
                result.append(css[index])
                index += 1
                continue
            }

            var cursor = index
            while (cursor < css.length && css[cursor] != '{' && css[cursor] != ';') {
                cursor += 1
            }
            if (cursor >= css.length || css[cursor] != '{') {
                result.append(css[index])
                index += 1
                continue
            }

            var depth = 0
            var blockEnd = cursor
            while (blockEnd < css.length) {
                if (css[blockEnd] == '{') {
                    depth += 1
                } else if (css[blockEnd] == '}') {
                    depth -= 1
                    if (depth == 0) {
                        blockEnd += 1
                        break
                    }
                }
                blockEnd += 1
            }
            index = blockEnd
        }
        return result.toString()
    }

    private fun normalizeHex(value: String): String {
        val hex = value.removePrefix("#")
        if (hex.length == 3) {
            return "#" + hex.map { "$it$it" }.joinToString("").uppercase()
        }
        if (hex.length == 8) {
            return "#" + hex.take(6).uppercase()
        }
        return "#${hex.uppercase()}"
    }
}
