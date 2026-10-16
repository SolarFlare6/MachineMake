package com.example.machmake2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object KeepAliveNotificationBuilder {
    const val CHANNEL_ID = "mm_keepalive_channel"
    const val CHANNEL_NAME = "Connected Devices & Quick Actions"
    const val GROUP_KEY = "mm_devices_group"
    const val SUMMARY_ID = 9001

    fun ensureChannel(context: Context, showOnLockScreen: Boolean = true) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing connection status and per-device quick actions"
                setShowBadge(false)
                enableVibration(false)
                lockscreenVisibility = if (showOnLockScreen) {
                    Notification.VISIBILITY_PUBLIC
                } else {
                    Notification.VISIBILITY_PRIVATE
                }
            }
            nm.createNotificationChannel(channel)
        }
    }

    fun buildSummaryNotification(
        context: Context,
        deviceCount: Int,
        showOnLockScreen: Boolean = true
    ): Notification {
        ensureChannel(context, showOnLockScreen)

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            SUMMARY_ID,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val disconnectAllIntent = Intent(context, QuickActionReceiver::class.java).apply {
            action = QuickActionReceiver.ACTION_QUICK_COMMAND
            putExtra(QuickActionReceiver.EXTRA_DEVICE_ID, "__all__")
            putExtra(QuickActionReceiver.EXTRA_ACTION_KEY, "disconnect_all")
        }
        val disconnectAllPending = PendingIntent.getBroadcast(
            context,
            SUMMARY_ID + 1,
            disconnectAllIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val plural = if (deviceCount == 1) "1 device connected" else "$deviceCount devices connected"
        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MachineMake · $plural")
            .setContentText("Keeping device connections active in background")
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setVisibility(
                if (showOnLockScreen) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_PRIVATE
            )
            builder.setCategory(Notification.CATEGORY_SERVICE)
        }

        val actionBuilder = Notification.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Disconnect All",
            disconnectAllPending
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            actionBuilder.setAuthenticationRequired(true)
        }
        builder.addAction(actionBuilder.build())

        return builder.build()
    }

    fun buildDeviceNotification(
        context: Context,
        deviceMap: Map<*, *>,
        showOnLockScreen: Boolean = true
    ): Pair<Int, Notification> {
        ensureChannel(context, showOnLockScreen)

        val deviceId = (deviceMap["deviceId"] as? String) ?: "unknown"
        val name = (deviceMap["name"] as? String) ?: "Device"
        val statusLine = (deviceMap["statusLine"] as? String) ?: "Connected"
        val actionsList = (deviceMap["actions"] as? List<*>) ?: emptyList<Any>()

        val notifId = 9100 + ((deviceId.hashCode() and 0x7FFFFFFF) % 10000)

        val openDeviceIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_device_id", deviceId)
        }
        val contentPending = PendingIntent.getActivity(
            context,
            notifId,
            openDeviceIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(name)
            .setContentText(statusLine)
            .setContentIntent(contentPending)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP_KEY)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setVisibility(
                if (showOnLockScreen) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_PRIVATE
            )
            builder.setCategory(Notification.CATEGORY_SERVICE)
        }

        actionsList.take(3).forEachIndexed { idx, rawAction ->
            val actMap = rawAction as? Map<*, *> ?: return@forEachIndexed
            val key = (actMap["key"] as? String) ?: return@forEachIndexed
            val label = (actMap["label"] as? String) ?: key
            val requiresUnlock = (actMap["requiresUnlock"] as? Boolean) ?: false

            val actIntent = Intent(context, QuickActionReceiver::class.java).apply {
                action = QuickActionReceiver.ACTION_QUICK_COMMAND
                putExtra(QuickActionReceiver.EXTRA_DEVICE_ID, deviceId)
                putExtra(QuickActionReceiver.EXTRA_ACTION_KEY, key)
            }
            val reqCode = notifId * 10 + idx + 1
            val actPending = PendingIntent.getBroadcast(
                context,
                reqCode,
                actIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val actionBuilder = Notification.Action.Builder(
                0,
                label,
                actPending
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && requiresUnlock) {
                actionBuilder.setAuthenticationRequired(true)
            }
            builder.addAction(actionBuilder.build())
        }

        return Pair(notifId, builder.build())
    }
}
