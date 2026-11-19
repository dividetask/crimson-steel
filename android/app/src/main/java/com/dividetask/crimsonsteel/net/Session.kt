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

    /** This player's dice colour (from /api/hello; changed in Settings). */
    var diceColor: Int = com.dividetask.crimsonsteel.ui.Ui.DICE_DEFAULT

    /** Last sheet fetched — used for the character name and to label public rolls. */
    var sheet: Sheet? = null

    /**
     * This phone's own id: Android's per-app id (16 hex digits, the same for
     * every install of this app on this phone, different for other apps). The
     * server accepts it as the device id, so the phone is always the same
     * device — never a new one. Null only if Android gives none; then the
     * server-issued id is kept as before.
     */
    private val phoneId: String? by lazy {
        runCatching {
            android.provider.Settings.Secure.getString(appCtx.contentResolver, android.provider.Settings.Secure.ANDROID_ID)
        }.getOrNull()?.lowercase()?.takeIf { it.matches(Regex("[0-9a-f]{16}")) }
    }

    private val cookieStore = object : CookieStore {
        override var deviceCookie: String?
            get() = phoneId ?: prefs.getString(KEY_COOKIE, null)
            // With the phone's own id, a server-issued id is never adopted.
            set(v) { if (phoneId == null) prefs.edit().putString(KEY_COOKIE, v).apply() }

        // The id the server issued before (older app versions): sent until the
        // server has carried its assignment over (see adopt()).
        override val previousDevice: String?
            get() = if (phoneId != null) prefs.getString(KEY_COOKIE, null)?.takeIf { it != phoneId } else null
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
     * Wi-Fi network. Succeeds
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
                throw java.io.IOException("No reply to the discovery broadcast")
            }
        }
    }, { r ->
        r.onSuccess { DebugLog.i(TAG, "connected to ${api?.server?.baseUrl}; campaign \"${it.campaign}\", device ${it.device}, character ${it.character?.name ?: "(not assigned)"}") }
         .onFailure { DebugLog.e(TAG, "search failed", it) }
        done(r)
    })

    /** Confirm [a] answers /api/hello, then make it the current server and remember it. */
    private fun adopt(a: Api): Hello {
        val h = Hello.from(a.get("/api/hello"))
        h.diceColor?.let { diceColor = it }
        // The server has seen the phone's own id (and carried over the old one): stop sending the old one.
        if (phoneId != null && prefs.contains(KEY_COOKIE)) {
            DebugLog.i(TAG, "device id is now this phone's own (${phoneId!!.take(8)})")
            prefs.edit().remove(KEY_COOKIE).apply()
        }
        api = a
        prefs.edit().putString(KEY_HOST, a.server.host).putInt(KEY_PORT, a.server.port).apply()
        return h
    }

    /** Server details for the Settings screen. */
    val serverAddress: String? get() = api?.server?.baseUrl ?: prefs.getString(KEY_HOST, null)?.let { "http://$it:${prefs.getInt(KEY_PORT, 4567)}" }
    val deviceId: String? get() = if (::prefs.isInitialized) cookieStore.deviceCookie?.take(8) else null

    /** Drop the remembered server so the next search starts from discovery. Keeps the device id. */
    fun forgetServer() {
        DebugLog.i(TAG, "forgetting server ${serverAddress ?: "(none)"}")
        api = null
        sheet = null
        prefs.edit().remove(KEY_HOST).remove(KEY_PORT).apply()
    }

    fun hello(done: (Result<Hello>) -> Unit) = withApi({ Hello.from(it.get("/api/hello")).also { h -> h.diceColor?.let { c -> diceColor = c } } }, done)

    /** This player's dice colour and every colour on offer (Settings). */
    fun diceColors(done: (Result<com.dividetask.crimsonsteel.data.DiceColors>) -> Unit) =
        withApi({ com.dividetask.crimsonsteel.data.DiceColors.from(it.get("/api/dice_colors")) }, done)

    /** Change this player's dice colour; refused when someone else has it. */
    fun setDiceColor(key: String, done: (Result<com.dividetask.crimsonsteel.data.DiceColors>) -> Unit) = withApi({
        val d = com.dividetask.crimsonsteel.data.DiceColors.from(it.postJson("/api/dice_color", JSONObject().put("color", key)))
        d.options.find { o -> o.key == d.mine }?.let { o -> diceColor = o.color }
        d
    }, done)

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

    /** Ask the DM for an action this turn. An attack also names its target and starts a step-by-step attack. */
    fun requestAction(key: String, dice: Int?, targetId: Int? = null, done: (Result<Unit>) -> Unit) = withApi({
        it.postJson("/api/turn/requests", JSONObject().put("key", key).apply {
            if (dice != null) put("dice", dice)
            if (targetId != null) put("target_id", targetId)
        })
        Unit
    }, done)

    /** Steps waiting on this player in any attack (for the tab badge). */
    fun prompts(done: (Result<List<com.dividetask.crimsonsteel.data.Prompt>>) -> Unit) =
        withApi({ com.dividetask.crimsonsteel.data.Prompt.list(it.get("/api/prompts").optJSONArray("prompts")) }, done)

    /** Steps waiting on this player, and what the DM committed lately. */
    fun promptsAndNews(done: (Result<Pair<List<com.dividetask.crimsonsteel.data.Prompt>, List<com.dividetask.crimsonsteel.data.NewsItem>>>) -> Unit) =
        withApi({
            val j = it.get("/api/prompts")
            Pair(com.dividetask.crimsonsteel.data.Prompt.list(j.optJSONArray("prompts")),
                com.dividetask.crimsonsteel.data.NewsItem.list(j.optJSONArray("news")))
        }, done)

    /** Answer a choice prompt (defense, ally shield, Luck) with one of its option values. */
    fun answerPrompt(flowId: String, taskId: String, value: String, done: (Result<Unit>) -> Unit) = withApi({
        it.postJson("/api/prompts/$flowId/$taskId", JSONObject().put("value", value)); Unit
    }, done)

    /** Send the dice rolled for a roll prompt (as rolled, any Luck rerolls, and the final dice). */
    fun submitRoll(flowId: String, taskId: String, dice: List<Int>, rerolled: List<Int?>, final: List<Int>,
                   done: (Result<Unit>) -> Unit) = withApi({
        val roll = JSONObject()
            .put("dice", org.json.JSONArray(dice))
            .put("rerolled", org.json.JSONArray().apply { rerolled.forEach { v -> put(v ?: JSONObject.NULL) } })
            .put("final", org.json.JSONArray(final))
        it.postJson("/api/prompts/$flowId/$taskId", JSONObject().put("roll", roll)); Unit
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
