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

# 1. Исправляем фильтр (оставляем треки с видео или пробегом > 1 метра)
old_filter = """          if (candidate.points.length >= 2 &&
              candidate.distanceKm >= 0.01) {
            tracks.add(candidate);
            debug += '; +track';
          } else {
            debug += '; skip(pts=${candidate.points.length},'
                'dist=${candidate.distanceKm.toStringAsFixed(3)})';
          }"""
new_filter = """          final hasVideo = candidate.points.any((p) => p.videoName != null);
          final hasMovement = candidate.points.length >= 2 &&
              candidate.distanceKm >= 0.001;
          if (hasMovement || hasVideo) {
            tracks.add(candidate);
            debug += '; +track';
          } else {
            debug += '; skip(pts=${candidate.points.length},'
                'dist=${candidate.distanceKm.toStringAsFixed(3)})';
          }"""
patch_file('lib/services/storage_service.dart', [(old_filter, new_filter)])

# 2. Исправляем отображение папки и добавляем кнопку очистки видео
old_path = """        FutureBuilder<String?>(
          future: StoragePaths.getCustomPath(),
          builder: (context, snapshot) {
            final custom = snapshot.data;
            return FutureBuilder<String>(
              future: custom != null ? Future.value(custom) : StoragePaths.defaultPath(),"""
new_path = """        FutureBuilder<String?>(
          future: LocalFolderService.getFolderName(),
          builder: (context, snapshot) {
            final custom = snapshot.data;
            return FutureBuilder<String>(
              future: custom != null && custom.isNotEmpty ? Future.value('Выбрана папка: $custom') : StoragePaths.defaultPath(),"""
patch_file('lib/screens/settings_screen.dart', [(old_path, new_path)])

old_btn = """        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _clearData, icon: const Icon(Icons.delete_forever), label: const Text('Очистить всё'))),"""
new_btn = """        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary), onPressed: _clearVideos, icon: const Icon(Icons.video_library), label: const Text('Очистить скачанные видео'))),
        const SizedBox(height: 8),
        SizedBox(height: 52, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: _clearData, icon: const Icon(Icons.delete_forever), label: const Text('Очистить всё'))),"""
patch_file('lib/screens/settings_screen.dart', [(old_btn, new_btn)])

print("\nГотово!")
