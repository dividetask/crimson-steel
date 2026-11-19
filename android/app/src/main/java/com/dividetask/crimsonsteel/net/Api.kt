package com.dividetask.crimsonsteel.net

import com.dividetask.crimsonsteel.debug.DebugLog
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder

/** The server answered with an error. [error] is the API's error code (e.g. "unassigned"). */
class ApiException(val status: Int, val error: String) : IOException("HTTP $status: $error")

/** Stores the device cookie between app launches. */
interface CookieStore {
    var deviceCookie: String?
}

/**
 * Blocking HTTP client for the Crimson Steel server's JSON API (lib/routes/api.rb).
 *
 * The device is identified exactly like a browser: by the server-issued
 * `crimson_device_id` cookie, which is saved and sent on every request. The
 * DM assigns this device a Character on the web Status page.
 */
class Api(val server: ServerInfo, private val cookies: CookieStore) {

    /**
     * Polling repeats the same GETs every few seconds; by default a successful
     * GET is logged only when its status changes, so the log stays readable.
     */
    var logEvery = false
    private val lastStatus = java.util.concurrent.ConcurrentHashMap<String, Int>()

    fun get(path: String): JSONObject = request("GET", path, null, null)

    fun postJson(path: String, body: JSONObject = JSONObject()): JSONObject =
        request("POST", path, body.toString(), "application/json")

    /**
     * POST a form to one of the web routes (e.g. /inventory/equip). Those
     * answer with a redirect back to the sheet, which is not followed.
     */
    fun postForm(path: String, fields: Map<String, String>) {
        val body = fields.entries.joinToString("&") {
            URLEncoder.encode(it.key, "UTF-8") + "=" + URLEncoder.encode(it.value, "UTF-8")
        }
        val started = System.currentTimeMillis()
        val conn = open("POST", path, "application/x-www-form-urlencoded")
        try {
            conn.outputStream.use { it.write(body.toByteArray()) }
            val status = conn.responseCode
            saveCookie(conn)
            DebugLog.i(TAG, "POST $path (form) -> $status in ${System.currentTimeMillis() - started}ms")
            if (status >= 400) throw ApiException(status, "request failed")
        } catch (e: java.io.IOException) {
            if (e !is ApiException) DebugLog.e(TAG, "POST $path (form) to ${server.baseUrl} failed", e)
            throw e
        } finally {
            conn.disconnect()
        }
    }

    /** Download [path] (e.g. a sound) into [to], with this device's cookie. */
    fun download(path: String, to: java.io.File) {
        dropCookieHandler()
        val conn = URI(server.baseUrl + path).toURL().openConnection() as HttpURLConnection
        conn.connectTimeout = 4000
        conn.readTimeout = 20_000
        cookies.deviceCookie?.let { conn.setRequestProperty("Cookie", "$COOKIE=$it") }
        try {
            if (conn.responseCode != 200) throw ApiException(conn.responseCode, "HTTP ${conn.responseCode}")
            conn.inputStream.use { input -> to.outputStream().use { input.copyTo(it) } }
            DebugLog.i(TAG, "GET $path -> 200 (${to.length()} bytes)")
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Open the live-updates stream (Server-Sent Events, GET /api/events). The
     * server writes a heartbeat every 20 seconds, so a read that waits much
     * longer than that means the connection is gone.
     */
    fun openEvents(): HttpURLConnection {
        dropCookieHandler()
        val conn = URI(server.baseUrl + "/api/events").toURL().openConnection() as HttpURLConnection
        conn.requestMethod = "GET"
        conn.connectTimeout = 4000
        conn.readTimeout = 50_000
        conn.setRequestProperty("Accept", "text/event-stream")
        cookies.deviceCookie?.let { conn.setRequestProperty("Cookie", "$COOKIE=$it") }
        return conn
    }

    private fun open(method: String, path: String, contentType: String?): HttpURLConnection {
        dropCookieHandler()
        val conn = URI(server.baseUrl + path).toURL().openConnection() as HttpURLConnection
        conn.requestMethod = method
        conn.connectTimeout = 4000
        conn.readTimeout = 8000
        conn.instanceFollowRedirects = false
        conn.setRequestProperty("Accept", "application/json")
        cookies.deviceCookie?.let { conn.setRequestProperty("Cookie", "$COOKIE=$it") }
        if (contentType != null) {
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", contentType)
        }
        return conn
    }

    private fun request(method: String, path: String, body: String?, contentType: String?): JSONObject {
        val started = System.currentTimeMillis()
        val conn = open(method, path, contentType)
        try {
            if (body != null) conn.outputStream.use { it.write(body.toByteArray()) }
            val status = conn.responseCode
            saveCookie(conn)
            val stream = if (status >= 400) conn.errorStream else conn.inputStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            val json = runCatching { JSONObject(text) }.getOrNull()
            val ms = System.currentTimeMillis() - started
            if (status >= 400 || json == null) {
                val err = json?.optString("error")?.takeIf { it.isNotEmpty() } ?: "HTTP $status"
                DebugLog.i(TAG, "$method $path -> $status ($err) in ${ms}ms" +
                    if (json == null) "; body starts: ${text.take(120).replace('\n', ' ')}" else "")
                throw ApiException(status, err)
            }
            if (logEvery || method != "GET" || status != lastStatus[path]) DebugLog.i(TAG, "$method $path -> $status in ${ms}ms")
            lastStatus[path] = status
            return json
        } catch (e: java.io.IOException) {
            if (e !is ApiException) DebugLog.e(TAG, "$method $path to ${server.baseUrl} failed", e)
            throw e
        } finally {
            conn.disconnect()
        }
    }

    private fun saveCookie(conn: HttpURLConnection) {
        val headers = conn.headerFields?.entries?.filter { it.key.equals("Set-Cookie", ignoreCase = true) }
            ?.flatMap { it.value } ?: return
        for (h in headers) parseDeviceCookie(h)?.let {
            if (it != cookies.deviceCookie) DebugLog.i(TAG, "server issued device id ${it.take(8)}")
            cookies.deviceCookie = it
        }
    }

    companion object {
        /**
         * The app sends its device id itself. Android's media player, the
         * first time it streams a URL, installs a cookie manager for the
         * whole app — which then replaces that Cookie header, so the server
         * no longer recognises the device and issues new ids (the device
         * looks unassigned). Remove any such manager before each request.
         */
        fun dropCookieHandler() {
            if (java.net.CookieHandler.getDefault() != null) {
                java.net.CookieHandler.setDefault(null)
                DebugLog.i(TAG, "removed a cookie manager that would replace the device id")
            }
        }

        const val COOKIE = "crimson_device_id"
        private const val TAG = "http"

        /** The device id from a Set-Cookie header, or null if it is some other cookie. */
        fun parseDeviceCookie(header: String): String? {
            val first = header.substringBefore(';').trim()
            if (!first.startsWith("$COOKIE=")) return null
            return first.removePrefix("$COOKIE=").takeIf { it.isNotEmpty() }
        }
    }
}
