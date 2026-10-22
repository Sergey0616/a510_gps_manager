import os
import re

# 1. Вставляем сохранение в SAF в FTP-метод
filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# Ищем сохранение треков (которое есть только в FTP-методе)
old_save = """    await storage.saveTracks(allTracks);
    _tracks = await storage.loadTracks();"""

new_save = """    await storage.saveTracks(allTracks);
    
    // Копируем новые GPX в выбранную SAF-папку
    final safUri = await LocalFolderService.getFolderUri();
    AppLogger.log('[SAF] Проверка папки при FTP: safUri = $safUri');
    if (safUri != null && safUri.isNotEmpty) {
      _status = 'Сохранение треков в локальную папку…';
      notifyListeners();
      try {
        final files = await storage.parsedDirectory.list().where((e) => e is File && e.path.endsWith('.gpx')).cast<File>().toList();
        await LocalFolderService.saveFilesToSaf(safUri, files);
      } catch (e) {
        AppLogger.log('[SAF] Ошибка при сохранении в папку: $e');
      }
    }

    _tracks = await storage.loadTracks();"""

if old_save in c:
    c = c.replace(old_save, new_save)
    print("OK: Сохранение в SAF добавлено в FTP-метод")
else:
    print("WARN: Не нашли await storage.saveTracks(allTracks)")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)

# 2. Добавляем автоповтор в FTP-клиент
filepath = 'lib/services/ftp_client.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# Используем регулярное выражение, чтобы найти создание сокета
pattern = r"final socket = await Socket\.connect\(host, port, timeout: const Duration\(seconds: \d+\)\);"
replacement = """Socket? socket;
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
    if (socket == null) throw Exception('Не удалось подключиться к FTP');"""

if re.search(pattern, c):
    c = re.sub(pattern, replacement, c)
    print("OK: Автоповтор (3 попытки) добавлен в FTP-клиент")
else:
    print("WARN: Не нашли строку Socket.connect в ftp_client.dart")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)

print("\nГотово! Проверьте ошибки: flutter analyze")
