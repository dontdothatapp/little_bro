#!/bin/bash
# Builds "build/Little Bro.app" (release) and signs it.
# Ad-hoc by default. To keep macOS permission grants (e.g. browser automation) across
# rebuilds, sign with your own identity — the first time macOS asks to allow keychain access:
#   LITTLEBRO_SIGN_IDENTITY="Apple Development" ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product LittleBro
APP="build/Little Bro.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LittleBro "$APP/Contents/MacOS/LittleBro"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${LITTLEBRO_SIGN_IDENTITY:-}"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null
echo "Built $APP (signed with ${IDENTITY:-ad-hoc})"
