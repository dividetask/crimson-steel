package com.dividetask.crimsonsteel.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import com.dividetask.crimsonsteel.data.MapShape
import com.dividetask.crimsonsteel.data.MapSnapshot
import com.dividetask.crimsonsteel.data.MapToken
import com.dividetask.crimsonsteel.debug.DebugLog
import com.dividetask.crimsonsteel.net.Session
import java.io.File
import java.util.concurrent.Executors

/** Map pictures from the server (token icons, terrain textures, map images), kept on disk and in memory. */
object MapImages {
    private val memory = LruCache<String, Bitmap>(64)
    private val failed = HashSet<String>()
    private val loading = HashSet<String>()
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    /** The picture if it is loaded; otherwise starts loading it and calls [ready] when it is. */
    fun get(ctx: Context, path: String, ready: () -> Unit): Bitmap? {
        memory.get(path)?.let { return it }
        synchronized(loading) {
            if (path in failed || !loading.add(path)) return null
        }
        val dir = File(ctx.cacheDir, "map-images").apply { mkdirs() }
        io.execute {
            val file = File(dir, Integer.toHexString(path.hashCode()) + ".img")
            val bmp = runCatching {
                if (!file.exists() || file.length() == 0L) {
                    val api = Session.api ?: throw java.io.IOException("not connected")
                    val encoded = path.split("/").joinToString("/") {
                        java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20")
                    }
                    api.download(encoded, file)
                }
                BitmapFactory.decodeFile(file.path)
            }.onFailure { DebugLog.e("map", "image $path", it) }.getOrNull()
            main.post {
                synchronized(loading) { loading.remove(path); if (bmp == null) failed.add(path) }
                if (bmp != null) { memory.put(path, bmp); ready() }
            }
        }
        return null
    }
}

/**
 * The Active Map for picking a target (docs/project/android_app.md): terrain,
 * grid, tokens and fog, fitted to the width. Tap a token that is a valid
 * target to pick it; others are faded. Pinch to zoom, drag to move.
 */
