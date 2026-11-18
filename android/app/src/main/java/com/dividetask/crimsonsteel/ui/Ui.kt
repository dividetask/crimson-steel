package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.roundToInt

/** Colors and small view builders shared by every screen (the UI is built in code, not XML). */
object Ui {
    const val BG = 0xFF14161A.toInt()
    const val SURFACE = 0xFF22252B.toInt()
    const val SURFACE_HI = 0xFF2E323A.toInt()
    const val CRIMSON = 0xFF9F1D24.toInt()
    const val CRIMSON_DARK = 0xFF5A0E14.toInt()
    const val TEXT = 0xFFE5E7EB.toInt()
    const val TEXT_DIM = 0xFF9CA3AF.toInt()
    const val TEXT_FAINT = 0xFF6B7280.toInt()
    const val GOLD = 0xFFD4A84A.toInt()
    const val AMBER = 0xFFF59E0B.toInt()

    // Die colors match public/style.css (.die.fail / .success / .crit).
    const val DIE_FAIL = 0xFFEF4444.toInt()
    const val DIE_SUCCESS = 0xFF22C55E.toInt()
    const val DIE_CRIT = 0xFF1E3A8A.toInt()
    const val DIE_NEUTRAL = 0xFFF3F4F6.toInt()
    const val DIE_ROLLING = 0xFFD6DCE0.toInt()

    fun dp(ctx: Context, v: Int): Int = (v * ctx.resources.displayMetrics.density).roundToInt()
    fun dpf(ctx: Context, v: Float): Float = v * ctx.resources.displayMetrics.density

    fun text(
        ctx: Context,
        s: CharSequence,
        sizeSp: Float = 15f,
        color: Int = TEXT,
        bold: Boolean = false,
    ): TextView = TextView(ctx).apply {
        text = s
        textSize = sizeSp
        setTextColor(color)
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    fun rounded(color: Int, radiusPx: Float, strokeColor: Int? = null, strokePx: Int = 0) =
        GradientDrawable().apply {
            setColor(color)
            cornerRadius = radiusPx
            if (strokeColor != null) setStroke(strokePx, strokeColor)
        }

    fun vertical(ctx: Context, padDp: Int = 0): LinearLayout = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        val p = dp(ctx, padDp)
        setPadding(p, p, p, p)
    }

    fun horizontal(ctx: Context): LinearLayout = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }

    fun card(ctx: Context): LinearLayout = vertical(ctx, 12).apply {
        background = rounded(SURFACE, dpf(ctx, 10f))
    }

    fun sectionHeader(ctx: Context, s: String): TextView =
        text(ctx, s.uppercase(), 13f, GOLD, bold = true).apply {
            letterSpacing = 0.08f
            setPadding(dp(ctx, 4), dp(ctx, 18), 0, dp(ctx, 6))
        }

    fun matchWidth(topMarginPx: Int = 0) =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            .apply { topMargin = topMarginPx }

    fun weighted(weight: Float = 1f) =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, weight)

    /** A tappable surface with a pressed state. */
    fun makeTappable(v: View, ctx: Context, onTap: () -> Unit) {
        v.isClickable = true
        v.isFocusable = true
        val attrs = intArrayOf(android.R.attr.selectableItemBackground)
        val ta = ctx.obtainStyledAttributes(attrs)
        v.foreground = ta.getDrawable(0)
        ta.recycle()
        v.setOnClickListener { onTap() }
    }

    fun signed(n: Int): String = if (n >= 0) "+$n" else "−${-n}"

    /** The app version, as built (BuildConfig.VERSION_NAME, e.g. "v0.006 a (1a2b)"). */
    val versionName: String
        get() = runCatching { com.dividetask.crimsonsteel.BuildConfig.VERSION_NAME }.getOrDefault("?")

    /**
     * The bar at the top of every screen: [title] on the left, the app version
     * small and grey (so screenshots show which build they came from), and a
     * gear button that opens Settings when [onSettings] is given.
     */
    fun topBar(ctx: Context, title: String, onSettings: (() -> Unit)?): Pair<LinearLayout, TextView> {
        val bar = horizontal(ctx).apply {
            setBackgroundColor(CRIMSON_DARK)
            setPadding(dp(ctx, 16), dp(ctx, 10), dp(ctx, 4), dp(ctx, 10))
        }
        val titleView = text(ctx, title, 24f, TEXT, bold = true).apply {
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        bar.addView(titleView, weighted())
        bar.addView(text(ctx, versionName, 11f, 0xFF9E9E9E.toInt()).apply {
            setPadding(dp(ctx, 8), 0, dp(ctx, 4), 0)
        })
        if (onSettings != null) {
            val gear = text(ctx, "\u2699\uFE0E", 26f, TEXT).apply {
                gravity = Gravity.CENTER
                contentDescription = "Settings"
                setPadding(dp(ctx, 10), 0, dp(ctx, 10), 0)
            }
            makeTappable(gear, ctx, onSettings)
            bar.addView(gear, LinearLayout.LayoutParams(dp(ctx, 48), dp(ctx, 48)))
        }
        return Pair(bar, titleView)
    }
}
