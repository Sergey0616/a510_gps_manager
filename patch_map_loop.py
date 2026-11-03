#!/usr/bin/env python3
import re
from pathlib import Path

path = Path("lib/screens/map_screen.dart")
text = path.read_text(encoding="utf-8")

# Ищем двойной цикл (по трекам и по точкам)
pattern = r"for \(var track in tracks\) \{\s*for \(var p in track\.points\) \{(.*?)\n\s*\}\s*\}"

def repl(m):
    # Оставляем только один цикл по точкам выбранного трека
    return "for (var p in selectedTrack.points) {" + m.group(1) + "\n    }"

new_text, count = re.subn(pattern, repl, text, flags=re.DOTALL)

if count > 0:
    path.write_text(new_text, encoding="utf-8")
    print(f"✅ map_screen.dart: цикл поиска успешно исправлен! (заменено блоков: {count})")
else:
    print("⚠️ Цикл не найден. Возможно, он уже исправлен или выглядит иначе.")
