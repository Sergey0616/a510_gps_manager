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

# 1. Находим и патчим MainActivity (добавляем метод getWifiIp)
res = subprocess.check_output(['find', 'android/app/src/main', '-name', 'MainActivity.*']).decode()
main_act_path = res.strip().split('\n')[0] if res.strip() else None
if main_act_path:
    patch_file(main_act_path, [
        (
            """if (call.method == "getWifiSsid") {""",
            """if (call.method == "getWifiIp") {
                    try {
                        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        val ip = manager.connectionInfo?.ipAddress
                        if (ip != null && ip != 0) {
                            val ipString = String.format("%d.%d.%d.%d", (ip and 0xff), (ip shr 8 and 0xff), (ip shr 16 and 0xff), (ip shr 24 and 0xff))
                            result.success(ipString)
                        } else {
                            result.success(null)
                        }
                    } catch (error: Exception) {
                        result.error("IP_ERROR", error.message, null)
                    }
                } else if (call.method == "getWifiSsid") {"""
        )
    ])

# 2. Патчим ftp_service.dart (добавляем sourceAddress в конструктор)
patch_file('lib/services/ftp_service.dart', [
    (
        """  FtpService({
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

  final InternetAddress? sourceAddress;"""
    )
])
with open('lib/services/ftp_service.dart', 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace("sourceAddress: await _getWifiAddress()", "sourceAddress: sourceAddress")
c = c.replace("sourceAddress: _getWifiAddress()", "sourceAddress: sourceAddress")
# Удаляем старый метод _getWifiAddress
c = re.sub(r"  Future<InternetAddress\?> _getWifiAddress\(\) async \{[\s\S]*?return null;\n  \}", "", c)
with open('lib/services/ftp_service.dart', 'w', encoding='utf-8') as f:
    f.write(c)

# 3. Патчим tracks_provider.dart (новая проверка Wi-Fi)
with open('lib/providers/tracks_provider.dart', 'r', encoding='utf-8') as f:
    c = f.read()

old_block = """  Future<InternetAddress?> _getWifiAddress() async {
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

  Future<bool> _isOnRecorderWifi() async {
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

new_block = """  InternetAddress? _activeWifiIp;

  Future<bool> _isOnRecorderWifi() async {
    _activeWifiIp = null;
    // 1. Прямое подключение (если мобильный интернет выключен или маршрут верный)
    try {
      final socket = await Socket.connect(_host, 21, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {}

    // 2. Через нативный IP (если мобильный интернет перебивает Wi-Fi)
    try {
      final wifiIpStr = await _wifiChannel.invokeMethod<String>('getWifiIp');
      if (wifiIpStr != null && wifiIpStr.isNotEmpty) {
        final wifiIp = InternetAddress(wifiIpStr);
        final socket = await Socket.connect(_host, 21, sourceAddress: wifiIp, timeout: const Duration(seconds: 2));
        socket.destroy();
        _activeWifiIp = wifiIp;
        return true;
      }
    } catch (_) {}

    return false;
  }"""
c = c.replace(old_block, new_block)

# Меняем создание _ftp() чтобы передавать _activeWifiIp
c = c.replace("FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);",
              "FtpService _ftp() => FtpService(host: _host, username: _username, password: _password, sourceAddress: _activeWifiIp);")

# В методе удаления видео тоже нужно обновить _activeWifiIp
c = c.replace("""  Future<int> deleteRecorderVideos() async {
    return await _ftp().deleteEventVideos();
  }""", """  Future<int> deleteRecorderVideos() async {
    await _isOnRecorderWifi();
    return await _ftp().deleteEventVideos();
  }""")

with open('lib/providers/tracks_provider.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен")

print("\nГотово! Проверьте ошибки: flutter analyze")
