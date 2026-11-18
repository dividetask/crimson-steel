package com.dividetask.crimsonsteel.debug

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

/**
 * Serves one read-only file — the shareable copy of the debug log — so another
 * app (email, Messages, Drive…) can attach it from the share sheet. A tiny
 * stand-in for AndroidX FileProvider, since the app uses no AndroidX libraries.
 *
 * URI: content://<applicationId>.logs/<file name>
 */
class LogProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    private fun shared(): File? = context?.let { File(it.cacheDir, SHARE_DIR) }?.let { dir ->
        dir.listFiles()?.maxByOrNull { it.lastModified() }
    }

    override fun getType(uri: Uri): String = "text/plain"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val f = shared()?.takeIf { it.name == uri.lastPathSegment } ?: throw java.io.FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    // Some apps (e.g. Gmail) ask for the display name and size before attaching.
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?,
                       sortOrder: String?): Cursor {
        val f = shared()?.takeIf { it.name == uri.lastPathSegment }
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(cols)
        if (f != null) {
            cursor.addRow(cols.map {
                when (it) {
                    OpenableColumns.DISPLAY_NAME -> f.name
                    OpenableColumns.SIZE -> f.length()
                    else -> null
                }
            }.toTypedArray())
        }
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    companion object {
        private const val SHARE_DIR = "shared-logs"

        /**
         * Copy the log (with [header] on top) to a shareable file and return a
         * share-sheet Intent that attaches it as a file.
         */
        fun shareIntent(ctx: Context, header: String, subject: String): Intent {
            val dir = File(ctx.cacheDir, SHARE_DIR).apply { mkdirs() }
            dir.listFiles()?.forEach { it.delete() }
            val name = "crimson-steel-debug-${System.currentTimeMillis() / 1000}.log"
            val f = File(dir, name)
            f.writeText(header + "\n\n" + DebugLog.read())
            val uri = Uri.parse("content://${ctx.packageName}.logs/$name")
            val send = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, subject)
                putExtra(Intent.EXTRA_TEXT, "Crimson Steel debug log attached ($name).")
                clipData = android.content.ClipData.newRawUri(name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            return Intent.createChooser(send, "Send debug log").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
}
