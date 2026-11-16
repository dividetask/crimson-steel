package com.dividetask.crimsonsteel.dice

import org.junit.Assert.assertEquals
import org.junit.Test

class CombatRulesTest {

    @Test fun firstStepIsFree() {
        assertEquals(4, CombatRules.combatPool(0, 0, 1))
    }

    @Test fun poolMatchesClosedForm() {
        // Closed form from the design: cost(P) = Step * T*(T-1)/2 + R * T, T = P / Step, R = P % Step.
        fun cost(p: Int): Int { val t = p / 4; val r = p % 4; return 4 * t * (t - 1) / 2 + r * t }
        for (budget in 0..80) {
            val p = CombatRules.combatPool(0, budget, 1)
            assert(cost(p) <= budget) { "budget $budget pool $p over" }
            assert(cost(p + 1) > budget) { "budget $budget pool $p not maximal" }
        }
    }

    @Test fun dummyRangerPool() {
        // Martial 3 ranks, Wisdom 15, Tier 1: budget 21 -> 15 dice.
        assertEquals(15, CombatRules.combatPool(3, 15, 1))
    }

    @Test fun higherTierDividesBudget() {
        // Tier 3 takes 2 turns per round: budget floor(21 / 2) = 10 -> 11 dice (4 free + 4 at 1 + 3 at 2).
        assertEquals(11, CombatRules.combatPool(3, 15, 3))
    }
}
