filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

old_block = """  await storage.saveTracks(allTracks);
  _tracks = await storage.loadTracks();"""

new_block = """  await storage.saveTracks(allTracks);
  
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

if old_block in c:
    c = c.replace(old_block, new_block)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK: Сохранение в SAF успешно добавлено в FTP-метод")
else:
    print("WARN: Строки не совпали. Возможно, другой отступ.")
