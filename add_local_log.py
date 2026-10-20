import re

filepath = 'lib/screens/settings_screen.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    c = f.read()

# 1. Добавляем импорты, если их нет
if 'package:flutter/services.dart' not in c:
    c = c.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';")
if 'app_logger.dart' not in c:
    c = c.replace("import '../services/system_info_service.dart';", "import '../services/system_info_service.dart';\nimport '../services/app_logger.dart';")

# 2. Код кнопки
log_button = """        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.bug_report),
          title: const Text('Локальный лог (отладка)'),
          subtitle: const Text('Скопируйте и отправьте разработчику'),
          onTap: () {
            final log = AppLogger.getLog();
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Локальный лог'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: SelectableText(log.isEmpty ? 'Лог пуст' : log, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: log));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Скопировано')));
                    },
                    child: const Text('Копировать'),
                  ),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
                ],
              ),
            );
          },
        ),
        const Divider(height: 32),
"""

if 'Локальный лог (отладка)' not in c:
    # Ищем заголовок "О приложении" и вставляем перед ним
    target = "Text('О приложении'"
    if target in c:
        c = c.replace(target, log_button + "        " + target)
        print("OK: Кнопка локального лога успешно вставлена перед 'О приложении'")
    else:
        print("WARN: Не нашли 'О приложении'. Кнопка не добавлена.")
else:
    print("INFO: Кнопка уже есть в коде.")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(c)
