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
import com.dividetask.crimsonsteel.debug.LogProvider
import com.dividetask.crimsonsteel.net.ServerLocator
import com.dividetask.crimsonsteel.net.Session
import com.dividetask.crimsonsteel.ui.Ui

/**
 * Settings, reached from the gear at the top of every screen (as in the
 * Sudoku Trainer): the app version, the connection, and the debug log —
 * which can be sent as a file from the share sheet.
 */
class SettingsActivity : Activity() {

    private var logView: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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

        // --- Connection ----------------------------------------------------------
        col.addView(Ui.sectionHeader(this, "Connection"))
        col.addView(infoCard(listOf(
            "Server" to (Session.serverAddress ?: "not connected"),
            "Device id" to (Session.deviceId ?: "not issued yet"),
            "Character" to (Session.sheet?.name ?: "—"),
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
            "Records how the app searches for the server and talks to it. Send it when something goes wrong.",
            13f, Ui.TEXT_DIM), Ui.matchWidth())
        col.addView(button("Share debug log", primary = true) { shareLog() }, Ui.matchWidth(Ui.dp(this, 8)))
        val row = Ui.horizontal(this)
        row.addView(button("View log") { toggleLog(col) }, Ui.weighted().apply { marginEnd = Ui.dp(this@SettingsActivity, 6) })
        row.addView(button("Clear log") { confirmClear() }, Ui.weighted())
        col.addView(row, Ui.matchWidth(Ui.dp(this, 4)))

        col.addView(button("Done") { finish() }, Ui.matchWidth(Ui.dp(this, 24)))

        root.addView(ScrollView(this).apply { addView(col) },
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
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

    private fun shareLog() {
        DebugLog.i("settings", "sharing debug log")
        val header = buildString {
            appendLine("Crimson Steel debug log")
            appendLine(Session.appInfo(this@SettingsActivity))
            appendLine("Server: ${Session.serverAddress ?: "not connected"}")
            appendLine("Device id: ${Session.deviceId ?: "not issued"}")
            appendLine("Character: ${Session.sheet?.name ?: "-"}")
            ServerLocator.localNetworks().forEach {
                appendLine("Network ${it.nic}: ${it.address.hostAddress}/${it.prefix} broadcast ${it.broadcast?.hostAddress}")
            }
            append("Shared: ${java.util.Date()}")
        }
        runCatching {
            startActivity(LogProvider.shareIntent(this, header, "Crimson Steel debug log (${Ui.versionName})"))
        }.onFailure {
            DebugLog.e("settings", "share failed", it)
            android.widget.Toast.makeText(this, "No app available to share the log", android.widget.Toast.LENGTH_LONG).show()
        }
    }

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
}
