import os
import re

# 1. Добавляем импорт и заменяем _withWifiNetwork в tracks_provider.dart
filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

if 'wifi_iot' not in c:
    c = c.replace("import 'package:connectivity_plus/connectivity_plus.dart';",
                  "import 'package:connectivity_plus/connectivity_plus.dart';\nimport 'package:wifi_iot/wifi_iot.dart';")

# Заменяем старую функцию на использование wifi_iot
pattern = r"Future<T> _withWifiNetwork<T>\(Future<T> Function\(\) action\) async \{.*?\n  \}"
new_with = """Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    try {
      // Принудительно направляем весь трафик приложения через Wi-Fi
      await WiFiForIoTPlugin.forceWifiUsage(true);
      AppLogger.log('[Net] forceWifiUsage(true) — трафик принудительно через Wi-Fi');
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      AppLogger.log('[Net] Ошибка forceWifiUsage(true): $e');
    }
    try {
      return await action();
    } finally {
      try {
        // Возвращаем стандартную маршрутизацию (мобильный интернет снова доступен)
        await WiFiForIoTPlugin.forceWifiUsage(false);
        AppLogger.log('[Net] forceWifiUsage(false) — маршрутизация восстановлена');
      } catch (_) {}
    }
  }"""

if re.search(pattern, c, re.DOTALL):
    c = re.sub(pattern, new_with, c, flags=re.DOTALL)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK: tracks_provider.dart обновлен (wifi_iot)")
else:
    print("WARN: Не нашли функцию _withWifiNetwork")

# 2. Добавляем разрешение CHANGE_WIFI_STATE в AndroidManifest
manifest_path = 'android/app/src/main/AndroidManifest.xml'
with open(manifest_path, 'r', encoding='utf-8') as f:
    m = f.read()

if 'CHANGE_WIFI_STATE' not in m:
    m = m.replace('<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />',
                  '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />\n    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />')
    with open(manifest_path, 'w', encoding='utf-8') as f:
        f.write(m)
    print("OK: Добавлено разрешение CHANGE_WIFI_STATE в манифест")
else:
    print("INFO: Разрешение CHANGE_WIFI_STATE уже есть")

print("\nГотово! Проверьте ошибки: flutter analyze")
