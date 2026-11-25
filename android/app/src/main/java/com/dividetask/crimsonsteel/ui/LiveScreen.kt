package com.dividetask.crimsonsteel.ui

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.ScrollView

/**
 * A screen backed by one server endpoint. [refresh] fetches it; the screen is
 * rebuilt only when the server's answer actually changed, so polling does not
 * reset the scroll position or an in-progress selection.
 */
abstract class LiveScreen<T>(protected val ctx: Context, private val onError: (Throwable) -> Unit) {

    private val scroll = ScrollView(ctx).apply { isFillViewport = true }
    /** Pinned under the scrolling content, always in view ([buildFooter]). */
    private val footer = android.widget.FrameLayout(ctx)
    private val root = android.widget.LinearLayout(ctx).apply {
        orientation = android.widget.LinearLayout.VERTICAL
        addView(scroll, android.widget.LinearLayout.LayoutParams(android.view.ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        addView(footer, Ui.matchWidth())
    }
    private var lastJson: String? = null
    protected var data: T? = null
        private set

    val view: View get() = root

    init {
        scroll.addView(Ui.text(ctx, "Loading…", 15f, Ui.TEXT_DIM).apply {
            gravity = Gravity.CENTER
            setPadding(0, Ui.dp(ctx, 40), 0, 0)
        })
    }

    protected abstract fun fetch(done: (Result<Pair<T, String>>) -> Unit)

    protected abstract fun build(d: T): View

    /** What stays in view under the scrolling content, or null for nothing. */
    protected open fun buildFooter(d: T): View? = null

    /**
     * While true (e.g. dice are rolling on screen), new data is kept but the
     * screen is not rebuilt; call [releaseRender] when it is safe again.
     */
    protected open fun holdRender(): Boolean = false
    private var renderPending = false

    protected fun releaseRender() {
        if (renderPending && !holdRender()) {
            renderPending = false
            render()
        }
    }

    fun refresh(force: Boolean = false) {
        fetch { r ->
            r.onSuccess { (d, json) ->
                if (force || json != lastJson) {
                    lastJson = json
                    data = d
                    if (holdRender()) renderPending = true else render()
                }
            }.onFailure(onError)
        }
    }

    /** Rebuild from the current data (e.g. after a local UI state change). */
    protected fun render() {
        val d = data ?: return
        val keepY = scroll.scrollY
        scroll.removeAllViews()
        scroll.addView(build(d))
        footer.removeAllViews()
        buildFooter(d)?.let { footer.addView(it) }
        scroll.post { scroll.scrollTo(0, keepY) }
    }

    /**
     * After the next layout, smoothly scroll so [v] (somewhere inside the
     * screen) sits at the top — e.g. the action the player just picked.
     */
    protected fun scrollToTop(v: View) {
        // Twice posted: after render()'s own restore of the scroll position.
        scroll.post { scroll.post {
            var y = 0
            var cur: View? = v
            while (cur != null && cur !== scroll) {
                y += cur.top
                cur = cur.parent as? View
            }
            if (cur === scroll) scroll.smoothScrollTo(0, (y - Ui.dp(ctx, 8)).coerceAtLeast(0))
        } }
    }

    protected fun toast(msg: String) {
        android.widget.Toast.makeText(ctx, msg, android.widget.Toast.LENGTH_SHORT).show()
    }
}
