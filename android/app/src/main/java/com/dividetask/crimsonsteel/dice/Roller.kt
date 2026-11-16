package com.dividetask.crimsonsteel.dice

import kotlin.random.Random

/** A Roll the player can make from the character sheet. */
data class RollRequest(
    val name: String,
    val inputs: RollInputs,
) {
    /** The Competency entry Proficiencies would add to the Roll's bonus_penalty_list. */
    val modifiers: List<Modifier>
        get() = if (inputs.bonus != 0) listOf(Modifier("Competency", inputs.bonus)) else emptyList()

    val target: TargetNumber get() = DiceRules.computeTn(modifiers)
}

enum class RollVisibility(val label: String) {
    /** Sent to the DM's Roll Log (once the app is connected to the server). */
    PUBLIC("Public roll"),

    /** Only shown on this device; never sent anywhere. */
    TEST("Test roll"),
}

data class RollResult(
    val request: RollRequest,
    val visibility: RollVisibility,
    val tn: Int,
    val startingValue: Int,
    val dice: List<Int>,
    val dois: Int,
    val criticalCount: Int,
    val outcome: Outcome,
    val at: Long = System.currentTimeMillis(),
)

object Roller {
    fun roll(request: RollRequest, visibility: RollVisibility, random: Random = Random.Default): RollResult {
        val target = request.target
        val dice = List(request.inputs.diceCap) { random.nextInt(1, DiceConfig.DIE_SIZE + 1) }
        val dois = DiceRules.dois(dice, target.tn, target.startingValue)
        return RollResult(
            request = request,
            visibility = visibility,
            tn = target.tn,
            startingValue = target.startingValue,
            dice = dice,
            dois = dois,
            criticalCount = dice.count { it == DiceConfig.DIE_SIZE },
            outcome = DiceRules.outcome(dois),
        )
    }
}

/**
 * Where public rolls go. Offline for now: rolls are only kept in memory.
 * When the app is connected this becomes a POST to the server's /dm/roll
 * (the same endpoint the web sheet's compact roll uses).
 */
object RollLog {
    private val entries = mutableListOf<RollResult>()

    val recent: List<RollResult> get() = entries.asReversed().toList()

    fun record(result: RollResult) {
        if (result.visibility == RollVisibility.PUBLIC) entries.add(result)
    }

    const val CONNECTED = false
}
