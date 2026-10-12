import 'dart:io';

import '../models/gps_point.dart';
import '../models/track.dart';

/// Парсер CSV GPS регистратора.
class GpsParser {
  const GpsParser({this.maxGapSeconds = 60});

  final int maxGapSeconds;

  Future<List<Track>> parseFiles(List<File> files) async {
    final points = <GpsPoint>[];
    for (final file in files) {
      try {
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        for (final line in content.split(RegExp(r'\r?\n'))) {
          final point = _parseLine(line);
          if (point != null) points.add(point);
        }
      } on FileSystemException {
        // Пропускаем недоступный файл и продолжаем обработку остальных.
        continue;
      } on FormatException {
        continue;
      }
    }

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

  String _trackId(GpsPoint first, int number) => '${first.timestamp}_$number';
}
