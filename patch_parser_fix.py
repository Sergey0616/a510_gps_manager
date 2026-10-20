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

# 1. Убираем таймауты со скачивания файлов (чтобы большие файлы успевали скачаться)
patch_file('lib/services/ftp_service.dart', [
    ("await ftp.retrieveFile(entry.name, temp).timeout(const Duration(seconds: 30));", "await ftp.retrieveFile(entry.name, temp);"),
    ("await ftp.retrieveFile('GPSData000001.txt', temp).timeout(const Duration(seconds: 90));", "await ftp.retrieveFile('GPSData000001.txt', temp);")
])

# 2. Возвращаем надежное чтение файлов и делаем парсер мягче
patch_file('lib/services/gps_parser.dart', [
    # Возвращаем readAsString
    ("""          final lines = await file.readAsLines();
          var lineCount = 0;
          for (final line in lines) {
            final point = _parseLine(line);
            if (point != null) points.add(point);
            lineCount++;
            if (lineCount % 5000 == 0) {
              await Future.delayed(Duration.zero);
            }
          }""",
     """          final content = await file.readAsString();
          final lines = content.split(RegExp(r'\\r?\\n'));
          var lineCount = 0;
          for (final line in lines) {
            final point = _parseLine(line);
            if (point != null) points.add(point);
            lineCount++;
            if (lineCount % 5000 == 0) {
              await Future.delayed(Duration.zero);
            }
          }"""),
    
    # Разрешаем 13 и более полей (на случай лишних запятых)
    ("""    final fields = line.trim().split(',');
    if (fields.length != 13) return null;""",
     """    final fields = line.trim().split(',');
    if (fields.length < 13) return null;""")
])

print("\nГотово! Теперь файлы будут читаться надежнее, а большие файлы успеют скачаться.")
