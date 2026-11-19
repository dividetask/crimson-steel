package com.dividetask.crimsonsteel.net

import android.os.Handler
import android.os.Looper
import com.dividetask.crimsonsteel.debug.DebugLog

/**
 * Live updates from the server (docs/project/live_updates.md): one open
 * connection (Server-Sent Events, GET /api/events) while the app is on
 * screen. The server says "changed" whenever something changed in the game,
 * and [onChange] runs on the main thread so the app fetches what it shows —
 * instead of asking every few seconds. A dropped connection is reopened
 * after a short wait; the app's slow fallback refresh covers the gap.
 */
class LiveEvents(private val onChange: () -> Unit) {

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    @Volatile private var conn: java.net.HttpURLConnection? = null
    private var thread: Thread? = null
    /** A notice is already waiting to run on the main thread (several become one). */
    @Volatile private var pending = false

    /** True while the connection is open (Settings and the debug log show it). */
    @Volatile var connected = false
        private set

    fun start() {
        if (running) return
        running = true
        thread = Thread({ loop() }, "live-events").apply { isDaemon = true; start() }
    }

    fun stop() {
        running = false
        conn?.disconnect()
        thread?.interrupt()
        thread = null
        connected = false
    }

    private fun loop() {
        var wait = 1000L
        while (running) {
            val api = Session.api
            if (api == null) { sleep(2000); continue }
            try {
                val c = api.openEvents()
                conn = c
                if (c.responseCode != 200) throw java.io.IOException("HTTP ${c.responseCode}")
                connected = true
                wait = 1000L
                DebugLog.i(TAG, "live updates connected")
                c.inputStream.bufferedReader().use { r ->
                    while (running) {
                        val line = r.readLine() ?: break
                        if (line.startsWith("data:")) notifyChange()
                    }
                }
            } catch (e: Exception) {
                if (running) DebugLog.i(TAG, "live updates dropped (${e.javaClass.simpleName}: ${e.message}); retrying")
            } finally {
                connected = false
                conn?.disconnect()
                conn = null
            }
            if (!running) break
            sleep(wait)
            wait = (wait * 2).coerceAtMost(15_000L)
        }
    }

    private fun notifyChange() {
        if (pending) return
        pending = true
        main.post {
            pending = false
            if (running) onChange()
        }
    }

    private fun sleep(ms: Long) = try { Thread.sleep(ms) } catch (_: InterruptedException) {}

    private companion object { const val TAG = "live" }
}
