package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import com.dividetask.crimsonsteel.data.Initiative
import com.dividetask.crimsonsteel.data.Note
import com.dividetask.crimsonsteel.data.Scene

/** Turn order for the current Combat. Highlights whose turn it is and which entry is you. */
object InitiativeScreen {
    fun build(ctx: Context, init: Initiative): View {
        val col = Ui.vertical(ctx, 12)
        col.addView(Ui.text(ctx, "Round ${init.round}", 20f, Ui.TEXT, bold = true))
        col.addView(Ui.text(ctx, "Current turn: ${init.order[init.currentIndex].name}", 14f, Ui.TEXT_DIM))

        init.order.forEachIndexed { i, e ->
            val current = i == init.currentIndex
            val card = Ui.horizontal(ctx).apply {
                setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 12), Ui.dp(ctx, 12), Ui.dp(ctx, 12))
                background = Ui.rounded(
                    if (current) Ui.CRIMSON_DARK else Ui.SURFACE, Ui.dpf(ctx, 10f),
                    if (current) Ui.CRIMSON else null, Ui.dp(ctx, 2),
                )
            }
            card.addView(
                Ui.text(ctx, "${i + 1}", 18f, Ui.TEXT_DIM, bold = true),
                LinearLayout.LayoutParams(Ui.dp(ctx, 32), LinearLayout.LayoutParams.WRAP_CONTENT),
            )
            val names = Ui.vertical(ctx)
            names.addView(Ui.text(ctx, e.name + if (e.isYou) "  (you)" else "", 16f, Ui.TEXT, bold = current || e.isYou))
            names.addView(Ui.text(ctx, if (e.isPlayerCharacter) "Player character" else "Enemy", 12f,
                if (e.isPlayerCharacter) Ui.TEXT_DIM else Ui.DIE_FAIL))
            card.addView(names, Ui.weighted())
            card.addView(Ui.text(ctx, e.diceResult, 14f, Ui.TEXT_DIM).apply {
                typeface = android.graphics.Typeface.MONOSPACE
                gravity = Gravity.END
            })
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        col.addView(Ui.text(ctx, "The right-hand column is each combatant's initiative dice, highest first (X = 10).",
            12f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 12)))
        return ScrollView(ctx).apply { addView(col) }
    }
}

/** Game notes, newest last. Tap a note to expand it. */
object NotesScreen {
    fun build(ctx: Context, notes: List<Note>): View {
        val col = Ui.vertical(ctx, 12)
        for (n in notes) {
            val card = Ui.card(ctx)
            card.addView(Ui.text(ctx, n.title, 16f, Ui.TEXT, bold = true))
            card.addView(Ui.text(ctx, n.date, 12f, Ui.GOLD))
            val body = Ui.text(ctx, n.body, 14f, Ui.TEXT_DIM).apply {
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(0, Ui.dp(ctx, 6), 0, 0)
            }
            card.addView(body)
            Ui.makeTappable(card, ctx) {
                val collapsed = body.maxLines == 2
                body.maxLines = if (collapsed) Int.MAX_VALUE else 2
            }
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        return ScrollView(ctx).apply { addView(col) }
    }
}

/** What the party is looking at right now. */
object SceneScreen {
    fun build(ctx: Context, s: Scene): View {
        val col = Ui.vertical(ctx, 12)
        col.addView(Ui.text(ctx, s.title, 22f, Ui.TEXT, bold = true))
        col.addView(Ui.text(ctx, s.location, 14f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 4)))
        col.addView(Ui.text(ctx, s.time, 13f, Ui.GOLD), Ui.matchWidth(Ui.dp(ctx, 2)))

        val desc = Ui.card(ctx)
        desc.addView(Ui.text(ctx, s.description, 15f, Ui.TEXT).apply { setLineSpacing(0f, 1.2f) })
        col.addView(desc, Ui.matchWidth(Ui.dp(ctx, 14)))

        col.addView(Ui.sectionHeader(ctx, "Present"))
        val present = Ui.card(ctx)
        for (p in s.present) present.addView(Ui.text(ctx, "• $p", 15f, Ui.TEXT), Ui.matchWidth(Ui.dp(ctx, 2)))
        col.addView(present, Ui.matchWidth())
        return ScrollView(ctx).apply { addView(col) }
    }
}
