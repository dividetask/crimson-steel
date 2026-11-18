package com.dividetask.crimsonsteel.dice

import org.json.JSONArray
import org.json.JSONObject
import kotlin.random.Random

/**
 * A Roll as the server computed it (lib/routes/api.rb → api_roll): Dice Count,
 * final TN and Starting Value already include every Bonus and Penalty, so the
 * app only throws the dice and scores them.
 */
data class RollSpec(
    val name: String,
    val diceCount: Int,
    val tn: Int,
    val startingValue: Int,
    val baseTn: Int,
    val bonusPenaltyList: List<Pair<String, Int>>,
    val ranks: Int,
)

enum class RollVisibility(val label: String) {
    /** Sent to the DM's Roll Log. */
    PUBLIC("Public roll"),

    /** Only shown on this device; never sent anywhere. */
    TEST("Test roll"),
}

data class RollResult(
    val spec: RollSpec,
    val visibility: RollVisibility,
    val dice: List<Int>,
    val dois: Int,
    val criticalCount: Int,
    val outcome: Outcome,
) {
    val tn: Int get() = spec.tn
    val startingValue: Int get() = spec.startingValue

    /** Body for the web's POST /dm/roll (the same fields the web compact roll sends). */
    fun toRollLogJson(creatureId: Int, creatureName: String): JSONObject = JSONObject().apply {
        put("creature_id", creatureId)
        put("creature_name", creatureName)
        put("roll_name", spec.name)
        put("ranks", spec.ranks)
        put("tn", spec.tn)
        put("base_tn", spec.baseTn)
        put("bonus_penalty_list", JSONArray().apply {
            spec.bonusPenaltyList.forEach { (type, v) -> put(JSONArray().put(type).put(v)) }
        })
        put("dice_count", spec.diceCount)
        put("starting_value", spec.startingValue)
        put("dice", JSONArray().apply { dice.forEach { put(it) } })
        put("dois", dois)
        put("critical_count", criticalCount)
    }
}

object Roller {
    fun roll(spec: RollSpec, visibility: RollVisibility, random: Random = Random.Default): RollResult {
        val dice = List(spec.diceCount) { random.nextInt(1, DiceConfig.DIE_SIZE + 1) }
        val dois = DiceRules.dois(dice, spec.tn, spec.startingValue)
        return RollResult(
            spec = spec,
            visibility = visibility,
            dice = dice,
            dois = dois,
            criticalCount = dice.count { it == DiceConfig.DIE_SIZE },
            outcome = DiceRules.outcome(dois),
        )
    }
}
