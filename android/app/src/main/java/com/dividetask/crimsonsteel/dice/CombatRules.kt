package com.dividetask.crimsonsteel.dice

/**
 * Player-side combat economy, mirroring docs/common/encounter/encounter_design.md
 * and encounter_config.yaml. Copied values; fetch from the server once connected.
 */
object CombatConfig {
    const val COMBAT_POOL_STEP = 4
    val TURNS_PER_ROUND = intArrayOf(1, 1, 1, 2, 4, 8)
    const val MAIN_ACTIONS_PER_TURN = 2
    const val MAIN_ACTION_MINIMUM = 4
    const val BONUS_ACTION_MINIMUM = 2
    const val FREE_ACTION_MINIMUM = 0
    const val MOVE_COST = 4
    /** Weapon attacks offer dice counts from 2 up to the Martial Dice Cap (as the web Attack step does). */
    const val ATTACK_MINIMUM_DICE = 2

    /** Mana Cost Per Tier (abilities_config.yaml). */
    val MANA_COST_PER_TIER = intArrayOf(1, 4, 6, 8, 10, 12)
}

enum class ActionCategory(val label: String) {
    MAIN("Main Action"),
    BONUS("Bonus Action"),
    FREE("Free Action"),
}

object CombatRules {

    /**
     * Combat Pool computation. Budget = floor((martial ranks * 2 + Combat Pool
     * Attribute) / Turns Per Round[tier]). Points 1..Step are free; each later
     * block of Step points costs one more per point than the block before.
     */
    fun combatPool(martialRanks: Int, poolAttribute: Int, tier: Int): Int {
        require(tier in CombatConfig.TURNS_PER_ROUND.indices) { "Tier $tier has no Turns Per Round entry" }
        val budget = Math.floorDiv(martialRanks * 2 + poolAttribute, CombatConfig.TURNS_PER_ROUND[tier])
        var points = 0
        var spent = 0
        while (true) {
            val price = points / CombatConfig.COMBAT_POOL_STEP   // cost of the next point
            if (spent + price > budget) return points
            spent += price
            points++
        }
    }

    /** Combat Pool cost of an action: flat Speed plus one per die. */
    fun poolCost(speed: Int, dice: Int): Int = speed + dice
}
