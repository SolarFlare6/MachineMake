package com.example.machmake2

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

object KeepAliveBridge {
    var channel: MethodChannel? = null
    var latestDevices: List<Map<*, *>> = emptyList()
    var showOnLockScreen: Boolean = true
    var isRunning: Boolean = false
}

class ConnectionKeepAliveService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private val activeDeviceNotifIds = mutableSetOf<Int>()

    companion object {
        const val ACTION_START_OR_UPDATE = "com.example.machmake2.KEEPALIVE_START_OR_UPDATE"
        const val ACTION_STOP = "com.example.machmake2.KEEPALIVE_STOP"

        fun startOrUpdate(context: Context, devices: List<Map<*, *>>, showOnLockScreen: Boolean) {
            KeepAliveBridge.latestDevices = devices
            KeepAliveBridge.showOnLockScreen = showOnLockScreen

            val intent = Intent(context, ConnectionKeepAliveService::class.java).apply {
                action = ACTION_START_OR_UPDATE
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !KeepAliveBridge.isRunning) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // On Android 12+, if called while backgrounded and not yet running, fallback safely
                try {
                    context.startService(intent)
                } catch (_: Exception) {}
            }
        }

        fun stop(context: Context) {
            KeepAliveBridge.latestDevices = emptyList()
            val intent = Intent(context, ConnectionKeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {
                try {
                    context.stopService(Intent(context, ConnectionKeepAliveService::class.java))
                } catch (_: Exception) {}
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelfCleanly()
                return START_NOT_STICKY
            }
            else -> {
                val devices = KeepAliveBridge.latestDevices
                if (devices.isEmpty()) {
                    stopSelfCleanly()
                    return START_NOT_STICKY
                }
                acquireLocks()
                publishNotifications(devices, KeepAliveBridge.showOnLockScreen)
                KeepAliveBridge.isRunning = true
                return START_STICKY
            }
        }
    }

    private fun publishNotifications(devices: List<Map<*, *>>, showOnLockScreen: Boolean) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val summary = KeepAliveNotificationBuilder.buildSummaryNotification(
            this,
            devices.size,
            showOnLockScreen
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                KeepAliveNotificationBuilder.SUMMARY_ID,
                summary,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(KeepAliveNotificationBuilder.SUMMARY_ID, summary)
        }

        val newNotifIds = mutableSetOf<Int>()
        for (dev in devices) {
            val (id, notif) = KeepAliveNotificationBuilder.buildDeviceNotification(
                this,
                dev,
                showOnLockScreen
            )
            nm.notify(id, notif)
            newNotifIds.add(id)
        }

        // Cancel notifications for devices that are no longer connected
        val removed = activeDeviceNotifIds - newNotifIds
        for (oldId in removed) {
            nm.cancel(oldId)
        }
        activeDeviceNotifIds.clear()
        activeDeviceNotifIds.addAll(newNotifIds)
    }

    private fun acquireLocks() {
        try {
            if (wakeLock == null) {
                val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MachineMake::ConnWakeLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire()
            }
        } catch (_: Exception) {}

        try {
            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(lockMode, "MachineMake::ConnWifiLock").apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
        } catch (_: Exception) {}
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (_: Exception) {}
    }

    private fun stopSelfCleanly() {
        KeepAliveBridge.isRunning = false
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (id in activeDeviceNotifIds) {
            nm.cancel(id)
        }
        activeDeviceNotifIds.clear()
        releaseLocks()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        KeepAliveBridge.isRunning = false
        releaseLocks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
