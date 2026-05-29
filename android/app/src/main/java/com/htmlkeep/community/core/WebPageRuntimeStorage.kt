package com.htmlkeep.community.core

import org.json.JSONObject
import java.io.File
import java.time.Instant

object WebPageRuntimeStorage {
    const val directoryName = ".htmlanywhere"
    const val localStorageFileName = "local-storage.json"
    const val localStorageRelativePath = "$directoryName/$localStorageFileName"
    const val projectIconFileName = "project-icon.png"
    const val projectIconRelativePath = "$directoryName/$projectIconFileName"
    private const val projectIconFileNamePrefix = "project-icon-"
    private const val projectIconFileNameExtension = ".png"

    fun localStorageItems(projectFolder: File): Map<String, String> {
        val file = localStorageFile(projectFolder)
        if (!file.exists()) return emptyMap()
        val json = runCatching { JSONObject(file.readText()) }.getOrNull() ?: return emptyMap()
        if (json.optInt("schemaVersion") != 1) return emptyMap()
        val items = json.optJSONObject("items") ?: return emptyMap()
        return items.keys().asSequence().associateWith { key -> items.optString(key, "") }
    }

    @Synchronized
    fun saveLocalStorageItems(projectFolder: File, items: Map<String, String>): Boolean {
        val file = localStorageFile(projectFolder)
        val existing = if (file.exists()) localStorageItems(projectFolder) else null
        if (existing == items) return false

        runtimeDirectory(projectFolder).mkdirs()
        val sortedItems = JSONObject()
        items.toSortedMap().forEach { (key, value) -> sortedItems.put(key, value) }
        val snapshot = JSONObject()
            .put("schemaVersion", 1)
            .put("savedAt", Instant.now().toString())
            .put("items", sortedItems)
        file.writeText(snapshot.toString(2))
        return true
    }

    fun clearRuntimeData(projectFolder: File) {
        val runtimeDirectory = runtimeDirectory(projectFolder)
        if (runtimeDirectory.exists()) {
            runtimeDirectory.listFiles()?.forEach { item ->
                if (!isProjectIconFileName(item.name)) item.deleteRecursively()
            }
        }
        saveLocalStorageItems(projectFolder, emptyMap())
    }

    fun copyRuntimeDirectoryIfPresent(sourceProjectFolder: File, destinationProjectFolder: File) {
        val source = runtimeDirectory(sourceProjectFolder)
        if (!source.exists()) return
        val destination = runtimeDirectory(destinationProjectFolder)
        if (destination.exists()) destination.deleteRecursively()
        source.copyRecursively(destination, overwrite = true)
    }

    fun isRuntimeStoragePath(relativePath: String): Boolean {
        return relativePath == directoryName || relativePath.startsWith("$directoryName/")
    }

    fun versionedProjectIconRelativePath(updatedAt: Long, sequence: Int = 0): String {
        val suffix = if (sequence <= 0) "" else "-$sequence"
        return "$directoryName/$projectIconFileNamePrefix$updatedAt$suffix$projectIconFileNameExtension"
    }

    fun cleanupProjectIconFiles(projectFolder: File, keepRelativePath: String?) {
        val keepFileName = keepRelativePath
            ?.replace(File.separatorChar, '/')
            ?.removePrefix("$directoryName/")
        runtimeDirectory(projectFolder).listFiles()?.forEach { item ->
            if (item.isFile && isProjectIconFileName(item.name) && item.name != keepFileName) {
                item.delete()
            }
        }
    }

    fun runtimeDirectory(projectFolder: File): File {
        return File(projectFolder, directoryName)
    }

    private fun isProjectIconFileName(fileName: String): Boolean {
        return fileName == projectIconFileName ||
            (fileName.startsWith(projectIconFileNamePrefix) && fileName.endsWith(projectIconFileNameExtension))
    }

    private fun localStorageFile(projectFolder: File): File {
        return File(runtimeDirectory(projectFolder), localStorageFileName)
    }
}
