import os
import re

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

# 1. Создаем AppLogger
logger_code = """import 'dart:io';

class AppLogger {
  static final List<String> _buffer = [];
  static File? _logFile;

  static Future<void> init(Directory baseDir) async {
    final logDir = Directory('${baseDir.path}/logs');
    if (!await logDir.exists()) await logDir.create(recursive: true);
    _logFile = File('${logDir.path}/app_debug.log');
    if (await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
    log('=== AppLogger initialized ===');
  }

  static void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $message';
    _buffer.add(line);
    if (_buffer.length > 10000) _buffer.removeAt(0);
    _logFile?.writeAsStringSync('$line\\n', mode: FileMode.append);
  }

  static String getLog() => _buffer.join('\\n');

  static Future<void> clear() async {
    _buffer.clear();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }
}
"""
os.makedirs('lib/services', exist_ok=True)
with open('lib/services/app_logger.dart', 'w', encoding='utf-8') as f:
    f.write(logger_code)
print("OK: app_logger.dart создан")

# 2. Патчим tracks_provider.dart (добавляем init и заменяем print)
patch_file('lib/providers/tracks_provider.dart', [
    ("import '../services/ftp_service.dart';", "import '../services/ftp_service.dart';\nimport '../services/app_logger.dart';"),
    ("await storage.initialize();\n    final prefs", "await storage.initialize();\n    await AppLogger.init(storage.parsedDirectory.parent);\n    final prefs"),
])
with open('lib/providers/tracks_provider.dart', 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace('print(', 'AppLogger.log(')
with open('lib/providers/tracks_provider.dart', 'w', encoding='utf-8') as f:
    f.write(c)

# 3. Патчим ftp_service.dart и ftp_client.dart (заменяем print и добавляем импорт)
for file in ['lib/services/ftp_service.dart', 'lib/services/ftp_client.dart']:
    with open(file, 'r', encoding='utf-8') as f:
        c = f.read()
    if 'app_logger.dart' not in c:
        c = c.replace("import 'ftp_client.dart';", "import 'ftp_client.dart';\nimport 'app_logger.dart';")
        c = c.replace("import 'dart:io';", "import 'dart:io';\nimport 'app_logger.dart';")
    c = c.replace('print(', 'AppLogger.log(')
    with open(file, 'w', encoding='utf-8') as f:
        f.write(c)
    print(f"OK: {file} обновлен")

# 4. Патчим gps_parser.dart (добавляем импорт и подробный лог)
with open('lib/services/gps_parser.dart', 'r', encoding='utf-8') as f:
    c = f.read()
if 'app_logger.dart' not in c:
    c = c.replace("import '../models/track.dart';", "import '../models/track.dart';\nimport 'app_logger.dart';")

c = c.replace("""          final content = await file.readAsString();
          final lines = content.split(RegExp(r'\\r?\\n'));
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
          var filePoints = 0;
          for (final line in lines) {
            final point = _parseLine(line);
            if (point != null) { points.add(point); filePoints++; }
            lineCount++;
            if (lineCount % 5000 == 0) {
              await Future.delayed(Duration.zero);
            }
          }
          AppLogger.log('[Parser] Файл ${file.path.split('/').last}: $lineCount строк, $filePoints точек');""")

c = c.replace("""    return _buildTracks(points);
  }

  /// Парсит новый формат""", """    AppLogger.log('[Parser] Всего собрано ${points.length} точек. Запуск _buildTracks');
    final result = _buildTracks(points);
    AppLogger.log('[Parser] Парсинг завершен. Получено ${result.length} треков');
    return result;
  }

  /// Парсит новый формат""")

c = c.replace("""  List<Track> _buildTracks(List<GpsPoint> points) {
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));""",
"""  List<Track> _buildTracks(List<GpsPoint> points) {
    AppLogger.log('[Parser] _buildTracks: входных точек ${points.length}');
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));""")

c = c.replace("""    return tracks;
  }

  GpsPoint? _parseLine""", """    AppLogger.log('[Parser] _buildTracks: создано ${tracks.length} треков');
    return tracks;
  }

  GpsPoint? _parseLine""")

with open('lib/services/gps_parser.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: gps_parser.dart обновлен (добавлены логи)")

# 5. Патчим storage_service.dart (логи в loadTracks)
with open('lib/services/storage_service.dart', 'r', encoding='utf-8') as f:
    c = f.read()
if 'app_logger.dart' not in c:
    c = c.replace("import 'storage_paths.dart';", "import 'storage_paths.dart';\nimport 'app_logger.dart';")

c = c.replace("""    debug = 'dir=${parsedDirectory.path}; files=${files.length}';""",
"""    debug = 'dir=${parsedDirectory.path}; files=${files.length}';
    AppLogger.log('[Storage] loadTracks: найдено ${files.length} GPX файлов в ${parsedDirectory.path}');""")

c = c.replace("""    debug += '; done=${tracks.length}';""",
"""    debug += '; done=${tracks.length}';
    AppLogger.log('[Storage] loadTracks: успешно загружено ${tracks.length} треков');""")

with open('lib/services/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: storage_service.dart обновлен (логи в loadTracks)")

# 6. Патчим settings_screen.dart (добавляем кнопку показа лога)
with open('lib/screens/settings_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()
if 'app_logger.dart' not in c:
    c = c.replace("import '../services/system_info_service.dart';", "import '../services/system_info_service.dart';\nimport '../services/app_logger.dart';")
if 'package:flutter/services.dart' not in c:
    c = c.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';")

# Ищем место перед "О приложении" и вставляем кнопку лога
old_block = """        const Divider(height: 32),
        Text('О приложении', style: Theme.of(context).textTheme.titleLarge),"""
new_block = """        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report),
          title: const Text('Показать локальный лог (отладка)'),
          onTap: () {
            final log = AppLogger.getLog();
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Локальный лог'),
                content: SingleChildScrollView(
                  child: SelectableText(log.isEmpty ? 'Лог пуст' : log),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: log));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Лог скопирован')));
                    },
                    child: const Text('Копировать'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 32),
        Text('О приложении', style: Theme.of(context).textTheme.titleLarge),"""
c = c.replace(old_block, new_block)
with open('lib/screens/settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: settings_screen.dart обновлен (кнопка лога)")

print("\nГотово! Теперь у нас есть подробный лог. Соберите APK, запустите синхронизацию, подождите и нажмите в настройках 'Показать локальный лог (отладка)'.")
