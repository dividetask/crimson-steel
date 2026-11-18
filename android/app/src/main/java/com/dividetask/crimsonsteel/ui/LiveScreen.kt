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
    private var lastJson: String? = null
    protected var data: T? = null
        private set

    val view: View get() = scroll

    init {
        scroll.addView(Ui.text(ctx, "Loading…", 15f, Ui.TEXT_DIM).apply {
            gravity = Gravity.CENTER
            setPadding(0, Ui.dp(ctx, 40), 0, 0)
        })
    }

    protected abstract fun fetch(done: (Result<Pair<T, String>>) -> Unit)

    protected abstract fun build(d: T): View

    fun refresh(force: Boolean = false) {
        fetch { r ->
            r.onSuccess { (d, json) ->
                if (force || json != lastJson) {
                    lastJson = json
                    data = d
                    render()
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
        scroll.post { scroll.scrollTo(0, keepY) }
    }

    protected fun toast(msg: String) {
        android.widget.Toast.makeText(ctx, msg, android.widget.Toast.LENGTH_SHORT).show()
    }
}
