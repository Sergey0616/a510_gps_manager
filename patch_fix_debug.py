import os
import re

def patch_file(filepath, replacements):
    print(f"--- Патчим {filepath} ---")
    if not os.path.exists(filepath):
        return
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    count = 0
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            count += 1
        else:
            print(f"WARN: Не найден фрагмент:\n{old[:80]}...")
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {count} замен.")

# 1. Фильтр 100 метров и убираем проверку на видео
patch_file('lib/services/storage_service.dart', [
    ("""          final hasVideo = candidate.points.any((p) => p.videoName != null);
          final hasMovement = candidate.points.length >= 2 &&
              candidate.distanceKm >= 0.05;
          if (hasMovement || hasVideo) {""",
     """          // Фильтр: только треки от 100 метров
          final hasMovement = candidate.points.length >= 2 &&
              candidate.distanceKm >= 0.1;
          if (hasMovement) {""")
])

# 2. Выводим URI папки в лог перед сохранением
patch_file('lib/providers/tracks_provider.dart', [
    ("""    final safUri = await LocalFolderService.getFolderUri();
    if (safUri != null) {""",
     """    final safUri = await LocalFolderService.getFolderUri();
    AppLogger.log('[SAF] Проверка папки: safUri = $safUri');
    if (safUri != null && safUri.isNotEmpty) {""")
])

# 3. Автоповтор для FTP (3 попытки)
patch_file('lib/services/ftp_client.dart', [
    ("""static Future<FtpClient> connect(String host, int port, String username, String password) async {
    print('[FTP] connect $host:$port');
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 12));""",
     """static Future<FtpClient> connect(String host, int port, String username, String password) async {
    Socket? socket;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        print('[FTP] connect $host:$port (попытка $attempt)');
        socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
        break;
      } catch (e) {
        if (attempt == 3) rethrow;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    if (socket == null) throw Exception('Не удалось подключиться к FTP');""")
])

print("\nГотово! Проверьте ошибки: flutter analyze")
