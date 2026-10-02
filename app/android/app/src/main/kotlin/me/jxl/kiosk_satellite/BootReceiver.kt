package me.jxl.kiosk_satellite

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Launches the kiosk when the device powers on, if the "Start on boot"
 * setting is on. The Flutter engine is not running at boot, so the setting
 * is read straight from the shared_preferences store ("flutter." + the
 * app's "ks." prefix). On Android 10+ a background activity start is only
 * honored because the app holds the draw-over-apps grant — the setting's
 * description sends the user to that permission. The keep-alive service is
 * started first and separately: a boot receiver may always start a
 * foreground service, so the kiosk's connections come up even on a device
 * whose Activity start is dropped.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON" -> Unit
            else -> return
        }
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE)
        // A reboot drops every AlarmManager entry. With an alarm on, the
        // process comes up whatever Start on boot says, so Dart can put the
        // next ring back; the Activity still waits for that setting.
        val alarmsOn = (prefs.getString("flutter.ks.alarms.list", "") ?: "")
            .contains("\"on\":true")
        if (alarmsOn) KioskSatelliteService.ensureRunning(context)
        if (!prefs.getBoolean("flutter.ks.kiosk.start_on_boot", false)) return
        KioskSatelliteService.ensureRunning(context)
        // A device with no usable renderer (DisplayCapability) never gets
        // the dashboard Activity, whatever "Start on boot" says — only
        // its crash is new there. HomeRole.setAliasEnabled already
        // refuses to make such a device HOME going forward, but an
        // existing install that was already set as HOME before this
        // check existed still has the alias on, so the explicit skip here
        // stays even once that refusal is in place.
        if (DisplayCapability.isHeadless(context)) return
        // As the device's home app the system has already launched the
        // kiosk itself, before this broadcast arrives; a second start is
        // harmless but log-noisy (issue #219).
        if (HomeRole.isHeld(context)) return
        // The launcher's own intent, not a bare component one: it carries
        // the flags that surface an existing task instead of rooting a
        // duplicate beside it.
        val launch = HomeRole.launchIntent(context) ?: return
        try {
            context.startActivity(launch)
        } catch (e: Exception) {
            // A Fire TV Stick's system server threw a NullPointerException
            // of its own out of this call at every boot, which took the
            // receiver and the app down with it. The service above is up
            // and its heartbeat brings the kiosk back; the launch is not
            // worth a crash.
            Log.w("BootReceiver", "launch at boot refused: $e")
        }
    }
}
