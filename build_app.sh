#!/bin/bash
# Собирает PuntoSwitcher.app из release-бинаря: Info.plist (LSUIElement), ad-hoc подпись.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/PuntoSwitcher.app"
BIN="$ROOT/.build/release/PuntoSwitcher"

echo "==> Сборка release"
swift build -c release >/dev/null

echo "==> Пересборка бандла $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/PuntoSwitcher"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>PuntoSwitcher</string>
    <key>CFBundleDisplayName</key>     <string>PuntoSwitcher</string>
    <key>CFBundleIdentifier</key>      <string>com.georgi.puntoswitcher</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>PuntoSwitcher</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Меню-бар агент: без иконки в доке -->
    <key>LSUIElement</key>            <true/>
</dict>
</plist>
PLIST

echo "==> Стабильная подпись (самоподписанный сертификат)"
# Одна и та же идентичность при каждой сборке → разрешение Accessibility не слетает.
# Если сертификата нет — падаем обратно на ad-hoc (тогда доступ придётся выдать заново).
SIGN_ID="PuntoSwitcher Local Signing"
if security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" --identifier com.georgi.puntoswitcher "$APP"
else
    echo "   ⚠️  Сертификат '$SIGN_ID' не найден — ad-hoc подпись."
    codesign --force --sign - "$APP"
fi

echo "==> Готово: $APP"
