#!/usr/bin/env python3
import re
from pathlib import Path

def fix():
    target = Path("lib/providers/tracks_provider.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")

    # Ищем метод _isOnRecorderWifi от начала до закрывающей скобки
    pattern = r"Future<bool> _isOnRecorderWifi\(\) async \{.*?\n  \}"
    
    new_method = """Future<bool> _isOnRecorderWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.wifi)) return false;
      if (!await Permission.locationWhenInUse.isGranted) return false;
      final ssidRaw = await _wifiChannel.invokeMethod<String>('getWifiSsid');
      final ssid = (ssidRaw ?? '').replaceAll('"', '').trim();
      if (ssid.startsWith('70mai_')) {
        await _wifiChannel.invokeMethod('bindToWifi');
        AppLogger.log('[Network] Привязано к Wi-Fi регистратора');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }"""
    
    text = re.sub(pattern, new_method, text, flags=re.DOTALL)
    target.write_text(text, encoding="utf-8")
    print("✅ tracks_provider.dart: метод _isOnRecorderWifi успешно обновлен (привязка к Wi-Fi)")

if __name__ == "__main__":
    fix()
