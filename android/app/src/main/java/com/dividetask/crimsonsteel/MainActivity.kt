package com.dividetask.crimsonsteel

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.dividetask.crimsonsteel.data.Hello
import com.dividetask.crimsonsteel.debug.DebugLog
import com.dividetask.crimsonsteel.net.ApiException
import com.dividetask.crimsonsteel.net.LiveEvents
import com.dividetask.crimsonsteel.net.Session
import com.dividetask.crimsonsteel.ui.InitiativeScreen
import com.dividetask.crimsonsteel.ui.InventoryScreen
import com.dividetask.crimsonsteel.ui.LiveScreen
import com.dividetask.crimsonsteel.ui.NotesScreen
import com.dividetask.crimsonsteel.ui.SceneScreen
import com.dividetask.crimsonsteel.ui.SheetScreen
import com.dividetask.crimsonsteel.ui.Ui

/**
 * Single-activity app with three states:
 *  1. Searching — looking for the server on the Wi-Fi network (no IP to type).
 *  2. Waiting — connected, but the DM has not assigned this device a Character
 *     yet (Status page on the web). Re-checks every few seconds.
 *  3. Playing — the Character's name at the top and five tabs, each refreshed
 *     from the server while it is on screen.
 */
class MainActivity : Activity() {

    private enum class Tab(val label: String, val pollMs: Long) {
        INITIATIVE("Initiative", 2000),
        SHEET("Sheet", 5000),
        INVENTORY("Items", 5000),
        NOTES("Notes", 10000),
        SCENE("Scene", 5000),
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var root: FrameLayout
    private var current = Tab.INITIATIVE
    private var screen: LiveScreen<*>? = null
    private val tabViews = mutableMapOf<Tab, TextView>()
    private var headerName: TextView? = null
    private var content: FrameLayout? = null
    private var playing = false
    private var resumed = false
    private var searching = false
    private var lastMessage: String? = null
    /** The Character on screen, and when the assignment was last checked while playing. */
    private var playingId: Int? = null
    private var lastAssignmentCheck = 0L

    /**
     * Live updates (docs/project/live_updates.md): the server says when
     * something changed, and only then is the screen fetched again.
     */
    private val live = LiveEvents { onLiveChange() }

    /** The audio bar for action sounds, over the bottom of every screen. */
    private var audioBar: com.dividetask.crimsonsteel.ui.AudioBar? = null

    private fun attachAudioBar() {
        val bar = audioBar ?: com.dividetask.crimsonsteel.ui.AudioBar(this).also { audioBar = it }
        (bar.view.parent as? ViewGroup)?.removeView(bar.view)
        root.addView(bar.view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.BOTTOM
            val m = Ui.dp(this@MainActivity, 8)
            setMargins(m, m, m, m)
        })
    }

    private fun onLiveChange() {
        if (!resumed) return
        if (playing) {
            screen?.refresh()
            checkAssignment()   // the DM may have moved this device to another Character
            checkPrompts()
        } else checkAssignment()
    }

    /**
     * How long until the next refresh by itself: a slow fallback while the
     * live-updates connection is open, the screen's own pace (as before live
     * updates) while it is not — e.g. a server without them.
     */
    private fun pollDelay(): Long = when {
        live.connected -> FALLBACK_MS
        playing -> minOf(current.pollMs, 3000)
        else -> 3000
    }

    private val poll = object : Runnable {
        override fun run() {
            if (!resumed) return
            if (playing) {
                screen?.refresh()
                // The DM may move this device to another Character at any time:
                // without live updates, check every few seconds.
                val now = System.currentTimeMillis()
                if (live.connected || now - lastAssignmentCheck >= ASSIGNMENT_CHECK_MS) {
                    lastAssignmentCheck = now
                    checkAssignment()
                }
                checkPrompts()
            } else checkAssignment()
            handler.postDelayed(this, pollDelay())
        }
    }

