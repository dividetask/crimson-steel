package com.dividetask.crimsonsteel.ui

import android.app.AlertDialog
import android.content.Context
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.NumberPicker
import com.dividetask.crimsonsteel.data.Inventory
import com.dividetask.crimsonsteel.data.InventoryRow
import com.dividetask.crimsonsteel.net.Session

/**
 * Inventory: the same three sections and actions as the web sheet's inventory
 * stub (docs/common/ui/equipment_inventory_stub.md):
 *  - Equipped — Unequip.
 *  - Carried — Equip (equippable items), Discard (to the Sell Pile; asks how many).
 *  - Sell Pile — Claim (asks how many), Equip (claim one and equip it).
 * The Sell Pile's Delete stays DM-only, as on the web.
 */
class InventoryScreen(ctx: Context, onError: (Throwable) -> Unit) : LiveScreen<Inventory>(ctx, onError) {

    private var busy = false

    override fun fetch(done: (Result<Pair<Inventory, String>>) -> Unit) = Session.inventory(done)

    override fun build(d: Inventory): View {
        val col = Ui.vertical(ctx, 12)
        section(col, "Equipped", d.equipped, "Nothing equipped.") { row ->
            listOf(action("Unequip") { act(d, "unequip", row, null) })
        }
        section(col, "Carried", d.carried, "Nothing carried.") { row ->
            buildList {
                if (row.equippable) add(action("Equip", primary = true) { act(d, "equip", row, null) })
                add(action("Discard") { withQuantity(row, "Discard") { q -> act(d, "discard", row, q) } })
            }
        }
        section(col, "Sell Pile", d.sellPile, "The Sell Pile is empty.") { row ->
            buildList {
                add(action("Claim") { withQuantity(row, "Claim") { q -> act(d, "claim", row, q) } })
                if (row.equippable) add(action("Equip", primary = true) { act(d, "claim_equip", row, null) })
            }
        }
        col.addView(Ui.text(ctx, "Discarded items go to the Sell Pile, shared by the party.", 12f, Ui.TEXT_FAINT),
            Ui.matchWidth(Ui.dp(ctx, 12)))
        return col
    }

    private fun section(
        col: LinearLayout, title: String, rows: List<InventoryRow>, empty: String,
        actions: (InventoryRow) -> List<View>,
    ) {
        col.addView(Ui.sectionHeader(ctx, title))
        if (rows.isEmpty()) {
            col.addView(Ui.text(ctx, empty, 14f, Ui.TEXT_FAINT).apply { setPadding(Ui.dp(ctx, 4), 0, 0, 0) })
            return
        }
        for (row in rows) {
            val card = Ui.card(ctx)
            val top = Ui.horizontal(ctx)
            top.addView(Ui.text(ctx, row.name, 16f, Ui.TEXT, bold = true), Ui.weighted())
            if (row.quantity > 1) top.addView(Ui.text(ctx, "×${row.quantity}", 15f, Ui.GOLD, bold = true))
            card.addView(top, Ui.matchWidth())
            if (row.category.isNotBlank()) card.addView(Ui.text(ctx, row.category, 12f, Ui.TEXT_DIM))
            val buttons = Ui.horizontal(ctx)
            for (b in actions(row)) buttons.addView(b, Ui.weighted().apply { marginEnd = Ui.dp(ctx, 6) })
            card.addView(buttons, Ui.matchWidth(Ui.dp(ctx, 6)))
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 6)))
        }
    }

    private fun action(label: String, primary: Boolean = false, onTap: () -> Unit): View = Button(ctx).apply {
        text = label
        isEnabled = !busy
        if (primary) setTextColor(Ui.GOLD)
        setOnClickListener { onTap() }
    }

    /** Ask how many when the stack has more than one, as the web's quantity box does. */
    private fun withQuantity(row: InventoryRow, verb: String, then: (Int) -> Unit) {
        if (row.quantity <= 1) return then(1)
        val picker = NumberPicker(ctx).apply {
            minValue = 1
            maxValue = row.quantity
            value = row.quantity
            wrapSelectorWheel = false
        }
        AlertDialog.Builder(ctx, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("$verb how many ${row.name}?")
            .setView(picker)
            .setPositiveButton(verb) { _, _ -> then(picker.value) }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun act(d: Inventory, action: String, row: InventoryRow, quantity: Int?) {
        busy = true
        render()
        Session.inventoryAction(action, d.creatureId, row.index, quantity) { r ->
            busy = false
            r.onFailure { toast("Could not ${action.replace('_', ' ')}: connection problem") }
            refresh(force = true)
        }
    }
}
