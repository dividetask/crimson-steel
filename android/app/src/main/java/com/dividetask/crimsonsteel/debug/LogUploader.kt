package com.dividetask.crimsonsteel.debug

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.PixelCopy
import com.dividetask.crimsonsteel.net.Session
import org.json.JSONObject
import java.io.ByteArrayOutputStream

/**
 * Sends the debug log — and, for a screenshot, a picture of the app — to the
 * server, which saves it in its device-logs/ folder with a header naming this
 * device and the app's build (docs/project/device_logs.md).
 *
 * Settings → Send log to server sends the log. A screenshot the player takes
 * while the app is open (Android 14+, which tells the app about it) sends a
 * copy of the app's screen along with the log.
 */
object LogUploader {
    private const val TAG = "logs"

    /** What the server writes at the top of the file about this device. */
    fun deviceInfo(ctx: Context): JSONObject {
        val dm = ctx.resources.displayMetrics
        return JSONObject()
            .put("manufacturer", Build.MANUFACTURER)
            .put("model", Build.MODEL)
            .put("android", "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            .put("screen", "${dm.widthPixels}x${dm.heightPixels} @ ${dm.densityDpi}dpi")
            .put("server", Session.serverAddress ?: "not connected")
            .put("cookie id", Session.deviceId ?: "not issued")
            .put("character (app)", Session.sheet?.name ?: "-")
            .put("vpn", if (Session.vpnActive) "on" else "off")
    }

    private fun appVersion(): String =
        runCatching { com.dividetask.crimsonsteel.BuildConfig.VERSION_NAME }.getOrDefault("?")

    /** Send the log (and [png], a screenshot) to the server. [done] runs on the main thread. */
    fun send(ctx: Context, png: ByteArray? = null, done: (Result<String>) -> Unit) {
        val body = JSONObject()
            .put("kind", if (png == null) "log" else "screenshot")
            .put("app", JSONObject().put("version", appVersion()))
            .put("device", deviceInfo(ctx))
        Session.withApiPublic({ api ->
            body.put("log", DebugLog.read())
            if (png != null) body.put("screenshot", Base64.encodeToString(png, Base64.NO_WRAP))
            val r = api.postJson("/api/logs", body)
            val saved = r.optJSONArray("saved")
            (0 until (saved?.length() ?: 0)).joinToString(", ") { saved!!.optString(it) }
        }, done)
    }

    /**
     * The player took a screenshot: copy this activity's window (what the app
     * shows) and send it with the log. Done in the background; a short toast
     * says it went to the server.
     */
    fun captureAndSend(activity: Activity) {
        if (Session.api == null) return
        val window = activity.window ?: return
        val view = window.decorView
        if (view.width <= 0 || view.height <= 0) return
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        DebugLog.i(TAG, "screenshot taken in ${activity.javaClass.simpleName}: sending a copy to the server")
        PixelCopy.request(window, bitmap, { result ->
            if (result != PixelCopy.SUCCESS) {
                DebugLog.i(TAG, "could not copy the screen (PixelCopy $result)")
                bitmap.recycle()
                return@request
            }
            Thread {
                val png = ByteArrayOutputStream().use { out ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    out.toByteArray()
                }
                bitmap.recycle()
                Handler(Looper.getMainLooper()).post {
                    send(activity.applicationContext, png) { r ->
                        r.onSuccess { DebugLog.i(TAG, "screenshot saved on the server: $it") }
                        r.onFailure { DebugLog.e(TAG, "screenshot not sent", it) }
                        if (!activity.isFinishing) {
                            android.widget.Toast.makeText(activity,
                                if (r.isSuccess) "Screenshot sent to the server" else "Screenshot not sent: ${r.exceptionOrNull()?.message}",
                                android.widget.Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            }.start()
        }, Handler(Looper.getMainLooper()))
    }
}

/**
 * Android 14+ tells an app when the player takes a screenshot of it. Register
 * in onStart and unregister in onStop of each screen (MainActivity,
 * SettingsActivity). Needs the DETECT_SCREEN_CAPTURE permission (granted at
 * install, no prompt). Older Android does not report screenshots, so nothing
 * is sent there.
 */
class ScreenshotWatcher(private val activity: Activity) {
    private val callback: Any? =
        if (Build.VERSION.SDK_INT >= 34) Activity.ScreenCaptureCallback { LogUploader.captureAndSend(activity) } else null

    fun start() {
        if (Build.VERSION.SDK_INT >= 34) runCatching {
            activity.registerScreenCaptureCallback(activity.mainExecutor, callback as Activity.ScreenCaptureCallback)
        }.onFailure { DebugLog.e("logs", "cannot watch for screenshots", it) }
    }

    fun stop() {
        if (Build.VERSION.SDK_INT >= 34) runCatching {
            activity.unregisterScreenCaptureCallback(callback as Activity.ScreenCaptureCallback)
        }
    }
}
