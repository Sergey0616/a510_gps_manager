import re

def revert_file(filepath):
    print(f"--- Откатываем {filepath} ---")
    with open(filepath, 'r', encoding='utf-8') as f:
        c = f.read()

    # 1. Убираем sourceAddress из connect
    c = c.replace(
        "static Future<FtpClient> connect(String host, int port, String username, String password, {InternetAddress? sourceAddress}) async {",
        "static Future<FtpClient> connect(String host, int port, String username, String password) async {"
    )
    c = c.replace(", sourceAddress: sourceAddress", "")
    c = c.replace(", sourceAddress: _control.address", "")
    
    # 2. Убираем sourceAddress из ftp_service
    if 'ftp_service.dart' in filepath:
        c = c.replace(", sourceAddress: _activeWifiIp", "")
        c = c.replace(", sourceAddress: sourceAddress", "")
        # Если в конструкторе остался sourceAddress, удаляем его
        c = re.sub(r"\s*this\.sourceAddress,", "", c)
        c = re.sub(r"\s*final InternetAddress\? sourceAddress;", "", c)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK")

revert_file('lib/services/ftp_client.dart')
revert_file('lib/services/ftp_service.dart')

# 3. Возвращаем tracks_provider к нормальному вызову без sourceAddress
with open('lib/providers/tracks_provider.dart', 'r', encoding='utf-8') as f:
    c = f.read()
c = c.replace(", sourceAddress: _activeWifiIp", "")
with open('lib/providers/tracks_provider.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: tracks_provider.dart очищен от sourceAddress")
