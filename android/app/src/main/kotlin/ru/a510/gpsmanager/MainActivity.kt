package ru.a510.gpsmanager

import android.content.Context
import android.net.wifi.WifiManager
import android.os.StatFs
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wifiNetwork: android.net.Network? = null
    private val networkCallback = object : android.net.ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: android.net.Network) {
            wifiNetwork = network
        }
        override fun onLost(network: android.net.Network) {
            if (wifiNetwork == network) wifiNetwork = null
        }
    }

    private val channelName = "ru.a510.gpsmanager/wifi"
    private val storageChannelName = "ru.a510.gpsmanager/storage"

    private fun bindToWifi(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val network = wifiNetwork ?: cm.activeNetwork
        val caps = cm.getNetworkCapabilities(network)
        if (caps != null && caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) {
            return cm.bindProcessToNetwork(network)
        }
        return false
    }

    private fun unbindWifi() {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val request = android.net.NetworkRequest.Builder()
            .addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        cm.registerNetworkCallback(request, networkCallback)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "bindToWifi") {
                    result.success(bindToWifi())
                } else if (call.method == "unbindWifi") {
                    unbindWifi()
                    result.success(true)
                } else if (call.method == "getWifiIp") {
                    try {
                        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val ip = manager.connectionInfo?.ipAddress
                        if (ip != null && ip != 0) {
                            val ipString = String.format("%d.%d.%d.%d", (ip and 0xff), (ip shr 8 and 0xff), (ip shr 16 and 0xff), (ip shr 24 and 0xff))
                            result.success(ipString)
                        } else {
                            result.success(null)
                        }
                    } catch (error: Exception) {
                        result.error("IP_ERROR", error.message, null)
                    }
                } else if (call.method == "getWifiSsid") {
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
