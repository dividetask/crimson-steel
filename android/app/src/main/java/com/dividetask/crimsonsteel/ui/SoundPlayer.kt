package com.dividetask.crimsonsteel.ui

import android.media.AudioAttributes
import android.media.MediaPlayer
import com.dividetask.crimsonsteel.debug.DebugLog
import com.dividetask.crimsonsteel.net.Session

/**
 * Plays an action's sound on this device (docs/project/action_sounds.md),
 * streamed from the server (e.g. /sounds/RAGE_AGAIN.mp3). One sound at a
 * time: playing another — or the same again — stops the first.
 */
object SoundPlayer {
    private var player: MediaPlayer? = null
    private var playingPath: String? = null

    val playing: String? get() = playingPath

    /** Play [path], or stop it if it is the one playing. [onChange] runs when it starts or stops. */
    fun toggle(path: String, onChange: () -> Unit) {
        if (playingPath == path) { stop(); onChange(); return }
        stop()
        val base = Session.api?.server?.baseUrl ?: return
        val p = MediaPlayer()
        player = p
        playingPath = path
        try {
            p.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            p.setDataSource(base + path)
            p.setOnPreparedListener { it.start() }
            p.setOnCompletionListener { if (player === it) { stop(); onChange() } }
            p.setOnErrorListener { mp, what, extra ->
                DebugLog.i("sound", "could not play $path ($what/$extra)")
                if (player === mp) { stop(); onChange() }
                true
            }
            p.prepareAsync()
            DebugLog.i("sound", "playing $path")
        } catch (e: Exception) {
            DebugLog.e("sound", "could not play $path", e)
            stop()
        }
        onChange()
    }

    fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        playingPath = null
    }
}
