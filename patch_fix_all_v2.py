#!/usr/bin/env python3
"""Мега-патч 2: Изоляция трека, фикс Wi-Fi, защита от пишущихся видео, лог дат."""
from pathlib import Path

def replace_once(path, old_text, new_text, file_desc):
    if not path.exists():
        print(f"❌ Файл {path} не найден")
        return
    content = path.read_text(encoding="utf-8")
    if old_text not in content:
        print(f"⚠️ {file_desc}: шаблон не найден (возможно, уже исправлен)")
        return
    content = content.replace(old_text, new_text, 1)
    path.write_text(content, encoding="utf-8")
    print(f"✅ {file_desc}: успешно обновлен")

def main():
    # 1. Изоляция Long-press в map_screen.dart
    map_path = Path("lib/screens/map_screen.dart")
    replace_once(
        map_path,
        "onLongPress: (_, tapPoint) => _handleLongPress(tapPoint, tracks),",
        "onLongPress: (_, tapPoint) => _handleLongPress(tapPoint, _selectedTrack),",
        "map_screen (вызов)"
    )
    replace_once(
        map_path,
        """  void _handleLongPress(LatLng tapPoint, List<Track> tracks) async {
    try {""",
        """  void _handleLongPress(LatLng tapPoint, Track? selectedTrack) async {
    try {
      if (selectedTrack == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сначала нажмите на трек, чтобы изолировать его')));
        return;
      }""",
        "map_screen (сигнатура)"
    )
    replace_once(
        map_path,
        """      for (var track in tracks) {
        for (var p in track.points) {
          final dLat = (p.latitude - tapPoint.latitude) * 111320;
          final dLon = (p.longitude - tapPoint.longitude) * 111320 * math.cos(tapPoint.latitude * math.pi / 180);
          final dist = math.sqrt(dLat * dLat + dLon * dLon);
          if (dist < minDistance) {
            minDistance = dist;
            nearest = p;
          }
        }
      }""",
        """      for (var p in selectedTrack.points) {
        final dLat = (p.latitude - tapPoint.latitude) * 111320;
        final dLon = (p.longitude - tapPoint.longitude) * 111320 * math.cos(tapPoint.latitude * math.pi / 180);
        final dist = math.sqrt(dLat * dLat + dLon * dLon);
        if (dist < minDistance) {
          minDistance = dist;
          nearest = p;
        }
      }""",
        "map_screen (цикл поиска)"
    )

    # 2. Улучшенный Wi-Fi bind в MainActivity.kt
    kotlin_path = Path("android/app/src/main/kotlin/ru/a510/gpsmanager/MainActivity.kt")
    replace_once(
        kotlin_path,
        """    private fun bindToWifi(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val network = wifiNetwork ?: cm.activeNetwork
        val caps = cm.getNetworkCapabilities(network)
        if (caps != null && caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) {
            return cm.bindProcessToNetwork(network)
        }
        return false
    }""",
        """    private fun bindToWifi(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        var wifiNet = wifiNetwork
        if (wifiNet == null) {
            for (net in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(net)
                if (caps != null && caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) {
                    wifiNet = net
                    break
                }
            }
        }
        return if (wifiNet != null) cm.bindProcessToNetwork(wifiNet) else false
    }""",
        "MainActivity.kt (bindToWifi)"
    )

    # 3. Защита от пишущегося видео в video_screen.dart
    video_path = Path("lib/screens/video_screen.dart")
    replace_once(
        video_path,
        """                            if (!mounted) return;
                            final url = 'http://${provider.host}${file.remotePath}';
                            Navigator.of(context).push(MaterialPageRoute<void>(""",
        """                            if (!mounted) return;
                            final url = 'http://${provider.host}${file.remotePath}';
                            if (file.recordedAt != null && DateTime.now().difference(file.recordedAt!).inMinutes < 5) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Видео ещё записывается, попробуйте позже')));
                              return;
                            }
                            Navigator.of(context).push(MaterialPageRoute<void>(""",
        "video_screen.dart (проверка записи)"
    )

    # 4. Логирование дат в tracks_provider.dart
    provider_path = Path("lib/providers/tracks_provider.dart")
    replace_once(
        provider_path,
        """    AppLogger.log('[Sync] GPSData: ${gpsDataTracks.length}, '
        'fresh: ${freshTracks.length}, merged points: ${uniquePoints.length}');""",
        """    final dates = uniquePoints.values.map((p) => p.timeUtc.toString().substring(0, 10)).toSet();
    AppLogger.log('[Sync] Найденные даты в точках: $dates');
    AppLogger.log('[Sync] GPSData: ${gpsDataTracks.length}, '
        'fresh: ${freshTracks.length}, merged points: ${uniquePoints.length}');""",
        "tracks_provider.dart (лог дат)"
    )

if __name__ == "__main__":
    main()
