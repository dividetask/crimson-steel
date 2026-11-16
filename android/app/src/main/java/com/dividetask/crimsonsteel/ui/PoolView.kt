package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * One small d10 per Combat Pool die. Remaining dice are filled with a color
 * that depends on how much of the pool is left; spent dice are hollow.
 */
class PoolView(context: Context) : View(context) {

    var max: Int = 0
        set(v) { field = v; requestLayout(); invalidate() }
    var remaining: Int = 0
        set(v) { field = v; invalidate() }

    private val cellPx = Ui.dpf(context, 26f)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeWidth = Ui.dpf(context, 1.2f)
    }
    private val outline = Path()
    private val face = Path()
    private val edges = Path()

    private fun perRow(width: Int) = max(1, (width / cellPx).toInt())

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val rows = max(1, ceil(max / perRow(w).toFloat()).toInt())
        setMeasuredDimension(w, resolveSize((rows * cellPx).toInt(), heightMeasureSpec))
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (max <= 0) return
        val color = colorFor(remaining, max)
        val per = min(perRow(width), max)
        val r = cellPx * 0.42f
        D10Shape.build(r, outline, face, edges)
        for (i in 0 until max) {
            val row = i / per
            val col = i % per
            val cx = cellPx * (col + 0.5f)
            val cy = cellPx * (row + 0.5f)
            canvas.save()
            canvas.translate(cx, cy)
            if (i < remaining) {
                fill.color = shade(color, 0.75f)
                canvas.drawPath(outline, fill)
                fill.color = color
                canvas.drawPath(face, fill)
                stroke.color = 0x88000000.toInt()
                canvas.drawPath(edges, stroke)
                canvas.drawPath(face, stroke)
                canvas.drawPath(outline, stroke)
            } else {
                stroke.color = Ui.TEXT_FAINT
                canvas.drawPath(outline, stroke)
            }
            canvas.restore()
        }
    }

    private fun shade(c: Int, f: Float) =
        Color.rgb((Color.red(c) * f).toInt(), (Color.green(c) * f).toInt(), (Color.blue(c) * f).toInt())

    companion object {
        /** More than half left: green. A quarter to a half: amber. Under a quarter: red. */
        fun colorFor(remaining: Int, max: Int): Int {
            if (max <= 0 || remaining <= 0) return Ui.TEXT_FAINT
            val frac = remaining.toFloat() / max
            return when {
                frac > 0.5f -> Ui.DIE_SUCCESS
                frac >= 0.25f -> Ui.AMBER
                else -> Ui.DIE_FAIL
            }
        }
    }
}
