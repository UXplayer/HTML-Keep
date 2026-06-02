package com.htmlkeep.community.core

import java.io.File

class ShareExporter(private val cacheDirectory: File) {
    data class ShareFile(val file: File, val isArchive: Boolean)

    fun shareFileForProject(projectFolder: File, preferredName: String): ShareFile {
        val files = ZipTools.regularFiles(projectFolder, excluding = { WebPageLibrary.isAppManagedFallbackPath(it) })
        if (files.size == 1) {
            return ShareFile(files.first(), false)
        }

        val safeName = preferredName.replace(Regex("[^A-Za-z0-9._ -]+"), "_").trim().ifBlank { "web-page" }
        val destination = File(cacheDirectory, "$safeName.zip")
        ZipTools.archiveFolder(projectFolder, destination, excluding = { WebPageLibrary.isAppManagedFallbackPath(it) })
        return ShareFile(destination, true)
    }
}
