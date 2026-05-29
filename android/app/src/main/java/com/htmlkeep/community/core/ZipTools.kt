package com.htmlkeep.community.core

import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object ZipTools {
    class ExpandedSizeLimitExceeded : Exception("Expanded ZIP content is too large")

    fun extract(
        zipData: ByteArray,
        destination: File,
        maximumExpandedByteCount: Long? = null
    ) {
        destination.mkdirs()
        var expandedByteCount = 0L
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        ZipInputStream(ByteArrayInputStream(zipData)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val relativePath = safeRelativePath(entry.name)
                if (shouldSkip(relativePath)) {
                    zip.closeEntry()
                    continue
                }

                val output = File(destination, relativePath)
                require(isDescendant(output, destination)) { "Unsafe ZIP path" }
                if (entry.isDirectory) {
                    output.mkdirs()
                } else {
                    output.parentFile?.mkdirs()
                    FileOutputStream(output).use { out ->
                        while (true) {
                            val read = zip.read(buffer)
                            if (read < 0) break
                            expandedByteCount += read.toLong()
                            if (maximumExpandedByteCount != null && expandedByteCount > maximumExpandedByteCount) {
                                throw ExpandedSizeLimitExceeded()
                            }
                            out.write(buffer, 0, read)
                        }
                    }
                }
                zip.closeEntry()
            }
        }
    }

    fun archiveFolder(source: File, destination: File, excluding: ((String) -> Boolean)? = null) {
        val files = regularFiles(source, excluding)
        require(files.isNotEmpty()) { "Folder is empty" }
        destination.parentFile?.mkdirs()
        if (destination.exists()) destination.delete()

        ZipOutputStream(FileOutputStream(destination)).use { zip ->
            for (file in files) {
                val relativePath = source.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
                val safePath = safeRelativePath(relativePath)
                zip.putNextEntry(ZipEntry(safePath))
                FileInputStream(file).use { input -> input.copyTo(zip) }
                zip.closeEntry()
            }
        }
    }

    fun regularFiles(root: File, excluding: ((String) -> Boolean)? = null): List<File> {
        return root.walkTopDown()
            .filter { it.isFile }
            .filter { file ->
                val relativePath = root.toPath().relativize(file.toPath()).toString().replace(File.separatorChar, '/')
                !shouldSkip(relativePath) && excluding?.invoke(relativePath) != true
            }
            .sortedBy { root.toPath().relativize(it.toPath()).toString() }
            .toList()
    }

    fun safeRelativePath(rawPath: String): String {
        val normalized = rawPath.replace('\\', '/')
        require(normalized.isNotBlank() && !normalized.startsWith("/") && !normalized.contains('\u0000')) {
            "Unsafe path"
        }
        val parts = normalized.split('/').filter { it.isNotBlank() }
        require(parts.isNotEmpty() && parts.all { it != "." && it != ".." }) { "Unsafe path" }
        return parts.joinToString("/")
    }

    fun shouldSkip(relativePath: String): Boolean {
        return relativePath == ".DS_Store" ||
            relativePath.startsWith("__MACOSX/") ||
            relativePath.endsWith("/.DS_Store")
    }

    fun isDescendant(candidate: File, root: File): Boolean {
        val rootPath = root.canonicalFile.toPath()
        val candidatePath = candidate.canonicalFile.toPath()
        return candidatePath == rootPath || candidatePath.startsWith(rootPath)
    }
}
