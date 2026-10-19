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

# 1. Делаем методы синхронизации публичными в tracks_provider.dart
patch_file('lib/providers/tracks_provider.dart', [
    ("Future<void> _syncViaFtp() async {", "Future<void> syncViaFtp() async {"),
    ("Future<void> _syncFromLocalFolder() async {", "Future<void> syncFromLocalFolder() async {"),
    ("await _syncViaFtp();", "await syncViaFtp();"),
    ("await _syncFromLocalFolder();", "await syncFromLocalFolder();")
])

# 2. Добавляем диалог выбора в home_screen.dart
with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Заменяем прямой вызов synchronize на вызов диалога
c = c.replace(
    "onPressed: provider.busy ? null : provider.synchronize,",
    "onPressed: provider.busy ? null : () => _showSyncDialog(context, provider),"
)

# Добавляем сам метод диалога перед закрывающей скобкой класса
if "_showSyncDialog" not in c:
    c = c.replace("""}

class _StatRow extends StatelessWidget {""", """
  void _showSyncDialog(BuildContext context, TracksProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Откуда синхронизировать?'),
        content: const Text('Выберите источник данных:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.syncViaFtp();
            },
            child: const Text('С регистратора (Wi-Fi)'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.syncFromLocalFolder();
            },
            child: const Text('Из локальной папки'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {""")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print("OK: home_screen.dart обновлен")

print("\nГотово! Проверьте ошибки: flutter analyze")
