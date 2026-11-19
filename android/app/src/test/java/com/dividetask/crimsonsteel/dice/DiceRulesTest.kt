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

    private fun dois(d: List<Int>, tn: Int, sv: Int) = sv + d.sumOf { DiceRules.contribution(it, tn) }

    @Test fun fudgeLandsEveryBandChangingFewDice() {
        val rnd = kotlin.random.Random(7)
        repeat(400) {
            val n = 2 + rnd.nextInt(9)
            val tn = 3 + rnd.nextInt(7)
            val sv = rnd.nextInt(-1, 2)
            val dice = List(n) { rnd.nextInt(1, 11) }
            for (f in listOf("success", "failure", "crit", "fumble")) {
                val out = DiceRules.fudge(dice, tn, sv, f, rnd)
                assertEquals(n, out.size)
                assert(out.all { it in 1..10 })
                // Reachable at all? (e.g. 2 dice with a Starting Value of -1 top out at +3: no Critical.)
                val reachable = when (f) {
                    "success" -> sv + 2 * n >= 2
                    "crit" -> sv + 2 * n >= 4
                    "fumble" -> sv - n <= -2
                    else -> sv - n <= 1 && sv + 2 * n >= -1
                }
                if (reachable) assert(DiceRules.fudgeFits(f, dois(out, tn, sv), out.count { it == 10 })) { "$f: $dice -> $out (tn $tn, sv $sv)" }
                else assertEquals(dice, out)
                if (DiceRules.fudgeFits(f, dois(dice, tn, sv), dice.count { it == 10 })) assertEquals(dice, out)
            }
        }
    }

    @Test fun fudgeChangesTheFewestDice() {
        // TN 7, one success short of Success: one die changes, the rest stay.
        val out = DiceRules.fudge(listOf(8, 3, 4), 7, 0, "success", kotlin.random.Random(1))
        assertEquals(2, out.zip(listOf(8, 3, 4)).count { (a, b) -> a == b })
        assert(dois(out, 7, 0) >= 2)
    }

    @Test fun noFudgeLeavesDiceAlone() {
        assertEquals(listOf(1, 2, 3), DiceRules.fudge(listOf(1, 2, 3), 7, 0, null))
        assertEquals(listOf(1, 2, 3), DiceRules.fudge(listOf(1, 2, 3), 7, 0, "none"))
    }
}
