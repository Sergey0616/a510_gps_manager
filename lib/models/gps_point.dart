import 'package:latlong2/latlong.dart';

/// Одна GPS-точка из CSV регистратора.
class GpsPoint {
  const GpsPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    this.videoName,
    this.course,
    this.tilt,
  });

  /// Unix timestamp в секундах UTC.
  final int timestamp;
  final double latitude;
  final double longitude;
  final double speedKmh;

  /// Имя MP4-файла (для GPSData-источника).
  final String? videoName;

  /// Курс в градусах (0-360).
  final int? course;

  /// Наклон в градусах.
  final int? tilt;

  DateTime get timeUtc =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
  LatLng get position => LatLng(latitude, longitude);
  double get speedMps => speedKmh / 3.6;
}
