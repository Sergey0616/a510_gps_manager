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

# 1. Исправляем LocalFolderService (добавляем логи и правильный mime)
patch_file('lib/services/local_folder_service.dart', [
    ("""  static Future<void> saveFilesToSaf(String safDirUri, List<File> files) async {
    final saf = Saf();
    for (final file in files) {
      try {
        final name = file.path.split('/').last;
        final bytes = await file.readAsBytes();
        await saf.writeFileBytes(safDirUri, name, 'application/gpx+xml', bytes);
      } catch (e) {
        print('[SAF] Ошибка сохранения \${file.path}: \$e');
      }
    }
  }""",
     """  static Future<void> saveFilesToSaf(String safDirUri, List<File> files) async {
    final saf = Saf();
    AppLogger.log('[SAF] Начинаем сохранение \${files.length} файлов в папку');
    for (final file in files) {
      try {
        final name = file.path.split('/').last;
        final bytes = await file.readAsBytes();
        await saf.writeFileBytes(safDirUri, name, 'application/octet-stream', bytes);
        AppLogger.log('[SAF] Успешно сохранен: \$name');
      } catch (e) {
        AppLogger.log('[SAF] Ошибка сохранения \${file.path}: \$e');
      }
    }
  }""")
])

# 2. Добавляем импорт логгера в LocalFolderService, если его нет
with open('lib/services/local_folder_service.dart', 'r', encoding='utf-8') as f:
    c = f.read()
if 'app_logger.dart' not in c:
    c = c.replace("import 'package:saf/saf.dart';", "import 'package:saf/saf.dart';\nimport 'app_logger.dart';")
    with open('lib/services/local_folder_service.dart', 'w', encoding='utf-8') as f:
        f.write(c)

# 3. Исправляем TracksProvider (получаем IP Wi-Fi и передаем в FTP)
with open('lib/providers/tracks_provider.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Убираем старый _withWifiNetwork и делаем новый, который сохраняет IP
if 'InternetAddress? _activeWifiIp;' not in c:
    old_with = re.search(r"Future<T> _withWifiNetwork<T>\(Future<T> Function\(\) action\) async \{.*?\n  \}", c, re.DOTALL)
    if old_with:
        new_with = """InternetAddress? _activeWifiIp;

  Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    _activeWifiIp = null;
    try {
      await _wifiChannel.invokeMethod('bindToWifi');
      final ipStr = await _wifiChannel.invokeMethod<String>('getWifiIp');
      if (ipStr != null && ipStr.isNotEmpty) {
        _activeWifiIp = InternetAddress(ipStr);
        AppLogger.log('[Net] Привязались к Wi-Fi IP: $ipStr');
      }
    } catch (e) {
      AppLogger.log('[Net] Ошибка привязки: $e');
    }
    try {
      return await action();
    } finally {
      try {
        await _wifiChannel.invokeMethod('unbindWifi');
        _activeWifiIp = null;
      } catch (_) {}
    }
  }"""
        c = c.replace(old_with.group(0), new_with)

# Передаем _activeWifiIp в _ftp()
c = c.replace("FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);",
              "FtpService _ftp() => FtpService(host: _host, username: _username, password: _password, sourceAddress: _activeWifiIp);")

with open('lib/providers/tracks_provider.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен (получение IP и привязка FTP)")

# 4. Добавляем sourceAddress в FtpService
with open('lib/services/ftp_service.dart', 'r', encoding='utf-8') as f:
    c = f.read()

if 'this.sourceAddress,' not in c:
    c = c.replace("""  FtpService({
    required this.host,
    required this.username,
    required this.password,
    this.port = 21,
    this.remoteDirectory = '/mnt/other/4g_gps',
  });""",
    """  FtpService({
    required this.host,
    required this.username,
    required this.password,
    this.port = 21,
    this.remoteDirectory = '/mnt/other/4g_gps',
    this.sourceAddress,
  });

  final InternetAddress? sourceAddress;""")

# Передаем sourceAddress во все вызовы FtpClient.connect
c = re.sub(r"FtpClient\.connect\(([^)]+)\)", r"FtpClient.connect(\1, sourceAddress: sourceAddress)", c)

with open('lib/services/ftp_service.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: ftp_service.dart обновлен (sourceAddress)")

# 5. Добавляем sourceAddress в FtpClient
with open('lib/services/ftp_client.dart', 'r', encoding='utf-8') as f:
    c = f.read()

if 'InternetAddress? sourceAddress' not in c:
    c = c.replace("static Future<FtpClient> connect(String host, int port, String username, String password) async {",
                  "static Future<FtpClient> connect(String host, int port, String username, String password, {InternetAddress? sourceAddress}) async {")
    c = c.replace("timeout: const Duration(seconds: 12)", "timeout: const Duration(seconds: 12), sourceAddress: sourceAddress")
    # Для пассивного сокета используем тот же интерфейс
    c = c.replace("sourceAddress: null", "sourceAddress: sourceAddress")
    with open('lib/services/ftp_client.dart', 'w', encoding='utf-8') as f:
        f.write(c)
print("OK: ftp_client.dart обновлен (sourceAddress)")
