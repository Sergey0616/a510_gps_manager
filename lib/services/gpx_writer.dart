import 'package:xml/xml.dart';

import '../models/track.dart';

/// Экспорт одного трека в GPX 1.1.
class GpxWriter {
  static const namespace = 'http://www.topografix.com/GPX/1/1';

  String writeTrack(Track track) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'gpx',
      namespaces: {'': namespace},
      attributes: {'version': '1.1', 'creator': '70mai A510 GPS Manager'},
      nest: () {
        builder.element('trk', nest: () {
          builder.element('name', nest: () {
            builder.text('Трек ${track.startLocal}');
          });
          builder.element('trkseg', nest: () {
            for (final point in track.points) {
              builder.element('trkpt', attributes: {
                'lat': point.latitude.toStringAsFixed(7),
                'lon': point.longitude.toStringAsFixed(7),
              }, nest: () {
                builder.element('time', nest: () {
                  builder.text(point.timeUtc.toIso8601String());
                });
                builder.element('extensions', nest: () {
                  builder.element('speed', nest: () {
                    builder.text(point.speedMps.toStringAsFixed(3));
                  });
                });
              });
            }
          });
        });
      },
    );
    return builder.buildDocument().toXmlString(pretty: true, indent: '  ');
  }
}
