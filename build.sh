#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Ошибка: Flutter SDK не найден в PATH."
  exit 1
fi
if ! command -v java >/dev/null 2>&1; then
  echo "Ошибка: Java не найдена."
  exit 1
fi

if [[ ! -f android/gradlew ]]; then
  echo "== Создаём android/ in-place через flutter create =="
  rm -rf android
  flutter create --platforms=android --org ru.a510 --project-name a510_gps_manager .

  echo "== Копируем overlay =="
  cp .github/android-overlay/app/build.gradle android/app/build.gradle
  cp .github/android-overlay/app/src/main/AndroidManifest.xml android/app/src/main/AndroidManifest.xml

  rm -rf android/app/src/main/kotlin
  mkdir -p android/app/src/main/kotlin/ru/a510/gpsmanager
  cp .github/android-overlay/app/src/main/kotlin/ru/a510/gpsmanager/MainActivity.kt \
     android/app/src/main/kotlin/ru/a510/gpsmanager/MainActivity.kt

  echo "== Патчим compileSdk/ndkVersion для ПЛАГИНОВ (не для :app) =="
  cat > android/compile-sdk-fix.gradle << 'FIXEOF'
subprojects { subproject ->
    if (subproject.name == 'app') return
    subproject.afterEvaluate {
        if (subproject.hasProperty('android')) {
            subproject.android {
                compileSdk 36
                ndkVersion "28.2.13676358"
            }
        }
    }
}
FIXEOF
  echo "" >> android/build.gradle
  echo "apply from: 'compile-sdk-fix.gradle'" >> android/build.gradle

  rm -f android/build.gradle.kts android/app/build.gradle.kts
fi

printf '\n== Flutter environment ==\n'
flutter --version
printf '\n== Clean old outputs ==\n'
flutter clean
printf '\n== Resolve dependencies ==\n'
flutter pub get
printf '\n== Static analysis ==\n'
flutter analyze --no-fatal-infos --no-fatal-warnings || true

printf '\n== Release APK ==\n'
df -h

# Чистим возможный залипший кэш Flutter-сборки (источник "Already watching path").
rm -rf .dart_tool/flutter_build 2>/dev/null || true

# flutter build apk иногда возвращает exit 1 из-за бага file-watcher'а
# ("Already watching path: .../android"), хотя APK успешно собирается.
# Поэтому || true и проверяем оба возможных пути к APK.
flutter build apk --release || true

apk_flutter="build/app/outputs/flutter-apk/app-release.apk"
apk_gradle="android/app/build/outputs/flutter-apk/app-release.apk"

if [[ ! -s "$apk_flutter" ]] && [[ -s "$apk_gradle" ]]; then
  echo "Flutter не перенёс APK; копируем вручную: $apk_gradle → $apk_flutter"
  mkdir -p "$(dirname "$apk_flutter")"
  cp "$apk_gradle" "$apk_flutter"
fi

echo "=== Все APK в проекте ==="
find "$PWD" -name "*.apk" -type f 2>/dev/null || true

if [[ ! -s "$apk_flutter" ]]; then
  echo "Ошибка: APK не найден или пуст: $apk_flutter"
  df -h
  exit 1
fi

printf '\nГотово: %s\n' "$apk_flutter"
ls -lh "$apk_flutter"
