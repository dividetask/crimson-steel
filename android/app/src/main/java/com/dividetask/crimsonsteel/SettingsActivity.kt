package com.dividetask.crimsonsteel

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.dividetask.crimsonsteel.debug.DebugLog
import com.dividetask.crimsonsteel.debug.LogSaver
import com.dividetask.crimsonsteel.net.ServerLocator
import com.dividetask.crimsonsteel.net.Session
import com.dividetask.crimsonsteel.ui.Ui

/**
 * Settings, reached from the gear at the top of every screen (as in the
 * Sudoku Trainer): the app version, the player's dice colour, the
 * connection, and the debug log — which can be saved as a file to the
 * phone's Downloads folder.
 */
class SettingsActivity : Activity() {

    private var logView: TextView? = null
    private val screenshots by lazy { com.dividetask.crimsonsteel.debug.ScreenshotWatcher(this) }

    override fun onStart() {
        super.onStart()
        screenshots.start()
    }

    override fun onStop() {
        screenshots.stop()
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The installer's answer can arrive after this screen was closed: it is reopened with it.
        com.dividetask.crimsonsteel.net.AppUpdater.handleStatus(this, intent)?.let { toast(it) }
        Session.init(this)
        DebugLog.i("settings", "opened")

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Ui.BG)
            fitsSystemWindows = true
        }
        root.addView(Ui.topBar(this, "Settings", null).first, Ui.matchWidth())

        val col = Ui.vertical(this, 16)

        // --- App ---------------------------------------------------------------
        col.addView(Ui.sectionHeader(this, "App"))
        col.addView(infoCard(listOf("Version" to Ui.versionName)), Ui.matchWidth())

        // --- App updates ---------------------------------------------------------------
        col.addView(Ui.sectionHeader(this, "App updates"))
        updateBox = Ui.vertical(this, 0)
        col.addView(updateBox, Ui.matchWidth())
        showUpdates()

        // --- Dice colour -------------------------------------------------------------
        col.addView(Ui.sectionHeader(this, "Dice colour"))
        col.addView(Ui.text(this,
            "Everyone sees your dice in this colour. A colour someone else has can't be picked.",
            13f, Ui.TEXT_DIM), Ui.matchWidth())
        val colors = Ui.vertical(this, 0)
        colors.addView(Ui.text(this, if (Session.api == null) "Connect to the server to choose a colour." else "Loading\u2026", 13f, Ui.TEXT_FAINT))
        col.addView(colors, Ui.matchWidth(Ui.dp(this, 6)))
        if (Session.api != null) Session.diceColors { r -> showColors(colors, r) }

        // --- Connection ----------------------------------------------------------
        col.addView(Ui.sectionHeader(this, "Connection"))
        col.addView(infoCard(listOf(
            "Server" to (Session.serverAddress ?: "not connected"),
            "Device id" to (Session.deviceId ?: "not issued yet"),
            "Character" to (Session.sheet?.name ?: "—"),
            "VPN" to (if (Session.vpnActive) "ON (e.g. a firewall app) \u2014 it must allow Crimson Steel" else "off"),
            "This phone" to (ServerLocator.localNetworks().joinToString { "${it.address.hostAddress}/${it.prefix}" }.ifBlank { "no network" }),
        )), Ui.matchWidth())
        col.addView(button("Search for the server again") {
            Session.forgetServer()
            finish()
        }, Ui.matchWidth(Ui.dp(this, 8)))
        col.addView(Ui.text(this,
            "Forgets the server used last time and searches the Wi-Fi network again.",
            12f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(this, 2)))

        // --- Debug log -------------------------------------------------------------
        col.addView(Ui.sectionHeader(this, "Debug log"))
        col.addView(Ui.text(this,
            "Records how the app searches for the server and talks to it. Send it to the server when something goes wrong; " +
                "the DM finds it in the server's device-logs folder. A screenshot taken in the app is sent there too" +
                (if (android.os.Build.VERSION.SDK_INT >= 34) "." else " (needs Android 14 or newer)."),
            13f, Ui.TEXT_DIM), Ui.matchWidth())
        col.addView(button("Send log to server", primary = true) { sendLog() }, Ui.matchWidth(Ui.dp(this, 8)))
        col.addView(button("Save debug log") { saveLog() }, Ui.matchWidth(Ui.dp(this, 4)))
        col.addView(button("Copy log to clipboard") { copyLog() }, Ui.matchWidth(Ui.dp(this, 4)))
        val row = Ui.horizontal(this)
        row.addView(button("View log") { toggleLog(col) }, Ui.weighted().apply { marginEnd = Ui.dp(this@SettingsActivity, 6) })
        row.addView(button("Clear log") { confirmClear() }, Ui.weighted())
        col.addView(row, Ui.matchWidth(Ui.dp(this, 4)))

        col.addView(button("Done") { finish() }, Ui.matchWidth(Ui.dp(this, 24)))

        root.addView(ScrollView(this).apply { addView(col) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
    }

    /** One swatch per colour, four to a row: yours outlined gold, others' taken ones faded with who has them. */
    private fun showColors(box: LinearLayout, r: Result<com.dividetask.crimsonsteel.data.DiceColors>) {
        if (isFinishing) return
        box.removeAllViews()
        val d = r.getOrElse {
            box.addView(Ui.text(this, "Could not load the colours: ${it.message}", 13f, Ui.TEXT_FAINT))
            return
        }
        d.options.chunked(4).forEach { rowOpts ->
            val row = Ui.horizontal(this)
            rowOpts.forEach { o ->
                val mine = o.key == d.mine
                val taken = o.takenBy != null
                val cell = Ui.vertical(this, 6).apply {
                    gravity = android.view.Gravity.CENTER_HORIZONTAL
                    alpha = if (taken) 0.35f else 1f
                    background = Ui.rounded(Ui.SURFACE, Ui.dpf(context, 8f), if (mine) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(context, if (mine) 2 else 1))
                }
                cell.addView(View(this).apply { background = Ui.rounded(o.color, Ui.dpf(context, 6f)) },
                    LinearLayout.LayoutParams(Ui.dp(this, 34), Ui.dp(this, 34)))
                cell.addView(Ui.text(this, o.name, 12f, Ui.TEXT).apply { gravity = android.view.Gravity.CENTER })
                if (taken) cell.addView(Ui.text(this, o.takenBy!!, 10f, Ui.TEXT_DIM).apply { gravity = android.view.Gravity.CENTER })
                if (!mine && !taken) cell.setOnClickListener {
                    Session.setDiceColor(o.key) { res ->
                        res.onFailure { e -> toast(e.message ?: "Could not change the colour") }
                        // Reload either way: someone may have just taken it.
                        Session.diceColors { again -> showColors(box, again) }
                    }
                }
                row.addView(cell, Ui.weighted().apply { marginEnd = Ui.dp(this@SettingsActivity, 4); bottomMargin = Ui.dp(this@SettingsActivity, 4) })
            }
            repeat(4 - rowOpts.size) { row.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f).apply { marginEnd = Ui.dp(this@SettingsActivity, 4) }) }
            box.addView(row, Ui.matchWidth())
        }
    }

    private var updateBox: LinearLayout? = null

    /**
     * This app's version next to the server's (the newest build in its
     * checkout). When the server's is newer, Update downloads it from the
     * server and hands it to Android's installer; the app never updates by
     * itself.
     */
    /** Bumped on every redraw: an answer for an older one is dropped (it would add a second button). */
    private var updatesShown = 0

    private fun showUpdates(status: String? = null) {
        val box = updateBox ?: return
        box.removeAllViews()
        val shown = ++updatesShown
        val U = com.dividetask.crimsonsteel.net.AppUpdater
        box.addView(Ui.text(this, "This app: ${Ui.versionName}", 14f, Ui.TEXT), Ui.matchWidth())
        if (Session.api == null) {
            box.addView(Ui.text(this, "Connect to the server to check for updates.", 13f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(this, 4)))
            return
        }
        val serverLine = Ui.text(this, status ?: "Server: checking\u2026", 14f, Ui.TEXT_DIM)
        box.addView(serverLine, Ui.matchWidth(Ui.dp(this, 2)))
        if (status != null) return
        U.latest { r ->
            if (isFinishing || shown != updatesShown) return@latest
            val rel = r.getOrNull()
            val theirs = U.parse(rel?.version)
            val mine = U.parse(Ui.versionName)
            when {
                r.isFailure -> serverLine.text = "Server: could not check (${r.exceptionOrNull()?.message})"
                rel == null || theirs == null -> serverLine.text = "Server: has no app build."
                U.needsUpdate(rel, Ui.versionName) -> {
                    serverLine.text = "Server: ${rel.version} \u2014 a newer build."
                    box.addView(button("Update to ${rel.version}", primary = true) { startUpdate(rel.version) },
                        Ui.matchWidth(Ui.dp(this, 6)))
                }
                mine != null && U.compare(theirs, mine) < 0 ->
                    serverLine.text = "Server: ${rel.version} \u2014 older than this app. Android cannot install an older build over a newer one; pull the server to get the newest."
                else -> serverLine.text = "Server: ${rel.version} \u2014 up to date."
            }
        }
    }

    private fun startUpdate(version: String) {
        com.dividetask.crimsonsteel.net.AppUpdater.start(this, version) { msg -> showUpdates(msg) }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        com.dividetask.crimsonsteel.net.AppUpdater.handleStatus(this, intent)?.let { msg -> toast(msg); showUpdates() }
    }

    override fun onResume() {
        super.onResume()
        // Back from Android's "install unknown apps" screen: show the current state.
        if (updateBox != null && updateBox!!.childCount > 0) showUpdates()
    }

    private fun infoCard(rows: List<Pair<String, String>>): View = Ui.card(this).apply {
        for ((label, value) in rows) {
            val r = Ui.horizontal(this@SettingsActivity).apply { setPadding(0, Ui.dp(context, 3), 0, Ui.dp(context, 3)) }
            r.addView(Ui.text(context, label, 14f, Ui.TEXT_DIM),
                LinearLayout.LayoutParams(Ui.dp(context, 96), LinearLayout.LayoutParams.WRAP_CONTENT))
            r.addView(Ui.text(context, value, 14f, Ui.TEXT).apply { setTextIsSelectable(true) }, Ui.weighted())
            addView(r, Ui.matchWidth())
        }
    }

    private fun button(label: String, primary: Boolean = false, onTap: () -> Unit) = Button(this).apply {
        text = label
        if (primary) setTextColor(Ui.GOLD)
        setOnClickListener { onTap() }
    }

    private fun logHeader(): String = buildString {
        appendLine("Crimson Steel debug log")
        appendLine(Session.appInfo(this@SettingsActivity))
        appendLine("Server: ${Session.serverAddress ?: "not connected"}")
        appendLine("Device id: ${Session.deviceId ?: "not issued"}")
        appendLine("Character: ${Session.sheet?.name ?: "-"}")
        appendLine("VPN: ${if (Session.vpnActive) "on" else "off"}")
        ServerLocator.localNetworks().forEach {
            appendLine("Network ${it.nic}: ${it.address.hostAddress}/${it.prefix} broadcast ${it.broadcast?.hostAddress}")
        }
        append("Saved: ${java.util.Date()}")
    }

    /** Save a copy of the log to Downloads (Android 10+), or let the player pick where (older Android). */
    private fun saveLog() {
        DebugLog.i("settings", "saving debug log")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            runCatching { LogSaver.saveToDownloads(this, logHeader()) }
                .onSuccess { name ->
                    DebugLog.i("settings", "saved Downloads/$name")
                    toast("Saved to Downloads: $name")
                }
                .onFailure {
                    DebugLog.e("settings", "save failed", it)
                    toast("Could not save the log: ${it.message}")
                }
        } else {
            val pick = android.content.Intent(android.content.Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(android.content.Intent.CATEGORY_OPENABLE)
                type = "text/plain"
                putExtra(android.content.Intent.EXTRA_TITLE, LogSaver.fileName())
            }
            @Suppress("DEPRECATION")
            startActivityForResult(pick, REQUEST_SAVE)
        }
    }

    /**
     * Copy the log (with the same header as the saved file) to the clipboard,
     * to paste into a message. Very long logs keep only their newest part: a
     * clipboard has a size limit.
     */
    private fun sendLog() {
        if (Session.api == null) return toast("Not connected to the server.")
        com.dividetask.crimsonsteel.debug.LogUploader.send(this) { r ->
            r.onSuccess { DebugLog.i("logs", "log saved on the server: $it") }
            r.onFailure { DebugLog.e("logs", "log not sent", it) }
            if (!isFinishing) toast(if (r.isSuccess) "Log sent to the server" else "Log not sent: ${r.exceptionOrNull()?.message}")
        }
    }

    private fun copyLog() {
        val lines = DebugLog.read().lines()
        var body = lines.takeLast(MAX_COPY_LINES).joinToString("\n")
        if (body.length > MAX_COPY_CHARS) body = body.takeLast(MAX_COPY_CHARS).substringAfter('\n')
        val cut = if (lines.size > MAX_COPY_LINES || body.length >= MAX_COPY_CHARS) "\n(only the newest part of the log)\n" else "\n"
        val text = logHeader() + cut + body
        val cm = getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        cm.setPrimaryClip(android.content.ClipData.newPlainText("Crimson Steel debug log", text))
        DebugLog.i("settings", "copied the debug log to the clipboard")
        toast("Debug log copied \u2014 paste it into your message")
    }

    @Deprecated("Activity result for the Android 8–9 save picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE || resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        runCatching { LogSaver.write(this, uri, logHeader()) }
            .onSuccess { DebugLog.i("settings", "saved debug log"); toast("Debug log saved") }
            .onFailure { DebugLog.e("settings", "save failed", it); toast("Could not save the log: ${it.message}") }
    }

    private fun toast(msg: String) = android.widget.Toast.makeText(this, msg, android.widget.Toast.LENGTH_LONG).show()

    /** Show the newest part of the log inline (the full log is in the shared file). */
    private fun toggleLog(col: LinearLayout) {
        logView?.let { col.removeView(it); logView = null; return }
        val lines = DebugLog.read().lines()
        val tail = lines.takeLast(300).joinToString("\n")
        val v = Ui.text(this, if (tail.isBlank()) "(the log is empty)" else tail, 11f, Ui.TEXT_DIM).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            setTextIsSelectable(true)
            background = Ui.rounded(Ui.SURFACE, Ui.dpf(context, 8f))
            setPadding(Ui.dp(context, 8), Ui.dp(context, 8), Ui.dp(context, 8), Ui.dp(context, 8))
        }
        // Just below the View / Clear row.
        col.addView(v, col.childCount - 1, Ui.matchWidth(Ui.dp(this, 8)))
        logView = v
    }

    private fun confirmClear() {
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Clear the debug log?")
            .setPositiveButton("Clear") { _, _ ->
                DebugLog.clear()
                DebugLog.i("settings", "log cleared")
                logView?.text = "(the log is empty)"
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private companion object {
        const val REQUEST_SAVE = 41
        /** What fits comfortably on the clipboard and in a chat message. */
        const val MAX_COPY_LINES = 2000
        const val MAX_COPY_CHARS = 200_000
    }
}
