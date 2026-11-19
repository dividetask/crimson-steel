package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import android.view.View

/**
 * One small d10 in the dice-count picker. A chip is either a plain die (the
 * dice every count includes — the action's minimum minus one) or a button
 * carrying its count. [lit] dice are part of the current selection.
 */
class DieChip(context: Context, private val number: Int?, private val speed: Boolean = false) : View(context) {

    var lit = false
        set(v) { field = v; invalidate() }
    var available = true
        set(v) { field = v; invalidate() }

    private var flashing = false

    /** Briefly red: this die cannot be picked (below the minimum, the Speed, or unaffordable). */
    fun flash() {
        flashing = true
        invalidate()
        removeCallbacks(endFlash)
        postDelayed(endFlash, 350)
    }
    private val endFlash = Runnable { flashing = false; invalidate() }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeWidth = Ui.dpf(context, 1.4f)
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val outline = Path()
    private val face = Path()
    private val edges = Path()

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = (w * 1.05f).toInt()
        setMeasuredDimension(w, resolveSize(h, heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val r = minOf(width, height) * 0.46f
        D10Shape.build(r, outline, face, edges)
        canvas.save()
        canvas.translate(width / 2f, height / 2f)
        val base = when {
            flashing -> Ui.DIE_FAIL
            !available -> Ui.SURFACE
            // A die the weapon's Speed costs: amber, marked "S".
            speed && lit -> 0xFF8A5A00.toInt()
            lit -> Ui.CRIMSON
            number != null -> Ui.SURFACE_HI
            else -> Ui.SURFACE_HI
        }
        fill.color = base
        canvas.drawPath(outline, fill)
        stroke.color = when {
            lit -> Ui.GOLD
            available -> if (number != null) Ui.TEXT_DIM else Ui.TEXT_FAINT
            else -> Ui.SURFACE_HI
        }
        canvas.drawPath(edges, stroke)
        canvas.drawPath(face, stroke)
        canvas.drawPath(outline, stroke)
        if (speed) {
            text.textSize = r * 0.62f
            text.color = if (lit) Ui.TEXT else Ui.TEXT_FAINT
            val y = r * 0.05f - (text.descent() + text.ascent()) / 2f
            canvas.drawText("S", 0f, y, text)
        }
        if (number != null) {
            text.textSize = r * 0.8f
            text.color = if (available) Ui.TEXT else Ui.TEXT_FAINT
            val y = r * 0.05f - (text.descent() + text.ascent()) / 2f
            canvas.drawText(number.toString(), 0f, y, text)
        }
        canvas.restore()
    }
}
