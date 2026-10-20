import 'dart:io';

import '../models/gps_point.dart';
import '../models/track.dart';

/// Парсер CSV GPS регистратора.
class GpsParser {
  const GpsParser({this.maxGapSeconds = 60});

  final int maxGapSeconds;

  /// Парсит старый формат `/mnt/other/4g_gps/gps_*` (13 полей, speed в км/ч).
  Future<List<Track>> parseFiles(List<File> files) async {
    final points = <GpsPoint>[];
    print('[Parser] Начинаем парсинг ${files.length} файлов');
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        if (!await file.exists()) continue;
        print('[Parser] Файл ${i + 1}/${files.length}: ${file.path.split('/').last}');
        // Читаем построчно, чтобы не загружать весь файл в память
        final lines = await file.readAsLines();
        for (final line in lines) {
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
  }

  /// Парсит новый формат `/mnt/sd/GPSData000001.txt`.
  /// CSV, первая строка — заголовок `$V02`, далее 13 полей.
  /// Формула скорости: speed_kmh = fields[4] / 1000.
  Future<List<Track>> parseGpsDataFile(String content) async {
    final points = <GpsPoint>[];
    final lines = content.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (line.startsWith('\$')) continue; // заголовок $V02
      final point = _parseGpsDataLine(line);
      if (point != null) points.add(point);
    }
    return _buildTracks(points);
  }

  /// Публичный метод: собрать треки из готового списка точек.
  /// Используется после merge из двух источников.
  List<Track> buildTracksFromPoints(List<GpsPoint> points) => _buildTracks(points);

  /// Собирает точки в треки, объединяет близкие по времени и сортирует.
  List<Track> _buildTracks(List<GpsPoint> points) {
    points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (points.isEmpty) return <Track>[];

    final tracks = <Track>[];
    var current = <GpsPoint>[points.first];
    var number = 1;

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      if (point.timestamp - previous.timestamp > maxGapSeconds) {
        tracks.add(Track(id: _trackId(current.first, number++), points: current));
        current = <GpsPoint>[];
      }
      current.add(point);
    }
    if (current.isNotEmpty) {
      tracks.add(Track(id: _trackId(current.first, number), points: current));
    }
    return tracks;
  }

  GpsPoint? _parseLine(String line) {
    if (line.trim().isEmpty) return null;
    final fields = line.trim().split(',');
    if (fields.length != 13) return null;

    try {
      final timestamp = int.parse(fields[0].trim());
      final latitude = double.parse(fields[1].trim());
      final longitude = double.parse(fields[2].trim());
      final speed = double.parse(fields[4].trim());
      if (timestamp < 0 ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          !speed.isFinite ||
          latitude < -90 || latitude > 90 ||
          longitude < -180 || longitude > 180 ||
          speed < 0) {
        return null;
      }
      return GpsPoint(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        speedKmh: speed,
      );
    } on FormatException {
      return null;
    }
  }

  GpsPoint? _parseGpsDataLine(String line) {
    final fields = line.split(',');
    if (fields.length < 10) return null;

    try {
      final timestamp = int.parse(fields[0].trim());
      final status = fields[1].trim();
      if (status != 'A') return null; // только активные точки
      final latitude = double.parse(fields[2].trim());
      final longitude = double.parse(fields[3].trim());
      final speedRaw = int.parse(fields[4].trim());
      final courseRaw = int.tryParse(fields[5].trim()) ?? 0;
      final tiltRaw = int.tryParse(fields[6].trim()) ?? 0;
      final videoName = fields[9].trim();

      if (timestamp < 0 ||
          !latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 || latitude > 90 ||
          longitude < -180 || longitude > 180) {
        return null;
      }
      return GpsPoint(
        timestamp: timestamp,
        latitude: latitude,
        longitude: longitude,
        speedKmh: speedRaw / 1000.0,
        videoName: videoName.isEmpty ? null : videoName,
        course: courseRaw,
        tilt: tiltRaw,
      );
    } on FormatException {
      return null;
    }
  }

  String _trackId(GpsPoint first, int number) => '${first.timestamp}_$number';
}
