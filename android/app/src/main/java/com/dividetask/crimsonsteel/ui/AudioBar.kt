package com.dividetask.crimsonsteel.ui

import android.app.Activity
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar

/**
 * The audio bar at the bottom of the screen (docs/project/action_sounds.md):
 * shown while an action's sound is offered or playing — Play, then Pause /
 * Resume and Stop with its progress — and gone when the sound ends.
 */
class AudioBar(private val activity: Activity) {
    val view: LinearLayout = LinearLayout(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(Ui.dp(activity, 12), Ui.dp(activity, 8), Ui.dp(activity, 12), Ui.dp(activity, 10))
        background = Ui.rounded(Ui.SURFACE_HI, Ui.dpf(activity, 12f), Ui.GOLD, Ui.dp(activity, 1))
        elevation = Ui.dpf(activity, 8f)
        isClickable = true // taps stay on the bar
        visibility = View.GONE
    }
    private val title = Ui.text(activity, "", 14f, Ui.TEXT, bold = true)
    private val main = Button(activity)
    private val stop = Button(activity).apply { text = "\u25A0  Stop" }
    private val progress = ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal).apply { max = 1000 }
    private val tick = object : Runnable {
        override fun run() {
            val d = SoundPlayer.duration
            progress.progress = if (d > 0) (SoundPlayer.position * 1000L / d).toInt() else 0
            if (SoundPlayer.state == SoundPlayer.State.PLAYING) view.postDelayed(this, 250)
        }
    }
    private val onChange = { update() }

    init {
        val row = Ui.horizontal(activity).apply { gravity = Gravity.CENTER_VERTICAL }
        row.addView(title, Ui.weighted())
        row.addView(main)
        row.addView(stop)
        view.addView(row, Ui.matchWidth())
        view.addView(progress, Ui.matchWidth(Ui.dp(activity, 4)))
        main.setOnClickListener {
            when (SoundPlayer.state) {
                SoundPlayer.State.PLAYING -> SoundPlayer.pause()
                else -> SoundPlayer.play(activity.cacheDir)
            }
        }
        stop.setOnClickListener { SoundPlayer.stop() }
        SoundPlayer.listen(onChange)
        update()
    }

    fun detach() = SoundPlayer.unlisten(onChange)

    private fun update() {
        val s = SoundPlayer.state
        view.visibility = if (s == SoundPlayer.State.IDLE) View.GONE else View.VISIBLE
        title.text = "\u266B  ${SoundPlayer.name}"
        main.text = when (s) {
            SoundPlayer.State.PLAYING -> "\u275A\u275A  Pause"
            SoundPlayer.State.PAUSED -> "\u25B6  Resume"
            SoundPlayer.State.LOADING -> "Loading\u2026"
            else -> "\u25B6  Play"
        }
        main.isEnabled = s != SoundPlayer.State.LOADING
        stop.text = if (s == SoundPlayer.State.OFFERED) "\u2715" else "\u25A0  Stop"
        progress.visibility = if (s == SoundPlayer.State.PLAYING || s == SoundPlayer.State.PAUSED) View.VISIBLE else View.GONE
        view.removeCallbacks(tick)
        if (s == SoundPlayer.State.PLAYING) view.post(tick) else tick.run()
    }
}
