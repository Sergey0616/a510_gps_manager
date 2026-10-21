filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

old_sync = """    await storage.initialize();
    final parsedDir = storage.parsedDirectory;
    if (!await parsedDir.exists()) {
      await parsedDir.create(recursive: true);
    }
    for (final f in gpxFiles) {"""
new_sync = """    await storage.initialize();
    final parsedDir = storage.parsedDirectory;
    if (!await parsedDir.exists()) {
      await parsedDir.create(recursive: true);
    }
    
    // Очищаем старые GPX файлы перед копированием новых
    final oldFiles = parsedDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gpx'));
    for (final f in oldFiles) {
      try { await f.delete(); } catch (_) {}
    }

    for (final f in gpxFiles) {"""
if old_sync in c:
    c = c.replace(old_sync, new_sync)
    print("OK: Локальная синхронизация теперь будет чистить старые файлы")
else:
    print("WARN: Не нашли блок копирования в syncFromLocalFolder")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
