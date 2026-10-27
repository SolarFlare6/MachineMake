package com.example.machmake2

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {

    private val WIFI_CHANNEL = "com.machinemake/wifi"
    private val KEEPALIVE_CHANNEL = "machinemake/keepalive"
    private val MEDIA_CHANNEL = "com.machinemake/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveSnapshot" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName")
                            ?: "MachineMake_${System.currentTimeMillis()}.jpg"
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("EMPTY_BYTES", "No image bytes provided", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val savedPath = saveJpegToPhoneStorage(bytes, fileName)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWifiSettings" -> {
                        // Android 10+ forbids direct Wi-Fi enable; open the panel instead.
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        val keepAliveChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEEPALIVE_CHANNEL)
        KeepAliveBridge.channel = keepAliveChannel

        keepAliveChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "updateDevices" -> {
                    val args = call.arguments as? Map<*, *>
                    val rawDevices = (args?.get("devices") as? List<*>) ?: (call.arguments as? List<*>) ?: emptyList<Any>()
                    val devices = rawDevices.mapNotNull { it as? Map<*, *> }
                    val showOnLockScreen = (args?.get("showOnLockScreen") as? Boolean) ?: true
                    ConnectionKeepAliveService.startOrUpdate(applicationContext, devices, showOnLockScreen)
                    result.success(true)
                }
                "stop" -> {
                    ConnectionKeepAliveService.stop(applicationContext)
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true)
                    }
                }
                "requestBatteryExemption" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                try {
                                    val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                    }
                                    startActivity(fallback)
                                    result.success(true)
                                } catch (_: Exception) {
                                    result.success(false)
                                }
                            }
                        } else {
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val openDevId = intent.getStringExtra("open_device_id")
        if (!openDevId.isNullOrEmpty()) {
            KeepAliveBridge.channel?.invokeMethod(
                "onOpenDevice",
                mapOf("deviceId" to openDevId)
            )
        }
    }

    private fun saveJpegToPhoneStorage(bytes: ByteArray, fileName: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/MachineMake"
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw IllegalStateException("Could not create MediaStore entry")
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: throw IllegalStateException("Could not open MediaStore output stream")

            contentValues.clear()
            contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
            return "Pictures/MachineMake/$fileName"
        } else {
            val baseDir = getExternalFilesDir(Environment.DIRECTORY_PICTURES) ?: filesDir
            val folder = File(baseDir, "MachineMake")
            if (!folder.exists()) {
                folder.mkdirs()
            }
            val outFile = File(folder, fileName)
            FileOutputStream(outFile).use { out ->
                out.write(bytes)
                out.flush()
            }
            return outFile.absolutePath
        }
    }
}
