package com.dividetask.crimsonsteel.ui

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.view.View
import android.view.animation.LinearInterpolator
import com.dividetask.crimsonsteel.dice.DiceConfig
import com.dividetask.crimsonsteel.dice.DiceRules
import com.dividetask.crimsonsteel.dice.DieState
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Draws a set of d10s and animates them tumbling onto the table before
 * settling on their final values. Every die is the roller's own soft colour
 * ([bodyColor]); once settled, its number shows what it counts for (Success
 * dark green, Critical deep blue, a 1 dark red, no effect dark grey).
 */
class DiceView(context: Context) : View(context) {

    private class Die(
        val finalValue: Int,
        val delay: Float,      // fraction of total animation before this die starts
        val startX: Float,     // start position, relative to the view (0..1)
        val startY: Float,
        val spin: Float,       // total degrees turned while rolling
        val restAngle: Float,  // small tilt once settled
        var face: Int,
        var lastFaceSwap: Float = -1f,
        /** Stays where it is while the others roll (a die Luck did not reroll). */
        val still: Boolean = false,
        /** '↻' rerolled, '±' nudged: a small badge on the die. */
        val mark: Char? = null,
        /** Placed by [showLayered] (kept for a layered layout): its column, row, and how many dice share its row band. */
        val col: Int = -1, val row: Int = -1, val bandSize: Int = 0,
        /** Drawn in this colour instead (yellow: a die that was replaced by a reroll or nudge). */
        val tint: Int? = null,
        /** Its value before a Luck reroll (a small die at its top left) and before a nudge (top right). */
        val original: Int? = null, val preNudge: Int? = null,
    )

    private var dice: List<Die> = emptyList()
    private var tn: Int = DiceConfig.BASE_TN
    private var progress = 1f
    private var animator: ValueAnimator? = null
    private val random = Random.Default

    /** The roller's dice colour (docs/project/dice_colors.md), for dice being rolled. */
    var bodyColor: Int = Ui.DICE_DEFAULT
        set(v) { field = v; invalidate() }

    /**
     * Dice shown as a result (under an action): each settled die coloured by
     * what it counts for — Success green, Critical blue, a 1 red, no effect
     * grey — instead of the roller's colour, for easier reading.
     */
    var colorByResult = false
        set(v) { field = v; invalidate() }

    /** 0 → 1 a second after the dice settle: their tilt eases away, so they read upright. */
    private var upright = 0f
    private var uprightAnim: ValueAnimator? = null

