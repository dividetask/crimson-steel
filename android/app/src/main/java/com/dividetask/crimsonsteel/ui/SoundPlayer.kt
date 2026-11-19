package com.dividetask.crimsonsteel.ui

import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import com.dividetask.crimsonsteel.debug.DebugLog
import com.dividetask.crimsonsteel.net.Session
import java.io.File
import java.util.concurrent.Executors

/**
 * An action's sound (docs/project/action_sounds.md). After the player takes
 * an action that has one, it is *offered*: the audio bar at the bottom of the
 * screen ([AudioBar]) shows Play. Playing downloads the mp3 from the server
 * through the app's own connection (once; kept in the app's cache) and plays
 * it from the phone, with Pause / Resume and Stop. When it ends — or is
 * stopped or dismissed — the bar goes away. One sound at a time.
 */
object SoundPlayer {
    enum class State { IDLE, OFFERED, LOADING, PLAYING, PAUSED }

    var state = State.IDLE
        private set
    var name: String = ""
        private set
    private var path: String? = null
    private var player: MediaPlayer? = null
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val listeners = mutableSetOf<() -> Unit>()

    /** Position and length in ms while playing / paused (0 when unknown). */
    val position: Int get() = runCatching { player?.currentPosition ?: 0 }.getOrDefault(0)
    val duration: Int get() = runCatching { player?.duration ?: 0 }.getOrDefault(0)

    fun listen(l: () -> Unit) { listeners += l }
    fun unlisten(l: () -> Unit) { listeners -= l }
    private fun changed(s: State) { state = s; listeners.toList().forEach { it() } }

    /** Offer [soundPath] (e.g. "/sounds/RAGE_AGAIN.mp3") for the action [actionName]. */
    fun offer(actionName: String, soundPath: String) {
        release()
        name = actionName
        path = soundPath
        changed(State.OFFERED)
    }

    fun play(cacheDir: File) {
        val p = path ?: return
        when (state) {
            State.PAUSED -> { player?.start(); changed(State.PLAYING); return }
            State.PLAYING, State.LOADING -> return
            else -> {}
        }
        changed(State.LOADING)
        io.execute {
            val file = File(File(cacheDir, "sounds").apply { mkdirs() }, p.substringAfterLast('/'))
            val ok = runCatching {
                if (!file.exists() || file.length() == 0L) {
                    val api = Session.api ?: throw java.io.IOException("not connected")
                    val tmp = File(file.path + ".part")
                    api.download(p, tmp)
                    tmp.renameTo(file)
                }
            }.onFailure { DebugLog.e("sound", "could not fetch $p", it) }.isSuccess
            main.post { if (path == p && state == State.LOADING) { if (ok) start(file) else stop() } }
        }
    }

    private fun start(file: File) {
        try {
            val mp = MediaPlayer()
            player = mp
            mp.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            mp.setDataSource(file.path)
            mp.setOnCompletionListener { if (player === it) stop() }
            mp.setOnErrorListener { m, what, extra ->
                DebugLog.i("sound", "playback error $what/$extra")
                if (player === m) stop()
                true
            }
            mp.prepare()
            mp.start()
            DebugLog.i("sound", "playing $name")
            changed(State.PLAYING)
        } catch (e: Exception) {
            DebugLog.e("sound", "could not play $name", e)
            stop()
        }
    }

    fun pause() {
        if (state != State.PLAYING) return
        runCatching { player?.pause() }
        changed(State.PAUSED)
    }

    /** Stop and dismiss: the bar goes away. */
    fun stop() {
        release()
        path = null
        changed(State.IDLE)
    }

    private fun release() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
    }
}
