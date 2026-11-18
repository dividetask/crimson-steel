package com.dividetask.crimsonsteel.ui

import android.app.AlertDialog
import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import com.dividetask.crimsonsteel.data.ActionCategory
import com.dividetask.crimsonsteel.data.Initiative
import com.dividetask.crimsonsteel.data.TurnOption
import com.dividetask.crimsonsteel.net.Session

/**
 * Combat screen. Top to bottom:
 *  - the Combat Pool as a row of dice (colored by how much is left),
 *  - the initiative order (compacts to a single "your turn" row on your turn; tap to expand),
 *  - on your turn, your action options grouped by Main / Bonus / Free Action.
 *
 * Picking an action and its dice sends a *request* to the DM (it appears on
 * the DM's turn panel). Nothing is spent until the DM resolves it, so the
 * pool shown here subtracts this turn's pending requests.
 */
class InitiativeScreen(ctx: Context, onError: (Throwable) -> Unit) : LiveScreen<Initiative>(ctx, onError) {

    private var selectedKey: String? = null
    private var selectedDice: Int? = null
    private var expanded = false
    private var wasMyTurn = false
    private var busy = false

    override fun fetch(done: (Result<Pair<Initiative, String>>) -> Unit) = Session.initiative { r ->
        r.onSuccess { (d, _) ->
            // A new turn starts with the initiative list compacted and nothing selected.
            if (d.myTurn && !wasMyTurn) { expanded = false; clearSelection() }
            wasMyTurn = d.myTurn
        }
        done(r)
    }

    private fun pending(d: Initiative) = d.requests.sumOf { it.poolCost }
    private fun poolLeft(d: Initiative) = (d.pool?.current ?: 0) - pending(d)
    private fun mainLeft(d: Initiative): Int? =
        d.mainActionsRemaining?.takeIf { it >= 0 }?.let { it - d.requests.count { r -> r.category == ActionCategory.MAIN } }
    private fun manaLeft(d: Initiative): Int? = d.mana?.let { m -> m.current - d.requests.sumOf { it.manaCost } }

    override fun build(d: Initiative): View {
        val col = Ui.vertical(ctx, 12)
        if (!d.combatActive) {
            col.addView(Ui.text(ctx, "No combat right now.", 18f, Ui.TEXT, bold = true))
            col.addView(Ui.text(ctx, "This screen fills in when the DM starts combat.", 14f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 6)))
            return col
        }
        d.pool?.let { col.addView(poolCard(d), Ui.matchWidth()) }
        col.addView(Ui.sectionHeader(ctx, "Initiative — ${d.roundLabel}"))
        if (d.myTurn && !expanded) col.addView(compactTurnRow(d), Ui.matchWidth()) else fullOrder(col, d)

