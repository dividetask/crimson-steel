package com.dividetask.crimsonsteel.ui

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import com.dividetask.crimsonsteel.dice.DiceConfig
import com.dividetask.crimsonsteel.dice.DiceRules
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * The dice table: dice thrown right over the screen — no backdrop, no box,
 * bounded only by the screen's edges. They fly in from a side, bounce off the
 * edges and each other, spin and slow down, flicker through faces while they
 * tumble, and stop on their real values.
 *
 * Each Roll of the action (the player's own first) has its own dice colour
 * and its own part of the screen: its dice are thrown into it and gently
 * pulled back if they wander, with no line drawn. Its label and result float
 * just above its dice. Another player's dice are thrown in when their result
 * arrives. Luck rerolls are thrown again after the first throw settles. The
 * dice stay on screen until the player taps.
 */
object RollTable {

    /** One band of the table: a Roll of the action. */
    data class Zone(val key: String, val label: String, val color: Int)

    /**
     * Fallback dice colours, only used when the server sent none: each roller
     * normally has their own colour, the same on every phone
     * (docs/project/dice_colors.md).
     */
    val COLORS = intArrayOf(
        Ui.DICE_DEFAULT,
        0xFFC4B5FD.toInt(), // lavender
        0xFFFDBA74.toInt(), // peach
        0xFFFDE68A.toInt(), // butter
        0xFF99F6E4.toInt(), // aqua
        0xFFF0ABFC.toInt(), // orchid
    )

    fun colorFor(index: Int) = COLORS[index.mod(COLORS.size)]

    /** How long a stopped die stays as it fell before turning upright. */
    private const val UPRIGHT_AFTER_MS = 1000L

    /** How long the first throw rests before its Luck rerolls / nudges happen. */
    private const val REROLL_AFTER_MS = 4000L

    /** Close the dice table if it is open (e.g. to throw an action's dice again from the start). */
    fun clear() {
        table?.let { (it.parent as? ViewGroup)?.removeView(it) }
        table = null
    }

    private var table: TableView? = null

    /**
     * Throw dice for [key] onto the table for [flowId] (opening it, with one
     * band per entry of [zones], if it is not open for that action). [onDone]
     * runs when they — and any Luck rerolls — have stopped.
     */
    fun throwDice(
        activity: Activity, flowId: String, zones: List<Zone>, key: String,
        initial: List<Int>, rerolled: List<Int?>?, final: List<Int>, tn: Int, startingValue: Int,
        title: String? = null, failureModifier: Int = -1, onDone: () -> Unit = {},
    ) {
        val t = table?.takeIf { it.flowId == flowId && it.isAttachedToWindow } ?: open(activity, flowId)
        t.setZones(zones)
        if (title != null) t.title = title
        t.throwInto(key, initial, rerolled, final, tn, startingValue, failureModifier, onDone)
    }

    private fun open(activity: Activity, flowId: String): TableView {
        table?.close()
        val v = TableView(activity, flowId)
        val root = activity.window.decorView as ViewGroup
        root.addView(v, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        table = v
        return v
    }

    private class Die(
        var x: Float, var y: Float, var vx: Float, var vy: Float,
        var angle: Float, var spin: Float,
        var face: Int, var target: Int,
        var travelled: Float = 0f, var moving: Boolean = true,
        /** Shown on the die once it has changed after the first throw: '↻' rerolled, '±' nudged. */
        var mark: Char? = null,
        /** Its value before a Luck reroll: a small die at its top left. */
        var original: Int? = null,
        /** Its value before a nudge: a small die at its top right. */
        var preNudge: Int? = null,
        /** About to be rerolled ('↻') or nudged ('±'): an icon under it while it waits. */
        var pending: Char? = null,
        /** When it last came to rest (0 while moving): a second later it turns upright. */
        var restSince: Long = 0,
    ) {
        val uprightAngle: Float get() = kotlin.math.round(angle / 360f) * 360f
        val upright: Boolean get() = abs(angle - uprightAngle) < 0.5f
    }

    /** A band's throw in progress: its dice and what happens when they stop. */
    private class Throw(
        val zone: Int, val dice: MutableList<Die>, val tn: Int, val startingValue: Int,
        val rerolled: List<Int?>?, val final: List<Int>, val onDone: () -> Unit,
        val failureModifier: Int = -1,
        var phase: Int = 0, var stoppedAt: Long = 0, var done: Boolean = false,
    )

    private class TableView(activity: Activity, val flowId: String) : View(activity) {
        private val density = resources.displayMetrics.density
        private val rnd = Random.Default
        private var zones: List<Zone> = emptyList()
        private val throws = mutableMapOf<String, Throw>()
        private var lastFrame = 0L
        private var running = false
        /** The action, at the top of the screen ("Garroth Vask Attacks Wolf with Great Sword"). */
        var title: String? = null
            set(v) { field = v; invalidate() }

        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeJoin = Paint.Join.ROUND }
        private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textSize = 15f * density
            color = Ui.TEXT
            setShadowLayer(4f * density, 0f, 1f * density, Color.BLACK) // readable over the screen beneath
        }
        private val small = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 13f * density
            color = Ui.TEXT
            setShadowLayer(4f * density, 0f, 1f * density, Color.BLACK)
        }
        private val outline = Path()
        private val face = Path()
        private val edges = Path()

        init {
            isClickable = true
            alpha = 0f
            animate().alpha(1f).setDuration(150).start()
        }

        fun setZones(z: List<Zone>) {
            if (z.map { it.key } != zones.map { it.key }) zones = z
        }

        private fun zoneRect(i: Int): RectF {
            val n = max(1, zones.size)
            val h = height / n.toFloat()
            return RectF(0f, i * h, width.toFloat(), (i + 1) * h)
        }

        /** Room at the top of a strip for its label (and, on the first, the action's title above it). */
        private fun labelSpace(zone: Int): Float = (if (zone == 0 && title != null) 64f else 28f) * density

        private fun dieRadius(): Float {
            val bandH = height / max(1, zones.size).toFloat()
            return min(min(bandH * 0.17f, width / 9f), 44f * density)
        }

        fun throwInto(key: String, initial: List<Int>, rerolled: List<Int?>?, final: List<Int>, tn: Int, sv: Int,
                      fm: Int, onDone: () -> Unit) {
            val zone = zones.indexOfFirst { it.key == key }.coerceAtLeast(0)
            val t = Throw(zone, mutableListOf(), tn, sv, rerolled, final, onDone, fm)
            throws[key] = t
            post {
                t.dice.addAll(initial.map { launch(zone, it) })
                start()
            }
        }

        /** A die flying in from the left or right edge of its band, aimed across it. */
        private fun launch(zone: Int, target: Int): Die {
            val r = zoneRect(zone)
            val rad = dieRadius()
            val fromLeft = rnd.nextBoolean()
            val x = if (fromLeft) r.left + rad else r.right - rad
            val top = r.top + rad + labelSpace(zone)
            val y = top + rnd.nextFloat() * max(0f, r.bottom - rad - top)
            val speed = (1100f + rnd.nextFloat() * 900f) * density
            val dir = (if (fromLeft) 0.0 else Math.PI) + (rnd.nextDouble() - 0.5) * 1.1
            return Die(x, y, (cos(dir) * speed).toFloat(), (sin(dir) * speed).toFloat(),
                rnd.nextFloat() * 360f, (rnd.nextFloat() - 0.5f) * 1400f,
                rnd.nextInt(1, DiceConfig.DIE_SIZE + 1), target)
        }

        private fun start() {
            if (running) return
            running = true
            lastFrame = System.nanoTime()
            postOnAnimation(frame)
        }

        private val frame = object : Runnable {
            override fun run() {
                if (!isAttachedToWindow) { running = false; return }
                val now = System.nanoTime()
                val dt = min((now - lastFrame) / 1e9f, 1f / 30f)
                lastFrame = now
                step(dt)
                invalidate()
                val busy = throws.values.any { t -> !t.done || t.dice.any { !it.upright } }
                if (busy) {
                    postOnAnimation(this)
                } else {
                    running = false
                }
            }
        }

        private fun step(dt: Float) {
            val rad = dieRadius()
            val friction = 1.6f            // velocity decay per second (exponential)
            val drag = 260f * density      // constant rolling resistance, px/s²
            val stopSpeed = 30f * density
            val w = width.toFloat()
            for ((_, t) in throws) {
                if (t.done) continue
                val r = zoneRect(t.zone)
                for (d in t.dice) {
                    if (!d.moving) continue
                    d.x += d.vx * dt
                    d.y += d.vy * dt
                    d.angle += d.spin * dt
                    // Each Roll keeps to its own strip of the screen (no line is
                    // drawn): its dice bounce off the strip's edges, losing some
                    // speed, so several Rolls never mix.
                    val top = r.top + rad + labelSpace(t.zone)
                    if (d.x < rad) { d.x = rad; d.vx = abs(d.vx) * 0.62f; d.spin *= -0.8f }
                    if (d.x > w - rad) { d.x = w - rad; d.vx = -abs(d.vx) * 0.62f; d.spin *= -0.8f }
                    if (d.y < top) { d.y = top; d.vy = abs(d.vy) * 0.62f; d.spin *= -0.8f }
                    if (d.y > r.bottom - rad) { d.y = r.bottom - rad; d.vy = -abs(d.vy) * 0.62f; d.spin *= -0.8f }
                    val speed = hypot(d.vx, d.vy)
                    val decay = max(0f, 1f - friction * dt) * max(0f, 1f - drag * dt / max(speed, 1f))
                    d.vx *= decay; d.vy *= decay; d.spin *= max(0f, 1f - 2.2f * dt)
                    // Tumble: a new face every so often while rolling.
                    d.travelled += speed * dt
                    if (d.travelled > rad * 1.3f) { d.travelled = 0f; d.face = rnd.nextInt(1, DiceConfig.DIE_SIZE + 1) }
                    if (speed < stopSpeed) { d.vx = 0f; d.vy = 0f; d.spin = 0f; d.moving = false; d.face = d.target }
                }
                if (t.dice.isNotEmpty() && t.dice.none { it.moving }) settled(t)
            }
            // Dice from every throw share the screen, so they knock each other too.
            collide(throws.values.flatMap { it.dice }, rad)
            // A second after a die comes to rest it turns upright, so it is easy to read.
            val now = System.currentTimeMillis()
            for (t in throws.values) for (d in t.dice) {
                if (d.moving) { d.restSince = 0; continue }
                if (d.restSince == 0L) { d.restSince = now; continue }
                if (now - d.restSince < UPRIGHT_AFTER_MS || d.upright) continue
                val diff = d.uprightAngle - d.angle
                d.angle = if (abs(diff) < 0.5f) d.uprightAngle else d.angle + diff * min(1f, dt * 5f)
            }
        }

        /** Dice in a band knock each other apart (equal mass, a little energy lost). */
        private fun collide(dice: List<Die>, rad: Float) {
            val minDist = rad * 1.85f
            for (i in dice.indices) for (j in i + 1 until dice.size) {
                val a = dice[i]; val b = dice[j]
                val dx = b.x - a.x; val dy = b.y - a.y
                val dist = hypot(dx, dy)
                if (dist <= 0.01f || dist >= minDist) continue
                val nx = dx / dist; val ny = dy / dist
                val push = (minDist - dist) / 2f
                a.x -= nx * push; a.y -= ny * push; b.x += nx * push; b.y += ny * push
                val rel = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
                if (rel > 0) {
                    val imp = rel * 0.9f
                    a.vx -= imp * nx; a.vy -= imp * ny; b.vx += imp * nx; b.vy += imp * ny
                    if (!a.moving && hypot(a.vx, a.vy) > 0f) a.moving = true
                    if (!b.moving && hypot(b.vx, b.vy) > 0f) b.moving = true
                    a.spin += rel * 0.3f; b.spin -= rel * 0.3f
                }
            }
        }

        /** A throw stopped: throw the Luck rerolls once, then it is done. */
        private fun settled(t: Throw) {
            val now = System.currentTimeMillis()
            if (t.stoppedAt == 0L) { t.stoppedAt = now; return }
            // After the first throw has stopped: the Luck rerolls are thrown
            // again, and a nudged die (its final value differs with no reroll)
            // hops onto its new value. Both are marked.
            val again = t.rerolled.orEmpty().indices.filter { t.rerolled!![it] != null }
            val nudged = t.dice.indices.filter { i ->
                i !in again && i < t.final.size && t.dice[i].target != t.final[i]
            }
            val changes = t.phase == 0 && (again.isNotEmpty() || nudged.isNotEmpty())
            if (!changes && now - t.stoppedAt < 450) return
            if (changes) {
                // Once a die has turned upright, an icon under it says it will be
                // rerolled (or nudged); the change itself waits a few seconds.
                for (i in again + nudged) {
                    val d = t.dice.getOrNull(i) ?: continue
                    if (d.pending == null && d.upright && d.restSince != 0L && now - d.restSince >= UPRIGHT_AFTER_MS)
                        d.pending = if (i in again) '\u21bb' else '\u00b1'
                }
                if (now - t.stoppedAt < REROLL_AFTER_MS) return
            }
            if (changes) {
                t.phase = 1
                t.stoppedAt = 0
                for (i in again + nudged) {
                    val d = t.dice.getOrNull(i) ?: continue
                    val speed = (if (i in again) 900f + rnd.nextFloat() * 600f else 260f) * density
                    val dir = rnd.nextDouble() * Math.PI * 2
                    d.vx = (cos(dir) * speed).toFloat(); d.vy = (sin(dir) * speed).toFloat()
                    d.spin = (rnd.nextFloat() - 0.5f) * (if (i in again) 1200f else 300f)
                    if (i in again) d.original = d.target else d.preNudge = d.target
                    d.target = t.final[i]
                    d.mark = if (i in again) '\u21bb' else '\u00b1'
                    d.pending = null
                    d.moving = true
                }
                return
            }
            t.done = true
            t.onDone()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            // No backdrop and no bands: just the dice, over whatever is on screen.
            val rad = dieRadius()
            for ((key, t) in throws) {
                val color = zones.find { it.key == key }?.color ?: COLORS[0]
                for (d in t.dice) drawDie(canvas, d, rad, color, t.tn, t.done || !d.moving)
            }
            // Each Roll's label — the character's name and the TN (a Damage
            // Rider: its kind) — fixed at the top left of its strip.
            for ((key, t) in throws) {
                val z = zones.find { it.key == key } ?: continue
                label.color = Color.rgb(min(255, Color.red(z.color) + 30), min(255, Color.green(z.color) + 30), min(255, Color.blue(z.color) + 30))
                val r = zoneRect(t.zone)
                canvas.drawText(z.label, 12 * density, r.top + labelSpace(t.zone) - 8 * density, label)
            }
            title?.let {
                label.textAlign = Paint.Align.CENTER
                canvas.drawText(it, width / 2f, 34 * density, label)
                label.textAlign = Paint.Align.LEFT
            }
            if (throws.isNotEmpty() && throws.values.all { it.done }) {
                small.textAlign = Paint.Align.CENTER
                canvas.drawText("Tap anywhere to clear the dice", width / 2f, height - 18 * density, small)
                small.textAlign = Paint.Align.LEFT
            }
        }

        private fun drawDie(canvas: Canvas, d: Die, r: Float, color: Int, tn: Int, still: Boolean) {
            fill.color = 0x66000000
            canvas.drawOval(d.x - r * 0.85f, d.y + r * 0.7f, d.x + r * 0.85f, d.y + r * 1.05f, fill)
            canvas.save()
            canvas.translate(d.x, d.y)
            canvas.rotate(d.angle)
            D10Shape.build(r, outline, face, edges)
            fill.color = shade(color, 0.82f)
            canvas.drawPath(outline, fill)
            fill.color = color
            canvas.drawPath(face, fill)
            stroke.color = 0x44000000; stroke.strokeWidth = r * 0.05f
            canvas.drawPath(edges, stroke)
            canvas.drawPath(face, stroke)
            stroke.color = 0x88000000.toInt(); stroke.strokeWidth = r * 0.06f
            canvas.drawPath(outline, stroke)
            text.textSize = r * 0.72f
            // A stopped die's number shows what it counts for (Success green,
            // Critical deep blue, a 1 red, no effect grey); dark grey while rolling.
            text.color = if (still) Ui.numberColor(d.face, tn) else Ui.NUM_NEUTRAL
            val ty = r * 0.05f - (text.descent() + text.ascent()) / 2f
            canvas.drawText(d.face.toString(), 0f, ty, text)
            canvas.restore()
            // Its earlier values as much smaller dice (upright): before a reroll
            // at its top left, before a nudge at its top right.
            d.original?.let { miniDie(canvas, it, d.x - r * 0.95f, d.y - r * 0.85f, r * 0.42f, color, tn) }
            d.preNudge?.let { miniDie(canvas, it, d.x + r * 0.95f, d.y - r * 0.85f, r * 0.42f, color, tn) }
            // About to change: an icon under it.
            d.pending?.let { badge(canvas, it, d.x, d.y + r * 1.3f, r * 0.34f) }
            // …and once changed, a small gold badge at its bottom right.
            d.mark?.let { badge(canvas, it, d.x + r * 0.8f, d.y + r * 0.8f, r * 0.34f) }
        }

        private fun badge(canvas: Canvas, m: Char, bx: Float, by: Float, br: Float) {
            fill.color = Ui.GOLD
            canvas.drawCircle(bx, by, br, fill)
            stroke.color = 0xCC000000.toInt(); stroke.strokeWidth = br * 0.15f
            canvas.drawCircle(bx, by, br, stroke)
            text.textSize = br * 1.3f
            text.color = Color.BLACK
            canvas.drawText(m.toString(), bx, by - (text.descent() + text.ascent()) / 2f, text)
        }

        private fun miniDie(canvas: Canvas, v: Int, x: Float, y: Float, mr: Float, color: Int, tn: Int) {
            canvas.save()
            canvas.translate(x, y)
            D10Shape.build(mr, outline, face, edges)
            fill.color = shade(color, 0.9f)
            canvas.drawPath(outline, fill)
            stroke.color = 0x99000000.toInt(); stroke.strokeWidth = mr * 0.08f
            canvas.drawPath(outline, stroke)
            text.textSize = mr * 0.8f
            text.color = Ui.numberColor(v, tn)
            canvas.drawText(v.toString(), 0f, mr * 0.05f - (text.descent() + text.ascent()) / 2f, text)
            canvas.restore()
        }

        private fun shade(c: Int, f: Float) =
            Color.rgb((Color.red(c) * f).toInt(), (Color.green(c) * f).toInt(), (Color.blue(c) * f).toInt())

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (event.action == MotionEvent.ACTION_UP && throws.values.all { it.done }) close()
            return true
        }

        fun close() {
            if (table === this) table = null
            animate().alpha(0f).setDuration(200).withEndAction { (parent as? ViewGroup)?.removeView(this) }.start()
        }

    }
}
