import re
import os
import subprocess

def patch_file(filepath, replacements):
    print(f"--- Патчим {filepath} ---")
    if not os.path.exists(filepath):
        print(f"ERROR: {filepath} не найден!")
        return
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    count = 0
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            count += 1
        else:
            print(f"WARN: Не найден фрагмент:\n{old[:80]}...")
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {count} замен.")

# 1. Очистка старых GPX при локальной синхронизации
patch_file('lib/providers/tracks_provider.dart', [
    ("""  final parsedDir = storage.parsedDirectory;
  if (!await parsedDir.exists()) {
    await parsedDir.create(recursive: true);
  }
  for (final f in gpxFiles) {""",
     """  final parsedDir = storage.parsedDirectory;
  if (!await parsedDir.exists()) {
    await parsedDir.create(recursive: true);
  }
  // Очищаем старые GPX файлы, чтобы не смешивать с новыми
  final oldFiles = parsedDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gpx'));
  for (final f in oldFiles) {
    try { await f.delete(); } catch (_) {}
  }
  for (final f in gpxFiles) {"""),
    
    # Оборачиваем FTP в привязку к Wi-Fi
    ("""  Future<void> syncViaFtp() async {
    _status = 'Загрузка GPSData000001.txt…';""",
     """  Future<void> syncViaFtp() async {
    await _withWifiNetwork(() => _syncViaFtpInternal());
  }

  Future<void> _syncViaFtpInternal() async {
    _status = 'Загрузка GPSData000001.txt…';"""),

    ("""  FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);""",
     """  FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);

  Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    try { await _wifiChannel.invokeMethod('bindToWifi'); } catch (_) {}
    try { return await action(); } finally {
      try { await _wifiChannel.invokeMethod('unbindWifi'); } catch (_) {}
    }
  }"""),
    
    # Оборачиваем удаление видео
    ("""  Future<int> deleteRecorderVideos() async {
    await _isOnRecorderWifi();
    return await _ftp().deleteEventVideos();
  }""",
     """  Future<int> deleteRecorderVideos() async {
    return await _withWifiNetwork(() async {
      return await _ftp().deleteEventVideos();
    });
  }""")
])

# 2. Добавляем bindToWifi в MainActivity.kt
res = subprocess.check_output(['find', 'android/app/src/main', '-name', 'MainActivity.*']).decode()
main_act_path = res.strip().split('\n')[0]
with open(main_act_path, 'r', encoding='utf-8') as f:
    kotlin_code = f.read()

if "bindToWifi" not in kotlin_code:
    kotlin_code = kotlin_code.replace(
        "import android.os.StatFs",
        "import android.os.StatFs\nimport android.net.ConnectivityManager\nimport android.net.NetworkCapabilities"
    )
    kotlin_code = kotlin_code.replace(
        "override fun configureFlutterEngine(flutterEngine: FlutterEngine) {",
        """private fun bindToWifi(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network)
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                return cm.bindProcessToNetwork(network)
            }
        }
        return false
    }

    private fun unbindWifi() {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        cm.bindProcessToNetwork(null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {"""
    )
    kotlin_code = kotlin_code.replace(
        'if (call.method == "getWifiIp") {',
        '''if (call.method == "bindToWifi") {
                    result.success(bindToWifi())
                } else if (call.method == "unbindWifi") {
                    unbindWifi()
                    result.success(true)
                } else if (call.method == "getWifiIp") {'''
    )
    with open(main_act_path, 'w', encoding='utf-8') as f:
        f.write(kotlin_code)
    print("OK: MainActivity.kt обновлен (добавлен bindToWifi)")

# 3. Исправляем versionCode в build.gradle (базовый)
with open('android/app/build.gradle', 'r', encoding='utf-8') as f:
    g = f.read()
g = g.replace("versionCode 1", "versionCode 1000 + (System.getenv(\"GITHUB_RUN_NUMBER\")?.toInteger() ?: 1)")
with open('android/app/build.gradle', 'w', encoding='utf-8') as f:
    f.write(g)
print("OK: android/app/build.gradle versionCode обновлен")

# 4. Исправляем versionCode в оверлее (если он есть)
overlay_path = '.github/android-overlay/app/build.gradle'
if os.path.exists(overlay_path):
    with open(overlay_path, 'r', encoding='utf-8') as f:
        go = f.read()
    go = go.replace("versionCode flutter.versionCode", "versionCode 1000 + (System.getenv(\"GITHUB_RUN_NUMBER\")?.toInteger() ?: 1)")
    with open(overlay_path, 'w', encoding='utf-8') as f:
        f.write(go)
    print("OK: Оверлей build.gradle обновлен")

print("\nГотово! Проверьте ошибки: flutter analyze")