    /** Dice per row; the dice are sized to fit. */
    var perRow = 5
    private val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        color = 0x66000000
    }
    private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        color = 0xAA000000.toInt()
    }
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x55000000 }
    private val numberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val markPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    /** The die being drawn's tint, if any (yellow: replaced). */
    private var tintNow: Int? = null
    private val outline = Path()
    private val face = Path()
    private val edges = Path()

    var onSettled: (() -> Unit)? = null

    /** Total animation time in ms. */
    var durationMs = 1600L

    /** Unrolled dice: [count] blank d10s, waiting to be rolled. */
    fun showBlank(count: Int) {
        animator?.cancel()
        dice = List(count) { Die(0, 0f, 0f, 0f, 0f, 0f, 0, still = true) }
        progress = 1f
        requestLayout()
        invalidate()
    }

    /**
     * Dice already rolled, shown settled (no animation). [marks]: per die,
     * '↻' for a Luck reroll or '±' for a nudge.
     */
    fun show(values: List<Int>, tn: Int, marks: List<Char?> = emptyList()) {
        animator?.cancel()
        this.tn = tn
        dice = values.mapIndexed { i, v -> Die(v, 0f, 0f, 0f, 0f, 0f, v, still = true, mark = marks.getOrNull(i)) }
        progress = 1f
        requestLayout()
        invalidate()
    }

    /**
     * A roll as it happened, under an action, in one row: each die shows its
     * final value; a die a Luck reroll changed has a small die at its top
     * left with the value it was first thrown at, and a nudged die a small
     * die at its top right with the value before the nudge — the same small
     * dice as on the dice table.
     */
    fun showHistory(initial: List<Int>, rerolled: List<Int?>?, final: List<Int>, tn: Int) {
        animator?.cancel()
        this.tn = tn
        dice = final.mapIndexed { i, v ->
            val re = rerolled?.getOrNull(i)
            val beforeNudge = re ?: initial.getOrNull(i)
            Die(v, 0f, 0f, 0f, 0f, 0f, v, still = true,
                original = if (re != null) initial.getOrNull(i) else null,
                preNudge = if (beforeNudge != null && beforeNudge != v) beforeNudge else null)
        }
        progress = 1f
        requestLayout()
        invalidate()
    }

    /**
     * Start rolling [values] (already decided by the Roller) against [tn].
     * With [only], just those positions tumble (Luck rerolls); the rest stay put.
     */
    fun roll(values: List<Int>, tn: Int, only: Set<Int>? = null) {
        this.tn = tn
        animator?.cancel()
        dice = values.mapIndexed { i, v ->
            if (only != null && i !in only) return@mapIndexed Die(v, 0f, 0f, 0f, 0f, 0f, v, still = true)
            Die(
                finalValue = v,
                delay = i * 0.04f,
                startX = random.nextFloat() * 0.3f - 0.15f + if (random.nextBoolean()) -0.1f else 1.1f,
                startY = -0.3f - random.nextFloat() * 0.5f,
                spin = (540 + random.nextInt(540)) * if (random.nextBoolean()) 1f else -1f,
                restAngle = random.nextFloat() * 16f - 8f,
                face = random.nextInt(1, DiceConfig.DIE_SIZE + 1),
            )
        }
        requestLayout()
        progress = 0f
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            interpolator = LinearInterpolator()
            addUpdateListener {
                progress = it.animatedValue as Float
                invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    progress = 1f
                    invalidate()
                    // A second after they settle, the dice turn upright.
                    upright = 0f
                    postDelayed({
                        uprightAnim?.cancel()
                        uprightAnim = ValueAnimator.ofFloat(0f, 1f).apply {
                            duration = 450
                            addUpdateListener { upright = it.animatedValue as Float; invalidate() }
                            start()
                        }
                    }, 1000)
                    onSettled?.invoke()
                }
            })
            start()
        }
    }

    override fun onDetachedFromWindow() {
        animator?.cancel()
        uprightAnim?.cancel()
        super.onDetachedFromWindow()
    }

    private fun rows() = if (dice.any { it.row >= 0 }) dice.maxOf { it.row } + 1
        else maxOf(1, ceil(dice.size / perRow.toFloat()).toInt())

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val cell = w / perRow.toFloat()
        val h = (rows() * cell * 1.1f + cell * 0.3f).toInt()
        setMeasuredDimension(w, resolveSize(h, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (dice.isEmpty()) return
        val w = width.toFloat()
        val cell = w / perRow
        val size = cell * 0.42f        // die "radius"
        edgePaint.strokeWidth = size * 0.05f
        outlinePaint.strokeWidth = size * 0.06f
        numberPaint.textSize = size * 0.72f

        dice.forEachIndexed { i, d ->
            val placed = d.row >= 0
            val row = if (placed) d.row else i / perRow
            val inRow = if (placed) d.bandSize else if (row == rows() - 1) dice.size - row * perRow else perRow
            val col = if (placed) d.col else i % perRow
            // Center each row, including a short last row.
            val restX = (w - inRow * cell) / 2f + cell * (col + 0.5f)
            val restY = cell * 0.65f + row * cell * 1.1f

            val local = if (d.still) 1f else ((progress - d.delay) / (1f - d.delay)).coerceIn(0f, 1f)
            val settled = local >= 1f
            val ease = 1f - (1f - local) * (1f - local) * (1f - local)   // ease-out cubic

            // Travel from off-screen toward the resting spot, with a decaying bounce.
            val x = if (d.still) restX else d.startX * w + (restX - d.startX * w) * ease
            val baseY = if (d.still) restY else d.startY * height + (restY - d.startY * height) * ease
            val bounce = abs(sin(local * PI * 3).toFloat()) * exp(-4f * local) * cell * 0.6f
            val y = baseY - bounce
            val angle = d.restAngle * (if (settled) 1f - upright else 1f) + d.spin * (1f - ease)
            val scale = 1f + 0.25f * (1f - ease)

            // Flicker through random faces while tumbling, slowing as it settles.
            if (!settled) {
                val swapEvery = 0.04f + 0.12f * local
                if (local - d.lastFaceSwap > swapEvery) {
                    d.face = random.nextInt(1, DiceConfig.DIE_SIZE + 1)
                    d.lastFaceSwap = local
                }
            }
            val value = if (settled) d.finalValue else d.face
            tintNow = d.tint
            drawDie(canvas, x, y, size * scale, angle, value, settled, lift = bounce / cell)
            if (settled) {
                d.original?.let { miniDie(canvas, it, x - size * 0.95f, y - size * 0.85f, size * 0.42f) }
                d.preNudge?.let { miniDie(canvas, it, x + size * 0.95f, y - size * 0.85f, size * 0.42f) }
            }
            if (settled) d.mark?.let { m ->
                val br = size * 0.34f
                val bx = x + size * 0.78f; val by = y - size * 0.78f
                markPaint.color = Ui.GOLD
                canvas.drawCircle(bx, by, br, markPaint)
                numberPaint.color = Color.BLACK
                val ts = numberPaint.textSize
                numberPaint.textSize = br * 1.3f
                canvas.drawText(m.toString(), bx, by - (numberPaint.descent() + numberPaint.ascent()) / 2f, numberPaint)
                numberPaint.textSize = ts
            }
        }
    }

    private fun drawDie(
        canvas: Canvas, cx: Float, cy: Float, r: Float, angle: Float,
        value: Int, settled: Boolean, lift: Float,
    ) {
        // Shadow under the die, smaller when it is in the air.
        val shadowScale = 1f - min(0.5f, lift)
        canvas.drawOval(
            cx - r * 0.8f * shadowScale, cy + r * 0.85f,
            cx + r * 0.8f * shadowScale, cy + r * 1.05f, shadowPaint,
        )

        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(angle)

        D10Shape.build(r, outline, face, edges)

        val blank = value == 0
        val base = tintNow ?: if (colorByResult && settled && !blank) resultColor(value) else bodyColor
        bodyPaint.color = shade(base, 0.82f)
        canvas.drawPath(outline, bodyPaint)
        bodyPaint.color = base
        canvas.drawPath(face, bodyPaint)
        canvas.drawPath(edges, edgePaint)
        canvas.drawPath(face, edgePaint)
        canvas.drawPath(outline, outlinePaint)

        if (blank) {
            canvas.restore()
            return
        }
        numberPaint.color = if (settled) Ui.numberColor(value, tn) else Ui.NUM_NEUTRAL
        val label = if (value == DiceConfig.DIE_SIZE) "10" else value.toString()
        val textY = r * 0.05f - (numberPaint.descent() + numberPaint.ascent()) / 2f
        if (label.length > 1) numberPaint.textScaleX = 0.8f else numberPaint.textScaleX = 1f
        canvas.drawText(label, 0f, textY, numberPaint)
        // Underline 6 and 9 so they can be told apart while spinning.
        if (value == 6 || value == 9) {
            val u = r * 0.18f
            canvas.drawRect(-u, textY + r * 0.06f, u, textY + r * 0.1f, numberPaint)
        }
        canvas.restore()
    }

    /** A small upright die showing an earlier value (before a reroll or a nudge). */
    private fun miniDie(canvas: Canvas, v: Int, cx: Float, cy: Float, r: Float) {
        canvas.save()
        canvas.translate(cx, cy)
        D10Shape.build(r, outline, face, edges)
        bodyPaint.color = if (colorByResult) resultColor(v) else bodyColor
        canvas.drawPath(outline, bodyPaint)
        val sw = outlinePaint.strokeWidth
        outlinePaint.strokeWidth = r * 0.08f
        canvas.drawPath(outline, outlinePaint)
        outlinePaint.strokeWidth = sw
        val ts = numberPaint.textSize
        numberPaint.textSize = r * 0.8f
        numberPaint.textScaleX = if (v >= 10) 0.8f else 1f
        numberPaint.color = Ui.numberColor(v, tn)
        canvas.drawText(v.toString(), 0f, r * 0.05f - (numberPaint.descent() + numberPaint.ascent()) / 2f, numberPaint)
        numberPaint.textSize = ts
        canvas.restore()
    }

    /** Soft result colours for dice shown under an action (the number keeps its own colour). */
    private fun resultColor(value: Int): Int = when (DiceRules.dieState(value, tn)) {
        DieState.SUCCESS -> 0xFF86EFAC.toInt()
        DieState.CRITICAL -> 0xFF93C5FD.toInt()
        DieState.FAILURE -> 0xFFFCA5A5.toInt()
        DieState.NEUTRAL -> 0xFFE5E7EB.toInt()
    }

    private fun shade(color: Int, f: Float): Int = Color.rgb(
        (Color.red(color) * f).toInt(), (Color.green(color) * f).toInt(), (Color.blue(color) * f).toInt(),
    )
}