    /** Prompt ids already announced, so each "your move" is announced once. */
    private val announced = mutableSetOf<String>()

    /**
     * From any tab: when an attack step waits on this player (choose a defense,
     * roll…), badge the Initiative tab and say so once.
     */
    /** Outcomes already announced (flow ids), so each is announced once. */
    private val announcedNews = mutableSetOf<String>()
    private var newsPrimed = false

    /**
     * From any tab: when a step waits on this player (choose a defense,
     * roll…), badge the Initiative tab and say so once; and when the DM
     * commits an action, say what happened, once.
     */
    private fun checkPrompts() {
        Session.promptsAndNews { r ->
            val (prompts, news) = r.getOrNull() ?: return@promptsAndNews
            val waiting = prompts.filter { it.waiting }
            tabViews[Tab.INITIATIVE]?.let { tv ->
                tv.text = if (waiting.isEmpty()) Tab.INITIATIVE.label else "${Tab.INITIATIVE.label} \u25CF${waiting.size}"
                tv.setTextColor(if (waiting.isEmpty()) (if (current == Tab.INITIATIVE) Ui.TEXT else Ui.TEXT_DIM) else Ui.GOLD)
            }
            if (current != Tab.INITIATIVE) {
                val fresh = waiting.filter { announced.add(it.taskId) }
                if (fresh.isNotEmpty()) {
                    DebugLog.i(TAG, "prompt: ${fresh.joinToString { it.title }}")
                    android.widget.Toast.makeText(this, "Your move: ${fresh.first().title} (Initiative tab)",
                        android.widget.Toast.LENGTH_LONG).show()
                }
            }
            // What just happened — not the outcomes from before the app opened.
            val freshNews = news.filter { announcedNews.add(it.flowId) }
            if (newsPrimed) freshNews.forEach {
                DebugLog.i(TAG, "news: ${it.text}")
                android.widget.Toast.makeText(this, it.text, android.widget.Toast.LENGTH_LONG).show()
            }
            newsPrimed = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The installer's answer can arrive after this screen was closed: it is reopened with it.
        com.dividetask.crimsonsteel.net.AppUpdater.handleStatus(this, intent)?.let { updateStatus = it }
        Session.init(this)
        savedInstanceState?.getString(KEY_TAB)?.let { n -> Tab.entries.find { it.name == n }?.let { current = it } }
        root = FrameLayout(this).apply {
            setBackgroundColor(Ui.BG)
            fitsSystemWindows = true
        }
        setContentView(root)
    }

    /** A screenshot taken in the app is copied to the server's device-logs/ (Android 14+). */
    private val screenshots by lazy { com.dividetask.crimsonsteel.debug.ScreenshotWatcher(this) }

    override fun onStart() {
        super.onStart()
        screenshots.start()
    }

    override fun onStop() {
        screenshots.stop()
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        live.start()
        if (Session.api == null) search() else checkAssignment()
    }

    override fun onPause() {
        super.onPause()
        resumed = false
        live.stop()   // the connection is held only while the app is on screen
        handler.removeCallbacks(poll)
    }

    override fun onDestroy() {
        audioBar?.detach()
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_TAB, current.name)
    }

    // --- Connection states ------------------------------------------------------------

    private fun search() {
        if (searching) return
        searching = true
        playing = false
        handler.removeCallbacks(poll)
        showMessage("Looking for the Crimson Steel server…",
            "Searching this Wi-Fi network. Make sure the DM's server is running and this phone is on the same Wi-Fi.")
        Session.connect { r ->
            searching = false
            r.onSuccess { onHello(it) }
             .onFailure {
                 if (!com.dividetask.crimsonsteel.net.LocalNetwork.onLocalNetwork(this)) {
                     DebugLog.i(TAG, "not on Wi-Fi")
                     showMessage("Not on Wi-Fi",
                         "This device isn't connected to Wi-Fi. Connect it to the same Wi-Fi network as the DM's computer, then try again.",
                         action = "Search again") { search() }
                     return@onFailure
                 }
                 val vpnHint = if (Session.vpnActive) {
                     "\n\nThis phone has a VPN or firewall app turned on (for example NetGuard). If it blocks " +
                         "Crimson Steel, allow the app in it, then try again."
                 } else ""
                 showMessage("No server found",
                     "Couldn't reach a Crimson Steel server on this Wi-Fi network. Check the server is running " +
                         "and the phone is on the same network, then try again." + vpnHint,
                     action = "Search again") { search() }
             }
        }
    }

