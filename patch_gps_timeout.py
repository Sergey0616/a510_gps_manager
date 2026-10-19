import os

def patch_file(filepath, replacements):
    print(f"--- Патчим {filepath} ---")
    if not os.path.exists(filepath):
        print(f"ERROR: {filepath} не найден!")
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

patch_file('lib/services/ftp_service.dart', [
    # 1. Пропускаем уже скачанные файлы
    ("""      for (final entry in gpsFiles) {
        final target = File('${destination.path}/${entry.name}');
        final temp = File('${destination.path}/${entry.name}.part');
        try {""",
     """      for (final entry in gpsFiles) {
        final target = File('${destination.path}/${entry.name}');
        final temp = File('${destination.path}/${entry.name}.part');
        if (await target.exists()) {
          done++;
          onProgress?.call(done, gpsFiles.length);
          continue;
        }
        try {"""),
    
    # 2. Добавляем тайм-аут на list
    ("""      final entries = await ftp.list('.');""",
     """      final entries = await ftp.list('.').timeout(const Duration(seconds: 30));"""),
    
    # 3. Добавляем тайм-аут на скачивание
    ("""          await ftp.retrieveFile(entry.name, temp);""",
     """          await ftp.retrieveFile(entry.name, temp).timeout(const Duration(seconds: 30));"""),
    
    # 4. Тайм-аут на GPSData000001.txt
    ("""      await ftp.retrieveFile('GPSData000001.txt', temp);""",
     """      await ftp.retrieveFile('GPSData000001.txt', temp).timeout(const Duration(seconds: 90));""")
])

print("\nГотово! Теперь зависаний не будет.")
