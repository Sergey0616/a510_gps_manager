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
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {count} замен.")

# 1. Откатываем ftp_client.dart (убираем sourceAddress)
filepath = 'lib/services/ftp_client.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace("static Future<FtpClient> connect(String host, int port, String username, String password, {InternetAddress? sourceAddress}) async {",
              "static Future<FtpClient> connect(String host, int port, String username, String password) async {")
c = re.sub(r",\s*sourceAddress:\s*sourceAddress", "", c)
c = re.sub(r",\s*sourceAddress:\s*_control\.address", "", c)
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: ftp_client.dart очищен")

# 2. Откатываем ftp_service.dart (убираем sourceAddress)
filepath = 'lib/services/ftp_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace(", sourceAddress: sourceAddress", "")
c = c.replace("    this.sourceAddress,\n", "")
c = c.replace("  final InternetAddress? sourceAddress;\n", "")
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: ftp_service.dart очищен")

# 3. Возвращаем нормальный вызов _ftp() и нативный bindToWifi
filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# Возвращаем _ftp без sourceAddress
c = c.replace("FtpService _ftp() => FtpService(host: _host, username: _username, password: _password, sourceAddress: _activeWifiIp);",
              "FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);")

# Упрощаем _withWifiNetwork (только bindToWifi)
old_with = re.search(r"InternetAddress\? _activeWifiIp;.*?Future<T> _withWifiNetwork<T>\(Future<T> Function\(\) action\) async \{.*?\n  \}", c, re.DOTALL)
if old_with:
    new_with = """Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    try {
      await _wifiChannel.invokeMethod('bindToWifi');
      AppLogger.log('[Net] Принудительно привязали процесс к Wi-Fi');
    } catch (e) {
      AppLogger.log('[Net] Ошибка привязки: $e');
    }
    try {
      return await action();
    } finally {
      try {
        await _wifiChannel.invokeMethod('unbindWifi');
        AppLogger.log('[Net] Отвязали процесс от Wi-Fi');
      } catch (_) {}
    }
  }"""
    c = c.replace(old_with.group(0), new_with)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен")

# 4. Добавляем логи в saveFilesToSaf
filepath = 'lib/services/local_folder_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

if 'AppLogger.log(\'[SAF] Начинаем' not in c:
    c = c.replace("""  static Future<void> saveFilesToSaf(String safDirUri, List<File> files) async {
    final saf = Saf();
    for (final file in files) {
      try {
        final name = file.path.split('/').last;
        final bytes = await file.readAsBytes();
        await saf.writeFileBytes(safDirUri, name, 'application/octet-stream', bytes);
        AppLogger.log('[SAF] Успешно сохранен: $name');
      } catch (e) {
        AppLogger.log('[SAF] Ошибка сохранения ${file.path}: $e');
      }
    }
  }""", """  static Future<void> saveFilesToSaf(String safDirUri, List<File> files) async {
    final saf = Saf();
    AppLogger.log('[SAF] Начинаем сохранение ${files.length} файлов в папку $safDirUri');
    for (final file in files) {
      try {
        final name = file.path.split('/').last;
        final bytes = await file.readAsBytes();
        await saf.writeFileBytes(safDirUri, name, 'application/octet-stream', bytes);
        AppLogger.log('[SAF] Успешно сохранен: $name');
      } catch (e) {
        AppLogger.log('[SAF] Ошибка сохранения ${file.path}: $e');
      }
    }
  }""")
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK: local_folder_service.dart (добавлены логи)")

print("\nГотово! Проверьте ошибки: flutter analyze")
