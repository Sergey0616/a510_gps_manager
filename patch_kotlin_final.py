#!/usr/bin/env python3
"""Мега-патч для MainActivity.kt: жесткая привязка к Wi-Fi без интернета."""
from pathlib import Path

TARGET = Path("android/app/src/main/kotlin/ru/a510/gpsmanager/MainActivity.kt")

NEW_CODE = """package ru.a510.gpsmanager

import android.content.Context
import android.net.wifi.WifiManager
import android.os.StatFs
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wifiNetwork: Network? = null
    
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            wifiNetwork = network
            // Принудительно пускаем весь трафик приложения через эту Wi-Fi сеть
            val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.bindProcessToNetwork(network)
        }
        override fun onLost(network: Network) {
            if (wifiNetwork == network) {
                wifiNetwork = null
                val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.bindProcessToNetwork(null)
            }
        }
    }

    private val channelName = "ru.a510.gpsmanager/wifi"
    private val storageChannelName = "ru.a510.gpsmanager/storage"

    private fun bindToWifi(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = wifiNetwork
        if (net != null) {
            return cm.bindProcessToNetwork(net)
        }
        return false
    }

    private fun unbindWifi() {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        
        // КЛЮЧЕВОЙ МОМЕНТ: Запрашиваем Wi-Fi сеть, у которой НЕТ интернета (removeCapability)
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
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
"""

def main():
    if not TARGET.exists():
        print(f"❌ Не найден {TARGET}")
        return
    TARGET.write_text(NEW_CODE, encoding="utf-8")
    print("✅ MainActivity.kt полностью перезаписан! Добавлена привязка к Wi-Fi без интернета.")

if __name__ == "__main__":
    main()
