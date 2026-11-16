package com.dividetask.crimsonsteel.data

import com.dividetask.crimsonsteel.dice.ActionCategory
import com.dividetask.crimsonsteel.dice.CombatConfig
import com.dividetask.crimsonsteel.dice.CombatRules

enum class ActionKind { ATTACK, MOVE, CAST, ABILITY, END_TURN }

/**
 * One choice in the player's action menu. When [diceChoices] is non-empty the
 * player picks how many dice to commit; otherwise the cost is [fixedPoolCost].
 */
data class ActionOption(
    val label: String,
    val kind: ActionKind,
    val category: ActionCategory,
    val detail: String,
    val diceChoices: List<Int> = emptyList(),
    val speed: Int = 0,
    val fixedPoolCost: Int = 0,
    val manaCost: Int = 0,
) {
    fun poolCost(dice: Int?): Int = if (dice == null) fixedPoolCost else CombatRules.poolCost(speed, dice)
}

/** An action the player has declared this turn (sent to the DM once connected). */
data class DeclaredAction(val option: ActionOption, val dice: Int?, val poolCost: Int) {
    val summary: String
        get() = buildString {
            append(option.label)
            if (dice != null) append(" — $dice dice")
            append(" (pool $poolCost")
            if (option.manaCost > 0) append(", mana ${option.manaCost}")
            append(")")
        }
}

object ActionMenu {

    private fun minimumFor(category: ActionCategory) = when (category) {
        ActionCategory.MAIN -> CombatConfig.MAIN_ACTION_MINIMUM
        ActionCategory.BONUS -> CombatConfig.BONUS_ACTION_MINIMUM
        ActionCategory.FREE -> CombatConfig.FREE_ACTION_MINIMUM
    }

    /** Every action the character can offer on their turn, in menu order. */
    fun options(c: Character): List<ActionOption> {
        val out = mutableListOf<ActionOption>()
        val martialCap = c.skillInputs("martial").diceCap

        for (w in c.weapons) {
            out += ActionOption(
                label = "Attack: ${w.name}",
                kind = ActionKind.ATTACK,
                category = ActionCategory.MAIN,
                detail = "Speed ${w.speed} + 1 per die · up to $martialCap dice (Martial)",
                diceChoices = (CombatConfig.ATTACK_MINIMUM_DICE..martialCap).toList(),
                speed = w.speed,
            )
        }
        out += ActionOption(
            label = "Move",
            kind = ActionKind.MOVE,
            category = ActionCategory.MAIN,
            detail = "Costs ${CombatConfig.MOVE_COST} Combat Pool dice",
            fixedPoolCost = CombatConfig.MOVE_COST,
        )
        for (s in c.spells) {
            val cap = c.skillInputs(s.skillKey).diceCap
            val min = minimumFor(s.category)
            val skillName = c.skill(s.skillKey)?.name ?: s.skillKey
            out += ActionOption(
                label = "Cast: ${s.name}",
                kind = ActionKind.CAST,
                category = s.category,
                detail = "Tier ${s.tier} · ${CombatConfig.MANA_COST_PER_TIER[s.tier]} mana · 1 per die · up to $cap dice ($skillName)",
                diceChoices = if (cap >= min) (min..cap).toList() else emptyList(),
                manaCost = CombatConfig.MANA_COST_PER_TIER[s.tier],
            )
        }
        for (a in c.activeAbilities) {
            val min = minimumFor(a.category)
            out += ActionOption(
                label = a.name,
                kind = ActionKind.ABILITY,
                category = a.category,
                detail = a.summary + if (min > 0) " Costs $min Combat Pool dice." else "",
                fixedPoolCost = min,
                manaCost = a.manaCost,
            )
        }
        out += ActionOption(
            label = "End Turn",
            kind = ActionKind.END_TURN,
            category = ActionCategory.FREE,
            detail = "Finish your turn.",
        )
        return out
    }
}

/**
 * The player's live combat state. Offline: kept in memory and driven by
 * DummyData. Once connected, the server owns this and the app mirrors it.
 */
class TurnState(private val character: Character, initiative: Initiative) {
    val poolMax: Int = character.combatPool
    var poolSpent: Int = 0
        private set
    var mainActionsLeft: Int = CombatConfig.MAIN_ACTIONS_PER_TURN
        private set
    var mana: Int = character.vitals.mana
        private set
    var round: Int = initiative.round
        private set
    var currentIndex: Int = initiative.currentIndex
        private set
    val order: List<InitiativeEntry> = initiative.order
    val declared = mutableListOf<DeclaredAction>()

    /** Whether the full initiative list is shown on your turn (it starts compact). */
    var initiativeExpanded = false

    val poolRemaining: Int get() = poolMax - poolSpent
    val isMyTurn: Boolean get() = order.getOrNull(currentIndex)?.isYou == true

    /** Why [option] can't be taken with [dice] right now, or null if it can. */
    fun blocker(option: ActionOption, dice: Int?): String? = when {
        !isMyTurn -> "It is not your turn."
        option.kind == ActionKind.END_TURN -> null
        option.category == ActionCategory.MAIN && mainActionsLeft <= 0 -> "No Main Actions left."
        option.manaCost > mana -> "Not enough mana."
        option.diceChoices.isNotEmpty() && dice == null -> "Choose how many dice."
        option.poolCost(dice) > poolRemaining -> "Not enough Combat Pool."
        else -> null
    }

    fun declare(option: ActionOption, dice: Int?): DeclaredAction? {
        if (blocker(option, dice) != null) return null
        if (option.kind == ActionKind.END_TURN) {
            endTurn()
            return null
        }
        val cost = option.poolCost(dice)
        poolSpent += cost
        mana -= option.manaCost
        if (option.category == ActionCategory.MAIN) mainActionsLeft--
        return DeclaredAction(option, dice, cost).also { declared += it }
    }

    fun undoLast() {
        val last = declared.removeLastOrNull() ?: return
        poolSpent -= last.poolCost
        mana += last.option.manaCost
        if (last.option.category == ActionCategory.MAIN) mainActionsLeft++
    }

    /** Pass the turn to the next combatant. The pool is not refilled until your next turn starts. */
    private fun endTurn() {
        declared.clear()
        currentIndex = (currentIndex + 1) % order.size
        if (currentIndex == 0) round++
    }

    /** Offline testing aid: jump the initiative to your turn, refilling the pool and Main Actions. */
    fun startMyTurn() {
        val me = order.indexOfFirst { it.isYou }
        if (me < 0) return
        if (me < currentIndex) round++   // wrapping past the top of the order starts a new round
        currentIndex = me
        poolSpent = 0
        mainActionsLeft = CombatConfig.MAIN_ACTIONS_PER_TURN
        declared.clear()
        initiativeExpanded = false
    }
}

/** App-wide session state (lives as long as the process; offline only). */
object Game {
    val character: Character get() = DummyData.character
    val turn: TurnState by lazy { TurnState(DummyData.character, DummyData.initiative) }
}
