import os, re, sys

def patch_file(filepath, replacements, description):
    print(f"--- Патчим {description} ---")
    if not os.path.exists(filepath):
        print(f"ERROR: {filepath} не найден!")
        return False
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    count = 0
    for old, new in replacements:
        if old in content:
            content = content.replace(old, new)
            count += 1
        else:
            print(f"WARN: Не найден фрагмент для замены:\n{old[:80]}...")
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"OK: {count} замен в {description}")
    return True

# --- 1. Фильтр треков (storage_service.dart) ---
old_filter = """        if (points.isNotEmpty) {
          points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          tracks.add(Track(
            id: file.path.split('/').last.replaceFirst(RegExp(r'\\.gpx$', caseSensitive: false), '').replaceFirst('track_', ''),
            points: points,
            gpxPath: file.path,
          ));
          debug += '; +track';
        }"""
new_filter = """        if (points.isNotEmpty) {
          points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          final candidate = Track(
            id: file.path
                .split('/')
                .last
                .replaceFirst(RegExp(r'\\.gpx$', caseSensitive: false), '')
                .replaceFirst('track_', ''),
            points: points,
            gpxPath: file.path,
          );
          // Мягкий фильтр: оставляем всё, где есть видео, или >=2 точек с пробегом > 1 метра
          final hasVideo = candidate.points.any((p) => p.videoName != null);
          if (candidate.points.length >= 2 || hasVideo) {
            if (candidate.distanceKm >= 0.001 || hasVideo) {
              tracks.add(candidate);
              debug += '; +track';
            } else {
              debug += '; skip_short(dist=${candidate.distanceKm})';
            }
          } else {
            debug += '; skip_pts(${candidate.points.length})';
          }
        }"""
patch_file('lib/services/storage_service.dart', [(old_filter, new_filter)], 'фильтр треков')

# --- 2. Экран настроек (settings_screen.dart) ---
# 2.1. Добавляем импорт LocalFolderService (если его нет)
patch_file('lib/screens/settings_screen.dart', [
    ("import '../services/storage_paths.dart';", "import '../services/storage_paths.dart';\nimport '../services/local_folder_service.dart';")
], 'импорт SAF')

# 2.2. Меняем отображение пути и добавляем кнопку «Очистить видео»
# Находим блок с текстом пути (примерно такой)
old_path_ui = """            Text(
              StoragePaths.defaultPath().toString(),"""
new_path_ui = """            FutureBuilder<String?>(
              future: LocalFolderService.getFolderName(),
              builder: (context, snapshot) {
                final name = snapshot.data;
                final displayPath = name != null && name.isNotEmpty
                    ? 'Выбрана папка: $name'
                    : '/storage/emulated/0/Android/data/ru.a510.gpsmanager/files/A510_Exports';
                return Text(
                  displayPath,"""

# 2.3. Добавляем кнопку очистки видео перед кнопкой «Очистить всё»
old_clear_all = """          FilledButton.icon(
            onPressed: _clearData,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Очистить всё'),
          ),"""
new_clear_all = """          OutlinedButton.icon(
            onPressed: _clearVideos,
            icon: const Icon(Icons.video_settings),
            label: const Text('Очистить видео'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _clearData,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Очистить всё'),
          ),"""

# 2.4. Добавляем метод _clearVideos и фикс логов
old_methods = """  Future<void> _clearData() async {"""
new_methods = """  Future<void> _clearVideos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить все видео?'),
        content: const Text('Будут удалены все скачанные видеофайлы. Треки останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    
    final provider = context.read<TracksProvider>();
    await provider.storage.clearVideos();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Видео удалены')));
  }

  Future<void> _clearData() async {"""

patch_file('lib/screens/settings_screen.dart', [
    (old_path_ui, new_path_ui),
    (old_clear_all, new_clear_all),
    (old_methods, new_methods)
], 'UI настроек (путь + очистка видео)')

# --- 3. Добавляем метод в StorageService для удаления видео ---
old_storage_end = """  Future<void> clearAll() async {
    final root = _root;
    if (root != null && await root.exists()) await root.delete(recursive: true);
    await initialize();
  }"""
new_storage_end = """  Future<void> clearVideos() async {
    final root = _root;
    if (root == null) return;
    final videoDir = Directory('${root.path}/videos');
    if (await videoDir.exists()) {
      await videoDir.delete(recursive: true);
      await videoDir.create(recursive: true);
    }
  }

  Future<void> clearAll() async {
    final root = _root;
    if (root != null && await root.exists()) await root.delete(recursive: true);
    await initialize();
  }"""
patch_file('lib/services/storage_service.dart', [(old_storage_end, new_storage_end)], 'метод clearVideos')

print("\nГотово! Проверьте ошибки через: flutter analyze")
