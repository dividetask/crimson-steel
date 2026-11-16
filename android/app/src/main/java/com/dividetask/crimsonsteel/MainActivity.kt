package com.dividetask.crimsonsteel

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.dividetask.crimsonsteel.data.DummyData
import com.dividetask.crimsonsteel.ui.InitiativeScreen
import com.dividetask.crimsonsteel.ui.NotesScreen
import com.dividetask.crimsonsteel.ui.SceneScreen
import com.dividetask.crimsonsteel.ui.SheetScreen
import com.dividetask.crimsonsteel.ui.Ui

/**
 * Single-activity app: the character name sits at the top, a tab row picks
 * one of four screens below it. Everything runs on DummyData for now.
 */
class MainActivity : Activity() {

    private enum class Tab(val label: String) {
        SHEET("Sheet"),
        INITIATIVE("Initiative"),
        NOTES("Notes"),
        SCENE("Scene"),
    }

    private lateinit var content: FrameLayout
    private val tabViews = mutableMapOf<Tab, TextView>()
    private var current = Tab.SHEET

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        savedInstanceState?.getString(KEY_TAB)?.let { name -> Tab.entries.find { it.name == name }?.let { current = it } }

        val character = DummyData.character
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Ui.BG)
            fitsSystemWindows = true
        }

        // Character name header.
        val header = Ui.vertical(this).apply {
            setBackgroundColor(Ui.CRIMSON_DARK)
            setPadding(Ui.dp(context, 16), Ui.dp(context, 14), Ui.dp(context, 16), Ui.dp(context, 12))
        }
        header.addView(Ui.text(this, character.name, 26f, Ui.TEXT, bold = true))
        header.addView(Ui.text(this, "Offline — showing sample data", 12f, 0xFFE8B4B8.toInt()))
        root.addView(header, Ui.matchWidth())

        // Tab row.
        val tabs = Ui.horizontal(this).apply { setBackgroundColor(Ui.SURFACE) }
        for (tab in Tab.entries) {
            val tv = Ui.text(this, tab.label, 14f, Ui.TEXT_DIM, bold = true).apply {
                gravity = Gravity.CENTER
                setPadding(0, Ui.dp(context, 12), 0, Ui.dp(context, 12))
            }
            Ui.makeTappable(tv, this) { select(tab) }
            tabViews[tab] = tv
            tabs.addView(tv, Ui.weighted())
        }
        root.addView(tabs, Ui.matchWidth())

        content = FrameLayout(this)
        root.addView(content, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        setContentView(root)
        select(current)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(KEY_TAB, current.name)
    }

    private fun select(tab: Tab) {
        current = tab
        for ((t, tv) in tabViews) {
            val on = t == tab
            tv.setTextColor(if (on) Ui.TEXT else Ui.TEXT_DIM)
            tv.background = if (on) Ui.rounded(Ui.SURFACE_HI, 0f) else null
        }
        val view: View = when (tab) {
            Tab.SHEET -> SheetScreen.build(this, DummyData.character)
            Tab.INITIATIVE -> InitiativeScreen.build(this, DummyData.initiative)
            Tab.NOTES -> NotesScreen.build(this, DummyData.notes)
            Tab.SCENE -> SceneScreen.build(this, DummyData.scene)
        }
        content.removeAllViews()
        content.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
    }

    private companion object {
        const val KEY_TAB = "tab"
    }
}
