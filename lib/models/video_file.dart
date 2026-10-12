import 'dart:io';

enum VideoCategory { normal, parking, event, photo }

extension VideoCategoryLabel on VideoCategory {
  String get label => switch (this) {
        VideoCategory.normal => 'Normal',
        VideoCategory.parking => 'Parking',
        VideoCategory.event => 'Event',
        VideoCategory.photo => 'Photo',
      };

  String get folderName => switch (this) {
        VideoCategory.normal => 'Normal',
        VideoCategory.parking => 'Parking',
        VideoCategory.event => 'Event',
        VideoCategory.photo => 'Photo',
      };
}

class VideoFile {
  VideoFile({
    required this.name,
    required this.remotePath,
    required this.category,
    required this.sizeBytes,
    required this.recordedAt,
    this.localPath,
  });

  final String name;
  final String remotePath;
  final VideoCategory category;
  final int sizeBytes;
  final DateTime? recordedAt;
  final String? localPath;

  bool get isDownloaded => localPath != null && File(localPath!).existsSync();
  bool get isPhoto => category == VideoCategory.photo || name.toLowerCase().endsWith('.jpg') || name.toLowerCase().endsWith('.jpeg');

  VideoFile copyWith({String? localPath}) => VideoFile(
        name: name,
        remotePath: remotePath,
        category: category,
        sizeBytes: sizeBytes,
        recordedAt: recordedAt,
        localPath: localPath ?? this.localPath,
      );

  static DateTime? parseDateFromName(String name) {
    // Ожидаемый шаблон: NOYYYYMMDD-HHMMSS-NNNNNNF.MP4 / ...R.MP4.
    final match = RegExp(r'NO(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-', caseSensitive: false).firstMatch(name);
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!),
        int.parse(match.group(4)!), int.parse(match.group(5)!), int.parse(match.group(6)!),
      );
    } on FormatException {
      return null;
    }
  }
}
