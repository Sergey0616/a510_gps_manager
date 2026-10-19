import os
import re

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

# 1. Патчим ftp_client.dart (добавляем sourceAddress)
try:
    with open('lib/services/ftp_client.dart', 'r', encoding='utf-8') as f:
        c = f.read()
    c = c.replace("static Future<FtpClient> connect(String host, int port, String user, String pass) async {",
                  "static Future<FtpClient> connect(String host, int port, String user, String pass, {InternetAddress? sourceAddress}) async {")
    c = re.sub(r"Socket\.connect\(([^)]+)\)", r"Socket.connect(\1, sourceAddress: sourceAddress)", c)
    with open('lib/services/ftp_client.dart', 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK: ftp_client.dart обновлен")
except Exception as e:
    print(f"WARN: ftp_client.dart - {e}")

# 2. Патчим ftp_service.dart (получаем Wi-Fi IP и добавляем удаление видео)
with open('lib/services/ftp_service.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Добавляем метод получения Wi-Fi IP
if "_getWifiAddress" not in c:
    c = c.replace("class FtpService {", """class FtpService {
  Future<InternetAddress?> _getWifiAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        if (iface.name.startsWith('wlan')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr;
          }
        }
      }
    } catch (_) {}
    return null;
  }
""")

# Заменяем вызовы connect на использование sourceAddress
c = c.replace("FtpClient.connect(host, port, username, password)", "FtpClient.connect(host, port, username, password, sourceAddress: await _getWifiAddress())")

# Добавляем метод удаления видео
if "deleteEventVideos" not in c:
    delete_method = """
  Future<int> deleteEventVideos() async {
    FtpClient? ftp;
    int deleted = 0;
    try {
      ftp = await FtpClient.connect(host, port, username, password, sourceAddress: await _getWifiAddress());
      final paths = ['/mnt/sd/Event', '/mnt/sd/events', '/mnt/sd/DCIM/Event', '/mnt/sd/DCIM/events'];
      bool found = false;
      for (final path in paths) {
        final cwd = await ftp.command('CWD $path');
        if (cwd.code < 400) {
          found = true;
          break;
        }
      }
      if (!found) return 0;
      final entries = await ftp.list('.');
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        try {
          await ftp.command('DELE ${entry.name}');
          deleted++;
        } catch (_) {}
      }
    } catch (e) {
      print('[FTP] deleteEventVideos error: $e');
    } finally {
      await ftp?.close();
    }
    return deleted;
  }
"""
    c = c.replace("  /// Скачивает сводный GPS-лог", delete_method + "\n  /// Скачивает сводный GPS-лог")
with open('lib/services/ftp_service.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: ftp_service.dart обновлен")

# 3. Патчим tracks_provider.dart (чиним проверку Wi-Fi)
with open('lib/providers/tracks_provider.dart', 'r', encoding='utf-8') as f:
    c = f.read()

old_wifi = """  Future<bool> _isOnRecorderWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.wifi)) return false;
      if (!await Permission.locationWhenInUse.isGranted) return false;
      final ssidRaw = await _wifiChannel.invokeMethod<String>('getWifiSsid');
      final ssid = (ssidRaw ?? '').replaceAll('"', '').trim();
      return ssid.startsWith('70mai_');
    } catch (_) {
      return false;
    }
  }"""
new_wifi = """  Future<bool> _isOnRecorderWifi() async {
    try {
      final wifiIp = await _getWifiAddress();
      if (wifiIp == null) return false;
      final socket = await Socket.connect(
        _host,
        21,
        sourceAddress: wifiIp,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }"""
c = c.replace(old_wifi, new_wifi)

if "_getWifiAddress" not in c:
    c = c.replace("  FtpService _ftp() =>", """  Future<InternetAddress?> _getWifiAddress() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        if (iface.name.startsWith('wlan')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  FtpService _ftp() =>""")

if "deleteRecorderVideos" not in c:
    c = c.replace("  Future<void> deleteTrack(Track track) async {", """  Future<int> deleteRecorderVideos() async {
    return await _ftp().deleteEventVideos();
  }

  Future<void> deleteTrack(Track track) async {""")

with open('lib/providers/tracks_provider.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен")

# 4. Патчим settings_screen.dart (кнопка удаления видео с регистратора)
with open('lib/screens/settings_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

if "_clearRecorderVideos" not in c:
    c = c.replace("  Future<void> _clearData() async {", """  Future<void> _clearRecorderVideos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить видео с регистратора?'),
        content: const Text('Будут удалены все файлы из папки Event на флешке регистратора.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _runningAction = true);
    try {
      final provider = context.read<TracksProvider>();
      final count = await provider.deleteRecorderVideos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Удалено файлов с регистратора: $count')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _clearData() async {""")

old_btn = """        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _clearData, icon: const Icon(Icons.delete_forever), label: const Text('Очистить всё'))),"""
new_btn = """        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _clearRecorderVideos, icon: const Icon(Icons.videocam_off), label: const Text('Удалить видео с регистратора'))),
        const SizedBox(height: 8),
        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _clearData, icon: const Icon(Icons.delete_forever), label: const Text('Очистить всё'))),"""
c = c.replace(old_btn, new_btn)

with open('lib/screens/settings_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: settings_screen.dart обновлен")

print("\nГотово! Проверьте ошибки: flutter analyze")
