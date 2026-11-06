#!/usr/bin/env python3
import re
from pathlib import Path

path = Path("lib/screens/map_screen.dart")
text = path.read_text(encoding="utf-8")

# Ищем любую проверку с 150 и заменяем на 300
pattern = r"(if \(nearest == null \|\| minDistance > )150(\))"
new_text, count = re.subn(pattern, r"\g<1>300\g<2>", text)

if count > 0:
    path.write_text(new_text, encoding="utf-8")
    print(f"✅ Радиус увеличен до 300 м (заменено: {count})")
else:
    print("⚠️ Проверка 150 не найдена. Уже исправлено или другой код.")
