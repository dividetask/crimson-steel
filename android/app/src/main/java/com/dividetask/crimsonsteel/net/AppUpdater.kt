package com.dividetask.crimsonsteel.net

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.dividetask.crimsonsteel.debug.DebugLog
import java.io.File
import java.util.concurrent.Executors

/**
 * Settings → App updates (docs/project/app_updates.md): the server offers the
 * newest app build in its checkout; when it differs from this app, the player
 * can download it from the server and install it. Android shows its own
 * confirmation; the app never updates by itself.
 */
object AppUpdater {
    const val ACTION_STATUS = "com.dividetask.crimsonsteel.INSTALL_STATUS"
    private const val TAG = "update"
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The version part of a version name: "v0.036 a (cb86)" → (0, 36). */
    fun parse(v: String?): Pair<Int, Int>? =
        v?.let { Regex("v(\\d+)\\.(\\d+)").find(it) }?.let { Pair(it.groupValues[1].toInt(), it.groupValues[2].toInt()) }

    fun compare(a: Pair<Int, Int>, b: Pair<Int, Int>) = compareValuesBy(a, b, { it.first }, { it.second })

    /** The version the server offers ("v0.037"), or null when it has none. */
    fun latest(done: (Result<String?>) -> Unit) = Session.withApiPublic({ api ->
        api.get("/api/app/latest").let { if (it.isNull("version")) null else it.optString("version") }
    }, done)

    /** Download the server's APK and hand it to Android's installer. */
    fun install(activity: Activity, version: String, progress: (String) -> Unit) {
        val api = Session.api ?: return progress("Not connected to the server.")
        progress("Downloading $version…")
        io.execute {
            val r = runCatching {
                val file = File(File(activity.cacheDir, "updates").apply { mkdirs() }, "crimson-steel-$version.apk")
                api.download("/api/app/apk", file)
                DebugLog.i(TAG, "downloaded $version (${file.length()} bytes)")
                val pi = activity.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
                val id = pi.createSession(params)
                pi.openSession(id).use { session ->
                    file.inputStream().use { input ->
                        session.openWrite("crimson-steel.apk", 0, file.length()).use { out ->
                            input.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    val intent = Intent(activity, activity.javaClass).setAction(ACTION_STATUS)
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                    session.commit(PendingIntent.getActivity(activity, 0, intent, flags).intentSender)
                }
            }
            main.post {
                r.onSuccess { progress("Waiting for Android to install $version…") }
                 .onFailure { DebugLog.e(TAG, "update failed", it); progress("Could not update: ${it.message}") }
            }
        }
    }

    /**
     * The installer's answer, delivered to the activity that started it: shows
     * Android's confirmation when asked to. Returns a message for the player,
     * or null.
     */
    fun handleStatus(activity: Activity, intent: Intent): String? {
        if (intent.action != ACTION_STATUS) return null
        return when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                confirm?.let { activity.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                null
            }
            PackageInstaller.STATUS_SUCCESS -> "Updated."
            else -> {
                val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
                DebugLog.i(TAG, "install did not finish: $msg")
                "Not installed: $msg"
            }
        }
    }
}
