package com.dividetask.crimsonsteel.net

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
        val conn = open("POST", path, "application/x-www-form-urlencoded")
        try {
            conn.outputStream.use { it.write(body.toByteArray()) }
            val status = conn.responseCode
            saveCookie(conn)
            if (status >= 400) throw ApiException(status, "request failed")
        } finally {
            conn.disconnect()
        }
    }

    private fun open(method: String, path: String, contentType: String?): HttpURLConnection {
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
        val conn = open(method, path, contentType)
        try {
            if (body != null) conn.outputStream.use { it.write(body.toByteArray()) }
            val status = conn.responseCode
            saveCookie(conn)
            val stream = if (status >= 400) conn.errorStream else conn.inputStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            val json = runCatching { JSONObject(text) }.getOrNull()
            if (status >= 400 || json == null) {
                throw ApiException(status, json?.optString("error")?.takeIf { it.isNotEmpty() } ?: "HTTP $status")
            }
            return json
        } finally {
            conn.disconnect()
        }
    }

    private fun saveCookie(conn: HttpURLConnection) {
        val headers = conn.headerFields?.entries?.filter { it.key.equals("Set-Cookie", ignoreCase = true) }
            ?.flatMap { it.value } ?: return
        for (h in headers) parseDeviceCookie(h)?.let { cookies.deviceCookie = it }
    }

    companion object {
        const val COOKIE = "crimson_device_id"

        /** The device id from a Set-Cookie header, or null if it is some other cookie. */
        fun parseDeviceCookie(header: String): String? {
            val first = header.substringBefore(';').trim()
            if (!first.startsWith("$COOKIE=")) return null
            return first.removePrefix("$COOKIE=").takeIf { it.isNotEmpty() }
        }
    }
}
