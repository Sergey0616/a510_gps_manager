import os
import re

# 1. Добавляем получение локального IP и привязку в tracks_provider.dart
filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# Убираем старую _withWifiNetwork, если она есть
c = re.sub(r"Future<T> _withWifiNetwork<T>\(Future<T> Function\(\) action\) async \{.*?\n  \}", "", c, flags=re.DOTALL)

# Добавляем новую переменную и метод
if 'InternetAddress? _activeWifiIp;' not in c:
    c = c.replace("FtpService _ftp() => FtpService(host: _host, username: _username, password: _password);",
"""InternetAddress? _activeWifiIp;

  Future<T> _withWifiNetwork<T>(Future<T> Function() action) async {
    _activeWifiIp = null;
    try {
      final ipStr = await _wifiChannel.invokeMethod<String>('getWifiIp');
      if (ipStr != null && ipStr.isNotEmpty) {
        _activeWifiIp = InternetAddress(ipStr);
        AppLogger.log('[Net] Локальный Wi-Fi IP: $ipStr');
      }
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      AppLogger.log('[Net] Ошибка получения IP: $e');
    }
    try {
      return await action();
    } finally {
      _activeWifiIp = null;
      AppLogger.log('[Net] Привязка к Wi-Fi сброшена');
    }
  }

  FtpService _ftp() => FtpService(host: _host, username: _username, password: _password, sourceAddress: _activeWifiIp);""")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен (локальный IP)")

# 2. FtpService принимает sourceAddress
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
    fs = re.sub(r"FtpClient\.connect\(([^)]+)\)", r"FtpClient.connect(\1, sourceAddress: sourceAddress)", fs)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(fs)
    print("OK: ftp_service.dart обновлен")

# 3. FtpClient использует sourceAddress
filepath = 'lib/services/ftp_client.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    fc = f.read()

if 'InternetAddress? sourceAddress' not in fc:
    fc = fc.replace("static Future<FtpClient> connect(String host, int port, String username, String password) async {",
                    "static Future<FtpClient> connect(String host, int port, String username, String password, {InternetAddress? sourceAddress}) async {")
    fc = fc.replace("socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));",
                    "socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5), sourceAddress: sourceAddress);")
    fc = fc.replace("return Socket.connect(address, dataPort, timeout: const Duration(seconds: 12));",
                    "return Socket.connect(address, dataPort, timeout: const Duration(seconds: 12), sourceAddress: sourceAddress);")
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(fc)
    print("OK: ftp_client.dart обновлен")

print("\nГотово! Проверьте ошибки: flutter analyze")