        if (d.myTurn) {
            actionMenu(col, d)
        } else {
            val acting = d.order.find { it.acting }
            col.addView(Ui.text(ctx, acting?.let { "Waiting for ${it.name}." } ?: "Waiting for the DM.", 14f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 14)))
        }
        return col
    }

    // --- Combat Pool ------------------------------------------------------------

    private fun poolCard(d: Initiative): View {
        val pool = d.pool!!
        val left = poolLeft(d).coerceAtLeast(0)
        val card = Ui.card(ctx)
        val top = Ui.horizontal(ctx)
        top.addView(Ui.text(ctx, "Combat Pool", 14f, Ui.TEXT_DIM), Ui.weighted())
        top.addView(Ui.text(ctx, "$left / ${pool.max}", 18f,
            if (left > 0) PoolView.colorFor(left, pool.max) else Ui.TEXT_DIM, bold = true))
        card.addView(top, Ui.matchWidth())
        card.addView(PoolView(ctx).apply { max = pool.max; remaining = left }, Ui.matchWidth(Ui.dp(ctx, 6)))
        val main = mainLeft(d)?.let { "$it / 2" } ?: "—"
        val mana = d.mana?.let { "${manaLeft(d)} / ${it.max}" } ?: "—"
        card.addView(Ui.text(ctx, "Main Actions $main  ·  Mana $mana", 13f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 6)))
        if (pending(d) > 0) {
            card.addView(Ui.text(ctx, "Includes ${pending(d)} dice requested this turn (not spent until the DM resolves them).",
                12f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 2)))
        }
        return card
    }

    // --- Initiative order ---------------------------------------------------------

    private fun compactTurnRow(d: Initiative): View {
        val me = d.order.find { it.isYou }
        val row = Ui.horizontal(ctx).apply {
            setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 12), Ui.dp(ctx, 12), Ui.dp(ctx, 12))
            background = Ui.rounded(Ui.CRIMSON_DARK, Ui.dpf(ctx, 10f), Ui.CRIMSON, Ui.dp(ctx, 2))
        }
        row.addView(Ui.text(ctx, "${me?.name ?: "You"} (you)", 16f, Ui.TEXT, bold = true), Ui.weighted())
        row.addView(Ui.text(ctx, "Your turn  ▾", 14f, Ui.GOLD, bold = true))
        Ui.makeTappable(row, ctx) { expanded = true; render() }
        return row
    }

    private fun fullOrder(col: LinearLayout, d: Initiative) {
        if (d.myTurn) {
            val collapse = Ui.text(ctx, "Hide initiative  ▴", 13f, Ui.GOLD, bold = true).apply {
                setPadding(Ui.dp(ctx, 4), Ui.dp(ctx, 4), Ui.dp(ctx, 4), Ui.dp(ctx, 8))
            }
            Ui.makeTappable(collapse, ctx) { expanded = false; render() }
            col.addView(collapse)
        }
        d.order.forEachIndexed { i, e ->
            val card = Ui.horizontal(ctx).apply {
                setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 10), Ui.dp(ctx, 12), Ui.dp(ctx, 10))
                background = Ui.rounded(
                    if (e.acting) Ui.CRIMSON_DARK else Ui.SURFACE, Ui.dpf(ctx, 10f),
                    if (e.acting) Ui.CRIMSON else null, Ui.dp(ctx, 2),
                )
            }
            card.addView(Ui.text(ctx, "${i + 1}", 16f, Ui.TEXT_DIM, bold = true),
                LinearLayout.LayoutParams(Ui.dp(ctx, 28), LinearLayout.LayoutParams.WRAP_CONTENT))
            val names = Ui.vertical(ctx)
            names.addView(Ui.text(ctx, e.name + if (e.isYou) "  (you)" else "", 15f, Ui.TEXT, bold = e.acting || e.isYou))
            names.addView(Ui.text(ctx, if (e.isPc) "Player character" else "Enemy", 12f,
                if (e.isPc) Ui.TEXT_DIM else Ui.DIE_FAIL))
            card.addView(names, Ui.weighted())
            if (e.acting) card.addView(Ui.text(ctx, "Turn", 13f, Ui.GOLD, bold = true))
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    // --- Action menu ----------------------------------------------------------------

    private fun actionMenu(col: LinearLayout, d: Initiative) {
        if (d.requests.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Requested this turn"))
            val card = Ui.card(ctx)
            for (r in d.requests) card.addView(Ui.text(ctx, "• ${r.summary}", 14f, Ui.TEXT), Ui.matchWidth(Ui.dp(ctx, 2)))
            card.addView(Ui.text(ctx, "Shown on the DM's turn panel. The DM resolves each one.", 12f, Ui.TEXT_FAINT),
                Ui.matchWidth(Ui.dp(ctx, 6)))
            card.addView(Button(ctx).apply {
                text = "Undo last"
                isEnabled = !busy
                setOnClickListener {
                    busy = true
                    Session.withdrawRequest(d.requests.last().id) { r -> busy = false; afterChange(r) }
                }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                gravity = Gravity.END
            })
            col.addView(card, Ui.matchWidth())
        }

        for (category in ActionCategory.entries) {
            val inCategory = d.options.filter { it.category == category }
            if (inCategory.isEmpty()) continue     // empty categories are skipped, as on the web
            col.addView(Ui.sectionHeader(ctx, category.label))
            for (opt in inCategory) col.addView(optionCard(d, opt), Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    /** Why [opt] can't be requested with [dice] right now, or null if it can. */
    private fun blocker(d: Initiative, opt: TurnOption, dice: Int?): String? {
        if (opt.isEndTurn) return null
        opt.disabledReason?.let { return it.replaceFirstChar { c -> c.uppercase() } + "." }
        if (opt.category == ActionCategory.MAIN && (mainLeft(d) ?: 1) <= 0) return "No Main Actions left."
        if (opt.manaCost > 0 && (manaLeft(d) ?: Int.MAX_VALUE) < opt.manaCost) return "Not enough mana."
        if (opt.dice.isNotEmpty()) {
            if (dice == null) {
                return if (opt.dice.none { affordable(d, it.poolCost, it.affordable) }) "Not enough Combat Pool." else null
            }
            val choice = opt.dice.find { it.dice == dice } ?: return "Choose how many dice."
            if (!affordable(d, choice.poolCost, choice.affordable)) return "Not enough Combat Pool."
        } else if ((opt.poolCost ?: 0) > poolLeft(d)) {
            return "Not enough Combat Pool."
        }
        return null
    }

    private fun affordable(d: Initiative, cost: Int, serverSays: Boolean) = serverSays && cost <= poolLeft(d)

    private fun optionCard(d: Initiative, opt: TurnOption): View {
        val isSelected = opt.key == selectedKey
        val baseBlocker = blocker(d, opt, null)
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
        if (opt.detail.isNotBlank()) card.addView(Ui.text(ctx, opt.detail, 12f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 2)))
        if (baseBlocker != null && !isSelected) {
            card.addView(Ui.text(ctx, baseBlocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 2)))
        }

        Ui.makeTappable(card, ctx) {
            if (selectedKey == opt.key) clearSelection() else { selectedKey = opt.key; selectedDice = null }
            render()
        }

        if (isSelected) {
            if (opt.dice.isNotEmpty()) {
                card.addView(Ui.text(ctx, "How many dice?", 13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
                card.addView(diceButtons(d, opt), Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            val needsDice = opt.dice.isNotEmpty() && selectedDice == null
            val blocker = blocker(d, opt, selectedDice)
            val cost = if (opt.dice.isEmpty()) opt.poolCost ?: 0 else opt.dice.find { it.dice == selectedDice }?.poolCost ?: 0
            val declare = Button(ctx).apply {
                text = when {
                    opt.isEndTurn -> "Ask to end my turn"
                    needsDice -> "Choose dice"
                    else -> "Request — pool $cost"
                }
                isEnabled = blocker == null && !needsDice && !busy
                setOnClickListener { request(opt) }
            }
            if (blocker != null && !needsDice) card.addView(Ui.text(ctx, blocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 6)))
            card.addView(declare, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        return card
    }

    /** Dice-count buttons, five per row; counts the pool can't afford are disabled. */
    private fun diceButtons(d: Initiative, opt: TurnOption): View {
        val grid = Ui.vertical(ctx)
        var row: LinearLayout? = null
        opt.dice.forEachIndexed { i, choice ->
            if (i % 5 == 0) {
                row = Ui.horizontal(ctx)
                grid.addView(row, Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            val ok = affordable(d, choice.poolCost, choice.affordable)
            val on = choice.dice == selectedDice
            val cell = Ui.vertical(ctx).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, Ui.dp(ctx, 6), 0, Ui.dp(ctx, 6))
                background = Ui.rounded(
                    when { on -> Ui.CRIMSON; ok -> Ui.BG; else -> Ui.SURFACE },
                    Ui.dpf(ctx, 8f), if (on) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 1),
                )
                addView(Ui.text(ctx, "${choice.dice}", 17f, if (ok) Ui.TEXT else Ui.TEXT_FAINT, bold = true))
                addView(Ui.text(ctx, "pool ${choice.poolCost}", 10f, if (ok) Ui.TEXT_DIM else Ui.TEXT_FAINT))
            }
            if (ok) Ui.makeTappable(cell, ctx) { selectedDice = choice.dice; render() }
            row!!.addView(cell, Ui.weighted().apply { marginEnd = Ui.dp(ctx, 4) })
        }
        val leftover = (5 - opt.dice.size % 5) % 5
        repeat(leftover) { row?.addView(View(ctx), Ui.weighted().apply { marginEnd = Ui.dp(ctx, 4) }) }
        return grid
    }

    private fun request(opt: TurnOption) {
        val send = {
            busy = true
            render()
            Session.requestAction(opt.key, if (opt.dice.isEmpty()) null else selectedDice) { r ->
                busy = false
                if (r.isSuccess) clearSelection()
                afterChange(r)
            }
        }
        if (opt.isEndTurn) {
            AlertDialog.Builder(ctx, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Ask the DM to end your turn?")
                .setPositiveButton("Ask") { _, _ -> send() }
                .setNegativeButton("Cancel", null)
                .show()
        } else {
            send()
        }
    }

    private fun afterChange(r: Result<Unit>) {
        r.onFailure { e ->
            val msg = (e as? com.dividetask.crimsonsteel.net.ApiException)?.error ?: "Connection problem"
            toast("Not sent: $msg")
        }
        refresh(force = true)
    }

    private fun clearSelection() {
        selectedKey = null
        selectedDice = null
    }
}
