import 'package:latlong2/latlong.dart';

/// Одна GPS-точка из CSV регистратора.
class GpsPoint {
  const GpsPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
  });

  /// Unix timestamp в секундах UTC.
  final int timestamp;
  final double latitude;
  final double longitude;
  final double speedKmh;

  DateTime get timeUtc =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
  LatLng get position => LatLng(latitude, longitude);
  double get speedMps => speedKmh / 3.6;
}
