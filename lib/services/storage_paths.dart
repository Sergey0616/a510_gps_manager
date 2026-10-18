import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Управление базовой папкой для сохранения файлов.
class StoragePaths {
  static const _prefsKey = 'save_dir_path';

  /// Базовая папка (пользовательская или стандартная).
  static Future<Directory> baseDir() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_prefsKey);
    if (custom != null && custom.isNotEmpty) {
      final d = Directory(custom);
      if (await d.exists()) return d;
    }
    // Пытаемся использовать публичную папку, которая не удаляется при удалении приложения
    if (Platform.isAndroid) {
      final publicDir = Directory('/storage/emulated/0/A510_Exports');
      try {
        if (await publicDir.exists() || await publicDir.create(recursive: true) != null) {
          return publicDir;
        }
      } catch (_) {}
    }
    // Запасной вариант — внутренняя папка приложения
    final external = await getExternalStorageDirectory();
    if (external == null) {
      throw FileSystemException('Внешнее хранилище недоступно');
    }
    return Directory('${external.path}/A510_Exports');
  }

  /// Выбранный путь или null.
  static Future<String?> getCustomPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  /// Путь по умолчанию.
  static Future<String> defaultPath() async {
    final external = await getExternalStorageDirectory();
    if (external == null) return 'A510_Exports';
    return '${external.path}/A510_Exports';
  }

  /// Установить пользовательскую папку. null — сброс.
  static Future<void> setCustomPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, path);
    }
  }
}
