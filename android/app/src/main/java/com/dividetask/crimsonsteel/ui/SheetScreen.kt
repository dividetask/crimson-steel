package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.dividetask.crimsonsteel.data.Sheet
import com.dividetask.crimsonsteel.data.StatMath
import com.dividetask.crimsonsteel.dice.RollSpec
import com.dividetask.crimsonsteel.net.Session

/**
 * Character sheet: vitals, Attributes (Check + Save), Skills, Abilities. Tap
 * any roll to roll it. With "?" on, a tap shows the math behind the number
 * instead ([MathDialog]).
 */
class SheetScreen(ctx: Context, onError: (Throwable) -> Unit) : LiveScreen<Sheet>(ctx, onError) {

    private val expandedAbilities = mutableSetOf<String>()

    /** "?" is on: taps explain instead of rolling. */
    private var explain = false

    override fun fetch(done: (Result<Pair<Sheet, String>>) -> Unit) = Session.sheet(done)

    /** The summary line, and "?" at the top right; pinned so "?" can be turned off from anywhere. */
    override fun buildHeader(d: Sheet): View {
        val row = Ui.horizontal(ctx).apply {
            setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 4), Ui.dp(ctx, 8), Ui.dp(ctx, 4))
        }
        val tier = d.tier?.let { " · Tier $it" } ?: ""
        row.addView(Ui.text(ctx, "${d.summary}$tier · Speed ${d.speed}", 14f, Ui.TEXT_DIM), Ui.weighted())
        if (d.hasMath) {
            val help = Ui.text(ctx, "?", 18f, if (explain) Ui.BG else Ui.GOLD, bold = true).apply {
                gravity = Gravity.CENTER
                contentDescription = "Show the math"
                background = Ui.rounded(if (explain) Ui.GOLD else Ui.SURFACE_HI, Ui.dpf(ctx, 20f), Ui.GOLD, Ui.dp(ctx, 1))
            }
            Ui.makeTappable(help, ctx) {
                explain = !explain
                render()
            }
            row.addView(help, LinearLayout.LayoutParams(Ui.dp(ctx, 40), Ui.dp(ctx, 40)))
        }
        return row
    }

    override fun build(d: Sheet): View {
        val col = Ui.vertical(ctx, 12)
        val tapFor = if (explain) "tap for the math" else "tap to roll"

        // --- Vitals -----------------------------------------------------------
        val vitals = Ui.horizontal(ctx)
        val hp = d.hp?.let { "${it.current}/${it.max}" + if (d.tempHp > 0) " +${d.tempHp}" else "" } ?: "—"
        vitals.addView(stat("HP", hp, d.math["hp"]), statParams())
        vitals.addView(stat("Mana", d.mana?.let { "${it.current}/${it.max}" } ?: "—", d.math["mana"]), statParams())
        vitals.addView(stat("Toxicity", d.toxicity?.let { "${it.current}/${it.max}" } ?: "—", d.math["toxicity"]),
            statParams(last = true))
        col.addView(vitals, Ui.matchWidth())
        val defense = Ui.horizontal(ctx)
        defense.addView(stat("Damage Reduction", "${d.damageReduction}", d.math["damage_reduction"]), statParams())
        defense.addView(stat("Damage Resilience", "${d.damageResilience}", d.math["damage_resilience"]),
            statParams(last = d.combatPool == null))
        d.combatPool?.let { defense.addView(stat("Combat Pool", "$it", d.math["combat_pool"]), statParams(last = true)) }
        col.addView(defense, Ui.matchWidth(Ui.dp(ctx, 6)))

        // --- Attributes -------------------------------------------------------
        col.addView(Ui.sectionHeader(ctx, "Attributes — $tapFor"))
        val attrCard = Ui.card(ctx)
        for (a in d.attributes) {
            val row = Ui.horizontal(ctx).apply { setPadding(0, Ui.dp(ctx, 4), 0, Ui.dp(ctx, 4)) }
            // Key and score share one tap target: the score's own math.
            val score = Ui.horizontal(ctx).apply { setPadding(0, Ui.dp(ctx, 8), 0, Ui.dp(ctx, 8)) }
            score.addView(Ui.text(ctx, a.key.uppercase(), 15f, Ui.TEXT, bold = true),
                LinearLayout.LayoutParams(Ui.dp(ctx, 48), LinearLayout.LayoutParams.WRAP_CONTENT))
            score.addView(Ui.text(ctx, a.score.toString(), 15f, Ui.TEXT),
                LinearLayout.LayoutParams(Ui.dp(ctx, 36), LinearLayout.LayoutParams.WRAP_CONTENT))
            if (explain) a.math?.let { m -> Ui.makeTappable(score, ctx) { MathDialog.show(ctx, m) } }
            row.addView(score)
            row.addView(rollChip("Check", a.check, a.checkMath, d.name), Ui.weighted().apply { marginEnd = Ui.dp(ctx, 6) })
            row.addView(rollChip("Save", a.save, a.saveMath, d.name), Ui.weighted())
            attrCard.addView(row, Ui.matchWidth())
        }
        col.addView(attrCard, Ui.matchWidth())

        // --- Skills -----------------------------------------------------------
        col.addView(Ui.sectionHeader(ctx, "Skills — $tapFor"))
        val skillCard = Ui.card(ctx).apply { setPadding(0, Ui.dp(ctx, 4), 0, Ui.dp(ctx, 4)) }
        val header = Ui.horizontal(ctx).apply { setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 4), Ui.dp(ctx, 12), Ui.dp(ctx, 4)) }
        header.addView(Ui.text(ctx, "Skill", 12f, Ui.TEXT_FAINT), Ui.weighted())
        header.addView(numCell("Ranks", 12f, Ui.TEXT_FAINT))
        header.addView(numCell("Dice", 12f, Ui.TEXT_FAINT))
        header.addView(numCell("Bonus", 12f, Ui.TEXT_FAINT))
        skillCard.addView(header, Ui.matchWidth())
        for (s in d.skills) {
            val color = if (s.trained) Ui.TEXT else Ui.TEXT_DIM
            val row = Ui.horizontal(ctx).apply {
                setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 9), Ui.dp(ctx, 12), Ui.dp(ctx, 9))
            }
            val name = Ui.horizontal(ctx)
            name.addView(Ui.text(ctx, s.name, 15f, color, bold = s.trained))
            name.addView(Ui.text(ctx, "  ${s.attribute.uppercase()}", 11f, Ui.TEXT_FAINT))
            row.addView(name, Ui.weighted())
            row.addView(numCell(s.ranks.toString(), 14f, color))
            row.addView(numCell("${s.dice}d", 14f, color))
            row.addView(numCell(Ui.signed(s.bonus), 14f, color))
            if (explain) {
                s.math?.let { m -> Ui.makeTappable(row, ctx) { MathDialog.show(ctx, m) } }
            } else {
                s.roll?.let { spec -> Ui.makeTappable(row, ctx) { RollFlow.start(ctx, d.name, spec) } }
            }
            skillCard.addView(row, Ui.matchWidth())
        }
        col.addView(skillCard, Ui.matchWidth())

        // --- Abilities (descriptive; tap to expand) -----------------------------
        if (d.abilities.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Abilities"))
            val abilityCard = Ui.card(ctx)
            for (ab in d.abilities) {
                val open = ab.name in expandedAbilities
                val item = Ui.vertical(ctx).apply { setPadding(0, Ui.dp(ctx, 6), 0, Ui.dp(ctx, 6)) }
                item.addView(Ui.text(ctx, "${if (open) "▾" else "▸"} ${ab.name}", 15f, Ui.TEXT, bold = true))
                if (open && ab.description.isNotBlank()) {
                    item.addView(Ui.text(ctx, ab.description, 14f, Ui.TEXT_DIM).apply {
                        setPadding(Ui.dp(ctx, 16), Ui.dp(ctx, 4), 0, 0)
                    })
                }
                Ui.makeTappable(item, ctx) {
                    if (!expandedAbilities.add(ab.name)) expandedAbilities.remove(ab.name)
                    render()
                }
                abilityCard.addView(item, Ui.matchWidth())
            }
            col.addView(abilityCard, Ui.matchWidth())
        }
        return col
    }

    /** A vital. With "?" on and its math known, it is outlined in gold and opens the math. */
    private fun stat(label: String, value: String, math: StatMath?): View {
        val shown = if (explain) math else null
        val card = Ui.card(ctx).apply {
            gravity = Gravity.CENTER
            setPadding(Ui.dp(ctx, 6), Ui.dp(ctx, 8), Ui.dp(ctx, 6), Ui.dp(ctx, 8))
            if (shown != null) background = Ui.rounded(Ui.SURFACE, Ui.dpf(ctx, 10f), Ui.GOLD, Ui.dp(ctx, 1))
            addView(Ui.text(ctx, value, 18f, Ui.TEXT, bold = true))
            addView(Ui.text(ctx, label, 11f, Ui.TEXT_DIM).apply { gravity = Gravity.CENTER })
        }
        if (shown != null) Ui.makeTappable(card, ctx) { MathDialog.show(ctx, shown) }
        return card
    }

    /** Full height, so a card whose label wraps (three across on a phone) does not stand taller than its row. */
    private fun statParams(last: Boolean = false) =
        LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f)
            .apply { if (!last) marginEnd = Ui.dp(ctx, 6) }

    private fun numCell(s: String, size: Float, color: Int): TextView =
        Ui.text(ctx, s, size, color).apply {
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(Ui.dp(ctx, 52), LinearLayout.LayoutParams.WRAP_CONTENT)
        }

    /** Check / Save chip showing the Dice Count and the TN it rolls against. */
    private fun rollChip(label: String, spec: RollSpec?, math: StatMath?, characterName: String): View {
        val chip = Ui.horizontal(ctx).apply {
            background = Ui.rounded(Ui.SURFACE_HI, Ui.dpf(ctx, 8f))
            setPadding(Ui.dp(ctx, 10), Ui.dp(ctx, 8), Ui.dp(ctx, 10), Ui.dp(ctx, 8))
        }
        chip.addView(Ui.text(ctx, label, 13f, Ui.TEXT_DIM), Ui.weighted())
        chip.addView(Ui.text(ctx, spec?.let { "${it.diceCount}d · TN ${it.tn}" } ?: "—", 14f, Ui.TEXT, bold = true))
        if (explain) {
            if (math != null) Ui.makeTappable(chip, ctx) { MathDialog.show(ctx, math) }
        } else if (spec != null) {
            Ui.makeTappable(chip, ctx) { RollFlow.start(ctx, characterName, spec) }
        }
        return chip
    }
}
