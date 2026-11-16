package com.dividetask.crimsonsteel.data

import com.dividetask.crimsonsteel.dice.ActionCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TurnStateTest {
    private val c = DummyData.character
    private val options = ActionMenu.options(c)
    private fun opt(label: String) = options.first { it.label == label }

    @Test fun menuListsWeaponsMoveSpellsRageAndEndTurn() {
        val labels = options.map { it.label }
        assertTrue("Attack: Longbow" in labels)
        assertTrue("Move" in labels)
        assertTrue("Cast: Entangle" in labels)
        assertTrue("Rage" in labels)
        assertEquals("End Turn", labels.last())
        assertEquals(ActionCategory.FREE, opt("Rage").category)
    }

    @Test fun attackDiceRunFromTwoToMartialCap() {
        // Martial 3 ranks + floor(18 / 2) = 12 Prowess -> 8 dice.
        assertEquals((2..8).toList(), opt("Attack: Longbow").diceChoices)
        assertEquals(8, opt("Attack: Longbow").poolCost(6))   // Speed 2 + 6 dice
    }

    @Test fun castDiceStartAtMainActionMinimum() {
        // Nature 3 ranks + floor(15 / 2) = 10 Prowess -> 6 dice.
        assertEquals((4..6).toList(), opt("Cast: Entangle").diceChoices)
        assertEquals(4, opt("Cast: Entangle").manaCost)
    }

    @Test fun declaringSpendsPoolMainActionsAndManaAndUndoRestores() {
        val t = TurnState(c, DummyData.initiative)
        assertTrue(t.isMyTurn)
        assertEquals(15, t.poolRemaining)
        assertNotNull(t.declare(opt("Attack: Longbow"), 6))
        assertEquals(7, t.poolRemaining)
        assertEquals(1, t.mainActionsLeft)
        assertNotNull(t.declare(opt("Rage"), null))
        assertEquals(c.vitals.mana - 1, t.mana)
        assertEquals(1, t.mainActionsLeft)          // Rage is a Free Action
        t.undoLast(); t.undoLast()
        assertEquals(15, t.poolRemaining)
        assertEquals(2, t.mainActionsLeft)
        assertEquals(c.vitals.mana, t.mana)
    }

    @Test fun cannotOverspendPoolOrMainActions() {
        val t = TurnState(c, DummyData.initiative)
        assertNotNull(t.declare(opt("Move"), null))
        assertNotNull(t.declare(opt("Move"), null))
        assertEquals("No Main Actions left.", t.blocker(opt("Move"), null))
        assertNull(t.declare(opt("Move"), null))
    }

    @Test fun endTurnPassesInitiative() {
        val t = TurnState(c, DummyData.initiative)
        t.declare(opt("End Turn"), null)
        assertEquals(false, t.isMyTurn)
        t.startMyTurn()
        assertTrue(t.isMyTurn)
        assertEquals(DummyData.initiative.round + 1, t.round)
        assertEquals(15, t.poolRemaining)
    }
}
