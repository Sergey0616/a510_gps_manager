#!/usr/bin/env python3
"""Мега-патч: фикс слияния точек, ускорение SAF, кнопка HTTP в видео, защита long-press."""
import re
from pathlib import Path

def fix_tracks_provider():
    target = Path("lib/providers/tracks_provider.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")
    
    # Ищем блок слияния и заменяем его на список
    pattern = re.compile(r"final merged = <int, GpsPoint>\{\};.*?final mergedPoints = merged\.values\.toList\(\)\s*\.\.sort\(\(a, b\) => a\.timestamp\.compareTo\(b\.timestamp\)\);", re.DOTALL)
    new_code = """// ИСПРАВЛЕНИЕ: Собираем точки в список
  final mergedList = <GpsPoint>[];
  for (final track in freshTracks) { mergedList.addAll(track.points); }
  for (final track in gpsDataTracks) { mergedList.addAll(track.points); }
  
  final uniquePoints = <String, GpsPoint>{};
  for (final p in mergedList) {
    final key = '${p.timestamp}_${p.latitude}_${p.longitude}';
    uniquePoints[key] = p;
  }
  AppLogger.log('[Sync] GPSData: ${gpsDataTracks.length}, fresh: ${freshTracks.length}, merged points: ${uniquePoints.length}');
  
  final mergedPoints = uniquePoints.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));"""
    
    if pattern.search(text):
        text = pattern.sub(new_code, text, count=1)
        target.write_text(text, encoding="utf-8")
        print("✅ tracks_provider.dart: слияние точек исправлено")
    else:
        print("⚠️ tracks_provider.dart: блок слияния не найден (возможно, уже исправлен)")

def fix_local_folder_service():
    target = Path("lib/services/local_folder_service.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")
    
    # Добавляем проверку существующих файлов перед сохранением
    old_loop = """    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        final name = file.path.split('/').last;"""
    new_loop = """    final existingFiles = <String>{};
    try {
      await for (final entry in saf.walk(targetUri)) {
        if (!entry.file.isDir) existingFiles.add(entry.file.name);
      }
    } catch (_) {}

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final name = file.path.split('/').last;
      if (existingFiles.contains(name)) {
        onProgress?.call(i + 1, files.length);
        continue; // Пропускаем уже сохраненные
      }
      try {"""
    if old_loop in text:
        text = text.replace(old_loop, new_loop, 1)
        target.write_text(text, encoding="utf-8")
        print("✅ local_folder_service.dart: добавлена инкрементальная синхронизация")
    else:
        print("⚠️ local_folder_service.dart: шаблон не найден")

def fix_video_screen():
    target = Path("lib/screens/video_screen.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")
    
    old_trailing = """                    trailing: IconButton(
                      tooltip: file.isDownloaded ? 'Воспроизвести' : 'Скачать и воспроизвести',
                      onPressed: _downloading ? null : () => _downloadOne(file),
                      icon: Icon(file.isDownloaded ? (file.isPhoto ? Icons.photo : Icons.play_circle) : Icons.download),
                    ),"""
    new_trailing = """                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Смотреть онлайн (HTTP)',
                          onPressed: () {
                            final provider = context.read<TracksProvider>();
                            final url = 'http://${provider.host}${file.remotePath}';
                            Navigator.of(context).push(MaterialPageRoute<void>(
                              builder: (_) => VideoPlayerScreen(path: url, title: '${file.name} (Online)'),
                            ));
                          },
                          icon: const Icon(Icons.cloud_queue, color: Colors.blue),
                        ),
                        IconButton(
                          tooltip: file.isDownloaded ? 'Воспроизвести' : 'Скачать и воспроизвести',
                          onPressed: _downloading ? null : () => _downloadOne(file),
                          icon: Icon(file.isDownloaded ? (file.isPhoto ? Icons.photo : Icons.play_circle) : Icons.download),
                        ),
                      ],
                    ),"""
    if old_trailing in text:
        text = text.replace(old_trailing, new_trailing, 1)
        target.write_text(text, encoding="utf-8")
        print("✅ video_screen.dart: добавлена кнопка HTTP-просмотра")
    else:
        print("⚠️ video_screen.dart: кнопка не найдена")

def fix_map_screen():
    target = Path("lib/screens/map_screen.dart")
    if not target.exists(): return
    text = target.read_text(encoding="utf-8")
    
    # Оборачиваем в try/catch
    if "void _handleLongPress(LatLng tapPoint, List<Track> tracks) async {" in text and "try {" not in text[text.find("void _handleLongPress"):text.find("void _handleLongPress")+200]:
        text = text.replace(
            "void _handleLongPress(LatLng tapPoint, List<Track> tracks) async {",
            "void _handleLongPress(LatLng tapPoint, List<Track> tracks) async {\n    try {"
        )
        text = text.replace(
            "    Navigator.of(context).push(MaterialPageRoute(\n      builder: (_) => VideoPlayerScreen(\n        path: playPath,\n        title: videoName,\n        startPosition: startPos,\n      ),\n    ));\n  }",
            "    Navigator.of(context).push(MaterialPageRoute(\n      builder: (_) => VideoPlayerScreen(\n        path: playPath,\n        title: videoName,\n        startPosition: startPos,\n      ),\n    ));\n    } catch (e, st) {\n      AppLogger.log('[LongPress] Ошибка: $e\\n$st');\n      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));\n    }\n  }"
        )
        target.write_text(text, encoding="utf-8")
        print("✅ map_screen.dart: long-press обернут в try/catch")
    else:
        print("⚠️ map_screen.dart: либо уже исправлен, либо структура не совпала")

if __name__ == "__main__":
    fix_tracks_provider()
    fix_local_folder_service()
    fix_video_screen()
    fix_map_screen()
    print("Готово! Теперь запусти 'flutter analyze'")
