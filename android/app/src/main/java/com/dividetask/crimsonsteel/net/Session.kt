package com.dividetask.crimsonsteel.net

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import com.dividetask.crimsonsteel.data.Hello
import com.dividetask.crimsonsteel.debug.DebugLog
import com.dividetask.crimsonsteel.data.Initiative
import com.dividetask.crimsonsteel.data.Inventory
import com.dividetask.crimsonsteel.data.Notes
import com.dividetask.crimsonsteel.data.Scene
import com.dividetask.crimsonsteel.data.Sheet
import com.dividetask.crimsonsteel.dice.RollResult
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * The app's connection to the server. All network work runs on one background
 * thread (so requests stay in order); results come back on the main thread.
 */
object Session {
    private const val PREFS = "crimson_steel"
    private const val KEY_COOKIE = "device_cookie"
    private const val KEY_HOST = "last_host"
    private const val KEY_PORT = "last_port"
    private const val TAG = "session"

    private lateinit var prefs: SharedPreferences
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    var api: Api? = null
        private set

    /** Last sheet fetched — used for the character name and to label public rolls. */
    var sheet: Sheet? = null

    private val cookieStore = object : CookieStore {
        override var deviceCookie: String?
            get() = prefs.getString(KEY_COOKIE, null)
            set(v) { prefs.edit().putString(KEY_COOKIE, v).apply() }
    }

    private lateinit var appCtx: Context

    /** An API client for [s]. Connections take the phone's normal route, so a VPN or firewall app (e.g. NetGuard) applies. */
    private fun newApi(s: ServerInfo) = Api(s, cookieStore)

    /** True when the phone has a VPN running — often a firewall app such as NetGuard, which may be blocking this app. */
    val vpnActive: Boolean get() = ::appCtx.isInitialized && LocalNetwork.vpnActive(appCtx)

    fun init(ctx: Context) {
        if (::prefs.isInitialized) return
        appCtx = ctx.applicationContext
        prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        DebugLog.init(ctx.applicationContext.filesDir)
        DebugLog.installCrashHandler()
        DebugLog.i(TAG, "app started: ${appInfo(ctx)}")
    }

    /** Version, Android release and device model — the header of a shared log, and its first line each launch. */
    fun appInfo(ctx: Context): String {
        val version = runCatching { com.dividetask.crimsonsteel.BuildConfig.VERSION_NAME }.getOrDefault("?")
        return "Crimson Steel $version; Android ${android.os.Build.VERSION.RELEASE} (API ${android.os.Build.VERSION.SDK_INT}); " +
            "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}"
    }

    private fun <T> background(work: () -> T, done: (Result<T>) -> Unit) {
        io.execute {
            val r = runCatching(work)
            main.post { done(r) }
        }
    }

    private fun <T> withApi(work: (Api) -> T, done: (Result<T>) -> Unit) {
        val a = api ?: return done(Result.failure(java.io.IOException("not connected")))
        background({ work(a) }, done)
    }

    /**
     * Find the server: try the one used last time, then broadcast on the
     * Wi-Fi network, then scan the Wi-Fi subnet for the web port. Succeeds
     * with the server's /api/hello answer. Each step goes to the debug log.
     */
    fun connect(done: (Result<Hello>) -> Unit) = background({
        DebugLog.i(TAG, "searching for the server")
        val remembered = prefs.getString(KEY_HOST, null)?.let { ServerInfo(it, prefs.getInt(KEY_PORT, ServerLocator.DEFAULT_HTTP_PORT), "") }
        val fromMemory = remembered?.let { s ->
            DebugLog.i(TAG, "trying last server ${s.baseUrl}")
            runCatching { adopt(newApi(s)) }
                .onFailure { DebugLog.i(TAG, "last server not reachable: ${DebugLog.describe(it)}") }
                .getOrNull()
        }
        fromMemory ?: run {
            DebugLog.i(TAG, "broadcasting a discovery probe on UDP ${ServerLocator.PORT}")
            val found = ServerLocator.discover()
            if (found != null) {
                DebugLog.i(TAG, "found ${found.name.ifBlank { "server" }} at ${found.baseUrl} by broadcast")
                adopt(newApi(found))
            } else {
                DebugLog.i(TAG, "no broadcast reply; scanning the Wi-Fi subnet for TCP ${ServerLocator.DEFAULT_HTTP_PORT}")
                scan() ?: throw java.io.IOException("No Crimson Steel server found on this network")
            }
        }
    }, { r ->
        r.onSuccess { DebugLog.i(TAG, "connected to ${api?.server?.baseUrl}; campaign \"${it.campaign}\", device ${it.device}, character ${it.character?.name ?: "(not assigned)"}") }
         .onFailure { DebugLog.e(TAG, "search failed", it) }
        done(r)
    })

