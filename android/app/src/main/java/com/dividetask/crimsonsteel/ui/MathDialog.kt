package com.dividetask.crimsonsteel.ui

import android.app.Dialog
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import com.dividetask.crimsonsteel.data.MathTable
import com.dividetask.crimsonsteel.data.StatMath

/** The math behind a number on the sheet ("?" on the Sheet tab), as the server wrote it. */
object MathDialog {

    fun show(ctx: Context, math: StatMath) {
        val dialog = Dialog(ctx, android.R.style.Theme_DeviceDefault_Dialog_NoActionBar)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val root = Ui.vertical(ctx, 18).apply {
            background = Ui.rounded(Ui.BG, Ui.dpf(ctx, 14f), Ui.SURFACE_HI, Ui.dp(ctx, 1))
        }
        root.addView(Ui.text(ctx, math.title, 20f, Ui.GOLD, bold = true))
        for (line in math.lines) root.addView(Ui.text(ctx, line, 15f, Ui.TEXT), Ui.matchWidth(Ui.dp(ctx, 8)))
        math.table?.let { root.addView(table(ctx, it), Ui.matchWidth(Ui.dp(ctx, 12))) }
        math.note?.let { root.addView(Ui.text(ctx, it, 13f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 10))) }

        val close = Button(ctx).apply {
            text = "Close"
            setOnClickListener { dialog.dismiss() }
        }
        root.addView(close, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply {
            gravity = Gravity.END
            topMargin = Ui.dp(ctx, 14)
        })

        // A long one (many Skill modifiers, a tall price table) scrolls inside the dialog.
        dialog.setContentView(ScrollView(ctx).apply { addView(root) })
        dialog.setCanceledOnTouchOutside(true)
        // Narrow enough to read on a tablet: the lines are short.
        val width = minOf((ctx.resources.displayMetrics.widthPixels * 0.94f).toInt(), Ui.dp(ctx, 480))
        dialog.window?.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.show()
    }

    /** First column left and wide, the rest right-aligned numbers; head faint, foot bold. */
    private fun table(ctx: Context, t: MathTable): View {
        val col = Ui.vertical(ctx)
        fun row(cells: List<String>, color: Int, bold: Boolean) {
            val r = Ui.horizontal(ctx).apply { setPadding(0, Ui.dp(ctx, 3), 0, Ui.dp(ctx, 3)) }
            cells.forEachIndexed { i, cell ->
                val tv = Ui.text(ctx, cell, 14f, color, bold)
                if (i == 0) {
                    r.addView(tv, Ui.weighted())
                } else {
                    tv.gravity = Gravity.END
                    r.addView(tv, LinearLayout.LayoutParams(Ui.dp(ctx, 56), ViewGroup.LayoutParams.WRAP_CONTENT))
                }
            }
            col.addView(r, Ui.matchWidth())
        }
        if (t.head.isNotEmpty()) row(t.head, Ui.TEXT_FAINT, false)
        t.rows.forEach { row(it, Ui.TEXT, false) }
        if (t.foot.isNotEmpty()) row(t.foot, Ui.TEXT, true)
        return col
    }
}
