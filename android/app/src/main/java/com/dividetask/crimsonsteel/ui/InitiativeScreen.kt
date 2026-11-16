package com.dividetask.crimsonsteel.ui

import android.app.AlertDialog
import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import com.dividetask.crimsonsteel.data.ActionKind
import com.dividetask.crimsonsteel.data.ActionMenu
import com.dividetask.crimsonsteel.data.ActionOption
import com.dividetask.crimsonsteel.data.Character
import com.dividetask.crimsonsteel.data.TurnState
import com.dividetask.crimsonsteel.dice.ActionCategory

/**
 * Combat screen. Top to bottom:
 *  - the Combat Pool as a row of dice (colored by how much is left),
 *  - the initiative order (compacts to a single "your turn" row on your turn; tap to expand),
 *  - on your turn, your action options grouped by Main / Bonus / Free Action.
 *
 * Picking an action and its dice *declares* it: the pool, Main Actions and mana
 * are spent locally. The DM resolves the action (rolls, targets, defenses).
 */
class InitiativeScreen(private val ctx: Context, private val c: Character, private val turn: TurnState) {

    private val scroll = ScrollView(ctx)
    private val options: List<ActionOption> = ActionMenu.options(c)
    private var selected: ActionOption? = null
    private var selectedDice: Int? = null

    val view: View get() = scroll

    init { render() }

