import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalFolderService {
  static const _prefsUriKey = 'local_folder_saf_uri';
  static const _prefsNameKey = 'local_folder_saf_name';

  static Future<String?> pickFolder() async {
    final saf = Saf();
    final dir = await saf.pickDirectory();
    if (dir == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsUriKey, dir.uri);
    await prefs.setString(_prefsNameKey, dir.name);
    return dir.uri;
  }

  static Future<String?> getFolderUri() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_prefsUriKey);
    if (uri == null || uri.isEmpty) return null;
    return uri;
  }

  static Future<String?> getFolderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsNameKey);
  }

  static Future<void> clearFolderUri() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsUriKey);
    await prefs.remove(_prefsNameKey);
  }
  /// Рекурсивно собирает все .gpx из выбранной SAF-папки
  /// во временную директорию и возвращает список File.
  static Future<List<File>> extractGpxRecursive(String uri) async {
    final saf = Saf();
    final temp = await getTemporaryDirectory();
    final target = Directory('${temp.path}/a510_gpx_in');
    if (await target.exists()) {
      await target.delete(recursive: true);
    }
    await target.create(recursive: true);

    final result = <File>[];
    final seen = <String>{};

    await for (final entry in saf.walk(uri)) {
      if (entry.file.isDir) continue;
      if (!entry.file.name.toLowerCase().endsWith('.gpx')) continue;

      var name = entry.file.name;
      if (seen.contains(name)) {
        final base = name.substring(0, name.length - 4);
        var i = 1;
        while (seen.contains('${base}_$i.gpx')) {
          i++;
        }
        name = '${base}_$i.gpx';
      }
      seen.add(name);

      try {
        final Uint8List bytes = await saf.readFileBytes(entry.file.uri);
        if (bytes.isEmpty) continue;
        final file = File('${target.path}/$name');
        await file.writeAsBytes(bytes);
        result.add(file);
      } catch (_) {}
    }
    return result;
  }
}
