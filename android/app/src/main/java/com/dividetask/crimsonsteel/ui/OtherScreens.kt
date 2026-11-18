package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.view.View
import com.dividetask.crimsonsteel.data.Notes
import com.dividetask.crimsonsteel.data.Scene
import com.dividetask.crimsonsteel.net.Session

/** Chronicle notes this Character can see, grouped by chapter. Tap a note to expand it. */
class NotesScreen(ctx: Context, onError: (Throwable) -> Unit) : LiveScreen<Notes>(ctx, onError) {

    private val expanded = mutableSetOf<Int>()

    override fun fetch(done: (Result<Pair<Notes, String>>) -> Unit) = Session.notes(done)

    override fun build(d: Notes): View {
        val col = Ui.vertical(ctx, 12)
        if (d.notes.isEmpty()) {
            col.addView(Ui.text(ctx, "No notes yet.", 15f, Ui.TEXT_DIM))
            return col
        }
        var chapter: Int? = -1
        for (n in d.notes) {
            if (n.chapter != chapter) {
                chapter = n.chapter
                val label = n.chapterName?.let { "Chapter ${n.chapter}: $it" } ?: n.chapter?.let { "Chapter $it" } ?: "Unfiled"
                col.addView(Ui.sectionHeader(ctx, label + if (n.chapter == d.currentChapter) " (current)" else ""))
            }
            val open = n.id in expanded
            val card = Ui.card(ctx)
            card.addView(Ui.text(ctx, n.title.ifBlank { "(untitled)" }, 16f, Ui.TEXT, bold = true))
            if (n.type == "creature") card.addView(Ui.text(ctx, "Character of interest", 12f, Ui.GOLD))
            if (n.body.isNotBlank()) {
                card.addView(Ui.text(ctx, n.body, 14f, Ui.TEXT_DIM).apply {
                    if (!open) {
                        maxLines = 2
                        ellipsize = android.text.TextUtils.TruncateAt.END
                    }
                    setPadding(0, Ui.dp(ctx, 6), 0, 0)
                })
            }
            Ui.makeTappable(card, ctx) {
                if (!expanded.add(n.id)) expanded.remove(n.id)
                render()
            }
            col.addView(card, Ui.matchWidth(Ui.dp(ctx, 8)))
        }
        return col
    }
}

/** What is in play right now: the Chronicle entries the DM has made active, plus the in-game time. */
class SceneScreen(ctx: Context, onError: (Throwable) -> Unit) : LiveScreen<Scene>(ctx, onError) {

    override fun fetch(done: (Result<Pair<Scene, String>>) -> Unit) = Session.scene(done)

    override fun build(d: Scene): View {
        val col = Ui.vertical(ctx, 12)
        col.addView(Ui.text(ctx, d.chapter ?: d.campaign ?: "Current scene", 22f, Ui.TEXT, bold = true))
        d.time?.let { col.addView(Ui.text(ctx, it, 13f, Ui.GOLD), Ui.matchWidth(Ui.dp(ctx, 2))) }
        if (d.combatActive) col.addView(Ui.text(ctx, "In combat — see Initiative", 13f, Ui.DIE_FAIL, bold = true),
            Ui.matchWidth(Ui.dp(ctx, 4)))

        if (d.entries.isEmpty()) {
            col.addView(Ui.text(ctx, "Nothing in the scene yet.", 15f, Ui.TEXT_DIM), Ui.matchWidth(Ui.dp(ctx, 14)))
            return col
        }
        val people = d.entries.filter { it.type == "creature" }
        val things = d.entries.filter { it.type != "creature" }
        if (things.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Scene"))
            for (e in things) col.addView(entryCard(e.title, e.body), Ui.matchWidth(Ui.dp(ctx, 6)))
        }
        if (people.isNotEmpty()) {
            col.addView(Ui.sectionHeader(ctx, "Present"))
            for (e in people) col.addView(entryCard(e.title, e.body), Ui.matchWidth(Ui.dp(ctx, 6)))
        }
        return col
    }

    private fun entryCard(title: String, body: String): View = Ui.card(ctx).apply {
        if (title.isNotBlank()) addView(Ui.text(ctx, title, 16f, Ui.TEXT, bold = true))
        if (body.isNotBlank()) addView(Ui.text(ctx, body, 14f, Ui.TEXT_DIM).apply { setLineSpacing(0f, 1.15f) })
    }
}