    /** Subnet scan fallback: the first open host that answers /api/hello as a Crimson Steel server. */
    private fun scan(): Hello? {
        for (host in ServerLocator.scanCandidates()) {
            val s = ServerInfo(host, ServerLocator.DEFAULT_HTTP_PORT, "")
            val ok = runCatching {
                val a = newApi(s)
                val j = a.get("/api/hello")
                if (j.optString("service") != ServerLocator.SERVICE) error("not a Crimson Steel server")
                a
            }
            ok.onFailure { DebugLog.i(TAG, "$host:${s.port} is not the server: ${DebugLog.describe(it)}") }
            ok.getOrNull()?.let { a ->
                DebugLog.i(TAG, "found the server at ${s.baseUrl} by subnet scan (UDP discovery did not answer)")
                return adopt(a)
            }
        }
        return null
    }

    /** Confirm [a] answers /api/hello, then make it the current server and remember it. */
    private fun adopt(a: Api): Hello {
        val h = Hello.from(a.get("/api/hello"))
        api = a
        prefs.edit().putString(KEY_HOST, a.server.host).putInt(KEY_PORT, a.server.port).apply()
        return h
    }

    /** Server details for the Settings screen. */
    val serverAddress: String? get() = api?.server?.baseUrl ?: prefs.getString(KEY_HOST, null)?.let { "http://$it:${prefs.getInt(KEY_PORT, 4567)}" }
    val deviceId: String? get() = if (::prefs.isInitialized) prefs.getString(KEY_COOKIE, null)?.take(8) else null

    /** Drop the remembered server so the next search starts from discovery. Keeps the device id. */
    fun forgetServer() {
        DebugLog.i(TAG, "forgetting server ${serverAddress ?: "(none)"}")
        api = null
        sheet = null
        prefs.edit().remove(KEY_HOST).remove(KEY_PORT).apply()
    }

    fun hello(done: (Result<Hello>) -> Unit) = withApi({ Hello.from(it.get("/api/hello")) }, done)

    fun sheet(done: (Result<Pair<Sheet, String>>) -> Unit) = withApi({
        val j = it.get("/api/sheet")
        Pair(Sheet.from(j), j.toString())
    }, { r -> r.onSuccess { sheet = it.first }; done(r) })

    fun initiative(done: (Result<Pair<Initiative, String>>) -> Unit) =
        withApi({ val j = it.get("/api/initiative"); Pair(Initiative.from(j), j.toString()) }, done)

    fun inventory(done: (Result<Pair<Inventory, String>>) -> Unit) =
        withApi({ val j = it.get("/api/inventory"); Pair(Inventory.from(j), j.toString()) }, done)

    fun notes(done: (Result<Pair<Notes, String>>) -> Unit) =
        withApi({ val j = it.get("/api/notes"); Pair(Notes.from(j), j.toString()) }, done)

    fun scene(done: (Result<Pair<Scene, String>>) -> Unit) =
        withApi({ val j = it.get("/api/scene"); Pair(Scene.from(j), j.toString()) }, done)

    /** Ask the DM for an action this turn. */
    fun requestAction(key: String, dice: Int?, done: (Result<Unit>) -> Unit) = withApi({
        it.postJson("/api/turn/requests", JSONObject().put("key", key).apply { if (dice != null) put("dice", dice) })
        Unit
    }, done)

    fun withdrawRequest(id: String, done: (Result<Unit>) -> Unit) =
        withApi({ it.postJson("/api/turn/requests/$id/delete"); Unit }, done)

    /**
     * One of the web inventory actions (equip, unequip, discard, claim,
     * claim_equip) for this Character, through the same route the web sheet posts to.
     */
    fun inventoryAction(action: String, creatureId: Int, index: Int, quantity: Int?, done: (Result<Unit>) -> Unit) =
        withApi({
            val fields = mutableMapOf(
                "creature_id" to creatureId.toString(),
                "index" to index.toString(),
                "detail" to "minimal",
            )
            if (quantity != null) fields["quantity"] = quantity.toString()
            it.postForm("/inventory/$action", fields)
        }, done)

    /** Send a public roll to the DM's Roll Log. */
    fun sendRoll(result: RollResult, done: (Result<Unit>) -> Unit) {
        val s = sheet ?: return done(Result.failure(java.io.IOException("no character")))
        withApi({ it.postJson("/dm/roll", result.toRollLogJson(s.id, s.name)); Unit }, done)
    }
}
