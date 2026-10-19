import os
import re

# 1. Починка ftp_client.dart
print("--- Патчим ftp_client.dart ---")
path = 'lib/services/ftp_client.dart'
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

# Добавляем параметр sourceAddress в сигнатуру метода connect
c = c.replace(
    "static Future<FtpClient> connect(String host, int port, String username, String password) async {",
    "static Future<FtpClient> connect(String host, int port, String username, String password, {InternetAddress? sourceAddress}) async {"
)

# Исправляем ошибку в Duration (sourceAddress попал внутрь Duration)
c = c.replace(
    "timeout: const Duration(seconds: 12, sourceAddress: sourceAddress)",
    "timeout: const Duration(seconds: 12), sourceAddress: sourceAddress"
)

# Для второго Socket.connect (соединение данных) используем локальный адрес управляющего сокета
c = c.replace("sourceAddress: sourceAddress", "sourceAddress: _control.address")
c = c.replace(
    "timeout: const Duration(seconds: 12), sourceAddress: _control.address",
    "timeout: const Duration(seconds: 12), sourceAddress: sourceAddress"
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: ftp_client.dart обновлен")

# 2. Починка tracks_provider.dart
print("--- Патчим tracks_provider.dart ---")
path = 'lib/providers/tracks_provider.dart'
with open(path, 'r', encoding='utf-8') as f:
    c = f.read()

if "deleteRecorderVideos" not in c:
    c = c.replace(
        "Future<void> clearAllTracks() async {",
        """Future<int> deleteRecorderVideos() async {
    return await _ftp().deleteEventVideos();
  }

  Future<void> clearAllTracks() async {"""
    )
with open(path, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен")

print("\nГотово! Все ошибки должны исчезнуть.")
