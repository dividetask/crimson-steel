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

    fun parse(v: String?) = AppVersions.parse(v)
    fun compare(a: Pair<Int, Int>, b: Pair<Int, Int>) = AppVersions.compare(a, b)
    fun needsUpdate(server: com.dividetask.crimsonsteel.data.AppRelease?) = AppVersions.needsUpdate(server)
    fun needsUpdate(server: com.dividetask.crimsonsteel.data.AppRelease?, mine: String) = AppVersions.needsUpdate(server, mine)

    /** The build the server offers, or null when it has none. */
    fun latest(done: (Result<com.dividetask.crimsonsteel.data.AppRelease?>) -> Unit) = Session.withApiPublic({ api ->
        api.get("/api/app/latest").let {
            if (it.isNull("version")) null
            else com.dividetask.crimsonsteel.data.AppRelease(it.optString("version"), if (it.isNull("commit")) null else it.optString("commit"))
        }
    }, done)

    /** Update to [version]: asks Android to allow installs from this app first, if needed. */
    fun start(activity: Activity, version: String, progress: (String) -> Unit) {
        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
            progress("Allow Crimson Steel to install apps, then tap Update again.")
            activity.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                android.net.Uri.parse("package:${activity.packageName}")))
            return
        }
        DebugLog.i(TAG, "updating to $version")
        install(activity, version, progress)
    }

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