/** d10 geometry shared by the rolling dice and the Combat Pool row. Centered on (0, 0), radius [r]. */
object D10Shape {
    fun build(r: Float, outline: Path, face: Path, edges: Path) {
        // Silhouette (pentagonal trapezohedron seen from above a vertex).
        outline.reset()
        outline.moveTo(0f, -r)
        outline.lineTo(r * 0.97f, -r * 0.2f)
        outline.lineTo(r * 0.62f, r * 0.72f)
        outline.lineTo(0f, r)
        outline.lineTo(-r * 0.62f, r * 0.72f)
        outline.lineTo(-r * 0.97f, -r * 0.2f)
        outline.close()

        // Front kite face, where the number sits.
        face.reset()
        face.moveTo(0f, -r)
        face.lineTo(r * 0.55f, r * 0.22f)
        face.lineTo(0f, r * 0.52f)
        face.lineTo(-r * 0.55f, r * 0.22f)
        face.close()

        edges.reset()
        edges.moveTo(r * 0.55f, r * 0.22f); edges.lineTo(r * 0.97f, -r * 0.2f)
        edges.moveTo(-r * 0.55f, r * 0.22f); edges.lineTo(-r * 0.97f, -r * 0.2f)
        edges.moveTo(0f, r * 0.52f); edges.lineTo(0f, r)
    }
}
