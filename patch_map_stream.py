#!/usr/bin/env python3
"""Патч: RTSP Live-трансляция + Long-press на карте для запуска видео (HTTP/локально) с нужной секунды."""
from pathlib import Path

TARGET = Path("lib/screens/map_screen.dart")
BACKUP = TARGET.with_suffix(".dart.bak")

def main():
    if not TARGET.exists():
        print(f"Не найден {TARGET}")
        return

    if not BACKUP.exists():
        BACKUP.write_text(TARGET.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"Бэкап: {BACKUP}")
    else:
        print(f"Бэкап уже существует: {BACKUP}")

    text = TARGET.read_text(encoding="utf-8")

    # 1. Импорты
    old_imports = "import 'dart:math' as math;\nimport 'package:flutter/material.dart';"
    new_imports = "import 'dart:io';\nimport 'dart:math' as math;\nimport 'package:flutter/material.dart';"
    if "import 'dart:io';" not in text:
        text = text.replace(old_imports, new_imports, 1)

    old_provider = "import '../providers/tracks_provider.dart';\nimport '../models/track.dart';"
    new_provider = "import '../providers/tracks_provider.dart';\nimport '../models/track.dart';\nimport '../models/gps_point.dart';\nimport '../models/video_file.dart';\nimport '../services/storage_paths.dart';\nimport 'video_player_screen.dart';"
    if "import 'video_player_screen.dart';" not in text:
        text = text.replace(old_provider, new_provider, 1)

    # 2. Кнопка Live в AppBar
    old_appbar = """          IconButton(
            tooltip: 'Обновить локальные треки',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<TracksProvider>().reloadFromDisk();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновление...')));
            },
          ),"""
    new_appbar = """          IconButton(
            tooltip: 'Live-трансляция (RTSP)',
            icon: const Icon(Icons.videocam),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const VideoPlayerScreen(
                  path: 'rtsp://192.168.0.1/liveRTSP/av4',
                  title: 'Live-трансляция',
                ),
              ));
            },
          ),
          IconButton(
            tooltip: 'Обновить локальные треки',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<TracksProvider>().reloadFromDisk();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Обновление...')));
            },
          ),"""
    if "tooltip: 'Live-трансляция (RTSP)'" not in text:
        if old_appbar in text:
            text = text.replace(old_appbar, new_appbar, 1)
        else:
            print("ВНИМАНИЕ: Не найден блок AppBar. Проверьте вручную.")

    # 3. Замена _handleLongPress
    old_stub = """  void _handleLongPress(LatLng tapPoint, List<Track> tracks) {
    // Заглушка для видео (если нужно, оставьте вашу логику)
  }"""
    new_long_press = """  void _handleLongPress(LatLng tapPoint, List<Track> tracks) async {
    GpsPoint? nearest;
    double minDistance = double.infinity;

    for (var track in tracks) {
      for (var p in track.points) {
        final dLat = (p.latitude - tapPoint.latitude) * 111320;
        final dLon = (p.longitude - tapPoint.longitude) * 111320 * math.cos(tapPoint.latitude * math.pi / 180);
        final dist = math.sqrt(dLat * dLat + dLon * dLon);
        if (dist < minDistance) {
          minDistance = dist;
          nearest = p;
        }
      }
    }

    if (nearest == null || minDistance > 150) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Рядом нет точек трека (ближе 150 м)')));
      return;
    }

    final videoName = nearest.videoName;
    if (videoName == null || videoName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('К этой точке не привязано видео')));
      return;
    }

    final videoTime = VideoFile.parseDateFromName(videoName);
    if (videoTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось распознать время файла')));
      return;
    }

    var startPos = nearest.timeUtc.difference(videoTime.toUtc());
    if (startPos.isNegative) startPos = Duration.zero;

    String? localPath;
    final base = await StoragePaths.baseDir();
    String category = 'Normal';
    String camera = videoName.toUpperCase().contains('R.MP4') ? 'Back' : 'Front';

    for (final cat in ['Normal', 'Parking', 'Event', 'Lapse']) {
      for (final cam in ['Front', 'Back', 'Rear']) {
        final f = File('${base.path}/video/$cat/$cam/$videoName');
        if (await f.exists()) {
          localPath = f.path;
          category = cat;
          camera = cam;
          break;
        }
      }
      if (localPath != null) break;
    }

    final String playPath = localPath ?? 'http://192.168.0.1/mnt/sd/$category/$camera/$videoName';
    final bool isLocal = localPath != null;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isLocal ? 'Открываем локальное видео с ${startPos.inSeconds} сек.' : 'Открываем онлайн с ${startPos.inSeconds} сек.'),
      duration: const Duration(seconds: 2),
    ));

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerScreen(
        path: playPath,
        title: videoName,
        startPosition: startPos,
      ),
    ));
  }"""
    if old_stub in text:
        text = text.replace(old_stub, new_long_press, 1)
    else:
        print("ВНИМАНИЕ: Не найден _handleLongPress. Возможно, патч уже применён.")

    TARGET.write_text(text, encoding="utf-8")
    print(f"Записан {TARGET} ({text.count(chr(10)) + 1} строк)")

if __name__ == "__main__":
    main()
