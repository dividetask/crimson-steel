package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.dividetask.crimsonsteel.data.Sheet
import com.dividetask.crimsonsteel.dice.RollSpec
import com.dividetask.crimsonsteel.net.Session

/** Character sheet: vitals, Attributes (Check + Save), Skills, Abilities. Tap any roll to roll it. */
class SheetScreen(ctx: Context, onError: (Throwable) -> Unit) : LiveScreen<Sheet>(ctx, onError) {

    private val expandedAbilities = mutableSetOf<String>()

    override fun fetch(done: (Result<Pair<Sheet, String>>) -> Unit) = Session.sheet(done)

    override fun build(d: Sheet): View {
        val col = Ui.vertical(ctx, 12)
        val tier = d.tier?.let { " · Tier $it" } ?: ""
        col.addView(Ui.text(ctx, "${d.summary}$tier · Speed ${d.speed}", 14f, Ui.TEXT_DIM))

        // --- Vitals -----------------------------------------------------------
        val vitals = Ui.horizontal(ctx)
        val hp = d.hp?.let { "${it.current}/${it.max}" + if (d.tempHp > 0) " +${d.tempHp}" else "" } ?: "—"
        vitals.addView(stat("HP", hp), statParams())
        vitals.addView(stat("Mana", d.mana?.let { "${it.current}/${it.max}" } ?: "—"), statParams())
        vitals.addView(stat("Toxicity", d.toxicity?.let { "${it.current}/${it.max}" } ?: "—"), statParams(last = true))
        col.addView(vitals, Ui.matchWidth(Ui.dp(ctx, 10)))
        val defense = Ui.horizontal(ctx)
        defense.addView(stat("Damage Reduction", "${d.damageReduction}"), statParams())
        defense.addView(stat("Damage Resilience", "${d.damageResilience}"), statParams(last = true))
        col.addView(defense, Ui.matchWidth(Ui.dp(ctx, 6)))

        // --- Attributes -------------------------------------------------------
        col.addView(Ui.sectionHeader(ctx, "Attributes — tap to roll"))
        val attrCard = Ui.card(ctx)
        for (a in d.attributes) {
            val row = Ui.horizontal(ctx).apply { setPadding(0, Ui.dp(ctx, 4), 0, Ui.dp(ctx, 4)) }
            row.addView(Ui.text(ctx, a.key.uppercase(), 15f, Ui.TEXT, bold = true),
                LinearLayout.LayoutParams(Ui.dp(ctx, 48), LinearLayout.LayoutParams.WRAP_CONTENT))
            row.addView(Ui.text(ctx, a.score.toString(), 15f, Ui.TEXT),
                LinearLayout.LayoutParams(Ui.dp(ctx, 36), LinearLayout.LayoutParams.WRAP_CONTENT))
            row.addView(rollChip("Check", a.check, d.name), Ui.weighted().apply { marginEnd = Ui.dp(ctx, 6) })
            row.addView(rollChip("Save", a.save, d.name), Ui.weighted())
            attrCard.addView(row, Ui.matchWidth())
        }
        col.addView(attrCard, Ui.matchWidth())

        // --- Skills -----------------------------------------------------------
        col.addView(Ui.sectionHeader(ctx, "Skills — tap to roll"))
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
            s.roll?.let { spec -> Ui.makeTappable(row, ctx) { RollFlow.start(ctx, d.name, spec) } }
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

    private fun stat(label: String, value: String): View =
        Ui.card(ctx).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(Ui.dp(ctx, 6), Ui.dp(ctx, 8), Ui.dp(ctx, 6), Ui.dp(ctx, 8))
            addView(Ui.text(ctx, value, 18f, Ui.TEXT, bold = true))
            addView(Ui.text(ctx, label, 11f, Ui.TEXT_DIM))
        }

    private fun statParams(last: Boolean = false) =
        Ui.weighted().apply { if (!last) marginEnd = Ui.dp(ctx, 6) }

    private fun numCell(s: String, size: Float, color: Int): TextView =
        Ui.text(ctx, s, size, color).apply {
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(Ui.dp(ctx, 52), LinearLayout.LayoutParams.WRAP_CONTENT)
        }

    /** Check / Save chip showing the Dice Count and the TN it rolls against. */
    private fun rollChip(label: String, spec: RollSpec?, characterName: String): View {
        val chip = Ui.horizontal(ctx).apply {
            background = Ui.rounded(Ui.SURFACE_HI, Ui.dpf(ctx, 8f))
            setPadding(Ui.dp(ctx, 10), Ui.dp(ctx, 8), Ui.dp(ctx, 10), Ui.dp(ctx, 8))
        }
        chip.addView(Ui.text(ctx, label, 13f, Ui.TEXT_DIM), Ui.weighted())
        chip.addView(Ui.text(ctx, spec?.let { "${it.diceCount}d · TN ${it.tn}" } ?: "—", 14f, Ui.TEXT, bold = true))
        if (spec != null) Ui.makeTappable(chip, ctx) { RollFlow.start(ctx, characterName, spec) }
        return chip
    }
}
