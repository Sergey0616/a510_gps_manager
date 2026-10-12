import '../models/track.dart';

/// Экспорт одного трека в GPX 1.1 (ручная генерация строк — надёжнее, чем
/// через XmlBuilder, где default namespace иногда превращается в `xmlns:URL`).
class GpxWriter {
  static const namespace = 'http://www.topografix.com/GPX/1/1';

  String writeTrack(Track track) {
    final b = StringBuffer();
    b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    b.writeln('<gpx version="1.1" creator="70mai A510 GPS Manager" xmlns="$namespace">');
    b.writeln('  <trk>');
    b.writeln('    <name>Трек ${track.startLocal}</name>');
    b.writeln('    <trkseg>');
    for (final p in track.points) {
      b.writeln('      <trkpt lat="${p.latitude.toStringAsFixed(7)}" lon="${p.longitude.toStringAsFixed(7)}">');
      b.writeln('        <time>${p.timeUtc.toIso8601String()}</time>');
      b.writeln('        <speed>${p.speedMps.toStringAsFixed(3)}</speed>');
      // Сохраняем имя MP4 и курс — нужны для открытия видео с точки на карте.
      final videoName = p.videoName;
      final course = p.course;
      if ((videoName != null && videoName.isNotEmpty) || course != null) {
        b.writeln('        <extensions>');
        if (videoName != null && videoName.isNotEmpty) {
          b.writeln('          <video>$videoName</video>');
        }
        if (course != null) {
          b.writeln('          <course>$course</course>');
        }
        b.writeln('        </extensions>');
      }
      b.writeln('      </trkpt>');
    }
    b.writeln('    </trkseg>');
    b.writeln('  </trk>');
    b.writeln('</gpx>');
    return b.toString();
  }
}
