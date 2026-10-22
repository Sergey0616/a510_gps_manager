import os
import re
import subprocess

# 1. Обновляем MainActivity.kt (используем NetworkCallback для надежности)
res = subprocess.check_output(['find', 'android/app/src/main', '-name', 'MainActivity.*']).decode()
main_act_path = res.strip().split('\n')[0]
with open(main_act_path, 'r', encoding='utf-8') as f:
    kotlin_code = f.read()

# Добавляем NetworkCallback для отслеживания Wi-Fi
if "registerNetworkCallback" not in kotlin_code:
    kotlin_code = kotlin_code.replace(
        "class MainActivity : FlutterActivity() {",
        """class MainActivity : FlutterActivity() {
    private var wifiNetwork: android.net.Network? = null
    private val networkCallback = object : android.net.ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: android.net.Network) {
            wifiNetwork = network
        }
        override fun onLost(network: android.net.Network) {
            if (wifiNetwork == network) wifiNetwork = null
        }
    }
"""
    )
    
    # Переписываем bindToWifi
    kotlin_code = re.sub(r"private fun bindToWifi\(\): Boolean \{.*?\n    \}", """private fun bindToWifi(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val network = wifiNetwork ?: cm.activeNetwork
        val caps = cm.getNetworkCapabilities(network)
        if (caps != null && caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)) {
            return cm.bindProcessToNetwork(network)
        }
        return false
    }""", kotlin_code, flags=re.DOTALL)
    
    # Регистрируем коллбэк при старте
    kotlin_code = kotlin_code.replace(
        "super.configureFlutterEngine(flutterEngine)",
        """super.configureFlutterEngine(flutterEngine)
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val request = android.net.NetworkRequest.Builder()
            .addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        cm.registerNetworkCallback(request, networkCallback)"""
    )
    
    with open(main_act_path, 'w', encoding='utf-8') as f:
        f.write(kotlin_code)
    print("OK: MainActivity.kt обновлен (NetworkCallback)")

# 2. Исправляем логи и добавляем обновление прогресса в SAF
filepath = 'lib/services/local_folder_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# Убираем лишние слеши перед $ и исправляем текст
c = c.replace("\\${files.length}", "${files.length}")
c = c.replace("\\$name", "$name")
c = c.replace("\\$safDirUri", "$safDirUri")
c = c.replace("\\$e", "$e")
c = c.replace("\\${file.path}", "${file.path}")

# Добавляем коллбэк прогресса
if "Future<void> saveFilesToSaf(String safDirUri, List<File> files, {void Function(int, int)? onProgress})" not in c:
    c = c.replace(
        "static Future<void> saveFilesToSaf(String safDirUri, List<File> files) async {",
        "static Future<void> saveFilesToSaf(String safDirUri, List<File> files, {void Function(int, int)? onProgress}) async {"
    )
    c = c.replace(
        "    for (final file in files) {",
        "    for (var i = 0; i < files.length; i++) {\n      final file = files[i];"
    )
    c = c.replace(
        "        AppLogger.log('[SAF] Успешно сохранен: $name');",
        "        AppLogger.log('[SAF] Успешно сохранен: $name');\n        onProgress?.call(i + 1, files.length);"
    )
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK: local_folder_service.dart обновлен (прогресс и логи)")

# 3. Передаем прогресс в UI
filepath = 'lib/providers/tracks_provider.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace(
    "await LocalFolderService.saveFilesToSaf(safUri, files);",
    """await LocalFolderService.saveFilesToSaf(safUri, files, onProgress: (done, total) {
        _status = 'Сохранение в папку: $done из $total';
        notifyListeners();
      });"""
)
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart обновлен (передача прогресса)")

print("\nГотово! Проверьте ошибки: flutter analyze")
