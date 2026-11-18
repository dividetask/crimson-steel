package com.dividetask.crimsonsteel.dice

/**
 * Single-Roll mechanics, mirroring docs/common/dice_resolution/dice_resolution_design.md
 * and the Prowess formula in docs/common/proficiencies/proficiencies_design.md.
 *
 * Config values are copied from dice_resolution_config.yaml and
 * proficiencies_config.yaml. Once the app talks to the server these should be
 * fetched from it instead of hard-coded here.
 *
 * Not implemented yet (no dummy Roll uses them): Rerolls, Nudges, Ascendancy.
 */
object DiceConfig {
    const val DIE_SIZE = 10
    const val BASE_TN = 8
    const val MIN_TN = 3
    const val MAX_TN = 9
    const val MIN_DICE = 6
    const val DICE_COUNT_RANGE = 5
    const val SUCCESS_THRESHOLD = 2
    const val FUMBLE_THRESHOLD = 2
    const val FAILURE_MODIFIER = -1
    const val CRITICAL_MODIFIER = 2

    const val ATTRIBUTE_DIVISOR = 2
    const val NON_PROFICIENCY_PENALTY = -2
}

/** One Bonus (positive) or Penalty (negative) entry with its Bonus/Penalty Type. */
data class Modifier(val type: String, val value: Int)

/** Output of "Translate Skill Prowess into Roll inputs". */
data class RollInputs(val diceCap: Int, val bonus: Int)

/** Final TN and Starting Value after stacking and clamping. */
data class TargetNumber(val tn: Int, val startingValue: Int)

enum class DieState { FAILURE, NEUTRAL, SUCCESS, CRITICAL }

enum class Outcome(val label: String) {
    SUCCESS("Success"),
    FAILURE("Failure"),
    FUMBLE("Fumble"),
}

object DiceRules {

    /** Prowess -> {dice_cap, bonus_penalty}. Uses floor division, as the design requires. */
    fun translateProwess(prowess: Int): RollInputs {
        val bonus = Math.floorDiv(prowess, DiceConfig.DICE_COUNT_RANGE)
        val remainder = prowess - bonus * DiceConfig.DICE_COUNT_RANGE
        return RollInputs(DiceConfig.MIN_DICE + remainder, bonus)
    }

    private fun attributeContribution(attribute: Int) =
        Math.floorDiv(attribute, DiceConfig.ATTRIBUTE_DIVISOR)

    /** Attribute Check: Prowess is floor(attribute / 2); no ranks, no penalty. */
    fun attributeCheck(attribute: Int): RollInputs =
        translateProwess(attributeContribution(attribute))

    /** Saving Throw: ranks + floor(attribute / 2). Saves never take the Non-Proficiency Penalty. */
    fun save(ranks: Int, attribute: Int): RollInputs =
        translateProwess(ranks + attributeContribution(attribute))

    /** Skill: ranks + floor(attribute / 2); untrained adds the Non-Proficiency Penalty to the bonus only. */
    fun skill(ranks: Int, attribute: Int): RollInputs {
        val inputs = translateProwess(ranks + attributeContribution(attribute))
        return if (ranks > 0) inputs
        else inputs.copy(bonus = inputs.bonus + DiceConfig.NON_PROFICIENCY_PENALTY)
    }

    /**
     * TN computation: per Bonus/Penalty Type only the highest Bonus and the
     * lowest Penalty count; the sum shifts the Base TN; overflow past the
     * bounds becomes Starting Successes (or Starting Failures).
     */
    fun computeTn(modifiers: List<Modifier>, startingContribution: Int = 0): TargetNumber {
        val net = modifiers.groupBy { it.type }.values.sumOf { entries ->
            val best = entries.filter { it.value > 0 }.maxOfOrNull { it.value } ?: 0
            val worst = entries.filter { it.value < 0 }.minOfOrNull { it.value } ?: 0
            best + worst
        }
        val raw = DiceConfig.BASE_TN - net
        val tn = raw.coerceIn(DiceConfig.MIN_TN, DiceConfig.MAX_TN)
        val overflow = when {
            raw < DiceConfig.MIN_TN -> DiceConfig.MIN_TN - raw
            raw > DiceConfig.MAX_TN -> -(raw - DiceConfig.MAX_TN)
            else -> 0
        }
        return TargetNumber(tn, startingContribution + overflow)
    }

    fun dieState(value: Int, tn: Int): DieState = when {
        value == DiceConfig.DIE_SIZE -> DieState.CRITICAL
        value == 1 -> DieState.FAILURE
        value >= tn -> DieState.SUCCESS
        else -> DieState.NEUTRAL
    }

    fun contribution(value: Int, tn: Int): Int = when (dieState(value, tn)) {
        DieState.CRITICAL -> DiceConfig.CRITICAL_MODIFIER
        DieState.FAILURE -> DiceConfig.FAILURE_MODIFIER
        DieState.SUCCESS -> 1
        DieState.NEUTRAL -> 0
    }

    /** Degree of Individual Success. */
    fun dois(dice: List<Int>, tn: Int, startingValue: Int): Int =
        startingValue + dice.sumOf { contribution(it, tn) }

    fun outcome(dois: Int, canFumble: Boolean = DiceConfig.FAILURE_MODIFIER != 0): Outcome = when {
        canFumble && dois <= -DiceConfig.FUMBLE_THRESHOLD -> Outcome.FUMBLE
        dois >= DiceConfig.SUCCESS_THRESHOLD -> Outcome.SUCCESS
        else -> Outcome.FAILURE
    }

    /**
     * Luck rerolls (dice_resolution_design.md → Reroll; the server's
     * ActionFlow.apply_rerolls): a positive reroll rerolls up to [positive]
     * non-Successes, lowest first; a negative reroll up to [negative]
     * Successes, highest first. Each die is rerolled at most once.
     * Returns the final dice and, per position, the new value or null.
     */
    fun applyRerolls(
        dice: List<Int>, tn: Int, positive: Int, negative: Int,
        roll: () -> Int,
    ): Pair<List<Int>, List<Int?>> {
        val final = dice.toMutableList()
        val rerolled = MutableList<Int?>(dice.size) { null }
        fun pick(count: Int, eligible: (Int) -> Boolean, highestFirst: Boolean) {
            if (count <= 0) return
            val idx = dice.indices.filter { eligible(dice[it]) && rerolled[it] == null }
                .sortedWith(compareBy<Int>({ if (highestFirst) -dice[it] else dice[it] }, { it }))
            for (i in idx.take(count)) {
                val v = roll()
                final[i] = v
                rerolled[i] = v
            }
        }
        pick(negative, { it >= tn }, highestFirst = true)
        pick(positive, { it < tn }, highestFirst = false)
        return Pair(final, rerolled)
    }
}
