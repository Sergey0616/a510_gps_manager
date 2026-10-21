import os

filepath = 'lib/services/storage_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# Добавляем паузу в цикл чтения файлов, чтобы не блокировать UI
old_loop = """    for (final file in files) {
      try {
        await Future.delayed(Duration.zero);
        var content = await file.readAsString();"""
new_loop = """    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        // Даем UI-потоку отрисовать кадр, чтобы приложение не зависало
        await Future.delayed(const Duration(milliseconds: 10));
        var content = await file.readAsString();"""

if old_loop in c:
    c = c.replace(old_loop, new_loop)
    print("OK: Цикл loadTracks оптимизирован (добавлены паузы)")
else:
    print("WARN: Не нашли старый цикл for, возможно патч уже применён или код изменён.")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
