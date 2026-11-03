#!/usr/bin/env python3
"""Патч: принудительная привязка к Wi-Fi регистратора для обхода блокировки мобильным интернетом."""
from pathlib import Path

def fix_tracks_provider():
    target = Path("lib/providers/tracks_provider.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")
    
    old_wifi_check = """        final ssidRaw = await _wifiChannel.invokeMethod<String>('getWifiSsid');
        final ssid = (ssidRaw ?? '').replaceAll('"', '').trim();
        return ssid.startsWith('70mai_');"""
        
    new_wifi_check = """        final ssidRaw = await _wifiChannel.invokeMethod<String>('getWifiSsid');
        final ssid = (ssidRaw ?? '').replaceAll('"', '').trim();
        if (ssid.startsWith('70mai_')) {
          await _wifiChannel.invokeMethod('bindToWifi');
          AppLogger.log('[Network] Привязано к Wi-Fi регистратора');
          return true;
        }
        return false;"""
        
    if old_wifi_check in text:
        text = text.replace(old_wifi_check, new_wifi_check, 1)
        target.write_text(text, encoding="utf-8")
        print("✅ tracks_provider.dart: добавлена привязка к Wi-Fi при синхронизации")
    else:
        print("⚠️ tracks_provider.dart: шаблон не найден")

def fix_video_screen():
    target = Path("lib/screens/video_screen.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")
    
    # Добавляем импорт
    if "import 'package:flutter/services.dart';" not in text:
        text = text.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';", 1)
        
    old_button = """                        IconButton(
                          tooltip: 'Смотреть онлайн (HTTP)',
                          onPressed: () {
                            final provider = context.read<TracksProvider>();
                            final url = 'http://${provider.host}${file.remotePath}';"""
                            
    new_button = """                        IconButton(
                          tooltip: 'Смотреть онлайн (HTTP)',
                          onPressed: () async {
                            final provider = context.read<TracksProvider>();
                            try {
                              await const MethodChannel('ru.a510.gpsmanager/wifi').invokeMethod('bindToWifi');
                            } catch (_) {}
                            if (!mounted) return;
                            final url = 'http://${provider.host}${file.remotePath}';"""
                            
    if old_button in text:
        text = text.replace(old_button, new_button, 1)
        target.write_text(text, encoding="utf-8")
        print("✅ video_screen.dart: добавлена привязка к Wi-Fi перед HTTP-стримингом")
    else:
        print("⚠️ video_screen.dart: кнопка не найдена")

if __name__ == "__main__":
    fix_tracks_provider()
    fix_video_screen()
    print("Готово! Теперь запусти 'flutter analyze'")
