#!/usr/bin/env python3
"""Патч: сохранение videoName при слиянии, увеличение радиуса поиска до 300м."""
from pathlib import Path

def main():
    # 1. tracks_provider.dart - сохраняем videoName
    path = Path("lib/providers/tracks_provider.dart")
    if path.exists():
        text = path.read_text(encoding="utf-8")
        old_merge = """    final uniquePoints = <String, GpsPoint>{};
    for (final p in mergedList) {
      final key = '${p.timestamp}_${p.latitude}_${p.longitude}';
      uniquePoints[key] = p;
    }"""
        new_merge = """    final uniquePoints = <String, GpsPoint>{};
    for (final p in mergedList) {
      final key = '${p.timestamp}_${p.latitude}_${p.longitude}';
      final existing = uniquePoints[key];
      // Если старая точка без видео, а новая с видео — заменяем!
      if (existing == null || (existing.videoName == null && p.videoName != null)) {
        uniquePoints[key] = p;
      }
    }"""
        if old_merge in text:
            text = text.replace(old_merge, new_merge, 1)
            path.write_text(text, encoding="utf-8")
            print("✅ tracks_provider: videoName теперь не теряется при слиянии")
        else:
            print("⚠️ tracks_provider: шаблон слияния не найден")

    # 2. map_screen.dart - увеличиваем радиус
    map_path = Path("lib/screens/map_screen.dart")
    if map_path.exists():
        text = map_path.read_text(encoding="utf-8")
        old_check = """      if (nearest == null || minDistance > 150) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Рядом нет точек трека (ближе 150 м)')));
        return;
      }"""
        new_check = """      if (nearest == null || minDistance > 300) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Рядом нет точек трека (ближе 300 м)')));
        return;
      }"""
        if old_check in text:
            text = text.replace(old_check, new_check, 1)
            path.write_text(text, encoding="utf-8")
            print("✅ map_screen: радиус поиска увеличен до 300 м")
        else:
            print("⚠️ map_screen: проверка расстояния не найдена")

if __name__ == "__main__":
    main()