    private fun checkAssignment() {
        Session.hello { r -> r.onSuccess { onHello(it) }.onFailure { onApiError(it) } }
    }

    /** The update in progress on the "Update required" screen: what Android or the download last said. */
    private var updateStatus: String? = null

    /** The server's build is newer than this app: every tab waits until it is installed. */
    private fun showUpdateRequired(version: String) {
        showMessage("Update required",
            updateStatus ?: "The server has Crimson Steel $version. Install it to keep playing.",
            action = "Update to $version") {
            com.dividetask.crimsonsteel.net.AppUpdater.start(this, version) { msg ->
                updateStatus = msg
                showUpdateRequired(version)
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        com.dividetask.crimsonsteel.net.AppUpdater.handleStatus(this, intent)?.let { msg ->
            updateStatus = msg
            checkAssignment()
        }
    }

    private fun onHello(h: Hello) {
        if (com.dividetask.crimsonsteel.net.AppUpdater.needsUpdate(h.app)) {
            playing = false
            showUpdateRequired(h.app!!.version)
            handler.removeCallbacks(poll)
            handler.postDelayed(poll, pollDelay())
            return
        }
        updateStatus = null
        val c = h.character
        if (c == null) {
            playing = false
            showMessage("Connected to ${h.campaign.ifBlank { "Crimson Steel" }}",
                "Waiting for the DM to assign this device a character.\n\n" +
                    "DM: open the Status page on the server and assign this device:",
                big = h.device)
        } else if (!playing) {
            playingId = c.id
            showPlaying(c.name)
        } else if (c.id != playingId) {
            // Assigned another Character: start over as them, on the same tab.
            DebugLog.i(TAG, "device moved to ${c.name} (#${c.id})")
            playingId = c.id
            Session.sheet = null
            android.widget.Toast.makeText(this, "You are now ${c.name}", android.widget.Toast.LENGTH_SHORT).show()
            showPlaying(c.name)
            return
        } else {
            headerName?.text = c.name
        }
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, pollDelay())
    }

    /** A screen's request failed: lost the server, or the device was unassigned. */
    private fun onApiError(e: Throwable) {
        if (!resumed) return
        when {
            e is ApiException && e.error == "unassigned" -> { DebugLog.i(TAG, "device is no longer assigned"); checkAssignment() }
            e is ApiException -> android.widget.Toast.makeText(this, "Server error: ${e.error}", android.widget.Toast.LENGTH_SHORT).show()
            else -> { DebugLog.e(TAG, "lost the server; searching again", e); search() }   // network gone: find the server again
        }
    }

    /** [big]: shown large under the body (the device id the DM assigns by). */
    private fun showMessage(title: String, body: String, action: String? = null, big: String? = null,
                            onAction: (() -> Unit)? = null) {
        playing = false
        screen = null
        if (title != lastMessage) DebugLog.i(TAG, "screen: $title")
        lastMessage = title
        val page = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        page.addView(Ui.topBar(this, "Crimson Steel", ::openSettings).first, Ui.matchWidth())
        val col = Ui.vertical(this, 28).apply { gravity = Gravity.CENTER }
        page.addView(col, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        col.addView(Ui.text(this, title, 18f, Ui.GOLD, bold = true).apply { gravity = Gravity.CENTER },
            Ui.matchWidth())
        col.addView(Ui.text(this, body, 15f, Ui.TEXT_DIM).apply { gravity = Gravity.CENTER },
            Ui.matchWidth(Ui.dp(this, 10)))
        if (big != null) {
            col.addView(Ui.text(this, big, 44f, Ui.TEXT, bold = true).apply {
                gravity = Gravity.CENTER
                typeface = android.graphics.Typeface.create(android.graphics.Typeface.MONOSPACE, android.graphics.Typeface.BOLD)
                setTextIsSelectable(true)
            }, Ui.matchWidth(Ui.dp(this, 14)))
        }
        if (action != null && onAction != null) {
            col.addView(Button(this).apply { text = action; setOnClickListener { onAction() } },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    gravity = Gravity.CENTER_HORIZONTAL
                    topMargin = Ui.dp(this@MainActivity, 20)
                })
        }
        if (action == "Search again") {
            col.addView(Ui.text(this, "Settings (\u2699\uFE0E) \u2192 Save debug log saves what the app tried to Downloads.", 12f, Ui.TEXT_FAINT).apply {
                gravity = Gravity.CENTER
            }, Ui.matchWidth(Ui.dp(this, 16)))
        }
        root.removeAllViews()
        root.addView(page, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        attachAudioBar()
        tabViews.clear()
        headerName = null
        content = null
    }

    // --- Playing -------------------------------------------------------------------------

    private fun showPlaying(characterName: String) {
        playing = true
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        DebugLog.i(TAG, "screen: playing as $characterName")
        lastMessage = null
        val (header, nameView) = Ui.topBar(this, characterName, ::openSettings)
        headerName = nameView
        col.addView(header, Ui.matchWidth())

        val tabs = Ui.horizontal(this).apply { setBackgroundColor(Ui.SURFACE) }
        tabViews.clear()
        for (tab in Tab.entries) {
            val tv = Ui.text(this, tab.label, 13f, Ui.TEXT_DIM, bold = true).apply {
                gravity = Gravity.CENTER
                setPadding(0, Ui.dp(context, 12), 0, Ui.dp(context, 12))
            }
            Ui.makeTappable(tv, this) { select(tab) }
            tabViews[tab] = tv
            tabs.addView(tv, Ui.weighted())
        }
        col.addView(tabs, Ui.matchWidth())

        content = FrameLayout(this)
        col.addView(content, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        root.removeAllViews()
        root.addView(col, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        attachAudioBar()
        select(current)
    }

    private fun select(tab: Tab) {
        current = tab
        tabViews[Tab.INITIATIVE]?.text = Tab.INITIATIVE.label
        for ((t, tv) in tabViews) {
            val on = t == tab
            tv.setTextColor(if (on) Ui.TEXT else Ui.TEXT_DIM)
            tv.background = if (on) Ui.rounded(Ui.SURFACE_HI, 0f) else null
        }
        val onError: (Throwable) -> Unit = { onApiError(it) }
        val s: LiveScreen<*> = when (tab) {
            Tab.SHEET -> SheetScreen(this, onError)
            Tab.INITIATIVE -> InitiativeScreen(this, onError)
            Tab.INVENTORY -> InventoryScreen(this, onError)
            Tab.NOTES -> NotesScreen(this, onError)
            Tab.SCENE -> SceneScreen(this, onError)
        }
        screen = s
        content?.removeAllViews()
        content?.addView(s.view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        s.refresh(force = true)
        // The sheet also feeds public rolls (character id + name), so make sure it is loaded once.
        if (tab != Tab.SHEET && Session.sheet == null) Session.sheet { }
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, if (live.connected) FALLBACK_MS else tab.pollMs)
    }

    private fun openSettings() {
        startActivity(android.content.Intent(this, SettingsActivity::class.java))
    }

    private companion object {
        const val KEY_TAB = "tab"
        const val ASSIGNMENT_CHECK_MS = 4000L
        /** With live updates on: refresh by itself this rarely, just in case. */
        const val FALLBACK_MS = 30_000L
        const val TAG = "main"
    }
}
