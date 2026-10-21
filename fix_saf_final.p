import os

# 1. Исправляем вызов writeFileBytes (4-й аргумент позиционный)
filepath = 'lib/services/local_folder_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

old_call = "await saf.writeFileBytes(safDirUri, name, bytes, mimeType: 'application/gpx+xml');"
new_call = "await saf.writeFileBytes(safDirUri, name, bytes, 'application/gpx+xml');"

if old_call in c:
    c = c.replace(old_call, new_call)
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(c)
    print("OK: writeFileBytes исправлен (позиционный аргумент)")
else:
    print("WARN: Не нашли вызов writeFileBytes")

# 2. Убираем дубликаты импортов в ftp_service.dart
filepath = 'lib/services/ftp_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

seen = set()
new_lines = []
for line in lines:
    if line.startswith('import '):
        if line in seen:
            continue # Пропускаем дубликат
        seen.add(line)
    new_lines.append(line)

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
print("OK: Дубликаты импортов в ftp_service.dart удалены")

# 3. Убираем неиспользуемые импорты в main.dart
filepath = 'lib/main.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace("import 'dart:io';\n", "")
c = c.replace("import 'package:permission_handler/permission_handler.dart';\n", "")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: Лишние импорты в main.dart удалены")
