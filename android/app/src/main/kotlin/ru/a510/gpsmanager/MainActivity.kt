package ru.a510.gpsmanager

import android.content.Context
import android.net.wifi.WifiManager
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "ru.a510.gpsmanager/wifi"
    private val storageChannelName = "ru.a510.gpsmanager/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getWifiSsid") {
                    try {
                        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        result.success(manager.connectionInfo?.ssid)
                    } catch (error: Exception) {
                        result.error("SSID_ERROR", error.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getFreeBytes") {
                    try {
                        val path = getExternalFilesDir(null)?.absolutePath
                        if (path == null) result.success(null)
                        else result.success(StatFs(path).availableBytes)
                    } catch (error: Exception) {
                        result.error("STORAGE_ERROR", error.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
