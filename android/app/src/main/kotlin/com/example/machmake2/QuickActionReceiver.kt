package com.example.machmake2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class QuickActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_QUICK_COMMAND = "com.example.machmake2.ACTION_QUICK_COMMAND"
        const val EXTRA_DEVICE_ID = "extra_device_id"
        const val EXTRA_ACTION_KEY = "extra_action_key"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_QUICK_COMMAND) return

        val deviceId = intent.getStringExtra(EXTRA_DEVICE_ID) ?: return
        val actionKey = intent.getStringExtra(EXTRA_ACTION_KEY) ?: return

        Handler(Looper.getMainLooper()).post {
            val channel = KeepAliveBridge.channel
            if (channel != null) {
                channel.invokeMethod(
                    "onQuickAction",
                    mapOf(
                        "deviceId" to deviceId,
                        "action" to actionKey
                    )
                )
            } else {
                // Queue action in SharedPreferences if Flutter engine was detached
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit()
                    .putString("flutter.pending_quick_action_device", deviceId)
                    .putString("flutter.pending_quick_action_key", actionKey)
                    .apply()
            }
        }
    }
}