@SuppressLint("ViewConstructor")
class MapTargetView(
    ctx: Context,
    private val map: MapSnapshot,
    /** Combatant id → shown as an enemy (red ring) or an ally (blue ring). */
    private val selectable: Map<Int, Boolean>,
    private val selected: Int?,
    private val onPick: (Int) -> Unit,
) : View(ctx) {

    private var zoom = 1f
    private var panX = 0f
    private var panY = 0f
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shaderMatrix = Matrix()
    private val redraw: () -> Unit = { invalidate() }

    private val baseCell get() = width.toFloat() / map.width
    private val cell get() = baseCell * zoom

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = (w * map.height.toFloat() / map.width).toInt().coerceAtMost((w * 1.25f).toInt())
        setMeasuredDimension(w, h)
    }

    private val scaler = ScaleGestureDetector(ctx, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean {
            val old = zoom
            zoom = (zoom * d.scaleFactor).coerceIn(1f, 5f)
            val f = zoom / old
            panX = d.focusX - (d.focusX - panX) * f
            panY = d.focusY - (d.focusY - panY) * f
            clampPan(); invalidate()
            return true
        }
    })

    private val gestures = GestureDetector(ctx, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent) = true
        override fun onScroll(e1: MotionEvent?, e2: MotionEvent, dx: Float, dy: Float): Boolean {
            panX -= dx; panY -= dy
            clampPan(); invalidate()
            return true
        }
        override fun onSingleTapUp(e: MotionEvent): Boolean {
            val gx = (e.x - panX) / cell
            val gy = (e.y - panY) / cell
            val hit = map.tokens.lastOrNull { t ->
                t.combatantId != null && selectable.containsKey(t.combatantId) &&
                    gx >= t.x && gx <= t.x + t.size && gy >= t.y && gy <= t.y + t.size
            }
            hit?.combatantId?.let(onPick)
            return hit != null
        }
    })

    private fun clampPan() {
        val mapW = map.width * cell
        val mapH = map.height * cell
        panX = if (mapW <= width) (width - mapW) / 2 else panX.coerceIn(width - mapW, 0f)
        panY = if (mapH <= height) (height - mapH) / 2 else panY.coerceIn(height - mapH, 0f)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        // The map scrolls inside the page: keep the page still while the map is zoomed or pinched.
        if (zoom > 1f || e.pointerCount > 1 || map.height * cell > height) parent?.requestDisallowInterceptTouchEvent(true)
        scaler.onTouchEvent(e)
        if (!scaler.isInProgress) gestures.onTouchEvent(e)
        return true
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        clampPan()
    }

    private fun rectOf(x0: Float, y0: Float, x1: Float, y1: Float) =
        RectF(panX + x0 * cell, panY + y0 * cell, panX + x1 * cell, panY + y1 * cell)

    private fun drawShape(c: Canvas, s: MapShape, p: Paint) {
        val r = rectOf(s.x0, s.y0, s.x1, s.y1)
        if (s.ellipse) c.drawOval(r, p) else c.drawRect(r, p)
    }

    override fun onDraw(c: Canvas) {
        c.drawColor(0xFF111111.toInt())
        val all = rectOf(0f, 0f, map.width.toFloat(), map.height.toFloat())
        paint.reset(); paint.isAntiAlias = true

        map.image?.let { path -> MapImages.get(context, path, redraw)?.let { c.drawBitmap(it, null, all, paint) } }

        // Terrain: its texture repeated once per grid square.
        for (t in map.terrain) {
            val tex = t.texture?.let { MapImages.get(context, "/images/terrain/$it", redraw) }
            paint.reset()
            if (tex != null) {
                val sh = BitmapShader(tex, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT)
                shaderMatrix.reset()
                shaderMatrix.setScale(cell / tex.width, cell / tex.height)
                shaderMatrix.postTranslate(panX, panY)
                sh.setLocalMatrix(shaderMatrix)
                paint.shader = sh
            } else {
                paint.color = 0xFF3A3A3A.toInt()
            }
            drawShape(c, t, paint)
        }

        // Grid.
        paint.reset()
        paint.color = 0x55FFFFFF
        paint.strokeWidth = 1f
        for (i in 0..map.width) { val x = panX + i * cell; c.drawLine(x, all.top, x, all.bottom, paint) }
        for (j in 0..map.height) { val y = panY + j * cell; c.drawLine(all.left, y, all.right, y, paint) }

        for (t in map.tokens) drawToken(c, t)

        // Fog of war: the server already left out tokens under it.
        paint.reset()
        paint.color = 0xFF7D8085.toInt()
        for (f in map.fog) drawShape(c, f, paint)
    }

    private fun drawToken(c: Canvas, t: MapToken) {
        val r = rectOf(t.x, t.y, t.x + t.size, t.y + t.size)
        val inset = cell * 0.06f
        r.inset(inset, inset)
        val id = t.combatantId
        val pickable = id != null && selectable.containsKey(id)
        val alpha = if (pickable) 255 else 90
        val bmp = t.image?.let { MapImages.get(context, it, redraw) }
        val clip = Path().apply { addOval(r, Path.Direction.CW) }
        paint.reset(); paint.isAntiAlias = true; paint.alpha = alpha
        c.save()
        c.clipPath(clip)
        if (bmp != null) {
            paint.isFilterBitmap = true
            c.drawBitmap(bmp, null, r, paint)
        } else {
            paint.color = Color.argb(alpha, 80, 80, 90)
            c.drawOval(r, paint)
            paint.color = Color.argb(alpha, 255, 255, 255)
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = r.height() * 0.5f
            c.drawText(t.label.take(1), r.centerX(), r.centerY() + paint.textSize / 3, paint)
        }
        c.restore()
        paint.reset(); paint.isAntiAlias = true
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = if (id == selected) cell * 0.12f else cell * 0.06f
        paint.color = when {
            id != null && id == selected -> Ui.GOLD
            !pickable -> Color.argb(alpha, 120, 120, 120)
            selectable[id] == true -> Ui.DIE_FAIL
            else -> 0xFF60A5FA.toInt()
        }
        c.drawOval(r, paint)
        if (id == selected) {
            paint.style = Paint.Style.FILL
            paint.color = Ui.GOLD
            paint.textAlign = Paint.Align.CENTER
            paint.textSize = (cell * 0.32f).coerceAtLeast(Ui.dpf(context, 11f))
            c.drawText(t.label, r.centerX(), r.bottom + paint.textSize * 1.1f, paint)
        }
    }
}
