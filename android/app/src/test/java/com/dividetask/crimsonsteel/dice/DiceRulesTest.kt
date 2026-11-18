package com.dividetask.crimsonsteel.dice

import org.junit.Assert.assertEquals
import org.junit.Test

class DiceRulesTest {

    @Test fun translateProwessFillsDiceThenBonus() {
        assertEquals(RollInputs(6, 0), DiceRules.translateProwess(0))
        assertEquals(RollInputs(10, 0), DiceRules.translateProwess(4))
        assertEquals(RollInputs(6, 1), DiceRules.translateProwess(5))
        assertEquals(RollInputs(8, 1), DiceRules.translateProwess(7))
    }

    @Test fun negativeProwessWrapsToMaxDiceWithPenalty() {
        assertEquals(RollInputs(10, -1), DiceRules.translateProwess(-1))
        assertEquals(RollInputs(6, -1), DiceRules.translateProwess(-5))
    }

    @Test fun untrainedSkillTakesPenaltyButSaveDoesNot() {
        // attribute 14 -> contribution 7 -> 8 dice, +1
        assertEquals(RollInputs(8, -1), DiceRules.skill(0, 14))
        assertEquals(RollInputs(8, 1), DiceRules.save(0, 14))
        assertEquals(RollInputs(9, 1), DiceRules.skill(1, 14))
    }

    @Test fun bonusOverflowBecomesStartingSuccesses() {
        // Explainer example uses Base TN 6; with Base TN 8 a +7 overflows by 2.
        assertEquals(TargetNumber(3, 2), DiceRules.computeTn(listOf(Modifier("Skill", 7))))
    }

    @Test fun penaltyOverflowBecomesStartingFailures() {
        assertEquals(TargetNumber(9, -2), DiceRules.computeTn(listOf(Modifier("Competency", -3))))
    }

    @Test fun sameTypeDoesNotStack() {
        val mods = listOf(Modifier("Skill", 1), Modifier("Skill", 2), Modifier("Equipment", 1))
        assertEquals(TargetNumber(5, 0), DiceRules.computeTn(mods))
    }

    @Test fun scoringMatchesExplainerExample() {
        // 7 6 3 10 1 1 at TN 6 -> +2
        assertEquals(2, DiceRules.dois(listOf(7, 6, 3, 10, 1, 1), 6, 0))
    }

    @Test fun outcomeThresholds() {
        assertEquals(Outcome.SUCCESS, DiceRules.outcome(2))
        assertEquals(Outcome.FAILURE, DiceRules.outcome(0))
        assertEquals(Outcome.FAILURE, DiceRules.outcome(-1))
        assertEquals(Outcome.FUMBLE, DiceRules.outcome(-2))
    }

    @Test fun rerollsMatchTheServerRule() {
        // Same case as spec/action_flow_spec.rb: negative 1 takes the 9, positive 2 the 1 then the 2.
        val (final, rerolled) = DiceRules.applyRerolls(listOf(2, 9, 3, 7, 1), 7, 2, 1) { 6 }
        assertEquals(listOf(6, 6, null, null, 6), rerolled)
        assertEquals(listOf(6, 6, 3, 7, 6), final)
    }

    @Test fun noRerollsLeavesDiceAlone() {
        val (final, rerolled) = DiceRules.applyRerolls(listOf(4, 5), 7, 0, 0) { error("must not roll") }
        assertEquals(listOf(4, 5), final)
        assertEquals(listOf<Int?>(null, null), rerolled)
    }
}
