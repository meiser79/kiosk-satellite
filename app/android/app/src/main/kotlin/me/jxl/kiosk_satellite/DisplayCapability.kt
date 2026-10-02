package me.jxl.kiosk_satellite

import android.content.Context
import android.hardware.display.DisplayManager
import android.util.DisplayMetrics
import android.view.Display
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.util.Log

/**
 * Whether this device has a renderer Flutter can actually draw with.
 *
 * Flutter's Android embedding (Skia-GL and Impeller alike) needs an
 * OpenGL ES 2.0 capable EGL config for its platform view surface and has
 * no software fallback: on a board whose EGL driver only enumerates ES 1.x
 * configs (libagl, EGL_RENDERABLE_TYPE == EGL_OPENGL_ES_BIT) every launch
 * of MainActivity aborts in platform_view_android.cc with "Could not
 * create surface from invalid Android context".
 *
 * IMPORTANT: do NOT use ActivityManager.ConfigurationInfo.reqGlEsVersion
 * for this. That value is not probed from the driver at all — the
 * framework just reads the build-time system property
 * `ro.opengles.version` (SystemProperties.getInt("ro.opengles.version",
 * ...)). Vendor images routinely declare 0x20000 there while the actual
 * EGL stack is ES 1.x only, so the check silently passes and the kiosk
 * keeps crash-looping. It is also why `dumpsys activity | grep GLES`
 * prints nothing on such a build: the property is simply unset/never
 * dumped.
 *
 * So we run the same cheap check Flutter itself fails: eglChooseConfig
 * with EGL_RENDERABLE_TYPE = EGL_OPENGL_ES2_BIT on the default display.
 * No window, no surface, no context — a few milliseconds, once per boot.
 *
 * Having a renderer is not the same as having a screen, though. Boards
 * like the Echo Dot running a headless ROM ship a software ES2 driver
 * (SwiftShader) behind a fake 1x1 primary display: Flutter can start its
 * engine there, but nobody will ever see or touch the dashboard. So the
 * device counts as headless when EITHER
 *  - there is no ES2-capable config (the engine
 *    cannot even be constructed), or
 *  - the ROM says it has no screen (`ro.config.no_gpu=true` or
 *    `ro.build.configuration=headless`), or the default display is
 *    smaller than [MIN_REAL_DISPLAY_PX] in either dimension.
 * There is a single answer, [isHeadless]: on a headless device the
 * dashboard is switched off and the services run. The Flutter engine
 * itself still needs an ES2 driver; a board without one needs a software
 * driver such as SwiftShader in its ROM.
 */
object DisplayCapability {
    private const val TAG = "DisplayCapability"
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY_HEADLESS = "flutter.ks.display.headless"

    /** Anything smaller than this on either side is a placeholder
     *  display, not a screen a person can use. */
    private const val MIN_REAL_DISPLAY_PX = 100

    /** True once a real Flutter frame has been seen (see MainActivity's
     *  first-frame callback) — a later probe must never re-flip the
     *  device back to headless. */
    private const val KEY_CONFIRMED = "flutter.ks.display.confirmed_gles2"

    /**
     * Probes and persists whether this device can render, once per
     * process. Call early in KioskApplication.onCreate(), before anything
     * reads [isHeadless].
     */
    fun detect(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // A confirmed Flutter frame proves the renderer; the screen check
        // still runs (it is cheap and never touches EGL).
        val headless = romDeclaresNoScreen() || displayTooSmall(context) ||
            !(prefs.getBoolean(KEY_CONFIRMED, false) || hasGles2Config())
        if (headless) {
            Log.w(TAG, "no usable screen: dashboard disabled, services run")
        } else {
            Log.i(TAG, "usable screen present")
        }
        prefs.edit().putBoolean(KEY_HEADLESS, headless).apply()

        // Defence in depth: a device provisioned as HOME before this check
        // existed is still launched by the system at boot, whatever
        // BootReceiver does. Drop the alias right here.
        if (headless && HomeRole.aliasEnabled(context)) {
            Log.w(TAG, "disabling home alias on headless device")
            HomeRole.setAliasEnabled(context, false)
        }
        return headless
    }

    /** eglChooseConfig for an ES2 renderable config — exactly the request
     *  that returns 0 configs on an ES1-only (libagl) stack. */
    private fun hasGles2Config(): Boolean {
        var display = EGL14.EGL_NO_DISPLAY
        return try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) return false
            val version = IntArray(2)
            if (!EGL14.eglInitialize(display, version, 0, version, 1)) return false

            val attribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val num = IntArray(1)
            val ok = EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0)
            if (!ok) {
                Log.w(TAG, "eglChooseConfig failed: 0x${EGL14.eglGetError().toString(16)}")
            }
            ok && num[0] > 0 && configs[0] != null
        } catch (t: Throwable) {
            // A throwing EGL stack is itself a stack Flutter cannot use.
            Log.w(TAG, "EGL probe threw: ${t.message}")
            false
        } finally {
            if (display != EGL14.EGL_NO_DISPLAY) {
                runCatching { EGL14.eglTerminate(display) }
            }
        }
    }

    /** `ro.config.no_gpu` / `ro.build.configuration`, read through the
     *  hidden SystemProperties API (stable since API 1, no permission). */
    private fun romDeclaresNoScreen(): Boolean {
        fun prop(key: String): String = runCatching {
            Class.forName("android.os.SystemProperties")
                .getMethod("get", String::class.java)
                .invoke(null, key) as String
        }.getOrDefault("")
        return prop("ro.config.no_gpu").equals("true", ignoreCase = true) ||
            prop("ro.build.configuration").equals("headless", ignoreCase = true)
    }

    private fun displayTooSmall(context: Context): Boolean = runCatching {
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val display = dm.getDisplay(Display.DEFAULT_DISPLAY) ?: return true
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        display.getRealMetrics(metrics)
        metrics.widthPixels < MIN_REAL_DISPLAY_PX || metrics.heightPixels < MIN_REAL_DISPLAY_PX
    }.getOrDefault(false)

    fun isHeadless(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_HEADLESS, false)

    /** A real Flutter frame made it to the screen: the renderer plainly
     *  works, clear the flag for good (e.g. an HDMI dock appeared). */
    fun noteFirstFrame(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_HEADLESS, false)
            .putBoolean(KEY_CONFIRMED, true)
            .apply()
    }
}
