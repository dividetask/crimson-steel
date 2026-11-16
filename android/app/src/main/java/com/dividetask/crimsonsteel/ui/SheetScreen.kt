package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.dividetask.crimsonsteel.data.Attribute
import com.dividetask.crimsonsteel.data.Character
import com.dividetask.crimsonsteel.data.Game
import com.dividetask.crimsonsteel.dice.RollRequest

/** Character sheet: vitals, Attributes (Check + Save), Skills, Abilities. Tap any roll to roll it. */
object SheetScreen {

    fun build(ctx: Context, c: Character): View {
        val col = Ui.vertical(ctx, 12)

        col.addView(Ui.text(ctx, "${c.summary} · Tier ${c.tier} · Speed ${c.speed}", 14f, Ui.TEXT_DIM))

        // --- Vitals -----------------------------------------------------------
        val v = c.vitals
        val vitals = Ui.horizontal(ctx)
        vitals.addView(stat(ctx, "HP", "${v.hp}/${v.hpMax}"), statParams(ctx))
        vitals.addView(stat(ctx, "Mana", "${Game.turn.mana}/${v.manaMax}"), statParams(ctx))
        vitals.addView(stat(ctx, "Toxicity", "${v.toxicity}/${v.toxicityThreshold}"), statParams(ctx, last = true))
        col.addView(vitals, Ui.matchWidth(Ui.dp(ctx, 10)))
        val defense = Ui.horizontal(ctx)
        defense.addView(stat(ctx, "Damage Reduction", "${v.damageReduction}"), statParams(ctx))
        defense.addView(stat(ctx, "Damage Resilience", "${v.damageResilience}"), statParams(ctx, last = true))
        col.addView(defense, Ui.matchWidth(Ui.dp(ctx, 6)))

        // --- Attributes -------------------------------------------------------
        col.addView(Ui.sectionHeader(ctx, "Attributes — tap to roll"))
        val attrCard = Ui.card(ctx)
        for (a in Attribute.entries) {
            val row = Ui.horizontal(ctx).apply { setPadding(0, Ui.dp(ctx, 4), 0, Ui.dp(ctx, 4)) }
            val label = Ui.text(ctx, a.abbr, 15f, Ui.TEXT, bold = true)
            row.addView(label, LinearLayout.LayoutParams(Ui.dp(ctx, 48), LinearLayout.LayoutParams.WRAP_CONTENT))
            row.addView(
                Ui.text(ctx, c.attributes.getValue(a).toString(), 15f, Ui.TEXT),
                LinearLayout.LayoutParams(Ui.dp(ctx, 36), LinearLayout.LayoutParams.WRAP_CONTENT),
            )
            row.addView(rollChip(ctx, "Check", c.attributeCheck(a), c.name), Ui.weighted().apply { marginEnd = Ui.dp(ctx, 6) })
            row.addView(rollChip(ctx, "Save", c.save(a), c.name), Ui.weighted())
            attrCard.addView(row, Ui.matchWidth())
        }
        col.addView(attrCard, Ui.matchWidth())

        // --- Skills -----------------------------------------------------------
        col.addView(Ui.sectionHeader(ctx, "Skills — tap to roll"))
        val skillCard = Ui.card(ctx).apply { setPadding(0, Ui.dp(ctx, 4), 0, Ui.dp(ctx, 4)) }
        val header = Ui.horizontal(ctx).apply { setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 4), Ui.dp(ctx, 12), Ui.dp(ctx, 4)) }
        header.addView(Ui.text(ctx, "Skill", 12f, Ui.TEXT_FAINT), Ui.weighted())
        header.addView(numCell(ctx, "Ranks", 12f, Ui.TEXT_FAINT))
        header.addView(numCell(ctx, "Dice", 12f, Ui.TEXT_FAINT))
        header.addView(numCell(ctx, "Bonus", 12f, Ui.TEXT_FAINT))
        skillCard.addView(header, Ui.matchWidth())
        for (s in c.skills) {
            val req = c.skillRoll(s)
            val trained = s.ranks > 0
            val color = if (trained) Ui.TEXT else Ui.TEXT_DIM
            val row = Ui.horizontal(ctx).apply {
                setPadding(Ui.dp(ctx, 12), Ui.dp(ctx, 9), Ui.dp(ctx, 12), Ui.dp(ctx, 9))
            }
            val name = Ui.horizontal(ctx)
            name.addView(Ui.text(ctx, s.name, 15f, color, bold = trained))
            name.addView(Ui.text(ctx, "  ${s.attribute.abbr}", 11f, Ui.TEXT_FAINT))
            row.addView(name, Ui.weighted())
            row.addView(numCell(ctx, s.ranks.toString(), 14f, color))
            row.addView(numCell(ctx, "${req.inputs.diceCap}d", 14f, color))
            row.addView(numCell(ctx, Ui.signed(req.inputs.bonus), 14f, color))
            Ui.makeTappable(row, ctx) { RollFlow.start(ctx, c.name, req) }
            skillCard.addView(row, Ui.matchWidth())
        }
        col.addView(skillCard, Ui.matchWidth())

        // --- Abilities (descriptive; tap to expand) -----------------------------
        col.addView(Ui.sectionHeader(ctx, "Abilities"))
        val abilityCard = Ui.card(ctx)
        for (ab in c.abilities) {
            val item = Ui.vertical(ctx).apply { setPadding(0, Ui.dp(ctx, 6), 0, Ui.dp(ctx, 6)) }
            val title = Ui.text(ctx, "▸ ${ab.name}", 15f, Ui.TEXT, bold = true)
            val body = Ui.text(ctx, ab.description, 14f, Ui.TEXT_DIM).apply {
                visibility = View.GONE
                setPadding(Ui.dp(ctx, 16), Ui.dp(ctx, 4), 0, 0)
            }
            item.addView(title)
            item.addView(body)
            Ui.makeTappable(item, ctx) {
                val open = body.visibility != View.VISIBLE
                body.visibility = if (open) View.VISIBLE else View.GONE
                title.text = "${if (open) "▾" else "▸"} ${ab.name}"
            }
            abilityCard.addView(item, Ui.matchWidth())
        }
        col.addView(abilityCard, Ui.matchWidth())

        return ScrollView(ctx).apply { addView(col) }
    }

    private fun stat(ctx: Context, label: String, value: String): View =
        Ui.card(ctx).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(Ui.dp(ctx, 6), Ui.dp(ctx, 8), Ui.dp(ctx, 6), Ui.dp(ctx, 8))
            addView(Ui.text(ctx, value, 18f, Ui.TEXT, bold = true))
            addView(Ui.text(ctx, label, 11f, Ui.TEXT_DIM))
        }

    private fun statParams(ctx: Context, last: Boolean = false) =
        Ui.weighted().apply { if (!last) marginEnd = Ui.dp(ctx, 6) }

    private fun numCell(ctx: Context, s: String, size: Float, color: Int): TextView =
        Ui.text(ctx, s, size, color).apply {
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(Ui.dp(ctx, 52), LinearLayout.LayoutParams.WRAP_CONTENT)
        }

    private fun rollChip(ctx: Context, label: String, req: RollRequest, characterName: String): View {
        val chip = Ui.horizontal(ctx).apply {
            background = Ui.rounded(Ui.SURFACE_HI, Ui.dpf(ctx, 8f))
            setPadding(Ui.dp(ctx, 10), Ui.dp(ctx, 8), Ui.dp(ctx, 10), Ui.dp(ctx, 8))
        }
        chip.addView(Ui.text(ctx, label, 13f, Ui.TEXT_DIM), Ui.weighted())
        chip.addView(Ui.text(ctx, "${req.inputs.diceCap}d ${Ui.signed(req.inputs.bonus)}", 14f, Ui.TEXT, bold = true))
        Ui.makeTappable(chip, ctx) { RollFlow.start(ctx, characterName, req) }
        return chip
    }
}
