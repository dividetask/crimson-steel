package com.dividetask.crimsonsteel.ui

import android.app.AlertDialog
import android.app.Dialog
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.Window
import android.widget.Button
import android.widget.LinearLayout
import com.dividetask.crimsonsteel.dice.RollSpec
import com.dividetask.crimsonsteel.dice.RollResult
import com.dividetask.crimsonsteel.dice.RollVisibility
import com.dividetask.crimsonsteel.dice.Roller
import com.dividetask.crimsonsteel.net.Session

/**
 * Tap a Skill / Check / Save -> ask "Public roll or Test roll?" -> show the
 * dice tumbling, then the result.
 *
 * A public roll is rolled once and cannot be re-rolled from the dialog, the
 * same rule as the web sheet's compact roll (so nobody can fish for a better
 * result). A test roll can be rolled again as often as the player likes.
 */
object RollFlow {

    fun start(ctx: Context, characterName: String, request: RollSpec) {
        val params = paramsLine(request.diceCount, request.tn, request.startingValue)
        AlertDialog.Builder(ctx, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Roll ${request.name}?")
            .setMessage(
                "$params\n\n" +
                    "Public roll: sent to the DM's Roll Log.\n" +
                    "Test roll: only shown on this device.",
            )
            .setPositiveButton(RollVisibility.PUBLIC.label) { _, _ ->
                showRoll(ctx, characterName, request, RollVisibility.PUBLIC)
            }
            .setNeutralButton(RollVisibility.TEST.label) { _, _ ->
                showRoll(ctx, characterName, request, RollVisibility.TEST)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    fun paramsLine(dice: Int, tn: Int, startingValue: Int): String {
        val sv = when {
            startingValue > 0 -> ", R+$startingValue"
            startingValue < 0 -> ", R−${-startingValue}"
            else -> ""
        }
        return "$dice dice @ TN $tn$sv"
    }

    private fun showRoll(ctx: Context, characterName: String, request: RollSpec, visibility: RollVisibility) {
        val dialog = Dialog(ctx, android.R.style.Theme_DeviceDefault_Dialog_NoActionBar)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)

        val root = Ui.vertical(ctx, 18).apply {
            background = Ui.rounded(Ui.BG, Ui.dpf(ctx, 14f), Ui.SURFACE_HI, Ui.dp(ctx, 1))
        }

        val badgeColor = if (visibility == RollVisibility.PUBLIC) Ui.CRIMSON else Ui.SURFACE_HI
        val badgeText = if (visibility == RollVisibility.TEST) "TEST ROLL — not sent" else "PUBLIC ROLL — sending…"
        val badge = Ui.text(ctx, badgeText, 12f, Ui.TEXT, bold = true).apply {
            background = Ui.rounded(badgeColor, Ui.dpf(ctx, 12f))
            setPadding(Ui.dp(ctx, 10), Ui.dp(ctx, 4), Ui.dp(ctx, 10), Ui.dp(ctx, 4))
        }
        root.addView(badge, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
        ))

        root.addView(Ui.text(ctx, characterName, 14f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 12)))
        root.addView(Ui.text(ctx, request.name, 22f, Ui.TEXT, bold = true))
        val paramsView = Ui.text(ctx, "", 14f, Ui.TEXT_DIM)
        root.addView(paramsView)

        val diceView = DiceView(ctx)
        root.addView(diceView, Ui.matchWidth(Ui.dp(ctx, 12)))

        val startingView = Ui.text(ctx, "", 13f, Ui.TEXT_DIM).apply { gravity = Gravity.CENTER }
        root.addView(startingView, Ui.matchWidth())

        val resultView = Ui.text(ctx, " ", 24f, Ui.TEXT, bold = true).apply { gravity = Gravity.CENTER }
        root.addView(resultView, Ui.matchWidth(Ui.dp(ctx, 6)))
        val detailView = Ui.text(ctx, " ", 14f, Ui.TEXT_DIM).apply { gravity = Gravity.CENTER }
        root.addView(detailView, Ui.matchWidth())

        val buttons = Ui.horizontal(ctx).apply { gravity = Gravity.END }
        val again = Button(ctx).apply { text = "Roll again" }
        val close = Button(ctx).apply { text = "Close" }
        if (visibility == RollVisibility.TEST) buttons.addView(again)
        buttons.addView(close)
        root.addView(buttons, Ui.matchWidth(Ui.dp(ctx, 14)))

        fun doRoll() {
            val result = Roller.roll(request, visibility)
            if (visibility == RollVisibility.PUBLIC) {
                // Rolled once, then logged for the DM (POST /dm/roll), like the web compact roll.
                Session.sendRoll(result) { r ->
                    badge.text = if (r.isSuccess) "PUBLIC ROLL — sent to DM" else "PUBLIC ROLL — NOT sent (connection problem)"
                }
            }
            paramsView.text = paramsLine(result.dice.size, result.tn, result.startingValue)
            startingView.text = startingText(result.startingValue)
            resultView.text = " "
            detailView.text = " "
            again.isEnabled = false
            diceView.onSettled = {
                showResult(result, resultView, detailView)
                again.isEnabled = true
            }
            diceView.roll(result.dice, result.tn)
        }

        again.setOnClickListener { doRoll() }
        close.setOnClickListener { dialog.dismiss() }

        dialog.setContentView(root)
        dialog.window?.setLayout(
            (ctx.resources.displayMetrics.widthPixels * 0.94f).toInt(),
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.show()
        doRoll()
    }

    private fun startingText(sv: Int): String = when {
        sv > 0 -> "Starts with $sv free success${if (sv == 1) "" else "es"}"
        sv < 0 -> "Starts with ${-sv} failure${if (sv == -1) "" else "s"}"
        else -> ""
    }

    private fun showResult(r: RollResult, resultView: android.widget.TextView, detailView: android.widget.TextView) {
        val noun = if (kotlin.math.abs(r.dois) == 1) "success" else "successes"
        resultView.text = "${r.dois} $noun — ${r.outcome.label}"
        resultView.setTextColor(
            when (r.outcome) {
                com.dividetask.crimsonsteel.dice.Outcome.SUCCESS -> Ui.DIE_SUCCESS
                com.dividetask.crimsonsteel.dice.Outcome.FUMBLE -> Ui.DIE_FAIL
                com.dividetask.crimsonsteel.dice.Outcome.FAILURE -> Ui.TEXT
            },
        )
        val crits = if (r.criticalCount > 0) " · ${r.criticalCount} crit${if (r.criticalCount == 1) "" else "s"}" else ""
        detailView.text = "Dice: ${r.dice.sortedDescending().joinToString(" ")}$crits"
    }

    /**
     * Roll for an attack step (docs/project/action_flow.md): the dice tumble,
     * then any Luck rerolls tumble on their own, then the result shows and is
     * sent to the DM at once — like a public roll, it cannot be rolled again.
     * [send] posts it and reports whether it arrived.
     */
    fun promptRoll(
        ctx: Context, title: String, roll: com.dividetask.crimsonsteel.data.PromptRoll,
        send: (dice: List<Int>, rerolled: List<Int?>, final: List<Int>, done: (Boolean) -> Unit) -> Unit,
    ) {
        val dialog = Dialog(ctx, android.R.style.Theme_DeviceDefault_Dialog_NoActionBar)
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        val root = Ui.vertical(ctx, 18).apply {
            background = Ui.rounded(Ui.BG, Ui.dpf(ctx, 14f), Ui.SURFACE_HI, Ui.dp(ctx, 1))
        }
        val badge = Ui.text(ctx, "ROLL \u2014 sent to the DM", 12f, Ui.TEXT, bold = true).apply {
            background = Ui.rounded(Ui.CRIMSON, Ui.dpf(ctx, 12f))
            setPadding(Ui.dp(ctx, 10), Ui.dp(ctx, 4), Ui.dp(ctx, 10), Ui.dp(ctx, 4))
        }
        root.addView(badge, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(Ui.text(ctx, title, 22f, Ui.TEXT, bold = true), Ui.matchWidth(Ui.dp(ctx, 12)))
        val luck = buildList {
            if (roll.positiveReroll > 0) add("Luck: reroll up to ${roll.positiveReroll} low dice")
            if (roll.negativeReroll > 0) add("Luck against you: reroll up to ${roll.negativeReroll} high dice")
        }
        root.addView(Ui.text(ctx, paramsLine(roll.diceCount, roll.tn, roll.startingValue) +
            if (luck.isEmpty()) "" else "\n" + luck.joinToString("\n"), 14f, Ui.TEXT_DIM))
        val diceView = DiceView(ctx)
        root.addView(diceView, Ui.matchWidth(Ui.dp(ctx, 12)))
        val stepView = Ui.text(ctx, " ", 13f, Ui.GOLD).apply { gravity = Gravity.CENTER }
        root.addView(stepView, Ui.matchWidth())
        val resultView = Ui.text(ctx, " ", 24f, Ui.TEXT, bold = true).apply { gravity = Gravity.CENTER }
        root.addView(resultView, Ui.matchWidth(Ui.dp(ctx, 6)))
        val statusView = Ui.text(ctx, " ", 13f, Ui.TEXT_DIM).apply { gravity = Gravity.CENTER }
        root.addView(statusView, Ui.matchWidth())
        val close = Button(ctx).apply { text = "Close"; isEnabled = false; setOnClickListener { dialog.dismiss() } }
        root.addView(close, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.END
            topMargin = Ui.dp(ctx, 14)
        })

        val rng = kotlin.random.Random.Default
        val die = { rng.nextInt(1, com.dividetask.crimsonsteel.dice.DiceConfig.DIE_SIZE + 1) }
        val initial = List(roll.diceCount) { die() }
        val (final, rerolled) = com.dividetask.crimsonsteel.dice.DiceRules.applyRerolls(
            initial, roll.tn, roll.positiveReroll, roll.negativeReroll, die)

        fun finish() {
            val dois = com.dividetask.crimsonsteel.dice.DiceRules.dois(final, roll.tn, roll.startingValue)
            val crits = final.count { it == com.dividetask.crimsonsteel.dice.DiceConfig.DIE_SIZE }
            resultView.text = "$dois ${if (kotlin.math.abs(dois) == 1) "success" else "successes"}" +
                if (crits > 0) " \u00b7 $crits crit${if (crits == 1) "" else "s"}" else ""
            statusView.text = "Sending to the DM\u2026"
            send(initial, rerolled, final) { ok ->
                statusView.text = if (ok) "Sent \u2014 waiting for the DM to approve." else "NOT sent (connection problem). The DM can roll for you."
                close.isEnabled = true
            }
        }

        val rerolledAt = rerolled.indices.filter { rerolled[it] != null }.toSet()
        diceView.onSettled = {
            if (rerolledAt.isEmpty()) finish() else {
                stepView.text = "Luck: rerolling ${rerolledAt.size} ${if (rerolledAt.size == 1) "die" else "dice"}"
                diceView.onSettled = { stepView.text = "After Luck"; finish() }
                diceView.postDelayed({ diceView.roll(final, roll.tn, only = rerolledAt) }, 700)
            }
        }
        dialog.setCancelable(false)
        dialog.setContentView(root)
        dialog.window?.setLayout((ctx.resources.displayMetrics.widthPixels * 0.94f).toInt(), ViewGroup.LayoutParams.WRAP_CONTENT)
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialog.show()
        diceView.roll(initial, roll.tn)
    }
}
