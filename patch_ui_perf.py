import os

filepath = 'lib/models/track.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Кэшируем maxSpeedKmh
c = c.replace(
"""  double get maxSpeedKmh => points.isEmpty
      ? 0
      : points.map((point) => point.speedKmh).reduce(math.max);""",
"""  late final double maxSpeedKmh = points.isEmpty
      ? 0
      : points.map((point) => point.speedKmh).reduce(math.max);"""
)

# 2. Кэшируем averageSpeedKmh
c = c.replace(
"""  double get averageSpeedKmh {
    final seconds = duration.inSeconds;
    return seconds <= 0 ? 0 : distanceKm * 3600 / seconds;
  }""",
"""  late final double averageSpeedKmh = _calculateAverageSpeed();

  double _calculateAverageSpeed() {
    final seconds = duration.inSeconds;
    return seconds <= 0 ? 0 : distanceKm * 3600 / seconds;
  }"""
)

# 3. Кэшируем videoNames
c = c.replace(
"""  Set<String> get videoNames => points
      .where((p) => p.videoName != null && p.videoName!.isNotEmpty)
      .map((p) => p.videoName!)
      .toSet();""",
"""  late final Set<String> videoNames = points
      .where((p) => p.videoName != null && p.videoName!.isNotEmpty)
      .map((p) => p.videoName!)
      .toSet();"""
)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: Модель Track обновлена (добавлено кэширование)")
