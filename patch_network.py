import os

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

# Меняем проверку SSID на проверку доступности IP регистратора
old_check = """  Future<bool> _isOnRecorderWifi() async {
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

new_check = """  Future<bool> _isOnRecorderWifi() async {
    try {
      // Вместо ненадежного чтения SSID проверяем, доступен ли порт 21 (FTP)
      // на IP-адресе регистратора (обычно 192.168.0.1).
      final socket = await Socket.connect(
        _host, 
        21, 
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }"""

patch_file('lib/providers/tracks_provider.dart', [(old_check, new_check)])
print("\nГотово! Теперь приложение будет проверять реальную доступность регистратора.")
