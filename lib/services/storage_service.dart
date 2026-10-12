import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../models/gps_point.dart';
import '../models/track.dart';
import 'gpx_writer.dart';

/// Локальное хранилище исходных CSV, GPX и сводной таблицы.
class StorageService {
  Directory? _root;
  Directory? _gpsDirectory;
  Directory? _parsedDirectory;

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
    final tracks = <Track>[];

    // Хелпер: первый дочерний элемент по локальному имени (без учёта namespace).
    XmlElement? childByLocal(XmlElement parent, String local) {
      for (final child in parent.childElements) {
        if (child.name.local == local) return child;
      }
      return null;
    }

    for (final file in files) {
      try {
        final xml = XmlDocument.parse(await file.readAsString());

        // Ищем все trkpt БЕЗ учёта namespace (GPX 1.1 использует default namespace).
        final trkpts = xml.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'trkpt')
            .toList();

        final points = <GpsPoint>[];
        for (final element in trkpts) {
          final lat = double.tryParse(element.getAttribute('lat') ?? '');
          final lon = double.tryParse(element.getAttribute('lon') ?? '');
          final timeEl = childByLocal(element, 'time');
          final timeText = timeEl?.innerText;
          if (lat == null || lon == null || timeText == null) continue;
          final time = DateTime.tryParse(timeText);
          if (time == null) continue;

          var speedText = '0';
          final extEl = childByLocal(element, 'extensions');
          if (extEl != null) {
            final speedEl = childByLocal(extEl, 'speed');
            if (speedEl != null) speedText = speedEl.innerText;
          }
          final speedMps = double.tryParse(speedText) ?? 0;
          if (!lat.isFinite || !lon.isFinite || lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
          points.add(GpsPoint(
            timestamp: time.toUtc().millisecondsSinceEpoch ~/ 1000,
            latitude: lat,
            longitude: lon,
            speedKmh: speedMps * 3.6,
          ));
        }
        if (points.isNotEmpty) {
          points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          tracks.add(Track(
            id: _basename(file.path).replaceFirst(RegExp(r'\.gpx$', caseSensitive: false), '').replaceFirst('track_', ''),
            points: points,
            gpxPath: file.path,
          ));
        }
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
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