    private fun render() {
        val keepY = scroll.scrollY
        val col = Ui.vertical(ctx, 12)
        col.addView(poolCard(), Ui.matchWidth())
        col.addView(Ui.sectionHeader(ctx, "Initiative — Round ${turn.round}"))
        if (turn.isMyTurn && !turn.initiativeExpanded) {
            col.addView(compactTurnRow(), Ui.matchWidth())
        } else {
            fullOrder(col)
        }
        if (turn.isMyTurn) {
            actionMenu(col)
        } else {
            col.addView(Ui.text(ctx, "Waiting for ${turn.order[turn.currentIndex].name}.", 14f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 14)))
            col.addView(Button(ctx).apply {
                text = "Offline test: start my turn"
                setOnClickListener { turn.startMyTurn(); clearSelection(); render() }
            }, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        scroll.removeAllViews()
        scroll.addView(col)
        scroll.post { scroll.scrollTo(0, keepY) }
    }

    // --- Combat Pool ------------------------------------------------------------

    private fun poolCard(): View {
        val card = Ui.card(ctx)
        val top = Ui.horizontal(ctx)
        top.addView(Ui.text(ctx, "Combat Pool", 14f, Ui.TEXT_DIM), Ui.weighted())
        top.addView(Ui.text(ctx, "${turn.poolRemaining} / ${turn.poolMax}", 18f,
            PoolView.colorFor(turn.poolRemaining, turn.poolMax).takeIf { turn.poolRemaining > 0 } ?: Ui.TEXT_DIM,
            bold = true))
        card.addView(top, Ui.matchWidth())
        card.addView(PoolView(ctx).apply { max = turn.poolMax; remaining = turn.poolRemaining }, Ui.matchWidth(Ui.dp(ctx, 6)))
        val main = if (turn.isMyTurn) "${turn.mainActionsLeft} / 2" else "—"
        card.addView(Ui.text(ctx, "Main Actions $main  ·  Mana ${turn.mana} / ${c.vitals.manaMax}", 13f, Ui.TEXT_DIM),
            Ui.matchWidth(Ui.dp(ctx, 6)))
        return card
    }

    // --- Initiative order ---------------------------------------------------------

    private fun compactTurnRow(): View {
        val me = turn.order[turn.currentIndex]
        val row = Ui.horizontal(ctx).apply {
            setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 12), Ui.dp(ctx, 12), Ui.dp(ctx, 12))
            background = Ui.rounded(Ui.CRIMSON_DARK, Ui.dpf(ctx, 10f), Ui.CRIMSON, Ui.dp(ctx, 2))
        }
        row.addView(Ui.text(ctx, "${me.name} (you)", 16f, Ui.TEXT, bold = true), Ui.weighted())
        row.addView(Ui.text(ctx, "Your turn  ▾", 14f, Ui.GOLD, bold = true))
        Ui.makeTappable(row, ctx) { turn.initiativeExpanded = true; render() }
        return row
    }

    private fun fullOrder(col: LinearLayout) {
        if (turn.isMyTurn) {
            val collapse = Ui.text(ctx, "Hide initiative  ▴", 13f, Ui.GOLD, bold = true).apply {
                setPadding(Ui.dp(ctx, 4), Ui.dp(ctx, 4), Ui.dp(ctx, 4), Ui.dp(ctx, 8))
            }
            Ui.makeTappable(collapse, ctx) { turn.initiativeExpanded = false; render() }
            col.addView(collapse)
        }
        turn.order.forEachIndexed { i, e ->
            val current = i == turn.currentIndex
            val card = Ui.horizontal(ctx).apply {
                setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 10), Ui.dp(ctx, 12), Ui.dp(ctx, 10))
                background = Ui.rounded(
                    if (current) Ui.CRIMSON_DARK else Ui.SURFACE, Ui.dpf(ctx, 10f),
                    if (current) Ui.CRIMSON else null, Ui.dp(ctx, 2),
                )
            }
            card.addView(Ui.text(ctx, "${i + 1}", 16f, Ui.TEXT_DIM, bold = true),
                LinearLayout.LayoutParams(Ui.dp(ctx, 28), LinearLayout.LayoutParams.WRAP_CONTENT))
            val names = Ui.vertical(ctx)
            names.addView(Ui.text(ctx, e.name + if (e.isYou) "  (you)" else "", 15f, Ui.TEXT, bold = current || e.isYou))
            names.addView(Ui.text(ctx, if (e.isPlayerCharacter) "Player character" else "Enemy", 12f,
                if (e.isPlayerCharacter) Ui.TEXT_DIM else Ui.DIE_FAIL))
            card.addView(names, Ui.weighted())
            if (current) card.addView(Ui.text(ctx, "Turn", 13f, Ui.GOLD, bold = true))
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    // --- Action menu ----------------------------------------------------------------

    private fun actionMenu(col: LinearLayout) {
        if (turn.declared.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Declared this turn"))
            val card = Ui.card(ctx)
            for (d in turn.declared) card.addView(Ui.text(ctx, "• ${d.summary}", 14f, Ui.TEXT), Ui.matchWidth(Ui.dp(ctx, 2)))
            card.addView(Ui.text(ctx, "Offline — not sent to the DM yet.", 12f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 6)))
            card.addView(Button(ctx).apply {
                text = "Undo last"
                setOnClickListener { turn.undoLast(); clearSelection(); render() }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.END
            })
            col.addView(card, Ui.matchWidth())
        }

        for (category in ActionCategory.entries) {
            val inCategory = options.filter { it.category == category }
            if (inCategory.isEmpty()) continue     // empty categories are skipped, as on the web
            col.addView(Ui.sectionHeader(ctx, category.label))
            for (opt in inCategory) col.addView(optionCard(opt), Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    private fun optionCard(opt: ActionOption): View {
        val isSelected = opt == selected
        val baseBlocker = turn.blocker(opt, opt.diceChoices.firstOrNull())
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(
                if (isSelected) Ui.SURFACE_HI else Ui.SURFACE, Ui.dpf(ctx, 10f),
                if (isSelected) Ui.GOLD else null, Ui.dp(ctx, 1),
            )
        }
        val title = Ui.horizontal(ctx)
        title.addView(Ui.text(ctx, opt.label, 16f, if (baseBlocker == null) Ui.TEXT else Ui.TEXT_FAINT, bold = true), Ui.weighted())
        if (opt.manaCost > 0) title.addView(Ui.text(ctx, "${opt.manaCost} mana", 12f, Ui.TEXT_DIM))
        card.addView(title, Ui.matchWidth())
        card.addView(Ui.text(ctx, opt.detail, 12f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 2)))
        if (baseBlocker != null && !isSelected) {
            card.addView(Ui.text(ctx, baseBlocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 2)))
        }

        Ui.makeTappable(card, ctx) {
            if (selected == opt) clearSelection() else { selected = opt; selectedDice = null }
            render()
        }

        if (isSelected) {
            if (opt.diceChoices.isNotEmpty()) {
                card.addView(Ui.text(ctx, "How many dice?", 13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
                card.addView(diceButtons(opt), Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            val blocker = turn.blocker(opt, selectedDice)
            val needsDice = opt.diceChoices.isNotEmpty() && selectedDice == null
            val declare = Button(ctx).apply {
                text = when {
                    opt.kind == ActionKind.END_TURN -> "End turn"
                    needsDice -> "Choose dice"
                    else -> "Declare \u2014 pool ${opt.poolCost(selectedDice)}"
                }
                isEnabled = blocker == null
                setOnClickListener { declare(opt) }
            }
            if (blocker != null && !needsDice) {
                card.addView(Ui.text(ctx, blocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 6)))
            }
            card.addView(declare, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        return card
    }

    /** Dice-count buttons, five per row; counts the pool can't afford are disabled. */
    private fun diceButtons(opt: ActionOption): View {
        val grid = Ui.vertical(ctx)
        var row: LinearLayout? = null
        opt.diceChoices.forEachIndexed { i, n ->
            if (i % 5 == 0) {
                row = Ui.horizontal(ctx)
                grid.addView(row, Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            val affordable = turn.blocker(opt, n) == null
            val on = n == selectedDice
            val cell = Ui.vertical(ctx).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, Ui.dp(ctx, 6), 0, Ui.dp(ctx, 6))
                background = Ui.rounded(
                    when { on -> Ui.CRIMSON; affordable -> Ui.BG; else -> Ui.SURFACE },
                    Ui.dpf(ctx, 8f), if (on) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 1),
                )
                addView(Ui.text(ctx, "$n", 17f, if (affordable) Ui.TEXT else Ui.TEXT_FAINT, bold = true))
                addView(Ui.text(ctx, "pool ${opt.poolCost(n)}", 10f, if (affordable) Ui.TEXT_DIM else Ui.TEXT_FAINT))
            }
            if (affordable) Ui.makeTappable(cell, ctx) { selectedDice = n; render() }
            row!!.addView(cell, Ui.weighted().apply { marginEnd = Ui.dp(ctx, 4) })
        }
        // Pad the last row so cells keep the same width.
        val leftover = (5 - opt.diceChoices.size % 5) % 5
        repeat(leftover) { row?.addView(View(ctx), Ui.weighted().apply { marginEnd = Ui.dp(ctx, 4) }) }
        return grid
    }

    private fun declare(opt: ActionOption) {
        if (opt.kind == ActionKind.END_TURN) {
            AlertDialog.Builder(ctx, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("End your turn?")
                .setMessage(if (turn.poolRemaining > 0) "${turn.poolRemaining} Combat Pool dice left for Reactions." else null)
                .setPositiveButton("End turn") { _, _ -> turn.declare(opt, null); clearSelection(); render() }
                .setNegativeButton("Cancel", null)
                .show()
            return
        }
        turn.declare(opt, if (opt.diceChoices.isEmpty()) null else selectedDice) ?: return
        clearSelection()
        render()
    }

    private fun clearSelection() {
        selected = null
        selectedDice = null
    }
}
