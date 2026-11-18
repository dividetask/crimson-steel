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
        SHEET("Sheet", 5000),
        INITIATIVE("Initiative", 2000),
        INVENTORY("Items", 5000),
        NOTES("Notes", 10000),
        SCENE("Scene", 5000),
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var root: FrameLayout
    private var current = Tab.SHEET
    private var screen: LiveScreen<*>? = null
    private val tabViews = mutableMapOf<Tab, TextView>()
    private var headerName: TextView? = null
    private var content: FrameLayout? = null
    private var playing = false
    private var resumed = false
    private var searching = false
    private var lastMessage: String? = null

    private val poll = object : Runnable {
        override fun run() {
            if (!resumed) return
            if (playing) screen?.refresh() else checkAssignment()
            handler.postDelayed(this, if (playing) current.pollMs else 3000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Session.init(this)
        savedInstanceState?.getString(KEY_TAB)?.let { n -> Tab.entries.find { it.name == n }?.let { current = it } }
        root = FrameLayout(this).apply {
            setBackgroundColor(Ui.BG)
            fitsSystemWindows = true
        }
        setContentView(root)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        if (Session.api == null) search() else checkAssignment()
    }

    override fun onPause() {
        super.onPause()
        resumed = false
        handler.removeCallbacks(poll)
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
                 val vpnHint = if (Session.vpnActive) {
                     "\n\nThis phone has a VPN turned on. A VPN can stop the app reaching computers on your " +
                         "Wi-Fi: turn the VPN off, or allow local network access in its settings, then try again."
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

    private fun onHello(h: Hello) {
        val c = h.character
        if (c == null) {
            playing = false
            showMessage("Connected to ${h.campaign.ifBlank { "Crimson Steel" }}",
                "Waiting for the DM to assign this device a character.\n\n" +
                    "DM: open the Status page on the server and assign device “${h.device}”.")
        } else if (!playing) {
            showPlaying(c.name)
        } else {
            headerName?.text = c.name
        }
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, if (playing) current.pollMs else 3000)
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

    private fun showMessage(title: String, body: String, action: String? = null, onAction: (() -> Unit)? = null) {
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
        select(current)
    }

    private fun select(tab: Tab) {
        current = tab
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
        handler.postDelayed(poll, tab.pollMs)
    }

    private fun openSettings() {
        startActivity(android.content.Intent(this, SettingsActivity::class.java))
    }

    private companion object {
        const val KEY_TAB = "tab"
        const val TAG = "main"
    }
}
