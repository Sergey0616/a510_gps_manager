import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

import '../models/gps_point.dart';
import '../models/track.dart';
import 'gpx_writer.dart';

/// Локальное хранилище исходных CSV, GPX и сводной таблицы.
class StorageService {
  Directory? _root;
  Directory? _gpsDirectory;
  Directory? _parsedDirectory;

  /// Отладочная информация о последнем loadTracks().
  String debug = '';

  Directory get gpsDirectory => _gpsDirectory ??
      (throw StateError('Хранилище не инициализировано'));
  Directory get parsedDirectory => _parsedDirectory ??
      (throw StateError('Хранилище не инициализировано'));

  Future<void> initialize() async {
    final external = await getExternalStorageDirectory();
    if (external == null) {
      throw FileSystemException('Внешний каталог приложения недоступен');
    }
    _root = Directory('${external.path}/A510_Exports');
    _gpsDirectory = Directory('${_root!.path}/gps');
    _parsedDirectory = Directory('${_root!.path}/parsed');
    await gpsDirectory.create(recursive: true);
    await parsedDirectory.create(recursive: true);
  }

  Future<void> saveTracks(List<Track> tracks) async {
    await parsedDirectory.create(recursive: true);
    if (tracks.isEmpty) return;

    await for (final entity in parsedDirectory.list()) {
      if (entity is File &&
          RegExp(r'^track_.*\.gpx$', caseSensitive: false)
              .hasMatch(entity.uri.pathSegments.last)) {
        await entity.delete();
      }
    }

    final writer = GpxWriter();
    final summary = StringBuffer()
      ..writeln('id,start_utc,end_utc,points,distance_km,duration_seconds,average_speed_kmh,max_speed_kmh');

    for (final track in tracks) {
      final safeId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${parsedDirectory.path}/track_$safeId.gpx');
      await file.writeAsString(writer.writeTrack(track), flush: true);
      summary.writeln([
        _csv(track.id),
        track.startUtc.toIso8601String(),
        track.endUtc.toIso8601String(),
        track.points.length,
        track.distanceKm.toStringAsFixed(3),
        track.duration.inSeconds,
        track.averageSpeedKmh.toStringAsFixed(2),
        track.maxSpeedKmh.toStringAsFixed(2),
      ].join(','));
    }
    await File('${parsedDirectory.path}/tracks_summary.csv')
        .writeAsString('\uFEFF$summary', flush: true);
  }

  Future<List<Track>> loadTracks() async {
    await parsedDirectory.create(recursive: true);
    final files = await parsedDirectory
        .list()
        .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.gpx'))
        .cast<File>()
        .toList();
    debug = 'dir=${parsedDirectory.path}; files=${files.length}';
    final tracks = <Track>[];

    for (final file in files) {
      try {
        var content = await file.readAsString();
        debug += '\n${file.path.split('/').last}: ${content.length}b';
        // Удаляем BOM и обрезаем пробелы — иначе XmlDocument.parse может упасть.
        content = content.replaceFirst('\uFEFF', '').trim();
        // Покажем начало файла для отладки.
        debug += '; head=${content.substring(0, content.length > 60 ? 60 : content.length).replaceAll('\n', '|')}';

        final XmlDocument xml;
        try {
          xml = XmlDocument.parse(content);
        } catch (e) {
          debug += '; XMLERR:$e';
          continue;
        }

        // Пробуем несколько стратегий поиска trkpt
        List<XmlElement> trkpts = xml
            .descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'trkpt')
            .toList();

        debug += '; s1=${trkpts.length}';

        if (trkpts.isEmpty) {
          trkpts = xml.findAllElements('trkpt', namespace: '*').toList();
          debug += '; s2=${trkpts.length}';
        }
        if (trkpts.isEmpty) {
          trkpts = xml.descendants.whereType<XmlElement>().where((e) => e.name.toString().contains('trkpt')).toList();
          debug += '; s3=${trkpts.length}';
        }

        final points = <GpsPoint>[];
        for (final element in trkpts) {
          final lat = double.tryParse(element.getAttribute('lat') ?? '');
          final lon = double.tryParse(element.getAttribute('lon') ?? '');
          if (lat == null || lon == null) continue;

          String? timeText;
          for (final child in element.childElements) {
            if (child.name.local == 'time') {
              timeText = child.innerText.trim();
              break;
            }
          }
          if (timeText == null) continue;

          final time = DateTime.tryParse(timeText);
          if (time == null) continue;

          var speedMps = 0.0;
          String? videoName;
          int? course;
          // speed может быть прямо в trkpt (новый формат) или внутри extensions (старый).
          // Также извлекаем videoName и course из extensions.
          for (final child in element.childElements) {
            if (child.name.local == 'speed') {
              speedMps = double.tryParse(child.innerText.trim()) ?? 0.0;
            } else if (child.name.local == 'extensions') {
              for (final ext in child.childElements) {
                if (ext.name.local == 'speed') {
                  speedMps = double.tryParse(ext.innerText.trim()) ?? 0.0;
                } else if (ext.name.local == 'video') {
                  final v = ext.innerText.trim();
                  if (v.isNotEmpty) videoName = v;
                } else if (ext.name.local == 'course') {
                  course = int.tryParse(ext.innerText.trim());
                }
              }
            }
          }

          if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
          points.add(GpsPoint(
            timestamp: time.toUtc().millisecondsSinceEpoch ~/ 1000,
            latitude: lat,
            longitude: lon,
            speedKmh: speedMps * 3.6,
            videoName: videoName,
            course: course,
          ));
        }
        debug += '; pts=${points.length}';

        if (points.isNotEmpty) {
          points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          tracks.add(Track(
            id: file.path.split('/').last.replaceFirst(RegExp(r'\.gpx$', caseSensitive: false), '').replaceFirst('track_', ''),
            points: points,
            gpxPath: file.path,
          ));
          debug += '; +track';
        }
      } catch (e, st) {
        debug += '; ERR:$e';
        continue;
      }
    }
    debug += '; done=${tracks.length}';
    tracks.sort((a, b) => b.startUtc.compareTo(a.startUtc));
    return tracks;
  }

  Future<int> getStorageSizeBytes() async {
    final root = _root;
    if (root == null || !await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // Файл мог исчезнуть во время подсчёта.
        }
      }
    }
    return total;
  }

  Future<void> clearAll() async {
    final root = _root;
    if (root != null && await root.exists()) await root.delete(recursive: true);
    await initialize();
  }

  String _basename(String path) => path.split(Platform.pathSeparator).last;
  String _csv(String value) => '"${value.replaceAll('"', '""')}"';
}
