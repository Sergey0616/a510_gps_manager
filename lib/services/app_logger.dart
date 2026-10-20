import 'dart:io';

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
    _logFile?.writeAsStringSync('$line\n', mode: FileMode.append);
  }

  static String getLog() => _buffer.join('\n');

  static Future<void> clear() async {
    _buffer.clear();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }
}
