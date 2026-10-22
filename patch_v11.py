import os
import re

def patch_file(filepath, replacements):
    print(f"--- Патчим {filepath} ---")
    if not os.path.exists(filepath):
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

# 1. Меняем applicationId (решает конфликт на 100%)
with open('android/app/build.gradle', 'r', encoding='utf-8') as f:
    g = f.read()
g = g.replace('applicationId "ru.a510.gpsmanager"', 'applicationId "ru.a510.gpsmanager.v2"')
with open('android/app/build.gradle', 'w', encoding='utf-8') as f:
    f.write(g)
print("OK: applicationId изменен на v2")

# 2. Создаем подпапки в SAF
filepath = 'lib/services/local_folder_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    lfs = f.read()

pattern = r"static Future<void> saveFilesToSaf\(String safDirUri, List<File> files.*?\n  \}"
new_method = """static Future<void> saveFilesToSaf(String safDirUri, List<File> files, {String subfolder = 'gps', void Function(int, int)? onProgress}) async {
    final saf = Saf();
    AppLogger.log('[SAF] Начинаем сохранение ${files.length} файлов в подпапку $subfolder');
    
    String targetUri = safDirUri;
    try {
      final targetDir = await saf.mkdirp(safDirUri, [subfolder]);
      targetUri = targetDir.uri;
      AppLogger.log('[SAF] Создана/открыта подпапка: $targetUri');
    } catch (e) {
      AppLogger.log('[SAF] Ошибка создания подпапки: $e');
    }

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        final name = file.path.split('/').last;
        final bytes = await file.readAsBytes();
        await saf.writeFileBytes(targetUri, name, 'application/octet-stream', bytes);
        AppLogger.log('[SAF] Успешно сохранен: $name');
        onProgress?.call(i + 1, files.length);
        await Future.delayed(const Duration(milliseconds: 10));
      } catch (e) {
        AppLogger.log('[SAF] Ошибка сохранения ${file.path}: $e');
      }
    }
    AppLogger.log('[SAF] Завершено сохранение всех файлов');
  }"""
lfs = re.sub(pattern, new_method, lfs, flags=re.DOTALL)
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(lfs)
print("OK: LocalFolderService обновлен (подпапки)")

# 3. Передаем IP и подпапку
filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace(
    "await LocalFolderService.saveFilesToSaf(safUri, files, onProgress: (done, total) {",
    "await LocalFolderService.saveFilesToSaf(safUri, files, subfolder: 'gps', onProgress: (done, total) {"
)

old_with = re.search(r"InternetAddress\? _activeWifiIp;.*?Future<T> _withWifiNetwork<T>\(Future<T> Function\(\) action\) async \{.*?\n  \}", c, re.DOTALL)
if old_with:
    new_with = """InternetAddress? _activeWifiIp;

  Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    _activeWifiIp = null;
    try {
      await _wifiChannel.invokeMethod('bindToWifi');
      final ipStr = await _wifiChannel.invokeMethod<String>('getWifiIp');
      if (ipStr != null && ipStr.isNotEmpty) {
        _activeWifiIp = InternetAddress(ipStr);
        AppLogger.log('[Net] Привязались к локальному Wi-Fi IP: $ipStr');
      }
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      AppLogger.log('[Net] Ошибка привязки: $e');
    }
    try {
      return await action();
    } finally {
      try {
        await _wifiChannel.invokeMethod('unbindWifi');
        _activeWifiIp = null;
        AppLogger.log('[Net] Отвязали процесс от Wi-Fi');
      } catch (_) {}
    }
  }"""
    c = re.sub(r"InternetAddress\? _activeWifiIp;.*?Future<T> _withWifiNetwork<T>\(Future<T> Function\(\) action\) async \{.*?\n  \}", new_with, c, flags=re.DOTALL)

c = c.replace("FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);",
              "FtpService _ftp() => FtpService(host: _host, username: _username, password: _password, sourceAddress: _activeWifiIp);")
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен")

# 4. FtpService принимает sourceAddress
filepath = 'lib/services/ftp_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    fs = f.read()

if 'this.sourceAddress,' not in fs:
    fs = fs.replace("""  FtpService({
    required this.host,
    required this.username,
    required this.password,
    this.port = 21,
    this.remoteDirectory = '/mnt/other/4g_gps',
  });""", """  FtpService({
    required this.host,
    required this.username,
    required this.password,
    this.port = 21,
    this.remoteDirectory = '/mnt/other/4g_gps',
    this.sourceAddress,
  });

  final InternetAddress? sourceAddress;""")
    
    fs = fs.replace("FtpClient.connect(host, port, username, password)", "FtpClient.connect(host, port, username, password, sourceAddress: sourceAddress)")
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(fs)
    print("OK: ftp_service.dart обновлен")

# 5. FtpClient привязывает сокет
filepath = 'lib/services/ftp_client.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    fc = f.read()

if 'InternetAddress? sourceAddress' not in fc:
    fc = fc.replace("class FtpClient {\n  FtpClient(this._control, this._lines);", "class FtpClient {\n  FtpClient(this._control, this._lines, this._sourceAddress);")
    fc = fc.replace("  final StreamIterator<String> _lines;", "  final StreamIterator<String> _lines;\n  final InternetAddress? _sourceAddress;")
    
    fc = fc.replace("static Future<FtpClient> connect(String host, int port, String username, String password) async {", "static Future<FtpClient> connect(String host, int port, String username, String password, {InternetAddress? sourceAddress}) async {")
    fc = fc.replace("socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));", "socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5), sourceAddress: sourceAddress);")
    fc = fc.replace("final client = FtpClient(socket, StreamIterator<String>(socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())));", "final client = FtpClient(socket, StreamIterator<String>(socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())), sourceAddress);")
    
    fc = fc.replace("return Socket.connect(address, dataPort, timeout: const Duration(seconds: 12));", "return Socket.connect(address, dataPort, timeout: const Duration(seconds: 12), sourceAddress: _sourceAddress);")
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(fc)
    print("OK: ftp_client.dart обновлен")

print("\nГотово! Проверьте ошибки: flutter analyze")
