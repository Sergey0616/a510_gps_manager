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

patch_file('lib/services/gps_parser.dart', [
    ("""  Future<List<Track>> parseFiles(List<File> files) async {
    final points = <GpsPoint>[];
    for (final file in files) {
      try {
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        for (final line in content.split(RegExp(r'\\r?\\n'))) {
          final point = _parseLine(line);
          if (point != null) points.add(point);
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return _buildTracks(points);
  }""",
     """  Future<List<Track>> parseFiles(List<File> files) async {
    final points = <GpsPoint>[];
    print('[Parser] Начинаем парсинг ${files.length} файлов');
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        if (!await file.exists()) continue;
        print('[Parser] Файл ${i + 1}/${files.length}: ${file.path.split('/').last}');
        // Читаем построчно, чтобы не загружать весь файл в память
        final lines = file.readAsLines();
        await for (final line in lines) {
          final point = _parseLine(line);
          if (point != null) points.add(point);
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }
    print('[Parser] Собрано ${points.length} точек. Строим треки...');
    final tracks = _buildTracks(points);
    print('[Parser] Готово. Треков: ${tracks.length}');
    return tracks;
  }""")
])

print("\nГотово! Теперь парсер не будет загружать всё в память.")
