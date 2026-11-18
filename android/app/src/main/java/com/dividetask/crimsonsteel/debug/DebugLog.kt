package com.dividetask.crimsonsteel.debug

import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The app's debug log: a plain-text file in the app's private storage that the
 * player can send from Settings → Share debug log (see LogProvider).
 *
 * Every line is `yyyy-MM-dd HH:mm:ss.SSS [tag] message`. The file is capped at
 * [MAX_BYTES]; when it grows past that, the oldest half is dropped. Lines are
 * also written to logcat. Nothing secret is logged (the device cookie is
 * shortened to its first 8 characters, like the DM's device table).
 */
object DebugLog {
    const val FILE_NAME = "debug.log"
    private const val MAX_BYTES = 512 * 1024
    private val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val lock = Any()

    @Volatile
    var file: File? = null
        private set

    /** Lines logged before [init] (or in unit tests), kept so nothing is lost. */
    private val early = ArrayDeque<String>()

    fun init(dir: File) {
        synchronized(lock) {
            if (file != null) return
            file = File(dir, FILE_NAME)
            val f = file!!
            early.forEach { f.appendText(it + "\n") }
            early.clear()
        }
    }

    fun i(tag: String, message: String) = write(tag, message)

    fun e(tag: String, message: String, error: Throwable? = null) =
        write(tag, if (error == null) "ERROR $message" else "ERROR $message: ${describe(error)}")

    /** `IOException: connect timed out` — the class and message, without the stack trace. */
    fun describe(error: Throwable): String = "${error.javaClass.simpleName}: ${error.message}"

    fun stackTrace(error: Throwable): String = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()

    private fun write(tag: String, message: String) {
        val line = "${synchronized(stamp) { stamp.format(Date()) }} [$tag] $message"
        runCatching { android.util.Log.i("CrimsonSteel", "[$tag] $message") }
        synchronized(lock) {
            val f = file
            if (f == null) {
                early.addLast(line)
                while (early.size > 500) early.removeFirst()
                return
            }
            runCatching {
                f.appendText(line + "\n")
                if (f.length() > MAX_BYTES) trim(f)
            }
        }
    }

    private fun trim(f: File) {
        val text = f.readText()
        val keepFrom = text.indexOf('\n', text.length / 2).let { if (it < 0) text.length / 2 else it + 1 }
        f.writeText("(older lines dropped)\n" + text.substring(keepFrom))
    }

    fun read(): String = synchronized(lock) {
        file?.takeIf { it.exists() }?.readText() ?: early.joinToString("\n")
    }

    fun clear() = synchronized(lock) {
        early.clear()
        file?.writeText("")
    }

    /** Log uncaught exceptions (with stack trace) before the app dies, so a crash is in the next shared log. */
    fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            write("crash", "Uncaught exception on ${thread.name}: ${describe(error)}\n${stackTrace(error)}")
            previous?.uncaughtException(thread, error)
        }
    }
}
