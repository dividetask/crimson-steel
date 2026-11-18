package com.dividetask.crimsonsteel.debug

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore

/**
 * Saves a copy of the debug log to the phone's Downloads folder (Settings →
 * Save debug log). Android 10+ writes it straight into Downloads with no
 * permission; older versions let the player pick where to save it (see
 * SettingsActivity), which needs no permission either.
 */
object LogSaver {

    fun fileName(): String {
        val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US).format(java.util.Date())
        return "crimson-steel-debug-$stamp.log"
    }

    fun contents(header: String): String = header + "\n\n" + DebugLog.read()

    /** Android 10+: write into Downloads. Returns the saved file's name, shown to the player. */
    fun saveToDownloads(ctx: Context, header: String): String {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { "Downloads needs Android 10" }
        val name = fileName()
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = ctx.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw java.io.IOException("could not create $name in Downloads")
        try {
            write(ctx, uri, header)
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return name
    }

    /** Write the log into a document the player picked (Android 8–9). */
    fun write(ctx: Context, uri: Uri, header: String) {
        val out = ctx.contentResolver.openOutputStream(uri) ?: throw java.io.IOException("could not open $uri")
        out.use { it.write(contents(header).toByteArray()) }
    }
}
