#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Ошибка: Flutter SDK не найден в PATH. Установите Flutter 3.24+ и повторите запуск."
  exit 1
fi
if ! command -v java >/dev/null 2>&1; then
  echo "Ошибка: Java не найдена. Для актуальной сборки Flutter Android требуется JDK, совместимый с используемым Gradle (обычно JDK 17)."
  exit 1
fi

# Если Android-обвязки нет, генерируем её через установленный Flutter SDK.
if [[ ! -f android/gradlew ]]; then
  echo "Android Gradle Wrapper не найден; создаём стандартный каркас Flutter…"
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  flutter create --platforms=android --org ru.a510 --project-name a510_gps_manager "$temp_dir/scaffold"
  rm -rf android
  cp -a "$temp_dir/scaffold/android" ./android
  cp .github/android-overlay/app/build.gradle android/app/build.gradle
  cp .github/android-overlay/app/src/main/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
  rm -rf android/app/src/main/kotlin
  mkdir -p android/app/src/main/kotlin/ru/a510/gpsmanager
  cp .github/android-overlay/app/src/main/kotlin/ru/a510/gpsmanager/MainActivity.kt android/app/src/main/kotlin/ru/a510/gpsmanager/MainActivity.kt
fi

printf '\n== Flutter environment ==\n'
flutter --version
printf '\n== Clean old outputs ==\n'
flutter clean
printf '\n== Resolve dependencies ==\n'
flutter pub get
printf '\n== Static analysis ==\n'
flutter analyze
printf '\n== Release APK ==\n'
flutter build apk --release

apk="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -s "$apk" ]]; then
  echo "Ошибка: APK не найден или пуст: $apk"
  exit 1
fi
printf '\nГотово: %s\n' "$apk"
ls -lh "$apk"
