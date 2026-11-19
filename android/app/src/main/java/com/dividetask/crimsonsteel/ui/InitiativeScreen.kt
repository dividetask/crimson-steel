package com.dividetask.crimsonsteel.ui

import android.app.AlertDialog
import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import com.dividetask.crimsonsteel.data.ActionCategory
import com.dividetask.crimsonsteel.data.Initiative
import com.dividetask.crimsonsteel.data.InitiativeEntry
import com.dividetask.crimsonsteel.data.Stat
import com.dividetask.crimsonsteel.data.TurnOption
import com.dividetask.crimsonsteel.net.Session

/**
 * Combat screen. Top to bottom:
 *  - anything waiting on this player (a defense, Luck, a roll), on anyone's turn;
 *  - **Status**: the player's own row — the name in its Tier colour, the
 *    Combat Pool dice, and *Acted* or *Waiting*. Tap it to open HP, Mana,
 *    Combat Pool and Conditions; tap again to close it;
 *  - **Initiative**: "<name>'s Turn" with that Combatant's Combat Pool dice
 *    under it; tap for the whole order, tap again to close;
 *  - **Actions** (on the player's turn): Melee, Ranged, Spell, Item, Move,
 *    Special and End Turn. Tap one to open its options.
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
    /** The Status row opened (combatant id), the whole initiative order shown, the action group opened. */
    private var statusOpen: Int? = null
    private var orderOpen = false
    private var openGroup: String? = null
    /** What to bring to the top of the screen once rebuilt: an option's key, or "group:<name>". */
    private var scrollTarget: String? = null
    /** Outcomes already seen here, so the player's own resets their options once. */
    private val seenNews = mutableSetOf<String>()
    private var newsPrimed = false
    private var wasMyTurn = false
    private var busy = false

    override fun fetch(done: (Result<Pair<Initiative, String>>) -> Unit) = Session.initiative { r ->
        r.onSuccess { (d, _) ->
            throwShared(d)
            // The DM finished this player's action: close what they had open.
            val mineDone = d.news.filter { it.yours && seenNews.add(it.flowId) }
            if (newsPrimed && mineDone.isNotEmpty()) { clearSelection(); openGroup = null; orderOpen = false }
            d.news.forEach { seenNews.add(it.flowId) }
            newsPrimed = true
            // A new turn starts with everything closed and nothing selected.
            if (d.myTurn && !wasMyTurn) { orderOpen = false; openGroup = null; clearSelection() }
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
        // What the DM just committed, for everyone.
        if (d.news.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Just happened"))
            val card = Ui.card(ctx)
            for (n in d.news.reversed()) card.addView(Ui.text(ctx, n.text, 15f, if (n.yours) Ui.GOLD else Ui.TEXT, bold = n.yours),
                Ui.matchWidth(Ui.dp(ctx, 3)))
            col.addView(card, Ui.matchWidth())
        }
        // Steps of an action waiting on this player — on anyone's turn.
        if (d.prompts.isNotEmpty()) promptsSection(col, d)
        // Every other action with dice on the table: everyone sees it, rolling or not.
        val asked = d.prompts.map { it.flowId }.toSet()
        val watching = d.actions.filter { it.flowId !in asked }
        if (watching.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "In play"))
            for (a in watching) col.addView(rollCard(viewOf(a)), Ui.matchWidth(Ui.dp(ctx, 6)))
        }
        if (!d.combatActive) {
            col.addView(Ui.text(ctx, "No combat right now.", 18f, Ui.TEXT, bold = true))
            col.addView(Ui.text(ctx, "This screen fills in when the DM starts combat.", 14f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 6)))
            return col
        }
        statusSection(col, d)
        initiativeSection(col, d)
        if (!d.myTurn) {
            val acting = d.order.find { it.acting }
            col.addView(Ui.text(ctx, acting?.let { "Waiting for ${it.name}." } ?: "Waiting for the DM.", 14f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 14)))
        }
        // Everything on the player's turn; on anyone else's, their Free actions (Rage…).
        if (d.myTurn || d.options.isNotEmpty() || d.busy) actionMenu(col, d)
        return col
    }

    // --- Status -------------------------------------------------------------------

    private fun statusSection(col: LinearLayout, d: Initiative) {
        val me = d.order.find { it.isYou } ?: return
        col.addView(Ui.sectionHeader(ctx, "Status"))
        col.addView(statusRow(d, me, statusOpen == me.combatantId), Ui.matchWidth(Ui.dp(ctx, 6)))
    }

    /** The Combat Pool a row shows: the player's own less what this turn's requests would spend. */
    private fun poolOf(d: Initiative, e: InitiativeEntry): Stat? =
        if (e.isYou) d.pool?.let { Stat(poolLeft(d).coerceAtLeast(0), it.max) } else e.pool

    private fun statusRow(d: Initiative, e: InitiativeEntry, open: Boolean): View {
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(if (e.acting) Ui.CRIMSON_DARK else Ui.SURFACE, Ui.dpf(ctx, 10f),
                if (open) Ui.GOLD else if (e.acting) Ui.CRIMSON else null, Ui.dp(ctx, if (open) 2 else 1))
        }
        val top = Ui.horizontal(ctx)
        val nameColor = e.tier?.let { Ui.tierColor(it) } ?: Ui.TEXT
        top.addView(Ui.text(ctx, e.name + if (e.isYou) "  (you)" else "", 16f, nameColor, bold = true), Ui.weighted())
        top.addView(Ui.text(ctx, if (e.acted) "Acted" else "Waiting", 13f, if (e.acted) Ui.TEXT_DIM else Ui.GOLD, bold = true))
        card.addView(top, Ui.matchWidth())
        val pool = poolOf(d, e)
        if (pool != null && !pool.hidden) {
            card.addView(PoolView(ctx).apply {
                max = pool.max; remaining = pool.current
                if (e.isYou) highlight = selectedCost(d)
            }, Ui.matchWidth(Ui.dp(ctx, 6)))
        }
        if (open) {
            val stats = Ui.vertical(ctx)
            fun line(label: String, value: String) {
                val r = Ui.horizontal(ctx).apply { setPadding(0, Ui.dp(ctx, 3), 0, Ui.dp(ctx, 3)) }
                r.addView(Ui.text(ctx, label, 14f, Ui.TEXT_DIM), LinearLayout.LayoutParams(Ui.dp(ctx, 110), LinearLayout.LayoutParams.WRAP_CONTENT))
                r.addView(Ui.text(ctx, value, 14f, Ui.TEXT, bold = true), Ui.weighted())
                stats.addView(r, Ui.matchWidth())
            }
            fun shown(s: Stat?) = when {
                s == null || s.hidden -> "?"
                else -> "${s.current} / ${s.max}"
            }
            line("HP", shown(e.hp))
            val mana = if (e.isYou) d.mana?.let { Stat(manaLeft(d) ?: it.current, it.max) } ?: e.mana else e.mana
            line("Mana", shown(mana))
            line("Combat Pool", shown(pool))
            if (e.isYou) mainLeft(d)?.let { line("Main Actions", "$it / 2") }
            line("Conditions", e.conditions?.ifEmpty { listOf("None") }?.joinToString(", ") ?: "?")
            if (e.isYou && pending(d) > 0) {
                stats.addView(Ui.text(ctx, "Combat Pool and Mana leave out what this turn's requests would spend (${pending(d)} dice).",
                    12f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 4)))
            }
            card.addView(stats, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        Ui.makeTappable(card, ctx) { statusOpen = if (open) null else e.combatantId; render() }
        return card
    }

    // --- Initiative order ---------------------------------------------------------

    private fun initiativeSection(col: LinearLayout, d: Initiative) {
        col.addView(Ui.sectionHeader(ctx, "Initiative \u2014 ${d.roundLabel}"))
        val acting = d.order.find { it.acting }
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(Ui.SURFACE, Ui.dpf(ctx, 10f), if (orderOpen) Ui.GOLD else null, Ui.dp(ctx, 1))
        }
        val head = Ui.horizontal(ctx)
        val who = when {
            acting == null -> "Nobody's turn yet"
            acting.isYou -> "Your Turn"
            else -> "${acting.name}'s Turn"
        }
        head.addView(Ui.text(ctx, who, 16f, if (acting?.isYou == true) Ui.GOLD else Ui.TEXT, bold = true), Ui.weighted())
        head.addView(Ui.text(ctx, if (orderOpen) "\u25b4" else "\u25be", 16f, Ui.TEXT_DIM))
        card.addView(head, Ui.matchWidth())
        // The acting Combatant's Combat Pool dice (the player's own are in Status).
        acting?.takeIf { !it.isYou }?.pool?.takeIf { !it.hidden }?.let { pool ->
            card.addView(PoolView(ctx).apply { max = pool.max; remaining = pool.current }, Ui.matchWidth(Ui.dp(ctx, 6)))
        }
        Ui.makeTappable(card, ctx) { orderOpen = !orderOpen; render() }
        col.addView(card, Ui.matchWidth())
        if (orderOpen) fullOrder(col, d)
    }

    private fun fullOrder(col: LinearLayout, d: Initiative) {
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
            names.addView(Ui.text(ctx, e.name + if (e.isYou) "  (you)" else "", 15f,
                e.tier?.let { Ui.tierColor(it) } ?: Ui.TEXT, bold = e.acting || e.isYou))
            names.addView(Ui.text(ctx, if (e.isPc) "Player character" else "Enemy", 12f,
                if (e.isPc) Ui.TEXT_DIM else Ui.DIE_FAIL))
            card.addView(names, Ui.weighted())
            card.addView(Ui.text(ctx, if (e.acting) "Turn" else if (e.acted) "Acted" else "Waiting", 13f,
                if (e.acting) Ui.GOLD else Ui.TEXT_DIM, bold = e.acting))
            Ui.makeTappable(card, ctx) { orderOpen = false; render() }
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    // --- Actions --------------------------------------------------------------------

    /** The action groups, in order, and which group an option belongs to. */
    private val groups = listOf("Melee", "Ranged", "Spell", "Item", "Move", "Special", "End Turn")

    private fun groupOf(o: TurnOption): String = when (o.kind) {
        "attack" -> if (o.ranged) "Ranged" else "Melee"
        "cast" -> "Spell"
        "item" -> "Item"
        "move" -> "Move"
        "end_turn" -> "End Turn"
        else -> "Special"
    }

    private fun actionMenu(col: LinearLayout, d: Initiative) {
        if (d.requests.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Sent to the DM this turn"))
            val card = Ui.card(ctx)
            for (r in d.requests) card.addView(Ui.text(ctx, "\u2022 ${r.summary}", 14f, Ui.TEXT), Ui.matchWidth(Ui.dp(ctx, 2)))
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

        col.addView(Ui.sectionHeader(ctx, if (d.myTurn) "Actions" else "Free actions"))
        // A die roll waiting on this player comes first: the actions come back
        // once it is rolled.
        if (d.busy) {
            col.addView(Ui.card(ctx).apply {
                addView(Ui.text(ctx, "Roll your dice first (under Your move). Your actions come back once it is rolled.", 14f, Ui.TEXT_DIM))
            }, Ui.matchWidth(Ui.dp(ctx, 8)))
            return
        }

        val byGroup = d.options.groupBy { groupOf(it) }
        if (openGroup != null && byGroup[openGroup].isNullOrEmpty()) openGroup = null
        for (g in groups) {
            val opts = byGroup[g].orEmpty()
            if (opts.isEmpty()) continue
            val open = g == openGroup
            val usable = opts.any { blocker(d, it, null) == null }
            val head = Ui.horizontal(ctx).apply {
                setPadding(Ui.dp(ctx, 14), Ui.dp(ctx, 12), Ui.dp(ctx, 14), Ui.dp(ctx, 12))
                background = Ui.rounded(if (open) Ui.SURFACE_HI else Ui.SURFACE, Ui.dpf(ctx, 10f),
                    if (open) Ui.GOLD else null, Ui.dp(ctx, 1))
            }
            head.addView(Ui.text(ctx, g, 16f, if (usable) Ui.TEXT else Ui.TEXT_FAINT, bold = true), Ui.weighted())
            if (opts.size > 1) head.addView(Ui.text(ctx, "${opts.size}", 13f, Ui.TEXT_DIM))
            head.addView(Ui.text(ctx, if (open) "  \u25b4" else "  \u25be", 16f, Ui.TEXT_DIM))
            Ui.makeTappable(head, ctx) {
                openGroup = if (open) null else g
                if (open || opts.none { it.key == selectedKey }) clearSelection()
                // A group of one opens straight onto its option.
                if (!open && opts.size == 1) { selectedKey = opts.first().key; selectedDice = null }
                // Opening a group brings it to the top of the screen.
                scrollTarget = when { open -> null; opts.size == 1 -> opts.first().key; else -> "group:$g" }
                render()
            }
            col.addView(head, Ui.matchWidth(Ui.dp(ctx, 6)))
            if (scrollTarget == "group:$g") { scrollTarget = null; scrollToTop(head) }
            if (open) for (opt in opts) col.addView(optionCard(d, opt), Ui.matchWidth(Ui.dp(ctx, 4)))
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
            if (selectedKey == opt.key) clearSelection() else {
                selectedKey = opt.key; selectedDice = null
                scrollTarget = opt.key  // the chosen action comes to the top of the screen
            }
            render()
        }

        if (isSelected) {
            if (opt.needsTarget) targetPicker(card, d, includeSelf = opt.kind != "attack")
            when (opt.target) {
                "self" -> card.addView(Ui.text(ctx, "Target: yourself", 13f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 8)))
                "object" -> card.addView(Ui.text(ctx, "Target: an object (the DM handles it)", 13f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 8)))
                "area" -> card.addView(Ui.text(ctx, "An area: the DM places it on the map, and everyone caught in it saves.", 13f, Ui.TEXT_DIM),
                    Ui.matchWidth(Ui.dp(ctx, 8)))
            }
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
            val needsTarget = opt.needsTarget && targetsFor(d, opt).none { it.combatantId == selectedTarget }
            val blocker = blocker(d, opt, selectedDice)
            val targetName = d.targets.find { it.combatantId == selectedTarget }?.name
            val confirm = Button(ctx).apply {
                text = when {
                    needsTarget -> "Choose a target"
                    needsDice -> "Choose dice"
                    opt.kind == "attack" -> "Attack $targetName with ${opt.name}"
                    opt.needsTarget -> "${opt.actionText} on ${targetWord(d)}"
                    else -> opt.actionText
                }
                isEnabled = blocker == null && !needsDice && !needsTarget && !busy
                setOnClickListener { request(opt) }
            }
            if (blocker != null && !needsDice) card.addView(Ui.text(ctx, blocker, 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 6)))
            card.addView(confirm, Ui.matchWidth(Ui.dp(ctx, 8)))
            card.addView(Ui.text(ctx, "Sent to the DM, who resolves it.", 11f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 2)))
        }
        if (isSelected && scrollTarget == opt.key) { scrollTarget = null; scrollToTop(card) }
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
        }, selectedDice ?: 0, speed = opt.speed)

    private fun request(opt: TurnOption) {
        val send = {
            busy = true
            render()
            val target = if (opt.needsTarget) selectedTarget else null
            Session.requestAction(opt.key, if (opt.dice.isEmpty()) null else selectedDice, target) { r ->
                busy = false
                if (r.isSuccess) {
                    clearSelection()
                    openGroup = null
                    // Taken: its sound (if any) is offered in the audio bar at the bottom.
                    opt.sound?.let { SoundPlayer.offer(opt.name, it) }
                }
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

    /** The chosen target in a sentence: "yourself" or their name. */
    private fun targetWord(d: Initiative): String =
        d.targets.find { it.combatantId == selectedTarget }?.let { if (it.self) "yourself" else it.name } ?: ""

    /** Who an option may target: attacks never yourself; Spells and Items anyone. */
    private fun targetsFor(d: Initiative, opt: TurnOption) =
        if (opt.kind == "attack") d.targets.filter { !it.self } else d.targets

    /** Who to target: one chip per Combatant, enemies first (yourself last, for Spells / Items). */
    private fun targetPicker(card: LinearLayout, d: Initiative, includeSelf: Boolean) {
        card.addView(Ui.text(ctx, "Target", 13f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 10)))
        var row: LinearLayout? = null
        val targets = if (includeSelf) d.targets else d.targets.filter { !it.self }
        targets.forEachIndexed { i, t ->
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
        if (targets.size % 2 == 1) row?.addView(View(ctx), LinearLayout.LayoutParams(0, 1, 1f)) // 1 px: a plain View grows to all the height on offer
        if (targets.isEmpty()) card.addView(Ui.text(ctx, "No one to target.", 13f, Ui.TEXT_DIM))
    }

    /** This player's own attacks in progress, one line per step. */
    private fun flowsSection(col: LinearLayout, d: Initiative) {
        if (d.flows.isEmpty()) return
        col.addView(Ui.sectionHeader(ctx, "In progress"))
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
        "declare" -> "Waiting for the DM to approve"
        "builder" -> "The DM is running it"
        else -> stage
    }

    /** Steps waiting on this player: defense, ally shield, Luck, or a roll. */
    /** Every roll this player owns in the actions on screen (task ids): "You", Roll buttons. */
    private var myRollTasks: Set<String> = emptySet()

    private fun promptsSection(col: LinearLayout, d: Initiative) {
        col.addView(Ui.sectionHeader(ctx, "Your move"))
        val rolls = d.prompts.filter { it.kind == "roll" && it.roll != null }
        myRollTasks = rolls.map { it.taskId }.toSet()
        for (p in d.prompts.filter { it !in rolls }) col.addView(promptCard(p), Ui.matchWidth(Ui.dp(ctx, 6)))
        // One card per action, however many of its rolls are this player's
        // (the attack roll, then its Damage Riders…): a Roll button under each.
        for ((_, own) in rolls.groupBy { it.flowId }) {
            val primary = own.firstOrNull { it.waiting } ?: own.last()
            col.addView(rollCard(primary, own), Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    /**
     * A choice waiting on the player (a defense, an ally's shield, Luck):
     *
     *   Garroth Vask Attacks Wolf with Great Sword        (the action)
     *   Use your luck?  3 Luck remaining                  (the question)
     *   Help Garroth Vask's Attack      [dice]            (each group, bold,
     *   Hinder Garroth Vask's Attack    [dice]             with its dice)
     *   …
     *   [ Help Garroth Vask's Attack — reroll 2 dice ]    (green to help, red to hinder)
     */
    private fun promptCard(p: com.dividetask.crimsonsteel.data.Prompt): View {
        if (p.kind == "roll" && p.roll != null) return rollCard(p)
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(Ui.CRIMSON_DARK, Ui.dpf(ctx, 10f), if (p.waiting) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 2))
        }
        card.addView(Ui.text(ctx, p.actionLine ?: p.body, 20f, Ui.TEXT, bold = true))
        val question = Ui.horizontal(ctx).apply { gravity = Gravity.BOTTOM }
        question.addView(Ui.text(ctx, p.title, 17f, Ui.GOLD, bold = true))
        p.luckRemaining?.let {
            question.addView(Ui.text(ctx, "   $it Luck remaining", 14f, Ui.TEXT_DIM))
        }
        card.addView(question, Ui.matchWidth(Ui.dp(ctx, 4)))
        if (!p.waiting) {
            card.addView(Ui.text(ctx, "Sent: ${p.summary ?: ""} \u2014 waiting for the DM.", 13f, Ui.TEXT_DIM),
                Ui.matchWidth(Ui.dp(ctx, 8)))
            return card
        }

        // The groups with dice, each under its bold name (Help / Hinder …, Dodge,
        // Parry…), then the plain choices (No luck, No defense) last.
        val picked = promptPick[p.taskId]
        val groups = p.options.groupBy { it.group }
        for ((_, opts) in groups) {
            val withDice = opts.filter { it.dice != null }
            if (withDice.isEmpty()) continue
            card.addView(Ui.text(ctx, opts.first().groupLabel, 15f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 12)))
            val chosen = withDice.find { it.value == picked }?.dice ?: 0
            card.addView(Ui.diceStrip(ctx, withDice.map { o ->
                Triple(o.dice!!, !o.disabled) { promptPick[p.taskId] = o.value; render() }
            }, chosen), Ui.matchWidth(Ui.dp(ctx, 4)))
            if (withDice.all { it.disabled }) {
                card.addView(Ui.text(ctx, "Not enough Combat Pool.", 12f, Ui.DIE_FAIL), Ui.matchWidth(Ui.dp(ctx, 2)))
            }
        }
        for ((_, opts) in groups) {
            if (opts.any { it.dice != null }) continue
            for (o in opts) card.addView(choiceChip(o.summary, o.value == picked, !o.disabled) {
                promptPick[p.taskId] = o.value; render()
            }, Ui.matchWidth(Ui.dp(ctx, 10)))
        }
        val pick = p.options.find { it.value == picked }
        card.addView(Button(ctx).apply {
            text = pick?.summary ?: "Choose one"
            isEnabled = pick != null && !busy
            // Helping is green, hindering red.
            when (pick?.tone) {
                "help" -> { setBackgroundColor(Ui.NUM_SUCCESS); setTextColor(android.graphics.Color.WHITE) }
                "hinder" -> { setBackgroundColor(Ui.NUM_FAIL); setTextColor(android.graphics.Color.WHITE) }
            }
            setOnClickListener {
                busy = true
                render()
                Session.answerPrompt(p.flowId, p.taskId, pick!!.value) { r ->
                    busy = false
                    if (r.isSuccess) promptPick.remove(p.taskId)
                    afterChange(r)
                }
            }
        }, Ui.matchWidth(Ui.dp(ctx, 12)))
        return card
    }

    /**
     * An action the DM just shared (Confirm): throw every Roll this phone has
     * not thrown yet onto the dice table — the first throw as rolled, then
     * the Luck rerolls and nudges, marked — with the action as its title.
     */
    private fun throwShared(d: Initiative) {
        val act = ctx as? android.app.Activity ?: return
        for (a in d.shared) {
            val fresh = a.rolls.filter { r -> r.final != null && "${r.taskId}:${r.final}" !in thrownShared && r.taskId !in shownRolling }
            if (fresh.isEmpty()) continue
            val zones = a.rolls.mapIndexed { i, r ->
                RollTable.Zone(r.taskId, zoneLabel(r), r.color ?: RollTable.colorFor(i))
            }
            for (r in fresh) {
                thrownShared += "${r.taskId}:${r.final}"
                shownRolling += r.taskId
                RollTable.throwDice(act, a.flowId, zones, r.taskId, r.dice ?: r.final!!, r.rerolled, r.final!!, r.tn, r.startingValue,
                    title = a.actionLine, failureModifier = r.failureModifier)
            }
        }
    }

    /** Shared Rolls already thrown here ("task id:final dice"). */
    private val thrownShared = mutableSetOf<String>()

    // --- Rolls ----------------------------------------------------------------------

    /** Not-yet-rolled dice under an action: plain light grey. */
    private val CARD_BLANK = 0xFFE5E7EB.toInt()

    /** Rolls whose dice have already been shown rolling (task ids). */
    private val shownRolling = mutableSetOf<String>()
    /** The dice table's parts of the screen for an action: one per Roll, the player's own first. */
    private fun zonesFor(p: com.dividetask.crimsonsteel.data.Prompt): List<RollTable.Zone> {
        val mine = p.allRolls.filter { it.taskId in myRollTasks || it.taskId == p.taskId }
        val others = p.allRolls.filter { it !in mine }
        return (mine + others).mapIndexed { i, r ->
            RollTable.Zone(r.taskId, zoneLabel(r), diceColorOf(p, r, i))
        }
    }

    /**
     * A Roll's label on the dice table: the character's name and the Roll's
     * TN — "Wolf (TN 9)" — or, for a Damage Rider, its kind — "Garroth Vask
     * (Vicious Damage)".
     */
    private fun zoneLabel(r: com.dividetask.crimsonsteel.data.RollLine): String =
        if (r.rider) "${r.owner} (${r.what.ifBlank { r.name }} Damage)" else "${r.owner} (TN ${r.tn})"

    /** Each roller's own dice colour, as the server sends it (the same on every phone). */
    private fun diceColorOf(p: com.dividetask.crimsonsteel.data.Prompt, r: com.dividetask.crimsonsteel.data.RollLine, i: Int): Int =
        r.color ?: if (r.taskId in myRollTasks || r.taskId == p.taskId) com.dividetask.crimsonsteel.net.Session.diceColor else RollTable.colorFor(i)

    /**
     * The roll card: the action as a header ("Casting Fire Dart"), then each
     * Roll — the player's own first label ("Arcana +3"), the others by name
     * ("Wolf Dodging +2") — with one die per die. The player's Roll button
     * sits under their dice. Every Roll's dice roll on screen when its result
     * arrives (the player's own the moment they press Roll), then stay showing.
     */
    /** An action this player watches (rolls nothing in it), shown as a read-only roll card. */
    private fun viewOf(a: com.dividetask.crimsonsteel.data.SharedAction) = com.dividetask.crimsonsteel.data.Prompt(
        flowId = a.flowId, taskId = "", kind = "view", step = "", title = a.actionLine, body = "", status = "approved",
        summary = null, options = emptyList(), roll = null, allRolls = a.rolls, headline = a.headline ?: a.actionLine,
        actionLine = a.actionLine,
    )

    private fun rollCard(p: com.dividetask.crimsonsteel.data.Prompt,
                         own: List<com.dividetask.crimsonsteel.data.Prompt> = listOf(p)): View {
        val ownById = own.associateBy { it.taskId }
        val card = Ui.vertical(ctx, 12).apply {
            background = Ui.rounded(Ui.CRIMSON_DARK, Ui.dpf(ctx, 10f), if (p.waiting) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 2))
        }
        card.addView(Ui.text(ctx, p.headline ?: p.title, 19f, Ui.GOLD, bold = true))
        val lines = p.allRolls.ifEmpty {
            val r = p.roll!!
            listOf(com.dividetask.crimsonsteel.data.RollLine(p.taskId, "", r.name, r.diceCount, r.tn, r.startingValue,
                r.positiveReroll, r.negativeReroll, p.status, p.summary, what = r.name))
        }
        for (line in lines) {
            val mineP = ownById[line.taskId]
            val mine = mineP != null
            val label = (if (mine) "" else "${line.owner} ") + listOf(line.what.ifBlank { line.name }, Ui.signed(line.bonus)).joinToString(" ")
            card.addView(Ui.text(ctx, label, 16f, if (mine) Ui.TEXT else Ui.TEXT_DIM, bold = true), Ui.matchWidth(Ui.dp(ctx, 12)))
            card.addView(Ui.text(ctx, RollFlow.paramsLine(line.diceCount, line.tn, line.startingValue) +
                luckText(line.positiveReroll, line.negativeReroll), 12f, Ui.TEXT_FAINT))
            // Under the action the dice read by result (Success green, Critical blue,
            // a 1 red); the roller's own colour is for dice rolled on the dice table.
            val dice = DiceView(ctx).apply { perRow = 8; bodyColor = CARD_BLANK; colorByResult = true }
            card.addView(dice, Ui.matchWidth(Ui.dp(ctx, 4)))
            val result = Ui.text(ctx, "", 13f, Ui.TEXT_DIM)
            card.addView(result, Ui.matchWidth())

            val final = line.final
            if (final != null) {
                // One row of final dice; small dice in the corners show the first throw / pre-nudge values.
                dice.showHistory(line.dice ?: final, line.rerolled, final, line.tn)
                result.text = resultText(line, final)
                // Someone else's dice just arrived: throw them on the dice table in their colour.
                if (line.taskId !in shownRolling) {
                    shownRolling += line.taskId
                    (ctx as? android.app.Activity)?.let { act ->
                        RollTable.throwDice(act, p.flowId, zonesFor(p), line.taskId, line.dice ?: final, line.rerolled,
                            final, line.tn, line.startingValue, title = p.actionLine ?: p.headline, failureModifier = line.failureModifier)
                    }
                }
            } else {
                dice.showBlank(line.diceCount)
                val inFlight = mine && line.taskId in shownRolling
                result.text = when {
                    inFlight -> "Rolling\u2026"
                    mine -> ""
                    else -> "waiting to roll"
                }
                if (mineP != null && mineP.waiting && !inFlight) {
                    card.addView(Button(ctx).apply {
                        text = "Roll"
                        isEnabled = !busy
                        setOnClickListener { isEnabled = false; rollMine(mineP, line, dice, result) }
                    }, Ui.matchWidth(Ui.dp(ctx, 6)))
                }
            }
        }
        if (p.status == "submitted") {
            card.addView(Ui.text(ctx, "Sent \u2014 waiting for the DM to approve.", 12f, Ui.TEXT_FAINT), Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        // Watch the dice again: the same results, a fresh throw.
        if (lines.any { it.final != null }) {
            card.addView(Button(ctx).apply {
                text = "Repeat"
                setOnClickListener { repeatThrow(p, lines) }
            }, Ui.matchWidth(Ui.dp(ctx, 10)))
        }
        return card
    }

    /** Throw every Roll of the action that has its dice again, on a fresh dice table. */
    private fun repeatThrow(p: com.dividetask.crimsonsteel.data.Prompt, lines: List<com.dividetask.crimsonsteel.data.RollLine>) {
        val act = ctx as? android.app.Activity ?: return
        RollTable.clear()
        val zones = zonesFor(p)
        for (line in lines) {
            val final = line.final ?: continue
            RollTable.throwDice(act, p.flowId, zones, line.taskId, line.dice ?: final, line.rerolled, final,
                line.tn, line.startingValue, title = p.actionLine ?: p.headline, failureModifier = line.failureModifier)
        }
    }

    private fun resultText(line: com.dividetask.crimsonsteel.data.RollLine, final: List<Int>): String {
        val n = line.successes ?: com.dividetask.crimsonsteel.dice.DiceRules.dois(final, line.tn, line.startingValue, line.failureModifier)
        val crits = final.count { it == com.dividetask.crimsonsteel.dice.DiceConfig.DIE_SIZE }
        val waiting = if (line.status == "submitted") " (waiting for the DM)" else ""
        return "$n ${if (kotlin.math.abs(n) == 1) "success" else "successes"}" +
            (if (crits > 0) " \u00b7 $crits crit${if (crits == 1) "" else "s"}" else "") + waiting
    }

    /**
     * The player throws their dice across the dice table (then any Luck
     * rerolls); when they stop, the result goes to the DM.
     */
    private fun rollMine(p: com.dividetask.crimsonsteel.data.Prompt, line: com.dividetask.crimsonsteel.data.RollLine,
                         view: DiceView, result: android.widget.TextView) {
        val rng = kotlin.random.Random.Default
        val die = { rng.nextInt(1, com.dividetask.crimsonsteel.dice.DiceConfig.DIE_SIZE + 1) }
        // Rolled as usual, then — before Luck — landed where the DM wants it, if anywhere.
        val initial = com.dividetask.crimsonsteel.dice.DiceRules.fudge(
            List(line.diceCount) { die() }, line.tn, line.startingValue, p.roll?.fudge)
        val (final, rerolled) = com.dividetask.crimsonsteel.dice.DiceRules.applyRerolls(
            initial, line.tn, line.positiveReroll, line.negativeReroll, die)
        shownRolling += line.taskId
        result.text = "Rolling\u2026"
        val act = ctx as? android.app.Activity ?: return
        RollTable.throwDice(act, p.flowId, zonesFor(p), line.taskId, initial, rerolled, final, line.tn, line.startingValue,
            title = p.actionLine ?: p.headline, failureModifier = line.failureModifier) {
            view.showHistory(initial, rerolled, final, line.tn)
            result.text = resultText(line, final) + " \u2014 sending to the DM\u2026"
            Session.submitRoll(p.flowId, p.taskId, initial, rerolled, final) { r ->
                if (r.isFailure) shownRolling -= line.taskId // not sent: let them try again
                afterChange(r)
            }
        }
    }

    /** ", reroll +1 / −2" for Luck on a roll, or "". */
    private fun luckText(positive: Int, negative: Int): String = buildList {
        if (positive > 0) add("+$positive")
        if (negative > 0) add("\u2212$negative")
    }.let { if (it.isEmpty()) "" else ", Luck reroll ${it.joinToString(" / ")}" }

    private fun choiceChip(label: String, on: Boolean, enabled: Boolean, onTap: () -> Unit): View =
        Ui.text(ctx, label, 14f, if (enabled) Ui.TEXT else Ui.TEXT_FAINT, bold = on).apply {
            setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 10), Ui.dp(ctx, 12), Ui.dp(ctx, 10))
            background = Ui.rounded(if (on) Ui.CRIMSON else Ui.BG, Ui.dpf(ctx, 8f), if (on) Ui.GOLD else Ui.SURFACE_HI, Ui.dp(ctx, 1))
            if (enabled) Ui.makeTappable(this, ctx, onTap)
        }
}
