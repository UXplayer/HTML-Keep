package com.htmlkeep.community.core

import java.io.File

internal object ProjectIconRules {
    private val supportedImageExtensions = setOf("png", "jpg", "jpeg", "webp", "gif", "ico", "svg")
    private val rejectedNameTokens = setOf(
        "sprite",
        "sprites",
        "background",
        "bg",
        "banner",
        "banners",
        "ad",
        "ads",
        "advert",
        "advertisement"
    )

    fun isSupportedImageFileName(fileName: String): Boolean {
        return File(fileName).extension.lowercase() in supportedImageExtensions
    }

    fun imageScore(fileName: String, byteCount: Long, width: Int, height: Int): Int? {
        if (!isSupportedImageFileName(fileName)) return null
        if (width < 32 || height < 32) return null
        val shortSide = minOf(width, height)
        val longSide = maxOf(width, height)
        if (longSide.toDouble() / shortSide.toDouble() > 2.2) return null

        val baseName = File(fileName).nameWithoutExtension.lowercase()
        val tokens = nameTokens(baseName)
        if (tokens.any { it in rejectedNameTokens }) return null

        var score = 0
        if ("favicon" in tokens || baseName.contains("favicon")) score += 80
        if ("touch" in tokens) score += 75
        if ("icon" in tokens || baseName.contains("icon")) score += 70
        if ("logo" in tokens || baseName.contains("logo")) score += 65
        if ("app" in tokens) score += 45
        if ("avatar" in tokens) score += 40
        if ("thumbnail" in tokens || "thumb" in tokens) score += 35
        if ("product" in tokens) score += 20

        val squareCloseness = 1.0 - (longSide - shortSide).toDouble() / longSide.toDouble()
        score += (squareCloseness * 20.0).toInt()
        score += minOf(24, shortSide / 16)
        if (byteCount in 1..1_000_000) score += 10
        return score
    }

    fun manifestIconScore(sizes: String?, type: String?, purpose: String?): Int {
        val bestSize = sizes
            ?.let { sizePattern.findAll(it).mapNotNull { match -> manifestSizeScore(match) }.maxOrNull() }
            ?: if (sizes?.contains("any", ignoreCase = true) == true) 128 else 0

        var score = bestSize
        val normalizedType = type.orEmpty().lowercase()
        if (normalizedType == "image/png") score += 30
        if (normalizedType == "image/webp") score += 24
        if (normalizedType == "image/jpeg" || normalizedType == "image/jpg") score += 18
        val normalizedPurpose = purpose.orEmpty().lowercase()
        if (normalizedPurpose.isBlank() || normalizedPurpose.contains("any")) score += 8
        if (normalizedPurpose.contains("maskable")) score += 4
        return score
    }

    private fun manifestSizeScore(match: MatchResult): Int? {
        val width = match.groupValues.getOrNull(1)?.toIntOrNull() ?: return null
        val height = match.groupValues.getOrNull(2)?.toIntOrNull() ?: return null
        val shortSide = minOf(width, height)
        val longSide = maxOf(width, height)
        var score = minOf(512, shortSide)
        if (width == height) score += 80
        if (longSide in 96..512) score += 40
        return score
    }

    private fun nameTokens(name: String): Set<String> {
        return name.split(Regex("[^a-z0-9]+"))
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .toSet()
    }

    private val sizePattern = Regex("(\\d+)\\s*x\\s*(\\d+)", RegexOption.IGNORE_CASE)
}
