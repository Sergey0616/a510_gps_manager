import os
import re
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

# 1. Исправляем build.gradle для постоянной подписи
with open('android/app/build.gradle', 'r', encoding='utf-8') as f:
    g = f.read()

if 'signingConfigs' not in g:
    g = g.replace("android {\n", """android {
    signingConfigs {
        release {
            storeFile file("../../a510-key.jks")
            storePassword "a510pass"
            keyAlias "a510"
            keyPassword "a510pass"
        }
    }
""")
    g = g.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    with open('android/app/build.gradle', 'w', encoding='utf-8') as f:
        f.write(g)
    print("OK: build.gradle обновлен (постоянная подпись)")

# 2. Добавляем метод копирования в SAF
with open('lib/services/local_folder_service.dart', 'r', encoding='utf-8') as f:
    lfs = f.read()

if 'saveFilesToSaf' not in lfs:
    lfs = lfs.replace("  static Future<List<File>> extractGpxRecursive(String uri) async {", """  static Future<void> saveFilesToSaf(String safDirUri, List<File> files) async {
    final saf = Saf();
    for (final file in files) {
      try {
        final name = file.path.split('/').last;
        await saf.pasteLocalFile(file.path, safDirUri, destName: name);
      } catch (e) {
        print('[SAF] Ошибка сохранения \${file.path}: \$e');
      }
    }
  }

  static Future<List<File>> extractGpxRecursive(String uri) async {""")
    with open('lib/services/local_folder_service.dart', 'w', encoding='utf-8') as f:
        f.write(lfs)
    print("OK: LocalFolderService обновлен (метод saveFilesToSaf)")

# 3. Обновляем tracks_provider.dart (привязка к Wi-Fi + сохранение в SAF + очистка)
with open('lib/providers/tracks_provider.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# 3.1. Добавляем _withWifiNetwork
if '_withWifiNetwork' not in c:
    c = c.replace("FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);",
"""FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);

  Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    try { await _wifiChannel.invokeMethod('bindToWifi'); } catch (_) {}
    try { return await action(); } finally {
      try { await _wifiChannel.invokeMethod('unbindWifi'); } catch (_) {}
    }
  }""")

# 3.2. Оборачиваем FTP синхронизацию
if 'Future<void> _syncViaFtpInternal() async {' not in c:
    c = c.replace("""Future<void> syncViaFtp() async {
    _status = 'Загрузка GPSData000001.txt…';""", """Future<void> syncViaFtp() async {
    await _withWifiNetwork(() => _syncViaFtpInternal());
  }

  Future<void> _syncViaFtpInternal() async {
    _status = 'Загрузка GPSData000001.txt…';""")

# 3.3. Оборачиваем удаление видео
if 'Future<int> deleteRecorderVideos() async {\n    await _isOnRecorderWifi();' in c:
    c = c.replace("""Future<int> deleteRecorderVideos() async {
    await _isOnRecorderWifi();
    return await _ftp().deleteEventVideos();
  }""", """Future<int> deleteRecorderVideos() async {
    return await _withWifiNetwork(() async {
      return await _ftp().deleteEventVideos();
    });
  }""")

# 3.4. Сохранение в SAF после FTP
if 'Сохранение треков в локальную папку' not in c:
    c = c.replace("""    await storage.saveTracks(allTracks);
    _tracks = await storage.loadTracks();""", """    await storage.saveTracks(allTracks);
    
    final safUri = await LocalFolderService.getFolderUri();
    if (safUri != null) {
      _status = 'Сохранение треков в локальную папку…';
      notifyListeners();
      try {
        final files = await storage.parsedDirectory.list().where((e) => e is File && e.path.endsWith('.gpx')).cast<File>().toList();
        await LocalFolderService.saveFilesToSaf(safUri, files);
      } catch (e) {
        print('[SAF] Ошибка: \$e');
      }
    }

    _tracks = await storage.loadTracks();""")

# 3.5. Очистка старых файлов при локальной синхронизации
if 'Очищаем старые GPX файлы' not in c:
    c = c.replace("""    final parsedDir = storage.parsedDirectory;
    if (!await parsedDir.exists()) {
      await parsedDir.create(recursive: true);
    }
    for (final f in gpxFiles) {""", """    final parsedDir = storage.parsedDirectory;
    if (!await parsedDir.exists()) {
      await parsedDir.create(recursive: true);
    }
    
    final oldFiles = parsedDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gpx'));
    for (final f in oldFiles) {
      try { await f.delete(); } catch (_) {}
    }

    for (final f in gpxFiles) {""")

with open('lib/providers/tracks_provider.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен (Wi-Fi, SAF, очистка)")

# 4. Добавляем bindToWifi в MainActivity.kt
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
    print("OK: MainActivity.kt обновлен (bindToWifi)")

print("\nГотово! Проверьте ошибки: flutter analyze")
