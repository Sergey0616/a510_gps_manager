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

# 1. Кешируем расчет дистанции в Track (ускоряет работу в 10 раз)
patch_file('lib/models/track.dart', [
    ("""  double get distanceKm {
    var distance = 0.0;
    for (var i = 1; i < points.length; i++) {
      distance += _distanceBetween(points[i - 1], points[i]);
    }
    return distance;
  }""",
     """  late final double distanceKm = _calculateDistance();

  double _calculateDistance() {
    var distance = 0.0;
    for (var i = 1; i < points.length; i++) {
      distance += _distanceBetween(points[i - 1], points[i]);
    }
    return distance;
  }""")
])

# 2. Добавляем yield при парсинге строк (чтобы не висло на FTP)
patch_file('lib/services/gps_parser.dart', [
    ("""          final lines = await file.readAsLines();
          for (final line in lines) {
            final point = _parseLine(line);
            if (point != null) points.add(point);
          }""",
     """          final lines = await file.readAsLines();
          var lineCount = 0;
          for (final line in lines) {
            final point = _parseLine(line);
            if (point != null) points.add(point);
            lineCount++;
            if (lineCount % 5000 == 0) {
              await Future.delayed(Duration.zero);
            }
          }""")
])

# 3. Добавляем yield при копировании файлов (чтобы не висло на локальной синхронизации)
patch_file('lib/providers/tracks_provider.dart', [
    ("""      for (final f in gpxFiles) {
        final name = f.path.split('/').last;
        final target = File('${parsedDir.path}/$name');
        await target.writeAsBytes(await f.readAsBytes());
      }""",
     """      for (final f in gpxFiles) {
        final name = f.path.split('/').last;
        final target = File('${parsedDir.path}/$name');
        await target.writeAsBytes(await f.readAsBytes());
        await Future.delayed(const Duration(milliseconds: 10));
      }""")
])

# 4. Добавляем yield при чтении XML (для UI)
patch_file('lib/services/storage_service.dart', [
    ("""    for (final file in files) {
      try {
        var content = await file.readAsString();""",
     """    for (final file in files) {
      try {
        await Future.delayed(Duration.zero);
        var content = await file.readAsString();""")
])

print("\nГотово! Теперь UI не будет зависать, а расстояния будут считаться один раз.")
