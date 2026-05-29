package com.htmlkeep.community.ui

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import com.htmlkeep.community.core.WebPageLibrary
import java.io.ByteArrayOutputStream

data class UriSource(
    val bytes: ByteArray,
    val fileName: String,
    val sourceDescription: String
)

object UriSourceReader {
    class SourceTooLargeException : Exception()

    fun read(
        contentResolver: ContentResolver,
        uri: Uri,
        maximumByteCount: Long = WebPageLibrary.maximumImportedFileByteCount
    ): UriSource {
        val name = displayName(contentResolver, uri)
            ?: uri.lastPathSegment?.substringAfterLast('/')
            ?: "webpage.html"
        val size = displaySize(contentResolver, uri)
        if (size != null && size > maximumByteCount) throw SourceTooLargeException()
        val bytes = contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var total = 0L
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                total += read.toLong()
                if (total > maximumByteCount) throw SourceTooLargeException()
                output.write(buffer, 0, read)
            }
            output.toByteArray()
        }
            ?: throw IllegalArgumentException("Unreadable URI")
        val description = uri.authority ?: uri.scheme ?: ""
        return UriSource(bytes, name, description)
    }

    private fun displayName(contentResolver: ContentResolver, uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }

    private fun displaySize(contentResolver: ContentResolver, uri: Uri): Long? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (index >= 0 && !cursor.isNull(index)) cursor.getLong(index) else null
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }
}
