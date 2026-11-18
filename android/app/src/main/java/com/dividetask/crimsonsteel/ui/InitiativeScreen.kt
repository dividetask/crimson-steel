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
    private var selectedTarget: Int? = null
    /** The option picked on each choice prompt, until it is sent (task id -> value). */
    private val promptPick = mutableMapOf<String, String>()
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

    /** Combat Pool asked for this turn but not spent yet: requests, plus attacks in progress (spent when the DM commits). */
    private fun pending(d: Initiative) = d.requests.sumOf { it.poolCost } + d.flows.sumOf { it.poolCost }
    private fun poolLeft(d: Initiative) = (d.pool?.current ?: 0) - pending(d)
    private fun mainLeft(d: Initiative): Int? =
        d.mainActionsRemaining?.takeIf { it >= 0 }?.let {
            it - d.requests.count { r -> r.category == ActionCategory.MAIN } - d.flows.size  // an Attack is a Main Action
        }
    private fun manaLeft(d: Initiative): Int? = d.mana?.let { m -> m.current - d.requests.sumOf { it.manaCost } }

    override fun build(d: Initiative): View {
        val col = Ui.vertical(ctx, 12)
        // Steps of an attack waiting on this player — on anyone's turn.
        if (d.prompts.isNotEmpty()) promptsSection(col, d)
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
        card.addView(PoolView(ctx).apply { max = pool.max; remaining = left; highlight = selectedCost(d) },
            Ui.matchWidth(Ui.dp(ctx, 6)))
        val main = mainLeft(d)?.let { "$it / 2" } ?: "—"
        val mana = d.mana?.let { "${manaLeft(d)} / ${it.max}" } ?: "—"
        card.addView(Ui.text(ctx, "Main Actions $main  ·  Mana $mana", 13f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 6)))
        if (pending(d) > 0) {
            card.addView(Ui.text(ctx, "Includes ${pending(d)} dice asked for this turn (not spent until the DM resolves them).",
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
            col.addView(Ui.sectionHeader(ctx, "Sent to the DM this turn"))
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

        flowsSection(col, d)

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

    /** Combat Pool the selected option would spend with the selected dice (0 when nothing is chosen yet). */
    private fun selectedCost(d: Initiative): Int {
        val opt = d.options.find { it.key == selectedKey } ?: return 0
        return if (opt.dice.isEmpty()) opt.poolCost ?: 0
        else opt.dice.find { it.dice == selectedDice }?.poolCost ?: 0
    }

    /** "Nature: 6 dice, +2" — the skill the action rolls. */
    private fun skillLine(opt: TurnOption): String? = opt.skill?.let { "${it.name}: ${it.dice} dice, ${Ui.signed(it.bonus)}" }

    private fun optionCard(d: Initiative, opt: TurnOption): View {
        val isSelected = opt.key == selectedKey
        val baseBlocker = blocker(d, opt, null)
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(
                if (isSelected) Ui.SURFACE_HI else Ui.SURFACE, Ui.dpf(ctx, 10f),
                if (isSelected) Ui.GOLD else null, Ui.dp(ctx, 1),
            )
        }
        // Spells and spell items: the name in its Tier colour, no "Tier n" text.
        val nameColor = when {
            baseBlocker != null -> Ui.TEXT_FAINT
            opt.tier != null -> Ui.tierColor(opt.tier)
            else -> Ui.TEXT
        }
        val title = Ui.horizontal(ctx)
        title.addView(Ui.text(ctx, opt.name, 16f, nameColor, bold = true), Ui.weighted())
        if (opt.manaCost > 0) title.addView(Ui.text(ctx, "${opt.manaCost} mana", 12f, Ui.TEXT_DIM))
        card.addView(title, Ui.matchWidth())
        skillLine(opt)?.let { card.addView(Ui.text(ctx, it, 13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 2))) }
        if (opt.detail.isNotBlank()) card.addView(Ui.text(ctx, opt.detail, 12f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 2)))
        if (baseBlocker != null && !isSelected) {
            card.addView(Ui.text(ctx, baseBlocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 2)))
        }

        Ui.makeTappable(card, ctx) {
            if (selectedKey == opt.key) clearSelection() else { selectedKey = opt.key; selectedDice = null }
            render()
        }

        if (isSelected) {
            if (opt.kind == "attack") targetPicker(card, d)
            val cost = selectedCost(d)
            val left = poolLeft(d).coerceAtLeast(0)
            // Exactly what is in the Combat Pool right now, with what this choice would spend in yellow.
            card.addView(Ui.text(ctx, "Combat Pool: $left dice" + if (cost > 0) " \u2014 this uses $cost" else "",
                13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
            d.pool?.let { pool ->
                card.addView(PoolView(ctx).apply { max = pool.max; remaining = left; highlight = cost },
                    Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            if (opt.dice.isNotEmpty()) {
                card.addView(Ui.text(ctx, "How many dice?", 13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
                card.addView(diceStrip(d, opt), Ui.matchWidth(Ui.dp(ctx, 4)))
                if (opt.speed > 0 && selectedDice != null) {
                    card.addView(Ui.text(ctx, "$selectedDice dice + Speed ${opt.speed} = $cost Combat Pool dice", 12f, Ui.TEXT_DIM),
                        Ui.matchWidth(Ui.dp(ctx, 4)))
                }
            }
            val needsDice = opt.dice.isNotEmpty() && selectedDice == null
            val needsTarget = opt.kind == "attack" && d.targets.none { it.combatantId == selectedTarget }
            val blocker = blocker(d, opt, selectedDice)
            val targetName = d.targets.find { it.combatantId == selectedTarget }?.name
            val confirm = Button(ctx).apply {
                text = when {
                    needsTarget -> "Choose a target"
                    needsDice -> "Choose dice"
                    opt.kind == "attack" -> "Attack $targetName with ${opt.name}"
                    else -> opt.actionText
                }
                isEnabled = blocker == null && !needsDice && !needsTarget && !busy
                setOnClickListener { request(opt) }
            }
            if (blocker != null && !needsDice) card.addView(Ui.text(ctx, blocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 6)))
            card.addView(confirm, Ui.matchWidth(Ui.dp(ctx, 8)))
            card.addView(Ui.text(ctx, "Sent to the DM, who resolves it.", 11f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 2)))
        }
        return card
    }

    /**
     * The dice picker: one die for each die below the action's minimum (always
     * included), then one die button per count. Choosing a count lights every
     * die up to it — choosing 6 lights the 5 dice to its left and the 6 button.
     */
    private fun diceStrip(d: Initiative, opt: TurnOption): View =
        Ui.diceStrip(ctx, opt.dice.map { c ->
            Triple(c.dice, affordable(d, c.poolCost, c.affordable)) { selectedDice = c.dice; render() }
        }, selectedDice ?: 0)

    private fun request(opt: TurnOption) {
        val send = {
            busy = true
            render()
            val target = if (opt.kind == "attack") selectedTarget else null
            Session.requestAction(opt.key, if (opt.dice.isEmpty()) null else selectedDice, target) { r ->
                busy = false
                if (r.isSuccess) clearSelection()
                afterChange(r)
            }
        }
        if (opt.isEndTurn) {
            AlertDialog.Builder(ctx, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("End your turn?")
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
        selectedTarget = null
    }

    // --- Attacks: target, prompts, status -------------------------------------------

    /** Who to attack: one chip per Combatant, enemies first. */
    private fun targetPicker(card: LinearLayout, d: Initiative) {
        card.addView(Ui.text(ctx, "Target", 13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
        var row: LinearLayout? = null
        d.targets.forEachIndexed { i, t ->
            if (i % 2 == 0) {
                row = Ui.horizontal(ctx)
                card.addView(row, Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            val on = t.combatantId == selectedTarget
            val chip = Ui.text(ctx, t.name + if (t.dying) " (dying)" else "", 14f,
                if (t.enemy) Ui.TEXT else Ui.TEXT_DIM, bold = on).apply {
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(Ui.dp(ctx, 8), Ui.dp(ctx, 9), Ui.dp(ctx, 8), Ui.dp(ctx, 9))
                background = Ui.rounded(if (on) Ui.CRIMSON else Ui.BG, Ui.dpf(ctx, 8f),
                    if (on) Ui.GOLD else if (t.enemy) Ui.DIE_FAIL else Ui.SURFACE_HI, Ui.dp(ctx, 1))
            }
            Ui.makeTappable(chip, ctx) { selectedTarget = t.combatantId; render() }
            row!!.addView(chip, Ui.weighted().apply { marginEnd = Ui.dp(ctx, 6) })
        }
        if (d.targets.size % 2 == 1) row?.addView(View(ctx), Ui.weighted())
        if (d.targets.isEmpty()) card.addView(Ui.text(ctx, "No one to attack.", 13f, Ui.TEXT_DIM))
    }

    /** This player's own attacks in progress, one line per step. */
    private fun flowsSection(col: LinearLayout, d: Initiative) {
        if (d.flows.isEmpty()) return
        col.addView(Ui.sectionHeader(ctx, "Your attack"))
        for (f in d.flows) {
            val card = Ui.card(ctx)
            card.addView(Ui.text(ctx, f.summary, 15f, Ui.TEXT, bold = true))
            card.addView(Ui.text(ctx, stageText(f.stage), 12f, Ui.GOLD), Ui.matchWidth(Ui.dp(ctx, 2)))
            for (st in f.steps) {
                val what = when {
                    st.step == "declare" -> "Your request"
                    st.step == "defense" -> "${st.owner}'s defense"
                    st.step == "ally_defense" -> "${st.owner}'s shield"
                    st.step.startsWith("luck:") -> "${st.owner}'s Luck"
                    st.step.startsWith("roll:") -> "${st.owner} rolls"
                    else -> st.step
                }
                val state = when (st.status) {
                    "waiting" -> "waiting"
                    "submitted" -> "${st.summary ?: "answered"} \u2014 waiting for the DM"
                    else -> st.summary ?: "done"
                }
                card.addView(Ui.text(ctx, "\u2022 $what: $state", 13f, if (st.status == "approved") Ui.TEXT_DIM else Ui.TEXT),
                    Ui.matchWidth(Ui.dp(ctx, 3)))
            }
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 4)))
        }
    }

    private fun stageText(stage: String) = when (stage) {
        "declare" -> "Waiting for the DM to approve your attack"
        "respond" -> "Defenses"
        "luck" -> "Luck"
        "roll" -> "Rolling"
        "resolve" -> "The DM is resolving it"
        else -> stage
    }

    /** Steps waiting on this player: defense, ally shield, Luck, or a roll. */
    private fun promptsSection(col: LinearLayout, d: Initiative) {
        col.addView(Ui.sectionHeader(ctx, "Your move"))
        for (p in d.prompts) col.addView(promptCard(p), Ui.matchWidth(Ui.dp(ctx, 6)))
    }

    private fun promptCard(p: com.dividetask.crimsonsteel.data.Prompt): View {
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(Ui.CRIMSON_DARK, Ui.dpf(ctx, 10f), if (p.waiting) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 2))
        }
        card.addView(Ui.text(ctx, p.title, 17f, Ui.GOLD, bold = true))
        card.addView(Ui.text(ctx, p.body, 13f, Ui.TEXT), Ui.matchWidth(Ui.dp(ctx, 2)))
        if (!p.waiting) {
            card.addView(Ui.text(ctx, "Sent: ${p.summary ?: ""} \u2014 waiting for the DM to approve.", 13f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 8)))
            return card
        }
        val roll = p.roll
        if (p.kind == "roll" && roll != null) {
            card.addView(Ui.text(ctx, RollFlow.paramsLine(roll.diceCount, roll.tn, roll.startingValue), 13f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 6)))
            card.addView(Button(ctx).apply {
                text = "Roll ${roll.name}"
                isEnabled = !busy
                setOnClickListener {
                    RollFlow.promptRoll(ctx, roll.name, roll) { dice, rerolled, final, done ->
                        Session.submitRoll(p.flowId, p.taskId, dice, rerolled, final) { r ->
                            done(r.isSuccess)
                            afterChange(r)
                        }
                    }
                }
            }, Ui.matchWidth(Ui.dp(ctx, 8)))
            return card
        }

        // A choice: options grouped as on the DM's builder (No defense, Dodge, Parry…).
        val picked = promptPick[p.taskId]
        for ((group, opts) in p.options.groupBy { it.group }) {
            val withDice = opts.filter { it.dice != null }
            if (withDice.isEmpty()) {
                for (o in opts) card.addView(choiceChip(o.summary, o.value == picked, !o.disabled) {
                    promptPick[p.taskId] = o.value; render()
                }, Ui.matchWidth(Ui.dp(ctx, 6)))
            } else {
                card.addView(Ui.text(ctx, opts.first().groupLabel, 14f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
                val chosen = withDice.find { it.value == picked }?.dice ?: 0
                card.addView(Ui.diceStrip(ctx, withDice.map { o ->
                    Triple(o.dice!!, !o.disabled) { promptPick[p.taskId] = o.value; render() }
                }, chosen), Ui.matchWidth(Ui.dp(ctx, 4)))
                if (group.isNotEmpty() && withDice.all { it.disabled }) {
                    card.addView(Ui.text(ctx, "Not enough Combat Pool.", 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 2)))
                }
            }
        }
        val pick = p.options.find { it.value == picked }
        card.addView(Button(ctx).apply {
            text = pick?.summary ?: "Choose one"
            isEnabled = pick != null && !busy
            setOnClickListener {
                busy = true
                render()
                Session.answerPrompt(p.flowId, p.taskId, pick!!.value) { r ->
                    busy = false
                    if (r.isSuccess) promptPick.remove(p.taskId)
                    afterChange(r)
                }
            }
        }, Ui.matchWidth(Ui.dp(ctx, 10)))
        return card
    }

    private fun choiceChip(label: String, on: Boolean, enabled: Boolean, onTap: () -> Unit): View =
        Ui.text(ctx, label, 14f, if (enabled) Ui.TEXT else Ui.TEXT_FAINT, bold = on).apply {
            setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 10), Ui.dp(ctx, 12), Ui.dp(ctx, 10))
            background = Ui.rounded(if (on) Ui.CRIMSON else Ui.BG, Ui.dpf(ctx, 8f), if (on) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 1))
            if (enabled) Ui.makeTappable(this, ctx, onTap)
        }
}
