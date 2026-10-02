package me.jxl.kiosk_satellite

import android.content.Context
import android.os.PowerManager
import android.util.Log

/**
 * Keeps a headless board awake for the lifetime of the process.
 *
 * Boards without a display (see [DisplayCapability]) drop to
 * `mWakefulness=Asleep` and never wake up. While asleep, Android keeps key
 * presses to itself: the System UI guard never sees the intercom action key.
 * A screen wake lock with ACQUIRE_CAUSES_WAKEUP wakes the device and holds it
 * in `Awake`. There is no screen to burn and the devices run on mains power,
 * so the cost is nil. Only used on headless devices.
 */
object HeadlessWakeLock {
    private var lock: PowerManager.WakeLock? = null

    @Suppress("DEPRECATION")
    @Synchronized
    fun acquire(context: Context) {
        if (lock?.isHeld == true) return
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            lock = pm.newWakeLock(
                PowerManager.SCREEN_DIM_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "kiosk_satellite:headless",
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
            Log.i("HeadlessWakeLock", "headless device: holding the device awake")
        } catch (e: Exception) {
            Log.w("HeadlessWakeLock", "could not keep the device awake", e)
        }
    }
}
