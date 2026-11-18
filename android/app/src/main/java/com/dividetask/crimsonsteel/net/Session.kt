package com.dividetask.crimsonsteel.net

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import com.dividetask.crimsonsteel.data.Hello
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

    fun init(ctx: Context) {
        if (!::prefs.isInitialized) prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
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
     * Wi-Fi network. Succeeds with the server's /api/hello answer.
     */
    fun connect(done: (Result<Hello>) -> Unit) = background({
        val remembered = prefs.getString(KEY_HOST, null)?.let { ServerInfo(it, prefs.getInt(KEY_PORT, 4567), "") }
        val hello = remembered?.let { s -> runCatching { hello(Api(s, cookieStore)) }.getOrNull() }
        hello ?: run {
            val found = ServerLocator.discover() ?: throw java.io.IOException("No Crimson Steel server found on this network")
            hello(Api(found, cookieStore))
        }
    }, done)

    private fun hello(a: Api): Hello {
        val h = Hello.from(a.get("/api/hello"))
        api = a
        prefs.edit().putString(KEY_HOST, a.server.host).putInt(KEY_PORT, a.server.port).apply()
        return h
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
