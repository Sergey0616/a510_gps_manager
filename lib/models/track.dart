import 'dart:math' as math;

import 'gps_point.dart';

/// Непрерывный GPS-трек.
class Track {
  Track({required this.id, required List<GpsPoint> points, this.gpxPath})
      : points = List.unmodifiable(points);

  final String id;
  final List<GpsPoint> points;
  final String? gpxPath;

  DateTime get startUtc => points.first.timeUtc;
  DateTime get endUtc => points.last.timeUtc;
  DateTime get startLocal => startUtc.toLocal();

  Duration get duration => points.length < 2
      ? Duration.zero
      : endUtc.difference(startUtc);

  double get distanceKm {
    var distance = 0.0;
    for (var i = 1; i < points.length; i++) {
      distance += _distanceBetween(points[i - 1], points[i]);
    }
    return distance;
  }

  double get maxSpeedKmh => points.isEmpty
      ? 0
      : points.map((point) => point.speedKmh).reduce(math.max);

  double get averageSpeedKmh {
    final seconds = duration.inSeconds;
    return seconds <= 0 ? 0 : distanceKm * 3600 / seconds;
  }

  static double _distanceBetween(GpsPoint a, GpsPoint b) {
    const earthRadiusKm = 6371.0088;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final deltaLat = (b.latitude - a.latitude) * math.pi / 180;
    final deltaLon = (b.longitude - a.longitude) * math.pi / 180;
    final sinLat = math.sin(deltaLat / 2);
    final sinLon = math.sin(deltaLon / 2);
    final h = sinLat * sinLat +
        math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
    final safeH = h.clamp(0.0, 1.0).toDouble();
    final angle = 2 * math.atan2(
      math.sqrt(safeH),
      math.sqrt(1 - safeH),
    );
    return earthRadiusKm * angle;
  }
}
