package com.example.quantum_ide

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.util.TypedValue
import android.view.ActionMode
import android.view.Gravity
import android.view.ViewGroup
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.min
import java.lang.reflect.Field
import java.lang.reflect.Method

class TerminalSelectionOverlay private constructor(
    context: Context,
    private var channel: MethodChannel,
    private val container: ViewGroup,
) : EditText(context) {

    private var suppressSelectionEvents = false
    private var actionMode: ActionMode? = null

    init {
        setBackgroundColor(Color.TRANSPARENT)
        setTextColor(Color.TRANSPARENT)
        setHighlightColor(Color.TRANSPARENT)
        setTextIsSelectable(true)
        isCursorVisible = false
        setShowSoftInputOnFocus(false)
        isFocusableInTouchMode = true
        setPadding(0, 0, 0, 0)
        setIncludeFontPadding(false)
        gravity = Gravity.TOP or Gravity.START

        setCustomSelectionActionModeCallback(object : ActionMode.Callback {
            override fun onCreateActionMode(mode: ActionMode, menu: android.view.Menu): Boolean {
                actionMode = mode
                // Explicitly populate the standard selection menu so the user
                // always sees Copy / Select all (requirement: Android ActionMode).
                val copyItem = menu.add(0, android.R.id.copy, 0, "Copy")
                copyItem.setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
                val selectAllItem = menu.add(0, android.R.id.selectAll, 1, "Select all")
                selectAllItem.setShowAsAction(android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
                return true
            }

            override fun onPrepareActionMode(mode: ActionMode, menu: android.view.Menu): Boolean = false

            override fun onActionItemClicked(mode: ActionMode, item: android.view.MenuItem): Boolean {
                val start = min(selectionStart, selectionEnd)
                val end = max(selectionStart, selectionEnd)
                val text = this@TerminalSelectionOverlay.text?.subSequence(start, end)?.toString() ?: ""
                return when (item.itemId) {
                    android.R.id.copy -> {
                        copyToClipboard(text)
                        channel.invokeMethod("onCopy", mapOf("text" to text))
                        mode.finish()
                        true
                    }
                    android.R.id.selectAll -> {
                        selectAll()
                        channel.invokeMethod("onSelectAll", null)
                        true
                    }
                    else -> false
                }
            }

            override fun onDestroyActionMode(mode: ActionMode) {
                actionMode = null
                channel.invokeMethod("onActionModeDestroyed", null)
            }
        })
    }

    override fun onSelectionChanged(selStart: Int, selEnd: Int) {
        super.onSelectionChanged(selStart, selEnd)
        if (!suppressSelectionEvents) {
            channel.invokeMethod("onSelectionChanged", mapOf(
                "start" to selStart,
                "end" to selEnd
            ))
        }
    }

    fun show(args: Map<String, Any>) {
        val text = args["text"] as String
        val start = args["start"] as Int
        val end = args["end"] as Int
        val left = args["left"] as Int
        val top = args["top"] as Int
        val width = args["width"] as Int
        val height = args["height"] as Int
        val fontSizePx = args["fontSizePx"] as Float
        val lineHeightPx = args["lineHeightPx"] as Float
        val fontFamily = args["fontFamily"] as String

        // Position the overlay
        val params = FrameLayout.LayoutParams(width, height)
        params.gravity = Gravity.NO_GRAVITY
        params.leftMargin = left
        params.topMargin = top
        if (parent == null) {
            container.addView(this, params)
        } else {
            container.updateViewLayout(this, params)
        }

        suppressSelectionEvents = true
        typeface = if (fontFamily == "monospace") Typeface.MONOSPACE else Typeface.create(fontFamily, Typeface.NORMAL)
        setTextSize(TypedValue.COMPLEX_UNIT_PX, fontSizePx)
        setLineSpacing(0f, lineHeightPx / fontSizePx)
        setText(text)
        setSelection(start, end)
        suppressSelectionEvents = false

        requestFocus()
        showSelectionActionMode()
    }

    fun hide() {
        if (parent != null) {
            container.removeView(this)
        }
        if (actionMode != null) {
            actionMode?.finish()
            actionMode = null
        }
    }

    fun updatePosition(left: Int, top: Int, width: Int, height: Int) {
        if (parent == null) return
        val params = layoutParams as FrameLayout.LayoutParams
        params.gravity = Gravity.NO_GRAVITY
        params.leftMargin = left
        params.topMargin = top
        params.width = width
        params.height = height
        container.updateViewLayout(this, params)
    }

    private fun showSelectionActionMode() {
        // Force show the native selection handles + ActionMode
        // Method 1: API 33+ has startTextActionMode()
        if (Build.VERSION.SDK_INT >= 33) {
            try {
                val method = TextView::class.java.getMethod("startTextActionMode")
                method.invoke(this)
                return
            } catch (e: Exception) {
                // fall through to reflection
            }
        }

        // Method 2: Reflectively call Editor.startSelectionActionMode()
        try {
            val editorField = TextView::class.java.getDeclaredField("mEditor")
            editorField.isAccessible = true
            val editor = editorField.get(this)
            val method = editor.javaClass.getDeclaredMethod("startSelectionActionMode")
            method.isAccessible = true
            method.invoke(editor)
        } catch (e: Exception) {
            // Method 3: Fallback - start action mode with our callback
            startActionMode(customSelectionActionModeCallback)
        }
    }

    fun copyToClipboard(text: String) {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("terminal", text))
    }

    companion object {
        private var INSTANCE: TerminalSelectionOverlay? = null

        fun getInstance(context: Context, channel: MethodChannel): TerminalSelectionOverlay {
            if (INSTANCE == null) {
                val activity = context as Activity
                val container = activity.window.decorView as ViewGroup
                INSTANCE = TerminalSelectionOverlay(context, channel, container)
            } else {
                // Update the channel in case it was recreated
                INSTANCE!!.channel = channel
            }
            return INSTANCE!!
        }
    }
}